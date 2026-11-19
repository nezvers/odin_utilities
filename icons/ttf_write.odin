package icons

// Writes a TrueType font file from outlines: one glyph per outline, every glyph as wide as the em, the characters one after the other from a first one (the private use area for
// icons). The file has the tables a font needs to be read by a parser (odin_utilities/font, stb_truetype, Karl2D, raylib) and by an operating system: head, hhea, maxp, OS/2, hmtx,
// cmap (formats 4 and 12), loca, glyf, name, post. Nothing is allocated: the file is written into the bytes of the caller.
//
// Contours may overlap (the glyphs are flagged for it): an outline of StrokePath goes in as it is.

FontGlyph :: struct {
    segments: []Segment,        // font units, y up
    ends: []int,                // where each contour ends in `segments`
}

FontDescription :: struct {
    family: string,             // "Lucide"
    version: string,            // "Version 1.44"
    copyright: string,
    license: string,
    license_url: string,
    units_per_em: int,
    ascent: int,                // above the baseline
    descent: int,               // below it: negative
    first_character: rune,      // the character of the first glyph
}

// A point of a glyph as the file stores it
FontPoint :: struct {
    x, y: i16,
    on_curve: bool,
}

@(private)
FontWriter :: struct {
    data: []u8,
    at: int,
    ok: bool,
}

@(private)
fontPut8 :: proc(writer: ^FontWriter, value: int) {
    if writer.at >= len(writer.data) {
        writer.ok = false
        writer.at += 1
        return
    }
    writer.data[writer.at] = u8(value)
    writer.at += 1
}

@(private)
fontPut16 :: proc(writer: ^FontWriter, value: int) {
    fontPut8(writer, value >> 8)
    fontPut8(writer, value)
}

@(private)
fontPut32 :: proc(writer: ^FontWriter, value: int) {
    fontPut16(writer, value >> 16)
    fontPut16(writer, value)
}

@(private)
fontPutAt16 :: proc(writer: ^FontWriter, at: int, value: int) {
    if at + 2 > len(writer.data) { return }
    writer.data[at] = u8(value >> 8)
    writer.data[at + 1] = u8(value)
}

@(private)
fontPutAt32 :: proc(writer: ^FontWriter, at: int, value: int) {
    fontPutAt16(writer, at, value >> 16)
    fontPutAt16(writer, at + 2, value)
}

// Tables start at a multiple of four bytes
@(private)
fontPad :: proc(writer: ^FontWriter) {
    for writer.at % 4 != 0 { fontPut8(writer, 0) }
}

@(private)
fontChecksum :: proc(data: []u8) -> u32 {
    sum: u32
    for i := 0; i < len(data); i += 4 {
        word: u32
        for k in 0 ..< 4 {
            word <<= 8
            if i + k < len(data) { word |= u32(data[i + k]) }
        }
        sum += word
    }
    return sum
}

// The points of one glyph into `points`: the contours the other way round (in a font file the inside is on the right of a contour with y up, the outline has it on the right
// with y down), pieces that are shorter than a font unit dropped. `contour_ends` gets the index of the last point of every contour.
@(private)
fontGlyphPoints :: proc(glyph: FontGlyph, points: []FontPoint, contour_ends: []int) -> (point_count: int, contour_count: int, ok: bool) {
    round :: proc(value: f32) -> i16 {
        return i16(clamp(int(value + 0.5 if value >= 0 else value - 0.5), -32768, 32767))
    }
    first: int
    for end in glyph.ends {
        contour_start: int = point_count
        // backwards: every piece gives its end point (where it starts when it is walked the other way) and its control point (a curve); it ends where the next one written starts
        for i := end - 1; i >= first; i -= 1 {
            segment: Segment = glyph.segments[i]
            start: FontPoint = {round(segment.p0.x), round(segment.p0.y), true}
            control: FontPoint = {round(segment.p1.x), round(segment.p1.y), false}
            finish: FontPoint = {round(segment.p2.x), round(segment.p2.y), true}
            if start.x == finish.x && start.y == finish.y { continue }
            needed: int = 1 if segment.line else 2
            if point_count + needed > len(points) { return point_count, contour_count, false }
            points[point_count] = finish
            point_count += 1
            if !segment.line {
                points[point_count] = control
                point_count += 1
            }
        }
        first = end
        // less than a triangle is nothing to fill
        if point_count - contour_start < 3 {
            point_count = contour_start
            continue
        }
        if contour_count >= len(contour_ends) { return point_count, contour_count, false }
        contour_ends[contour_count] = point_count - 1
        contour_count += 1
    }
    return point_count, contour_count, true
}

