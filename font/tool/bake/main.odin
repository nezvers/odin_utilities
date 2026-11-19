// Bakes the glyphs of a font file into an atlas file that a program reads at start (font.AtlasRead), so that it does no baking at run time.
//
//     odin run font/tool/bake -- font.ttf out.atlas [--method slug|scanline] [--range 32 126]... [--text "words"] [--rows 16]
//
// Without --range and --text the printable ASCII characters (32 to 126) are baked. Prints how many glyphs and bytes it made.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import font "../.."

main :: proc() {
    arguments: []string = os.args[1:]
    if len(arguments) < 2 {
        fmt.eprintln("bake <font file> <out file> [--method slug|scanline] [--range first last]... [--text words] [--rows n]")
        os.exit(2)
    }
    method: font.Method = .SLUG
    rows: int = 16
    ranges: [dynamic][2]rune
    text: string
    for index := 2; index < len(arguments); index += 1 {
        switch arguments[index] {
        case "--method":
            index += 1
            if index < len(arguments) && arguments[index] == "scanline" { method = .SCANLINE }
        case "--range":
            if index + 2 >= len(arguments) { fmt.eprintln("--range wants two numbers"); os.exit(2) }
            first, _ := strconv.parse_int(arguments[index + 1])
            last, _ := strconv.parse_int(arguments[index + 2])
            append(&ranges, [2]rune{rune(first), rune(last)})
            index += 2
        case "--text":
            index += 1
            if index < len(arguments) { text = arguments[index] }
        case "--rows":
            index += 1
            if index < len(arguments) { rows, _ = strconv.parse_int(arguments[index]) }
        case:
            fmt.eprintfln("unknown option %s", arguments[index])
            os.exit(2)
        }
    }
    if len(ranges) == 0 && text == "" { append(&ranges, [2]rune{32, 126}) }

    bytes, read_error := os.read_entire_file(arguments[0], context.allocator)
    if read_error != nil {
        fmt.eprintfln("cannot read %s", arguments[0])
        os.exit(1)
    }
    face: font.Font
    if !font.FontInit(&face, bytes) {
        fmt.eprintfln("%s is not a font", arguments[0])
        os.exit(1)
    }
    texels: []f32 = make([]f32, 4 * font.ATLAS_WIDTH * rows)
    slots: []i32 = make([]i32, font.FontSlotCount(&face))
    atlas: font.Atlas
    font.AtlasInit(&atlas, &face, method, texels, slots)
    total: int
    full: bool
    for range in ranges {
        baked, ok := font.AtlasBakeRange(&atlas, range[0], range[1])
        total += baked
        full = full || !ok
    }
    if text != "" { full = !font.AtlasReserveText(&atlas, text) || full }
    font.AtlasGlyph(&atlas, font.GlyphMissing(&face))
    out: []u8 = make([]u8, font.AtlasWriteSize(&atlas))
    written, ok := font.AtlasWrite(&atlas, out)
    if !ok || os.write_entire_file(arguments[1], out[:written]) != nil {
        fmt.eprintfln("cannot write %s", arguments[1])
        os.exit(1)
    }
    fmt.printfln("%d glyphs, %d bytes, %s%s", atlas.slots, written, "slug" if method == .SLUG else "scanline", " (the atlas was full: use --rows)" if full else "")
    if full { os.exit(1) }
}
