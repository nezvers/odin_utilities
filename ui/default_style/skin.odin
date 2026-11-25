package ui_default

// A skin is a style (the `Theme`) and the fonts it is drawn in: one font file for each face of the painter (regular, strong, italic, mono, ...). A face with no file is the built in one (Inter and
// JetBrains Mono), so a skin may change only the strong face, or all eight. The fonts are named in the same `<name>.style` file as the colors, as lines `font_<face> = <file>`; a relative file is
// read from the folder of the style (the program decides: see SkinFontsRead in skin_files.odin).
//
//     fonts: ui_default.SkinFonts
//     ui_default.SkinFontSet(&fonts, .STRONG, "fonts/Lato-Bold.ttf")
//     store.save_fonts(&store, "my skin", &fonts)                    // the same file as the theme of that name; store.load_fonts(...) brings them back
//
// The style editor has a Fonts section with a field for each face and a serial that changes when a name does (`StyleEditor.fonts_serial`): a program loads the new fonts when it sees the serial move
// (`ui_kit.UseSkinFonts` does it for the demos, `glue_karl2d.FontsLoad` and `glue_raylib.FontsLoad` take the bytes).
//
// Limits: a font per face, not per size or script (a program that needs a fallback for other scripts uses the text system, see ui/font); the icons are always Lucide; no font is embedded in the style
//     file (only its name), so a skin that is moved takes its font files with it; a file that cannot be read or is not a font leaves the built in face.

FONT_FILE_LENGTH :: 128

SkinFonts :: struct {
    files: [Face][FONT_FILE_LENGTH]u8,
    lengths: [Face]int,                 // 0: the built in font
}

// The bytes of the font files of a skin, a face with no bytes is the built in one (SkinFontsRead in skin_files.odin makes them)
SkinFontBytes :: [Face][]u8

// The key of a face in the style file: "regular", "strong", "italic", "mono", "mono_strong", "strong_italic", "mono_italic", "mono_strong_italic"
FaceKey :: proc(face: Face) -> string {
    switch face {
    case .REGULAR: return "regular"
    case .STRONG: return "strong"
    case .ITALIC: return "italic"
    case .MONO: return "mono"
    case .MONO_STRONG: return "mono_strong"
    case .STRONG_ITALIC: return "strong_italic"
    case .MONO_ITALIC: return "mono_italic"
    case .MONO_STRONG_ITALIC: return "mono_strong_italic"
    }
    return ""
}

SkinFontFile :: proc(fonts: ^SkinFonts, face: Face) -> string {
    return string(fonts.files[face][:fonts.lengths[face]])
}

// Names the file of a face ("" goes back to the built in one). False when the name is too long.
SkinFontSet :: proc(fonts: ^SkinFonts, face: Face, file: string) -> bool {
    if len(file) > FONT_FILE_LENGTH { return false }
    fonts.lengths[face] = copy(fonts.files[face][:], file)
    return true
}

SkinFontsCount :: proc(fonts: ^SkinFonts) -> (count: int) {
    for face in Face {
        if fonts.lengths[face] > 0 { count += 1 }
    }
    return
}

// The lines of the fonts that have a file (nothing for the built in ones)
SkinFontsText :: proc(fonts: ^SkinFonts, out: []u8) -> string {
    length: int
    put :: proc(out: []u8, length: ^int, text: string) {
        length^ += copy(out[length^:], text)
    }
    for face in Face {
        if fonts.lengths[face] == 0 { continue }
        put(out, &length, "font_")
        put(out, &length, FaceKey(face))
        put(out, &length, " = ")
        put(out, &length, SkinFontFile(fonts, face))
        put(out, &length, "\n")
    }
    return string(out[:length])
}

// The font lines of a style text into `fonts` (a face the text does not name is left as it is). The number of lines that named a font.
SkinFontsParse :: proc(text: string, fonts: ^SkinFonts) -> (applied: int) {
    rest: string = text
    for len(rest) > 0 {
        line: string
        newline: int = -1
        for i in 0 ..< len(rest) {
            if rest[i] == '\n' {
                newline = i
                break
            }
        }
        if newline < 0 {
            line, rest = rest, ""
        } else {
            line, rest = rest[:newline], rest[newline + 1:]
        }
        line = trimSpace(line)
        if len(line) < 6 || line[:5] != "font_" { continue }
        equals: int = -1
        for i in 0 ..< len(line) {
            if line[i] == '=' {
                equals = i
                break
            }
        }
        if equals < 0 { continue }
        key: string = trimSpace(line[5:equals])
        value: string = trimSpace(line[equals + 1:])
        for face in Face {
            if FaceKey(face) == key && SkinFontSet(fonts, face, value) {
                applied += 1
                break
            }
        }
    }
    return
}

@(private)
trimSpace :: proc(text: string) -> string {
    start, end: int = 0, len(text)
    for start < end && (text[start] == ' ' || text[start] == '\t' || text[start] == '\r') { start += 1 }
    for end > start && (text[end - 1] == ' ' || text[end - 1] == '\t' || text[end - 1] == '\r') { end -= 1 }
    return text[start:end]
}

// The lines of a style text that are not font lines (a store that rewrites the fonts keeps the colors, and the other way round)
SkinTextWithoutFonts :: proc(text: string, out: []u8) -> string {
    length: int
    rest: string = text
    for len(rest) > 0 {
        line: string
        newline: int = -1
        for i in 0 ..< len(rest) {
            if rest[i] == '\n' {
                newline = i
                break
            }
        }
        whole: string
        if newline < 0 {
            whole, rest = rest, ""
        } else {
            whole, rest = rest[:newline + 1], rest[newline + 1:]
        }
        line = trimSpace(whole)
        if len(line) >= 5 && line[:5] == "font_" { continue }
        length += copy(out[length:], whole)
        if newline < 0 && length < len(out) {
            out[length] = '\n'
            length += 1
        }
    }
    return string(out[:length])
}
