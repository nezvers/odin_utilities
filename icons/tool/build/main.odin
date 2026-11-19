package main

// Builds the icon font of the icons library from the Lucide sprite sheet:
//
//     odin run icons/tool/build                (from odin_utilities; `odin run tool/build` in the icons folder)
//
// reads icons/lucide/sprite.svg and the names in icons/lucide/icons.txt and writes icons/lucide.ttf (one glyph per icon from U+E000 on, the strokes of the icons as filled
// outlines) and icons/lucide_icons.odin (the enum of the icons, in the order of the list). Add a name to icons.txt and run it again; new names go at the end, so the characters
// of the icons that were there stay.
//
// A line of icons.txt is the id of an icon in the sprite, or `name = id` when the enum should say something else than the sprite does. A `#` starts a comment.

import "core:encoding/xml"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import icons "../.."

// The files are found from where this source file is, so the tool runs from any folder
ICONS :: #directory + "/../../"
SPRITE :: ICONS + "lucide/sprite.svg"
LIST :: ICONS + "lucide/icons.txt"
FONT_OUT :: ICONS + "lucide.ttf"
ENUM_OUT :: ICONS + "lucide_icons.odin"

// The numbers of the font are constants of the library (icons.odin): a program that draws the glyphs needs the same ones
STROKE_WIDTH :: f32(2)                  // the line of Lucide in its box of 24

attribute :: proc(element: ^xml.Element, key: string) -> (value: string, found: bool) {
    for a in element.attribs {
        if a.key == key { return a.val, true }
    }
    return "", false
}

number :: proc(element: ^xml.Element, key: string, fallback: f64 = 0) -> f64 {
    if text, found := attribute(element, key); found {
        value, _ := strconv.parse_f64(text)
        return value
    }
    return fallback
}

// A shape of the sprite as path data: paths are taken as they are, the basic shapes become moves, lines and arcs
shapePath :: proc(element: ^xml.Element) -> string {
    switch element.ident {
    case "path":
        d, _ := attribute(element, "d")
        return d
    case "circle":
        cx, cy, r: f64 = number(element, "cx"), number(element, "cy"), number(element, "r")
        return fmt.tprintf("M%g %gA%g %g 0 1 0 %g %gA%g %g 0 1 0 %g %gZ", cx - r, cy, r, r, cx + r, cy, r, r, cx - r, cy)
    case "ellipse":
        cx, cy, rx, ry: f64 = number(element, "cx"), number(element, "cy"), number(element, "rx"), number(element, "ry")
        return fmt.tprintf("M%g %gA%g %g 0 1 0 %g %gA%g %g 0 1 0 %g %gZ", cx - rx, cy, rx, ry, cx + rx, cy, rx, ry, cx - rx, cy)
    case "rect":
        x, y, w, h: f64 = number(element, "x"), number(element, "y"), number(element, "width"), number(element, "height")
        rx: f64 = number(element, "rx")
        ry: f64 = number(element, "ry", rx)
        rx = min(rx, w / 2)
        ry = min(ry, h / 2)
        if rx <= 0 || ry <= 0 { return fmt.tprintf("M%g %gH%gV%gH%gZ", x, y, x + w, y + h, x) }
        return fmt.tprintf(
            "M%g %gH%gA%g %g 0 0 1 %g %gV%gA%g %g 0 0 1 %g %gH%gA%g %g 0 0 1 %g %gV%gA%g %g 0 0 1 %g %gZ",
            x + rx, y, x + w - rx, rx, ry, x + w, y + ry, y + h - ry, rx, ry, x + w - rx, y + h, x + rx, rx, ry, x, y + h - ry, y + ry, rx, ry, x + rx, y,
        )
    case "line":
        return fmt.tprintf("M%g %gL%g %g", number(element, "x1"), number(element, "y1"), number(element, "x2"), number(element, "y2"))
    case "polyline", "polygon":
        points, _ := attribute(element, "points")
        builder: strings.Builder = strings.builder_make(context.temp_allocator)
        // the numbers of the list are pairs, with spaces or commas between them
        fields: []string = strings.fields_proc(points, proc(r: rune) -> bool { return r == ' ' || r == ',' || r == '\n' || r == '\t' }, context.temp_allocator)
        for i := 0; i + 1 < len(fields); i += 2 {
            fmt.sbprintf(&builder, "%s%s %s", "M" if i == 0 else "L", fields[i], fields[i + 1])
        }
        if element.ident == "polygon" { strings.write_string(&builder, "Z") }
        return strings.to_string(builder)
    }
    return ""
}

