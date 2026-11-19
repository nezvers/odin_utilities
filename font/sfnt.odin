package font

// The container of a font file (sfnt: .ttf, .otf, and .ttc collections of them) and the tables that do not depend on the kind of outline: the character map, the advances and the kerning.
// The outlines are in truetype.odin (glyf) and cff.odin (CFF). Everything reads the bytes the caller gave to FontInit, nothing is copied or allocated.
//
// A font file is untrusted data: every read checks its place and gives 0 outside of the bytes, a slice that would start outside is empty. A broken file gives wrong glyphs, never a
// read outside of the file.
//
// This is a port of stb_truetype v1.28 (Sean Barrett, public domain / MIT) by way of the Odin port in Karl2D (karl2d/opentype, Karl Zylinski): the same tables, the same choices, so the
// numbers are the ones stb_truetype gives (font_test.odin compares them glyph by glyph).

import "base:intrinsics"

@(private)
readU8 :: #force_inline proc "contextless" (data: []u8, offset: int) -> int #no_bounds_check {
    if offset < 0 || offset >= len(data) { return 0 }
    return int(data[offset])
}

@(private)
readU16 :: #force_inline proc "contextless" (data: []u8, offset: int) -> int #no_bounds_check {
    if offset < 0 || offset + 2 > len(data) { return 0 }
    return int(intrinsics.unaligned_load((^u16be)(&data[offset])))
}

@(private)
readI16 :: #force_inline proc "contextless" (data: []u8, offset: int) -> int #no_bounds_check {
    if offset < 0 || offset + 2 > len(data) { return 0 }
    return int(intrinsics.unaligned_load((^i16be)(&data[offset])))
}

@(private)
readU32 :: #force_inline proc "contextless" (data: []u8, offset: int) -> int #no_bounds_check {
    if offset < 0 || offset + 4 > len(data) { return 0 }
    return int(intrinsics.unaligned_load((^u32be)(&data[offset])))
}

// The bytes from `count` on, empty when that is outside
@(private)
skipBytes :: #force_inline proc "contextless" (data: []u8, count: int) -> []u8 {
    if count < 0 || count > len(data) { return nil }
    return data[count:]
}

@(private)
sfntTag :: proc "contextless" (data: []u8, offset: int, tag: string) -> bool {
    if offset < 0 || offset + 4 > len(data) { return false }
    return string(data[offset:offset + 4]) == tag
}

@(private)
sfntIsFont :: proc "contextless" (data: []u8, offset: int) -> bool {
    if offset < 0 || offset + 12 > len(data) { return false }
    return sfntTag(data, offset, "1\x00\x00\x00") || sfntTag(data, offset, "typ1") || sfntTag(data, offset, "OTTO") || sfntTag(data, offset, "\x00\x01\x00\x00") || sfntTag(data, offset, "true")
}

// Where the font number `index` starts in the file: 0 for a plain font, the entry of the directory for a collection
@(private)
sfntStart :: proc "contextless" (data: []u8, index: int) -> (start: int, ok: bool) {
    if sfntIsFont(data, 0) { return 0, index == 0 }
    if len(data) >= 12 && sfntTag(data, 0, "ttcf") {
        version: int = readU32(data, 4)
        if version != 0x00010000 && version != 0x00020000 { return }
        if index < 0 || index >= readU32(data, 8) { return }
        start = readU32(data, 12 + index * 4)
        return start, sfntIsFont(data, start)
    }
    return
}

// A table of the font by its four letters, empty when the font has none (or when it would not be inside the file)
@(private)
sfntTable :: proc "contextless" (data: []u8, start: int, tag: string) -> []u8 {
    table_count: int = readU16(data, start + 4)
    directory: int = start + 12
    if directory + 16 * table_count > len(data) { return nil }
    for i in 0 ..< table_count {
        entry: int = directory + 16 * i
        if sfntTag(data, entry, tag) {
            offset: int = readU32(data, entry + 8)
            length: int = readU32(data, entry + 12)
            if offset + length > len(data) { return nil }
            return data[offset:offset + length]
        }
    }
    return nil
}

