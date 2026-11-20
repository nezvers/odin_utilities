package main

// Makes unicode_data/tables.odin from the files of the Unicode Character Database:
//
//     odin run unicode_data/tool/gen -- <folder with the files> [<output file>]
//
// The files (https://www.unicode.org/Public/UCD/latest/ucd/): EastAsianWidth.txt, extracted/DerivedGeneralCategory.txt, emoji/emoji-data.txt, auxiliary/GraphemeBreakProperty.txt,
// DerivedCoreProperties.txt (their base names are looked for in the folder). Run it again for a new version of Unicode and look at the diff.
//
// What a code point gets (the u16 of `Props`, see ../../unicode_data.odin):
//   width         0 for the general categories Mn, Me, Cf and Cc and for the Hangul vowels and finals of the grapheme break classes V and T; 2 for East Asian Width W and F and for
//                 the regional indicators (half of a flag, drawn two cells wide); else 1
//   ambiguous     East Asian Width A
//   emoji text    Emoji = Yes and Emoji_Presentation = No, above 0x7F (a variation selector 16 makes it an emoji picture, two cells wide)
//   break class   the Grapheme_Cluster_Break value, Extended_Pictographic, and InCB (Consonant, Linker, Extend: the rule GB9c of Unicode 15.1)
// The two stage table: the high bits of the code point pick a block of 256 properties, equal blocks are stored once.

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

LAST :: 0x10FFFF
BLOCK :: 256

// bits of a property word (keep in step with unicode_data.odin)
WIDTH_MASK :: u16(0x3)
AMBIGUOUS :: u16(1 << 2)
EMOJI_TEXT :: u16(1 << 3)
CLASS_SHIFT :: 4                       // four bits: Grapheme_Cluster_Break
EXT_PICT :: u16(1 << 8)
INCB_SHIFT :: 9                        // two bits: 0 none, 1 Consonant, 2 Linker, 3 Extend

CLASSES :: [?]string{"Other", "CR", "LF", "Control", "Extend", "ZWJ", "Regional_Indicator", "Prepend", "SpacingMark", "L", "V", "T", "LV", "LVT"}

Range :: struct { first: int, last: int, value: string }

// The lines "0000..001F ; value # comment" or "0000 ; value" of a file; `fields` is how many ; separated fields come before the comment (2, or 3 for DerivedCoreProperties' InCB lines)
parse :: proc(path: string, ranges: ^[dynamic]Range, wanted_property: string = "") -> bool {
    data, read_error := os.read_entire_file(path, context.allocator)
    if read_error != nil {
        fmt.eprintln("cannot read", path)
        return false
    }
    defer delete(data)
    text: string = string(data)
    for line in strings.split_lines_iterator(&text) {
        content: string = line
        if hash := strings.index_byte(content, '#'); hash >= 0 { content = content[:hash] }
        content = strings.trim_space(content)
        if content == "" { continue }
        fields, _ := strings.split(content, ";", context.temp_allocator)
        if len(fields) < 2 { continue }
        value: string = strings.trim_space(fields[1])
        if wanted_property != "" {
            if value != wanted_property || len(fields) < 3 { continue }
            value = strings.trim_space(fields[2])
        }
        span: string = strings.trim_space(fields[0])
        first, last: int
        if dots := strings.index(span, ".."); dots >= 0 {
            first = int(strconv.parse_int(span[:dots], 16) or_else -1)
            last = int(strconv.parse_int(span[dots + 2:], 16) or_else -1)
        } else {
            first = int(strconv.parse_int(span, 16) or_else -1)
            last = first
        }
        if first < 0 || last < first { continue }
        append(ranges, Range{first, last, strings.clone(value)})
    }
    return true
}