// "folder-open" as an enum member: FOLDER_OPEN (N before a digit, which a name cannot start with)
enumName :: proc(name: string) -> string {
    builder: strings.Builder = strings.builder_make()
    if len(name) > 0 && name[0] >= '0' && name[0] <= '9' { strings.write_byte(&builder, 'N') }
    for character in name {
        switch {
        case character == '-':
            strings.write_byte(&builder, '_')
        case character >= 'a' && character <= 'z':
            strings.write_rune(&builder, character - 32)
        case:
            strings.write_rune(&builder, character)
        }
    }
    return strings.to_string(builder)
}

main :: proc() {
    document, xml_error := xml.load_from_file(SPRITE)
    if xml_error != .None {
        fmt.eprintln("cannot read", SPRITE, xml_error)
        os.exit(1)
    }
    list_bytes, list_error := os.read_entire_file(LIST, context.allocator)
    if list_error != nil {
        fmt.eprintln("cannot read", LIST)
        os.exit(1)
    }
    names: [dynamic]string          // what the enum says
    ids: [dynamic]string            // what the sprite calls it
    for line in strings.split_lines(string(list_bytes)) {
        text: string = strings.trim_space(line)
        if text == "" || strings.has_prefix(text, "#") { continue }
        name, id: string = text, text
        if equals := strings.index_byte(text, '='); equals >= 0 {
            name = strings.trim_space(text[:equals])
            id = strings.trim_space(text[equals + 1:])
        }
        append(&names, name)
        append(&ids, id)
    }
    symbols: map[string]xml.Element_ID
    for element, id in document.elements {
        if element.kind != .Element || element.ident != "symbol" { continue }
        if symbol_id, found := attribute(&document.elements[id], "id"); found { symbols[symbol_id] = xml.Element_ID(id) }
    }

    // the outlines of all icons, one after the other
    all_segments: [dynamic]icons.Segment
    all_ends: [dynamic]int
    ranges: [dynamic][4]int         // per glyph: the first segment, one past the last, the first end, one past the last
    path: []icons.PathSegment = make([]icons.PathSegment, 4096)
    room: []icons.Segment = make([]icons.Segment, 16384)
    segments: []icons.Segment = make([]icons.Segment, 65536)
    ends: []int = make([]int, 4096)
    missing: int
    for name, i in names {
        symbol, found := symbols[ids[i]]
        if !found {
            fmt.eprintln("no such icon in the sprite:", ids[i])
            missing += 1
            continue
        }
        outline: icons.Outline
        icons.OutlineInit(&outline, segments, ends)
        for value in document.elements[symbol].value {
            child, is_element := value.(xml.Element_ID)
            if !is_element || document.elements[child].kind != .Element { continue }
            element: ^xml.Element = &document.elements[child]
            count, parsed := icons.SvgPathParse(shapePath(element), path)
            if !parsed {
                fmt.eprintfln("%s: a shape (%s) is not understood", name, element.ident)
                missing += 1
                continue
            }
            // a shape with a fill is filled and has its outline stroked as well, as every shape of the sprite
            if fill, has_fill := attribute(element, "fill"); has_fill && fill != "none" { icons.FillPath(path[:count], room, &outline) }
            icons.StrokePath(path[:count], STROKE_WIDTH, room, &outline)
            free_all(context.temp_allocator)
        }
        if !outline.ok {
            fmt.eprintfln("%s: too many curves", name)
            missing += 1
            continue
        }
        // into the units of the font: the box of 24 is the em, y up, the bottom of the box at the descent
        first_segment: int = len(all_segments)
        first_end: int = len(all_ends)
        scale: f32 = f32(icons.ICON_UNITS_PER_EM) / icons.ICON_GRID
        for segment in outline.segments[:outline.count] {
            place :: proc(p: icons.Vec2, scale: f32) -> icons.Vec2 {
                return {p.x * scale, (icons.ICON_GRID - p.y) * scale + f32(icons.ICON_DESCENT)}
            }
            append(&all_segments, icons.Segment{p0 = place(segment.p0, scale), p1 = place(segment.p1, scale), p2 = place(segment.p2, scale), line = segment.line})
        }
        for end in outline.ends[:outline.end_count] { append(&all_ends, end) }
        append(&ranges, [4]int{first_segment, len(all_segments), first_end, len(all_ends)})
    }
    if missing > 0 { os.exit(1) }

    glyphs: []icons.FontGlyph = make([]icons.FontGlyph, len(ranges))
    most_segments: int
    for range, i in ranges {
        glyphs[i] = {segments = all_segments[range[0]:range[1]], ends = all_ends[range[2]:range[3]]}
        most_segments = max(most_segments, range[1] - range[0])
    }
    description: icons.FontDescription = {
        family = "Lucide Icons (odin_utilities)",
        version = "Version 1.44, built by odin_utilities/icons from lucide-static 1.44.0",
        copyright = "Copyright (c) Lucide Icons and Contributors. Icons derived from Feather: Copyright (c) 2013-present Cole Bemis.",
        license = "ISC License (Lucide), MIT License (the icons derived from Feather). The full texts are in icons/lucide/LICENSE of odin_utilities.",
        license_url = "https://lucide.dev/license",
        units_per_em = icons.ICON_UNITS_PER_EM,
        ascent = icons.ICON_ASCENT,
        descent = icons.ICON_DESCENT,
        first_character = icons.ICON_FIRST_CHARACTER,
    }
    file: []u8 = make([]u8, 16 * 1024 * 1024)
    size, written := icons.FontWrite(glyphs, description, file, make([]icons.FontPoint, 65536), make([]int, 4096))
    if !written {
        fmt.eprintln("the font does not fit")
        os.exit(1)
    }
    if os.write_entire_file(FONT_OUT, file[:size]) != nil {
        fmt.eprintln("cannot write", FONT_OUT)
        os.exit(1)
    }

    builder: strings.Builder = strings.builder_make()
    fmt.sbprintln(&builder, "package icons")
    fmt.sbprintln(&builder, "")
    fmt.sbprintln(&builder, "// Generated by icons/tool/build from icons/lucide/sprite.svg and icons/lucide/icons.txt: do not edit, add a name to icons.txt and run the tool.")
    fmt.sbprintln(&builder, "// The icons are Lucide (ISC License, Copyright (c) Lucide Icons and Contributors) with icons derived from Feather (MIT License, Copyright (c) 2013-present")
    fmt.sbprintln(&builder, "// Cole Bemis): icons/lucide/LICENSE. An icon is the glyph at ICON_FIRST_CHARACTER + its number - 1 of lucide.ttf (IconRune).")
    fmt.sbprintln(&builder, "")
    fmt.sbprintln(&builder, "Icon :: enum u16 {")
    fmt.sbprintln(&builder, "    NONE,")
    for name in names { fmt.sbprintfln(&builder, "    %s,", enumName(name)) }
    fmt.sbprintln(&builder, "}")
    fmt.sbprintln(&builder, "")
    fmt.sbprintln(&builder, "// The names the icons have in the list (and on lucide.dev)")
    fmt.sbprintln(&builder, "@(rodata)")
    fmt.sbprintln(&builder, "ICON_NAMES := [Icon]string {")
    fmt.sbprintln(&builder, "    .NONE = \"\",")
    for name in names { fmt.sbprintfln(&builder, "    .%s = %q,", enumName(name), name) }
    fmt.sbprintln(&builder, "}")
    if os.write_entire_file(ENUM_OUT, transmute([]u8)strings.to_string(builder)) != nil {
        fmt.eprintln("cannot write", ENUM_OUT)
        os.exit(1)
    }
    fmt.printfln("%d icons, %d curves (%d in the biggest), lucide.ttf: %d bytes", len(names), len(all_segments), most_segments, size)
}