// The subtable of `cmap` that maps Unicode to glyphs (a symbol font's own map when there is nothing else), empty when the font has none that is understood
@(private)
sfntCharacterMap :: proc "contextless" (cmap: []u8) -> []u8 {
    PLATFORM_UNICODE :: 0
    PLATFORM_MICROSOFT :: 3
    MICROSOFT_SYMBOL :: 0
    MICROSOFT_UNICODE_BMP :: 1
    MICROSOFT_UNICODE_FULL :: 10
    subtable_count: int = readU16(cmap, 2)
    if 4 + 8 * subtable_count > len(cmap) { return nil }
    chosen: []u8
    symbol: []u8
    for i in 0 ..< subtable_count {
        record: int = 4 + 8 * i
        offset: int = readU32(cmap, record + 4)
        if offset + 2 > len(cmap) { continue }
        subtable: []u8 = cmap[offset:]
        switch readU16(subtable, 0) {
        case 0, 4, 6, 12, 13:
        case:
            continue
        }
        switch readU16(cmap, record) {
        case PLATFORM_UNICODE:
            chosen = subtable
        case PLATFORM_MICROSOFT:
            switch readU16(cmap, record + 2) {
            case MICROSOFT_UNICODE_BMP, MICROSOFT_UNICODE_FULL:
                chosen = subtable
            case MICROSOFT_SYMBOL:
                symbol = subtable
            }
        }
    }
    return chosen if len(chosen) > 0 else symbol
}

// The glyph of a character in a character map, 0 when it has none
@(private)
sfntGlyphIndex :: proc "contextless" (cmap: []u8, character: rune) -> int {
    code: int = int(character)
    format: int = readU16(cmap, 0)
    switch format {
    case 0:
        if code < readU16(cmap, 2) - 6 { return readU8(cmap, 6 + code) }
    case 6:
        first: int = readU16(cmap, 6)
        count: int = readU16(cmap, 8)
        if code >= first && code < first + count { return readU16(cmap, 10 + (code - first) * 2) }
    case 4:
        // segments sorted by their last character: a binary search made of the steps the table itself gives
        segment_count: int = readU16(cmap, 6) >> 1
        search_range: int = readU16(cmap, 8) >> 1
        entry_selector: int = readU16(cmap, 10)
        range_shift: int = readU16(cmap, 12) >> 1
        end_codes: int = 14
        search: int = end_codes
        if code > 0xffff { return 0 }
        if code >= readU16(cmap, search + range_shift * 2) { search += range_shift * 2 }
        search -= 2
        for entry_selector != 0 {
            search_range >>= 1
            if code > readU16(cmap, search + search_range * 2) { search += search_range * 2 }
            entry_selector -= 1
        }
        search += 2
        item: int = int(u16((search - end_codes) >> 1))
        first: int = readU16(cmap, 14 + segment_count * 2 + 2 + 2 * item)
        last: int = readU16(cmap, end_codes + 2 * item)
        if code < first || code > last { return 0 }
        offset: int = readU16(cmap, 14 + segment_count * 6 + 2 + 2 * item)
        delta: int = readI16(cmap, 14 + segment_count * 4 + 2 + 2 * item)
        if offset == 0 { return int(u16(code + delta)) }
        index: int = readU16(cmap, offset + (code - first) * 2 + 14 + segment_count * 6 + 2 + 2 * item)
        if index == 0 { return 0 }
        return int(u16(index + delta))
    case 12, 13:
        low: int = 0
        high: int = readU32(cmap, 12)
        for low < high {
            middle: int = low + ((high - low) >> 1)
            first: int = readU32(cmap, 16 + middle * 12)
            last: int = readU32(cmap, 16 + middle * 12 + 4)
            if code < first {
                high = middle
            } else if code > last {
                low = middle + 1
            } else {
                glyph: int = readU32(cmap, 16 + middle * 12 + 8)
                return glyph + code - first if format == 12 else glyph
            }
        }
    }
    return 0
}

// ---------------------------------------------------------------- Kerning

// The kerning of a pair in font units: the GPOS table (pair adjustment) when it knows the pair, else the old kern table
@(private)
sfntKerning :: proc "contextless" (font: ^Font, first: int, second: int) -> int {
    if advance, found := gposAdvance(font.gpos, first, second); found { return advance }
    kern: []u8 = font.kern
    if len(kern) == 0 { return 0 }
    low: int = 0
    high: int = readU16(kern, 10) - 1
    needle: int = first << 16 | second
    for low <= high {
        middle: int = (low + high) >> 1
        straw: int = readU32(kern, 18 + middle * 6)
        if needle < straw {
            high = middle - 1
        } else if needle > straw {
            low = middle + 1
        } else {
            return readI16(kern, 22 + middle * 6)
        }
    }
    return 0
}