@(private)
fontPutName :: proc(writer: ^FontWriter, text: string) -> (length: int) {
    // UTF-16, big endian (the characters of the names here are in the basic plane)
    for character in text {
        fontPut16(writer, int(character) if character < 0x10000 else '?')
        length += 2
    }
    return
}

// Writes the font into `out`. `points` and `contour_ends` are working room for one glyph (its points and contours). `size` is the length of the file; `ok` is false when
// `out` or the room is too small, or a glyph has more points than a font may have.
FontWrite :: proc(glyphs: []FontGlyph, description: FontDescription, out: []u8, points: []FontPoint, contour_ends: []int) -> (size: int, ok: bool) {
    TABLES :: 10
    writer: FontWriter = {data = out, ok = true}
    glyph_count: int = len(glyphs) + 1                  // glyph 0 is the empty "missing glyph"
    if glyph_count > 0xffff { return 0, false }
    units: int = description.units_per_em
    first_character: int = int(description.first_character)
    last_character: int = first_character + len(glyphs) - 1

    Table :: struct {
        tag: string,
        offset: int,
        length: int,
    }
    tables: [TABLES]Table
    begin :: proc(writer: ^FontWriter, table: ^Table, tag: string) {
        fontPad(writer)
        table.tag = tag
        table.offset = writer.at
    }
    finish :: proc(writer: ^FontWriter, table: ^Table) {
        table.length = writer.at - table.offset
    }

    // the directory is written at the end, when the lengths and checksums are known
    writer.at = 12 + 16 * TABLES

    // head, hhea, maxp: their numbers come from the glyphs, they are filled in below
    head: ^Table = &tables[3]
    begin(&writer, head, "head")
    for _ in 0 ..< 54 { fontPut8(&writer, 0) }
    finish(&writer, head)
    hhea: ^Table = &tables[4]
    begin(&writer, hhea, "hhea")
    for _ in 0 ..< 36 { fontPut8(&writer, 0) }
    finish(&writer, hhea)
    maxp: ^Table = &tables[7]
    begin(&writer, maxp, "maxp")
    for _ in 0 ..< 32 { fontPut8(&writer, 0) }
    finish(&writer, maxp)

    os2: ^Table = &tables[0]
    begin(&writer, os2, "OS/2")
    fontPut16(&writer, 4)                               // version
    fontPut16(&writer, units)                           // average width
    fontPut16(&writer, 400)                             // weight: regular
    fontPut16(&writer, 5)                               // width: normal
    fontPut16(&writer, 0)                               // embedding: no restriction
    for _ in 0 ..< 10 { fontPut16(&writer, 0) }         // subscript, superscript, strikeout
    fontPut16(&writer, 0)                               // family class
    for _ in 0 ..< 10 { fontPut8(&writer, 0) }          // panose
    fontPut32(&writer, 0)                               // Unicode ranges: the private use area is bit 60
    fontPut32(&writer, 1 << 28)
    fontPut32(&writer, 0)
    fontPut32(&writer, 0)
    fontPut8(&writer, ' ')                              // vendor
    fontPut8(&writer, ' ')
    fontPut8(&writer, ' ')
    fontPut8(&writer, ' ')
    fontPut16(&writer, 0x40)                            // selection: regular
    fontPut16(&writer, min(first_character, 0xffff))
    fontPut16(&writer, min(last_character, 0xffff))
    fontPut16(&writer, description.ascent)              // typographic ascender, descender, line gap
    fontPut16(&writer, description.descent)
    fontPut16(&writer, 0)
    fontPut16(&writer, description.ascent)              // the Windows ascent and descent (both positive)
    fontPut16(&writer, -description.descent)
    fontPut32(&writer, 0)                               // code pages
    fontPut32(&writer, 0)
    fontPut16(&writer, description.ascent / 2)          // x height
    fontPut16(&writer, description.ascent)              // cap height
    fontPut16(&writer, 0)                               // default character
    fontPut16(&writer, 0x20)                            // break character
    fontPut16(&writer, 0)                               // longest context
    finish(&writer, os2)

    // hmtx: one advance for every glyph (the em), then the left side bearing of the others
    hmtx: ^Table = &tables[5]
    begin(&writer, hmtx, "hmtx")
    fontPut16(&writer, units)
    fontPut16(&writer, 0)
    hmtx_bearings: int = writer.at
    for _ in 1 ..< glyph_count { fontPut16(&writer, 0) }
    finish(&writer, hmtx)

    cmap: ^Table = &tables[1]
    begin(&writer, cmap, "cmap")
    basic_plane: bool = last_character < 0xffff
    fontPut16(&writer, 0)
    fontPut16(&writer, 2 if basic_plane else 1)
    if basic_plane {
        fontPut16(&writer, 3)                           // Windows, Unicode basic plane
        fontPut16(&writer, 1)
        fontPut32(&writer, 4 + 8 * 2)
    }
    fontPut16(&writer, 3)                               // Windows, all of Unicode
    fontPut16(&writer, 10)
    fontPut32(&writer, 4 + 8 * (2 if basic_plane else 1) + (32 if basic_plane else 0))
    if basic_plane {
        // format 4: the segment of the characters and the one that ends the table
        fontPut16(&writer, 4)
        fontPut16(&writer, 32)                          // length
        fontPut16(&writer, 0)                           // language
        fontPut16(&writer, 4)                           // segments * 2
        fontPut16(&writer, 4)                           // search range
        fontPut16(&writer, 1)                           // entry selector
        fontPut16(&writer, 0)                           // range shift
        fontPut16(&writer, last_character)              // the ends
        fontPut16(&writer, 0xffff)
        fontPut16(&writer, 0)
        fontPut16(&writer, first_character)             // the starts
        fontPut16(&writer, 0xffff)
        fontPut16(&writer, (1 - first_character) & 0xffff)      // what is added to a character to get its glyph
        fontPut16(&writer, 1)
        fontPut16(&writer, 0)                           // no glyph arrays
        fontPut16(&writer, 0)
    }
    fontPut16(&writer, 12)                              // format 12: one group
    fontPut16(&writer, 0)
    fontPut32(&writer, 16 + 12)
    fontPut32(&writer, 0)
    fontPut32(&writer, 1)
    fontPut32(&writer, first_character)
    fontPut32(&writer, last_character)
    fontPut32(&writer, 1)
    finish(&writer, cmap)

    // loca: where every glyph is in glyf, and one more for the end
    loca: ^Table = &tables[6]
    begin(&writer, loca, "loca")
    loca_at: int = writer.at
    for _ in 0 ..= glyph_count { fontPut32(&writer, 0) }
    finish(&writer, loca)

    glyf: ^Table = &tables[2]
    begin(&writer, glyf, "glyf")
    font_low: [2]int = {32767, 32767}
    font_high: [2]int = {-32768, -32768}
    most_points, most_contours: int
    least_left, least_right, most_right: int = 32767, 32767, -32768
    fontPutAt32(&writer, loca_at, 0)
    fontPutAt32(&writer, loca_at + 4, 0)                // the missing glyph has no outline
    for glyph, index in glyphs {
        point_count, contour_count, fits := fontGlyphPoints(glyph, points, contour_ends)
        if !fits || point_count > 0xffff { return 0, false }
        if contour_count > 0 {
            low: [2]int = {32767, 32767}
            high: [2]int = {-32768, -32768}
            for point in points[:point_count] {
                low = {min(low.x, int(point.x)), min(low.y, int(point.y))}
                high = {max(high.x, int(point.x)), max(high.y, int(point.y))}
            }
            font_low = {min(font_low.x, low.x), min(font_low.y, low.y)}
            font_high = {max(font_high.x, high.x), max(font_high.y, high.y)}
            most_points = max(most_points, point_count)
            most_contours = max(most_contours, contour_count)
            least_left = min(least_left, low.x)
            least_right = min(least_right, units - high.x)
            most_right = max(most_right, high.x)
            fontPutAt16(&writer, hmtx_bearings + 2 * index, low.x)

            fontPut16(&writer, contour_count)
            fontPut16(&writer, low.x)
            fontPut16(&writer, low.y)
            fontPut16(&writer, high.x)
            fontPut16(&writer, high.y)
            for end in contour_ends[:contour_count] { fontPut16(&writer, end) }
            fontPut16(&writer, 0)                       // no instructions
            // the flags of every point, then every x, then every y: a step of 0 takes no byte, a small one a byte and its sign in the flag
            ON_CURVE :: 1
            X_BYTE :: 2
            Y_BYTE :: 4
            X_SAME_OR_POSITIVE :: 16
            Y_SAME_OR_POSITIVE :: 32
            OVERLAP :: 64
            before: FontPoint
            for point, i in points[:point_count] {
                flag: int = ON_CURVE if point.on_curve else 0
                if i == 0 { flag |= OVERLAP }
                dx: int = int(point.x) - int(before.x)
                dy: int = int(point.y) - int(before.y)
                if dx == 0 {
                    flag |= X_SAME_OR_POSITIVE
                } else if abs(dx) <= 255 {
                    flag |= X_BYTE | (X_SAME_OR_POSITIVE if dx > 0 else 0)
                }
                if dy == 0 {
                    flag |= Y_SAME_OR_POSITIVE
                } else if abs(dy) <= 255 {
                    flag |= Y_BYTE | (Y_SAME_OR_POSITIVE if dy > 0 else 0)
                }
                fontPut8(&writer, flag)
                before = point
            }
            before = {}
            for point in points[:point_count] {
                dx: int = int(point.x) - int(before.x)
                if dx != 0 {
                    if abs(dx) <= 255 {
                        fontPut8(&writer, abs(dx))
                    } else {
                        fontPut16(&writer, dx)
                    }
                }
                before = point
            }
            before = {}
            for point in points[:point_count] {
                dy: int = int(point.y) - int(before.y)
                if dy != 0 {
                    if abs(dy) <= 255 {
                        fontPut8(&writer, abs(dy))
                    } else {
                        fontPut16(&writer, dy)
                    }
                }
                before = point
            }
            fontPad(&writer)
        }
        fontPutAt32(&writer, loca_at + 4 * (index + 2), writer.at - glyf.offset)
    }
    finish(&writer, glyf)
    if font_low.x > font_high.x {
        font_low, font_high = {}, {}
        least_left, least_right, most_right = 0, 0, 0
    }

    // name: the names an operating system shows, and who made the pictures
    name: ^Table = &tables[8]
    begin(&writer, name, "name")
    postscript: string = description.family
    names: [9]struct { id: int, text: string } = {
        {0, description.copyright},
        {1, description.family},
        {2, "Regular"},
        {3, description.family},
        {4, description.family},
        {5, description.version},
        {6, postscript},
        {13, description.license},
        {14, description.license_url},
    }
    fontPut16(&writer, 0)
    fontPut16(&writer, len(names))
    fontPut16(&writer, 6 + 12 * len(names))
    records_at: int = writer.at
    for _ in 0 ..< len(names) * 12 { fontPut8(&writer, 0) }
    strings_at: int = writer.at
    for entry, i in names {
        offset: int = writer.at - strings_at
        length: int = fontPutName(&writer, entry.text)
        record: int = records_at + 12 * i
        fontPutAt16(&writer, record, 3)                 // Windows, Unicode, English
        fontPutAt16(&writer, record + 2, 1)
        fontPutAt16(&writer, record + 4, 0x409)
        fontPutAt16(&writer, record + 6, entry.id)
        fontPutAt16(&writer, record + 8, length)
        fontPutAt16(&writer, record + 10, offset)
    }
    finish(&writer, name)

    post: ^Table = &tables[9]
    begin(&writer, post, "post")
    fontPut32(&writer, 0x00030000)                      // no glyph names
    fontPut32(&writer, 0)                               // upright
    fontPut16(&writer, -units / 10)                     // underline
    fontPut16(&writer, units / 20)
    fontPut32(&writer, 1)                               // every glyph is as wide
    for _ in 0 ..< 4 { fontPut32(&writer, 0) }
    finish(&writer, post)
    fontPad(&writer)
    size = writer.at
    if !writer.ok { return size, false }

    // head
    at: int = head.offset
    fontPutAt32(&writer, at, 0x00010000)                // version
    fontPutAt32(&writer, at + 4, 0x00010000)            // revision
    fontPutAt32(&writer, at + 12, 0x5F0F3CF5)           // the magic number
    fontPutAt16(&writer, at + 16, 0x000B)               // baseline at 0, left side bearing at 0, whole pixel sizes
    fontPutAt16(&writer, at + 18, units)
    // created and modified stay 0: the same input gives the same file
    fontPutAt16(&writer, at + 36, font_low.x)
    fontPutAt16(&writer, at + 38, font_low.y)
    fontPutAt16(&writer, at + 40, font_high.x)
    fontPutAt16(&writer, at + 42, font_high.y)
    fontPutAt16(&writer, at + 46, 8)                    // the smallest size that reads
    fontPutAt16(&writer, at + 48, 2)
    fontPutAt16(&writer, at + 50, 1)                    // loca has 32 bit places
    // hhea
    at = hhea.offset
    fontPutAt32(&writer, at, 0x00010000)
    fontPutAt16(&writer, at + 4, description.ascent)
    fontPutAt16(&writer, at + 6, description.descent)
    fontPutAt16(&writer, at + 10, units)                // the widest advance
    fontPutAt16(&writer, at + 12, least_left)
    fontPutAt16(&writer, at + 14, least_right)
    fontPutAt16(&writer, at + 16, most_right)
    fontPutAt16(&writer, at + 18, 1)                    // an upright caret
    fontPutAt16(&writer, at + 34, 1)                    // one advance in hmtx
    // maxp
    at = maxp.offset
    fontPutAt32(&writer, at, 0x00010000)
    fontPutAt16(&writer, at + 4, glyph_count)
    fontPutAt16(&writer, at + 6, most_points)
    fontPutAt16(&writer, at + 8, most_contours)
    fontPutAt16(&writer, at + 14, 2)                    // zones

    // the directory (the tables are in the order of their tags already) and the checksums
    fontPutAt32(&writer, 0, 0x00010000)
    fontPutAt16(&writer, 4, TABLES)
    fontPutAt16(&writer, 6, 128)                        // 16 times the largest power of two under the number of tables
    fontPutAt16(&writer, 8, 3)
    fontPutAt16(&writer, 10, 16 * TABLES - 128)
    for table, i in tables {
        entry: int = 12 + 16 * i
        for k in 0 ..< 4 { out[entry + k] = table.tag[k] }
        fontPutAt32(&writer, entry + 4, int(fontChecksum(out[table.offset:table.offset + table.length])))
        fontPutAt32(&writer, entry + 8, table.offset)
        fontPutAt32(&writer, entry + 12, table.length)
    }
    fontPutAt32(&writer, head.offset + 8, int(0xB1B0AFBA - fontChecksum(out[:size])))
    return size, true
}
