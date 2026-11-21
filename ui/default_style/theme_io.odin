package ui_default

// A Theme as text and back, for styles that are saved and loaded (the files of ui/styles, the style editor): one line for each field, `name = value`, colors as `#rrggbbaa`, numbers as
// they are, a bool as true or false. The fields are found by reflection, so a field that is added to Theme is saved, loaded and editable without a change here. Lines that start with `#` or `//` and
// empty lines are comments; a name that Theme does not have, or a value that does not read, is skipped (and counted): a file of an older or a newer version still loads what it can, the fields
// it does not have keep what the theme had.
//
//     text := ui_default.ThemeText(&theme, buffer[:])          // into a caller's buffer (about 2 KB)
//     applied, skipped := ui_default.ThemeParse(text, &theme)

import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"
import ui ".."

// How a field is edited: the kind of its type
ThemeFieldKind :: enum u8 {
    NONE,       // a type that the text format does not carry
    COLOR,
    NUMBER,
    FLAG,
}

// How many fields Theme has and what the i-th one is: its name, its kind and where it is in the Theme (a pointer to read and write it). For a style editor.
ThemeFieldCount :: proc() -> int {
    return len(reflect.struct_field_names(Theme))
}

ThemeFieldName :: proc(index: int) -> string {
    return reflect.struct_field_names(Theme)[index]
}

ThemeFieldKindOf :: proc(index: int) -> ThemeFieldKind {
    id: typeid = reflect.struct_field_types(Theme)[index].id
    switch {
    case id == ui.Color: return .COLOR
    case id == f32: return .NUMBER
    case id == bool: return .FLAG
    }
    return .NONE
}

ThemeFieldColor :: proc(theme: ^Theme, index: int) -> ^ui.Color {
    return cast(^ui.Color)(uintptr(theme) + reflect.struct_field_offsets(Theme)[index])
}

ThemeFieldNumber :: proc(theme: ^Theme, index: int) -> ^f32 {
    return cast(^f32)(uintptr(theme) + reflect.struct_field_offsets(Theme)[index])
}

ThemeFieldFlag :: proc(theme: ^Theme, index: int) -> ^bool {
    return cast(^bool)(uintptr(theme) + reflect.struct_field_offsets(Theme)[index])
}

// The index of a field by name, -1 when Theme has none
ThemeFieldFind :: proc(name: string) -> int {
    names: []string = reflect.struct_field_names(Theme)
    for field, i in names {
        if field == name { return i }
    }
    return -1
}

// The theme as text in `out` (nothing allocates; cut at the end of the buffer). The text of a theme that was read is the same text again.
ThemeText :: proc(theme: ^Theme, out: []u8) -> string {
    length: int
    put :: proc(out: []u8, length: ^int, text: string) {
        count: int = min(len(text), len(out) - length^)
        copy(out[length^:], text[:count])
        length^ += count
    }
    scratch: [48]u8
    for i in 0 ..< ThemeFieldCount() {
        put(out, &length, ThemeFieldName(i))
        put(out, &length, " = ")
        switch ThemeFieldKindOf(i) {
        case .COLOR:
            color: ui.Color = ThemeFieldColor(theme, i)^
            put(out, &length, fmt.bprintf(scratch[:], "#%02x%02x%02x%02x", color.r, color.g, color.b, color.a))
        case .NUMBER:
            number: string = strconv.write_float(scratch[:], f64(ThemeFieldNumber(theme, i)^), 'g', 6, 32)
            put(out, &length, number[1:] if len(number) > 1 && number[0] == '+' else number)
        case .FLAG:
            put(out, &length, "true" if ThemeFieldFlag(theme, i)^ else "false")
        case .NONE:
        }
        put(out, &length, "\n")
    }
    return string(out[:length])
}

// Reads the text into `theme`: only the fields that the text has are changed. `applied` counts the lines that set a field, `skipped` the lines that did not (a name that is not a field, a value that
// does not read).
ThemeParse :: proc(text: string, theme: ^Theme) -> (applied: int, skipped: int) {
    rest: string = text
    for len(rest) > 0 {
        line: string
        newline: int = strings.index_byte(rest, '\n')
        if newline < 0 {
            line, rest = rest, ""
        } else {
            line, rest = rest[:newline], rest[newline + 1:]
        }
        line = strings.trim_space(line)
        if line == "" || line[0] == '#' || strings.has_prefix(line, "//") { continue }
        equals: int = strings.index_byte(line, '=')
        if equals < 0 {
            skipped += 1
            continue
        }
        name: string = strings.trim_space(line[:equals])
        value: string = strings.trim_space(line[equals + 1:])
        index: int = ThemeFieldFind(name)
        if index < 0 {
            skipped += 1
            continue
        }
        ok: bool
        switch ThemeFieldKindOf(index) {
        case .COLOR:
            color: ui.Color
            color, ok = themeParseColor(value)
            if ok { ThemeFieldColor(theme, index)^ = color }
        case .NUMBER:
            number: f64
            number, ok = strconv.parse_f64(value)
            if ok { ThemeFieldNumber(theme, index)^ = f32(number) }
        case .FLAG:
            if value == "true" || value == "false" {
                ThemeFieldFlag(theme, index)^ = value == "true"
                ok = true
            }
        case .NONE:
        }
        if ok { applied += 1 } else { skipped += 1 }
    }
    return
}

// `#rrggbb` or `#rrggbbaa`
@(private)
themeParseColor :: proc(text: string) -> (color: ui.Color, ok: bool) {
    if len(text) != 7 && len(text) != 9 { return {}, false }
    if text[0] != '#' { return {}, false }
    values: [4]u8 = {0, 0, 0, 255}
    for i in 0 ..< (len(text) - 1) / 2 {
        high, high_ok := themeHexDigit(text[1 + i * 2])
        low, low_ok := themeHexDigit(text[2 + i * 2])
        if !high_ok || !low_ok { return {}, false }
        values[i] = u8(high * 16 + low)
    }
    return values, true
}

@(private)
themeHexDigit :: proc(character: u8) -> (value: int, ok: bool) {
    switch character {
    case '0' ..= '9': return int(character - '0'), true
    case 'a' ..= 'f': return int(character - 'a') + 10, true
    case 'A' ..= 'F': return int(character - 'A') + 10, true
    }
    return 0, false
}