main :: proc() {
    if len(os.args) < 2 {
        fmt.eprintln("usage: gen <folder with the Unicode files> [<output file>]")
        os.exit(2)
    }
    folder: string = os.args[1]
    output: string = os.args[2] if len(os.args) > 2 else "unicode_data/tables.odin"
    path :: proc(folder: string, name: string) -> string { return strings.join({folder, "/", name}, "", context.temp_allocator) }

    width: []u8 = make([]u8, LAST + 1)
    for i in 0 ..= LAST { width[i] = 1 }
    props: []u16 = make([]u16, LAST + 1)

    // East Asian Width
    eaw: [dynamic]Range
    if !parse(path(folder, "EastAsianWidth.txt"), &eaw) { os.exit(1) }
    for range in eaw {
        for code in range.first ..= range.last {
            switch range.value {
            case "W", "F": width[code] = 2
            case "A": props[code] |= AMBIGUOUS
            }
        }
    }

    // general categories that take no room
    categories: [dynamic]Range
    if !parse(path(folder, "DerivedGeneralCategory.txt"), &categories) { os.exit(1) }
    for range in categories {
        switch range.value {
        case "Mn", "Me", "Cf", "Cc":
            for code in range.first ..= range.last { width[code] = 0 }
        }
    }

    // grapheme break classes
    breaks: [dynamic]Range
    if !parse(path(folder, "GraphemeBreakProperty.txt"), &breaks) { os.exit(1) }
    names := CLASSES
    for range in breaks {
        class: int = -1
        for name, i in names { if name == range.value { class = i } }
        if class < 0 { continue }
        for code in range.first ..= range.last {
            props[code] |= u16(class) << CLASS_SHIFT
            switch range.value {
            case "V", "T": width[code] = 0              // the vowels and the finals of a Hangul syllable go with the letter before them
            case "Regional_Indicator": width[code] = 2
            }
        }
    }

    // emoji
    emoji: [dynamic]Range
    if !parse(path(folder, "emoji-data.txt"), &emoji) { os.exit(1) }
    presentation: []bool = make([]bool, LAST + 1)
    is_emoji: []bool = make([]bool, LAST + 1)
    for range in emoji {
        for code in range.first ..= range.last {
            switch range.value {
            case "Extended_Pictographic": props[code] |= EXT_PICT
            case "Emoji_Presentation": presentation[code] = true
            case "Emoji": is_emoji[code] = true
            }
        }
    }
    for code in 0x80 ..= LAST {
        if is_emoji[code] && !presentation[code] { props[code] |= EMOJI_TEXT }
    }

    // the conjunct break of the Indic scripts
    conjuncts: [dynamic]Range
    if !parse(path(folder, "DerivedCoreProperties.txt"), &conjuncts, "InCB") { os.exit(1) }
    for range in conjuncts {
        value: u16
        switch range.value {
        case "Consonant": value = 1
        case "Linker": value = 2
        case "Extend": value = 3
        case: continue
        }
        for code in range.first ..= range.last { props[code] |= value << INCB_SHIFT }
    }

    for code in 0 ..= LAST { props[code] |= u16(width[code]) & WIDTH_MASK }

    // two stages: equal blocks once
    blocks: [dynamic][BLOCK]u16
    index: [(LAST + 1) / BLOCK]u16
    for block_number in 0 ..< (LAST + 1) / BLOCK {
        block: [BLOCK]u16
        for i in 0 ..< BLOCK { block[i] = props[block_number * BLOCK + i] }
        found: int = -1
        for known, k in blocks {
            if known == block { found = k; break }
        }
        if found < 0 {
            append(&blocks, block)
            found = len(blocks) - 1
        }
        index[block_number] = u16(found)
    }

    builder: strings.Builder
    strings.builder_init(&builder)
    version: string = "unknown"
    if data, read_error := os.read_entire_file(path(folder, "EastAsianWidth.txt"), context.allocator); read_error == nil {
        first_line: string = string(data)
        if newline := strings.index_byte(first_line, '\n'); newline >= 0 { first_line = first_line[:newline] }
        first_line = strings.trim_space(first_line)
        if dash := strings.index_byte(first_line, '-'); dash >= 0 { version = strings.trim_suffix(first_line[dash + 1:], ".txt") }
    }
    fmt.sbprintf(&builder, "package unicode_data\n\n// Generated by tool/gen from the Unicode Character Database %s: do not edit, run `odin run unicode_data/tool/gen -- <folder> unicode_data/tables.odin`.\n", version)
    fmt.sbprintf(&builder, "// %d blocks of 256 properties and one index of %d entries.\n\n", len(blocks), len(index))
    fmt.sbprintf(&builder, "UNICODE_VERSION :: \"%s\"\n\n", version)
    fmt.sbprintf(&builder, "@(rodata)\nSTAGE1 := [%d]u16{{", len(index))
    for value, i in index {
        if i % 24 == 0 { fmt.sbprint(&builder, "\n    ") }
        fmt.sbprintf(&builder, "%d, ", value)
    }
    fmt.sbprint(&builder, "\n}\n\n")
    fmt.sbprintf(&builder, "@(rodata)\nSTAGE2 := [%d]u16{{", len(blocks) * BLOCK)
    for block in blocks {
        fmt.sbprint(&builder, "\n    // a block")
        for value, i in block {
            if i % 24 == 0 { fmt.sbprint(&builder, "\n    ") }
            fmt.sbprintf(&builder, "%d, ", value)
        }
    }
    fmt.sbprint(&builder, "\n}\n")
    if os.write_entire_file(output, transmute([]u8)strings.to_string(builder)) != nil {
        fmt.eprintln("cannot write", output)
        os.exit(1)
    }
    fmt.printf("%s: Unicode %s, %d blocks, %d bytes of tables\n", output, version, len(blocks), len(blocks) * BLOCK * 2 + len(index) * 2)
}