// The place of a glyph in a coverage table, -1 when it is not covered
@(private)
gposCoverageIndex :: proc "contextless" (coverage: []u8, glyph: int) -> int {
    switch readU16(coverage, 0) {
    case 1:
        glyphs: []u8 = skipBytes(coverage, 4)
        low: int = 0
        high: int = readU16(coverage, 2) - 1
        for low <= high {
            middle: int = (low + high) >> 1
            straw: int = readU16(glyphs, 2 * middle)
            if glyph < straw {
                high = middle - 1
            } else if glyph > straw {
                low = middle + 1
            } else {
                return middle
            }
        }
    case 2:
        ranges: []u8 = skipBytes(coverage, 4)
        low: int = 0
        high: int = readU16(coverage, 2) - 1
        for low <= high {
            middle: int = (low + high) >> 1
            record: []u8 = skipBytes(ranges, 6 * middle)
            first: int = readU16(record, 0)
            last: int = readU16(record, 2)
            if glyph < first {
                high = middle - 1
            } else if glyph > last {
                low = middle + 1
            } else {
                return readU16(record, 4) + glyph - first
            }
        }
    }
    return -1
}

// The class of a glyph in a class definition table (0 for a glyph that is in none), -1 for a table that is not understood
@(private)
gposGlyphClass :: proc "contextless" (classes: []u8, glyph: int) -> int {
    switch readU16(classes, 0) {
    case 1:
        first: int = readU16(classes, 2)
        count: int = readU16(classes, 4)
        if glyph >= first && glyph < first + count { return readU16(classes, 6 + 2 * (glyph - first)) }
    case 2:
        ranges: []u8 = skipBytes(classes, 4)
        low: int = 0
        high: int = readU16(classes, 2) - 1
        for low <= high {
            middle: int = (low + high) >> 1
            record: []u8 = skipBytes(ranges, 6 * middle)
            first: int = readU16(record, 0)
            last: int = readU16(record, 2)
            if glyph < first {
                high = middle - 1
            } else if glyph > last {
                low = middle + 1
            } else {
                return readU16(record, 4)
            }
        }
    case:
        return -1
    }
    return 0
}

// The pair adjustment of GPOS (lookup type 2, also behind an extension lookup): the advance of the pair and whether the table had an answer.
// `lookups` is the lookup list of the table.
@(private)
gposAdvance :: proc "contextless" (lookups: []u8, first: int, second: int) -> (advance: int, found: bool) {
    if len(lookups) == 0 { return }
    for i in 0 ..< readU16(lookups, 0) {
        lookup: []u8 = skipBytes(lookups, readU16(lookups, 2 + 2 * i))
        lookup_type: int = readU16(lookup, 0)
        if lookup_type != 2 && lookup_type != 9 { continue }
        for subtable in 0 ..< readU16(lookup, 4) {
            table: []u8 = skipBytes(lookup, readU16(lookup, 6 + 2 * subtable))
            if lookup_type == 9 {
                if readU16(table, 0) != 1 || readU16(table, 2) != 2 { continue }
                table = skipBytes(table, readU32(table, 4))
            }
            coverage_index: int = gposCoverageIndex(skipBytes(table, readU16(table, 2)), first)
            if coverage_index == -1 { continue }
            // only the horizontal advance of the first glyph (4), alone or with its placement (68), and nothing for the second glyph
            value_size: int
            switch readU16(table, 4) {
            case 4:
                value_size = 2
            case 68:
                value_size = 4
            }
            if value_size == 0 || readU16(table, 6) != 0 { return }
            switch readU16(table, 0) {
            case 1:
                if coverage_index >= readU16(table, 8) { return }
                pairs: []u8 = skipBytes(table, readU16(table, 10 + 2 * coverage_index))
                values: []u8 = skipBytes(pairs, 2)
                low: int = 0
                high: int = readU16(pairs, 0) - 1
                for low <= high {
                    middle: int = (low + high) >> 1
                    pair: []u8 = skipBytes(values, (2 + value_size) * middle)
                    straw: int = readU16(pair, 0)
                    if second < straw {
                        high = middle - 1
                    } else if second > straw {
                        low = middle + 1
                    } else {
                        return readI16(pair, 2), true
                    }
                }
            case 2:
                first_class: int = gposGlyphClass(skipBytes(table, readU16(table, 8)), first)
                second_class: int = gposGlyphClass(skipBytes(table, readU16(table, 10)), second)
                first_count: int = readU16(table, 12)
                second_count: int = readU16(table, 14)
                if first_class < 0 || first_class >= first_count { return }
                if second_class < 0 || second_class >= second_count { return }
                return readI16(table, 16 + value_size * (first_class * second_count + second_class)), true
            case:
                return
            }
        }
    }
    return
}
