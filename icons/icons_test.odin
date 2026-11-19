#+build !js
package icons

// Tests of the package. They are in one file and not at the bottom of the tested ones because they share helpers, and the last ones read the font file back with the parser of
// odin_utilities/font (a library of its own: the icons package does not need it).

import "core:math"
import "core:testing"
import vector_font "../font"

// Twice the area the contours of an outline go around, added up: negative for an inside on the right. The area under a quadratic is exact: the triangle of its ends and
// two thirds of the triangle to its control point.
@(private = "file")
outlineArea2 :: proc(outline: ^Outline) -> f32 {
    area: f32
    for segment in outline.segments[:outline.count] {
        area += cross2(segment.p0, segment.p2)
        if !segment.line { area += (cross2(segment.p0, segment.p1) + cross2(segment.p1, segment.p2) - cross2(segment.p0, segment.p2)) * 2 / 3 }
    }
    return area
}

// Every contour is closed: a piece starts where the one before ended, the first where the last ended
@(private = "file")
outlineIsClosed :: proc(outline: ^Outline) -> bool {
    first: int
    for end in outline.ends[:outline.end_count] {
        for i in first ..< end {
            before: Segment = outline.segments[end - 1 if i == first else i - 1]
            if length2(outline.segments[i].p0 - before.p2) > 1e-4 { return false }
        }
        first = end
    }
    return first == outline.count
}

@(test)
test_path_commands_come_out_absolute :: proc(t: ^testing.T) {
    out: [32]PathSegment
    // a move, more pairs after it (lines), relative steps, the short forms and a close
    count, ok := SvgPathParse("M2 3 4 5l1 1H10v2h-3V1z", out[:])
    testing.expect(t, ok)
    testing.expect_value(t, count, 8)
    testing.expect_value(t, out[0], PathSegment{kind = .MOVE, p = {{2, 3}, {}, {}}})
    testing.expect_value(t, out[1], PathSegment{kind = .LINE, p = {{4, 5}, {}, {}}})
    testing.expect_value(t, out[2].p[0], Vec2{5, 6})
    testing.expect_value(t, out[3].p[0], Vec2{10, 6})
    testing.expect_value(t, out[4].p[0], Vec2{10, 8})
    testing.expect_value(t, out[5].p[0], Vec2{7, 8})
    testing.expect_value(t, out[6].p[0], Vec2{7, 1})
    testing.expect_value(t, out[7].kind, SegmentKind.CLOSE)

    // numbers without anything between them: a sign or a second point starts the next one
    count, ok = SvgPathParse("M1.5.5-2-3 1e1-1E-1", out[:])
    testing.expect(t, ok)
    testing.expect_value(t, count, 3)
    testing.expect_value(t, out[0].p[0], Vec2{1.5, 0.5})
    testing.expect_value(t, out[1].p[0], Vec2{-2, -3})
    testing.expect_value(t, out[2].p[0], Vec2{10, -0.1})

    // curves: S and T mirror the control point of the curve before, and only of a curve of their kind
    count, ok = SvgPathParse("M0 0C1 2 3 2 4 0S7 -2 8 0Q9 3 10 0T12 0", out[:])
    testing.expect(t, ok)
    testing.expect_value(t, count, 5)
    testing.expect_value(t, out[2], PathSegment{kind = .CUBIC, p = {{5, -2}, {7, -2}, {8, 0}}})
    testing.expect_value(t, out[3], PathSegment{kind = .QUADRATIC, p = {{9, 3}, {10, 0}, {}}})
    testing.expect_value(t, out[4], PathSegment{kind = .QUADRATIC, p = {{11, -3}, {12, 0}, {}}})
    count, ok = SvgPathParse("M0 0L4 0S7 -2 8 0", out[:])
    testing.expect(t, ok && count == 3)
    testing.expect_value(t, out[2].p[0], Vec2{4, 0})

    // what is not a path, and room that is too small
    _, ok = SvgPathParse("5 5", out[:])
    testing.expect(t, !ok, "a path starts with a command")
    _, ok = SvgPathParse("M1 2 L3", out[:])
    testing.expect(t, !ok, "half a pair")
    _, ok = SvgPathParse("M1 2 X3 4", out[:])
    testing.expect(t, !ok)
    count, ok = SvgPathParse("M0 0L1 1L2 2", out[:2])
    testing.expect(t, !ok && count == 2)
    count, ok = SvgPathParse("", out[:])
    testing.expect(t, ok && count == 0)
}

@(test)
test_an_arc_is_cubics_on_the_circle :: proc(t: ^testing.T) {
    out: [16]PathSegment
    // a circle of radius 5 around (12, 12) as two half turns, the flags written without spaces
    count, ok := SvgPathParse("M7 12a5 5 0 1010 0a5 5 0 10-10 0z", out[:])
    testing.expect(t, ok)
    testing.expect_value(t, count, 6)                           // a move, two cubics per half, a close
    pen: Vec2 = out[0].p[0]
    for segment in out[1:5] {
        testing.expect_value(t, segment.kind, SegmentKind.CUBIC)
        // the middle of every piece is on the circle
        middle: Vec2 = (pen + 3 * segment.p[0] + 3 * segment.p[1] + segment.p[2]) / 8
        distance: f32 = length2(middle - Vec2{12, 12})
        testing.expectf(t, abs(distance - 5) < 0.002, "%v from the center", distance)
        pen = segment.p[2]
    }
    testing.expect_value(t, out[2].p[2], Vec2{17, 12})
    testing.expect_value(t, out[4].p[2], Vec2{7, 12})
    // sweep 1 is clockwise on a screen (y down): from the point on the left over the top
    count, ok = SvgPathParse("M7 12A5 5 0 0 1 17 12", out[:])
    testing.expect(t, ok && count == 3)
    testing.expect(t, out[1].p[2].y < 8, "over the top")
    // radii that are too small for the two points are scaled up to a half circle; a radius of zero is a line
    count, ok = SvgPathParse("M0 0A1 1 0 0 0 10 0", out[:])
    testing.expect(t, ok && count == 3)
    testing.expect(t, abs(abs(out[1].p[2].y) - 5) < 0.001)
    count, ok = SvgPathParse("M0 0A0 5 0 0 0 10 0", out[:])
    testing.expect(t, ok && count == 2 && out[1].kind == .LINE)
}

@(test)
test_a_stroked_line_is_a_bar_with_round_ends :: proc(t: ^testing.T) {
    path: [8]PathSegment
    room: [256]Segment
    segments: [256]Segment
    ends: [8]int
    outline: Outline
    OutlineInit(&outline, segments[:], ends[:])
    count, _ := SvgPathParse("M4 12h16", path[:])
    StrokePath(path[:count], 2, room[:], &outline)
    testing.expect(t, outline.ok)
    testing.expect_value(t, outline.end_count, 1)
    testing.expect(t, outlineIsClosed(&outline))
    // two sides and two half circles of four pieces each
    testing.expect_value(t, outline.count, 10)
    area: f32 = -outlineArea2(&outline) / 2
    // (the arcs are quadratics of 45 degrees: a third of a percent more than the half circles)
    testing.expectf(t, abs(area - (16 * 2 + math.PI)) < 0.02, "the bar and the two half circles: %v", area)
    low: Vec2 = {1e9, 1e9}
    high: Vec2 = {-1e9, -1e9}
    for segment in outline.segments[:outline.count] {
        low = {min(low.x, segment.p0.x), min(low.y, segment.p0.y)}
        high = {max(high.x, segment.p0.x), max(high.y, segment.p0.y)}
    }
    testing.expect(t, abs(low.x - 3) < 1e-4 && abs(high.x - 21) < 1e-4 && abs(low.y - 11) < 1e-4 && abs(high.y - 13) < 1e-4, "a radius around the line")

    // a path of no length is a dot
    OutlineInit(&outline, segments[:], ends[:])
    count, _ = SvgPathParse("M12 12", path[:])
    StrokePath(path[:count], 2, room[:], &outline)
    testing.expect(t, outline.ok && outline.end_count == 1 && outlineIsClosed(&outline))
    testing.expect(t, abs(-outlineArea2(&outline) / 2 - math.PI) < 0.02)
}

@(test)
test_a_stroked_circle_is_a_ring_and_corners_are_round :: proc(t: ^testing.T) {
    path: [32]PathSegment
    room: [1024]Segment
    segments: [1024]Segment
    ends: [8]int
    outline: Outline
    OutlineInit(&outline, segments[:], ends[:])
    count, _ := SvgPathParse("M2 12a10 10 0 1020 0a10 10 0 10-20 0z", path[:])
    StrokePath(path[:count], 2, room[:], &outline)
    testing.expect(t, outline.ok)
    testing.expect_value(t, outline.end_count, 2)               // the outer and the inner edge
    testing.expect(t, outlineIsClosed(&outline))
    // both edges have the ring on their right, so their areas add up to it: pi * (11 * 11 - 9 * 9)
    area: f32 = -outlineArea2(&outline) / 2
    testing.expectf(t, abs(area - 40 * math.PI) < 0.1, "the ring: %v, wanted %v", area, 40 * f32(math.PI))
    for segment in outline.segments[:outline.count] {
        distance: f32 = length2(segment.p2 - Vec2{12, 12})
        testing.expect(t, abs(distance - 11) < 0.01 || abs(distance - 9) < 0.01, "every point is on one of the two edges")
    }

    // a right angle: outside, the corner is an arc around the corner point; inside, the two sides cross (and cover the same place twice, which a nonzero fill does not mind)
    OutlineInit(&outline, segments[:], ends[:])
    count, _ = SvgPathParse("M4 4h8v8", path[:])
    StrokePath(path[:count], 2, room[:], &outline)
    testing.expect(t, outline.ok && outline.end_count == 1 && outlineIsClosed(&outline))
    furthest: f32
    for segment in outline.segments[:outline.count] {
        // nothing of the outline is further than a radius from the path (the bar from (4,4) to (12,4) and the one down to (12,12))
        for point in ([2]Vec2{segment.p0, segment.p2}) {
            to_first: f32 = length2(point - Vec2{clamp(point.x, 4, 12), 4})
            to_second: f32 = length2(point - Vec2{12, clamp(point.y, 4, 12)})
            furthest = max(furthest, min(to_first, to_second))
        }
    }
    testing.expectf(t, abs(furthest - 1) < 0.001, "the outline is a radius from the path: %v", furthest)
}

@(test)
test_a_filled_shape_goes_the_way_the_strokes_go :: proc(t: ^testing.T) {
    path: [16]PathSegment
    room: [256]Segment
    segments: [256]Segment
    ends: [8]int
    // the same square written both ways comes out with the inside on the right: its area is negative
    for data in ([2]string{"M2 2h4v4h-4z", "M2 2v4h4v-4z"}) {
        outline: Outline
        OutlineInit(&outline, segments[:], ends[:])
        count, _ := SvgPathParse(data, path[:])
        FillPath(path[:count], room[:], &outline)
        testing.expect(t, outline.ok && outline.end_count == 1 && outlineIsClosed(&outline))
        testing.expect_value(t, outlineArea2(&outline), -32)
    }
    // room that is too small is told
    outline: Outline
    OutlineInit(&outline, segments[:2], ends[:])
    count, _ := SvgPathParse("M2 2h4v4h-4z", path[:])
    FillPath(path[:count], room[:], &outline)
    testing.expect(t, !outline.ok)
    OutlineInit(&outline, segments[:], ends[:])
    StrokePath(path[:count], 2, room[:4], &outline)
    testing.expect(t, !outline.ok)
}

// The part of a square of the icon grid (x and y from 0 to 24, y down as in the sprite) that an icon of the font covers
@(private = "file")
iconCoverage :: proc(font: ^vector_font.Font, icon: Icon, x: f32, y: f32, side: f32) -> f32 {
    curves: [1024]vector_font.Curve
    pieces: [3072]vector_font.Curve
    count, _ := vector_font.FontGlyphCurves(font, vector_font.FontGlyph(font, IconRune(icon)), curves[:])
    piece_count, _ := vector_font.CurvesMonotonic(curves[:count], pieces[:])
    // the grid in em units: the bottom of the box is at the descent
    bottom: f32 = f32(ICON_DESCENT) / ICON_UNITS_PER_EM
    low: vector_font.Vec2 = {x / ICON_GRID, bottom + (ICON_GRID - y - side) / ICON_GRID}
    high: vector_font.Vec2 = {(x + side) / ICON_GRID, bottom + (ICON_GRID - y) / ICON_GRID}
    return vector_font.CurvesCoverage(pieces[:piece_count], low, high)
}

@(test)
test_the_font_file_is_read_back_with_every_icon :: proc(t: ^testing.T) {
    // the sum of the whole file is the number the format asks for (the checksum in `head` makes it so), and the directory is in the order of the tags
    sum: u32 = fontChecksum(LUCIDE_FONT)
    testing.expect_value(t, sum, u32(0xB1B0AFBA))
    file: []u8 = LUCIDE_FONT
    table_count: int = int(file[4]) << 8 | int(file[5])
    for i in 1 ..< table_count {
        testing.expect(t, string(file[12 + 16 * (i - 1):][:4]) < string(file[12 + 16 * i:][:4]))
    }

    font: ^vector_font.Font = new(vector_font.Font)
    defer free(font)
    testing.expect(t, vector_font.FontInit(font, LUCIDE_FONT))
    testing.expect_value(t, font.glyph_count, len(Icon))                    // the missing glyph and one per icon
    testing.expect_value(t, font.units_per_em, f32(ICON_UNITS_PER_EM))
    testing.expect_value(t, font.ascent - font.descent, 1)                  // the box of an icon is the em
    curves: []vector_font.Curve = make([]vector_font.Curve, 2048)
    defer delete(curves)
    for icon in Icon {
        if icon == .NONE { continue }
        glyph: int = vector_font.FontGlyph(font, IconRune(icon))
        testing.expect_value(t, glyph, int(icon))
        testing.expect_value(t, vector_font.FontAdvance(font, glyph), 1)
        count, ok := vector_font.FontGlyphCurves(font, glyph, curves)
        testing.expectf(t, ok && count >= 8, "%v has an outline", icon)
        low, high, has_box := vector_font.FontGlyphBox(font, glyph)
        testing.expectf(t, has_box && low.x >= 0 && high.x <= 1 && low.y >= font.descent && high.y <= font.ascent, "%v is inside of its box: %v %v", icon, low, high)
    }
    // a character before and after the icons is not in the font
    testing.expect_value(t, vector_font.FontGlyph(font, ICON_FIRST_CHARACTER - 1), 0)
    testing.expect_value(t, vector_font.FontGlyph(font, ICON_FIRST_CHARACTER + rune(len(Icon)) - 1), 0)
    testing.expect_value(t, vector_font.FontGlyph(font, 'A'), 0)

    // the pictures: a minus is a bar in the middle ("M5 12h14"), a plus has the bar that stands too, a circle is a ring of radius 10 around the middle
    testing.expect_value(t, iconCoverage(font, .MINUS, 11.5, 11.5, 1), 1)
    testing.expect_value(t, iconCoverage(font, .MINUS, 11.5, 6, 1), 0)
    testing.expect_value(t, iconCoverage(font, .MINUS, 1, 11.5, 1), 0)
    testing.expect(t, abs(iconCoverage(font, .MINUS, 11.5, 10.5, 1) - 0.5) < 0.01, "the edge of the bar goes through the middle of this square")
    testing.expect_value(t, iconCoverage(font, .PLUS, 11.5, 6, 1), 1)
    testing.expect_value(t, iconCoverage(font, .PLUS, 6, 6, 1), 0)
    testing.expect_value(t, iconCoverage(font, .PLUS, 11.5, 11.5, 1), 1)    // where the two bars cross is covered once, not twice and not left out
    testing.expect(t, iconCoverage(font, .CIRCLE, 11.5, 11.5, 1) < 0.001, "the two edges of the ring cancel in the middle (up to the rounding of the sums)")
    testing.expect(t, iconCoverage(font, .CIRCLE, 11.75, 1.75, 0.5) > 0.99)
    testing.expect(t, iconCoverage(font, .CIRCLE, 1.75, 11.75, 0.5) > 0.99)
    testing.expect_value(t, iconCoverage(font, .CIRCLE, 0.2, 0.2, 2), 0)
}

@(test)
test_icon_characters_and_names :: proc(t: ^testing.T) {
    testing.expect_value(t, IconRune(.NONE), rune(0))
    testing.expect_value(t, IconRune(.FOLDER), rune(0xE000))
    testing.expect_value(t, IconRune(.FOLDER_OPEN), rune(0xE001))
    text, length := IconText(.FOLDER)
    testing.expect_value(t, IconString(&text, length), "")
    _, none := IconText(.NONE)
    testing.expect_value(t, none, 0)
    testing.expect_value(t, IconFromName("folder-open"), Icon.FOLDER_OPEN)
    testing.expect_value(t, IconFromName("chevron-down"), Icon.CHEVRON_DOWN)
    testing.expect_value(t, IconFromName("no such icon"), Icon.NONE)
    testing.expect_value(t, IconFromName(""), Icon.NONE)
    // every name is there once
    for name, icon in ICON_NAMES {
        if icon != .NONE { testing.expect_value(t, IconFromName(name), icon) }
    }
}

@(test)
test_a_font_of_two_glyphs_and_room_that_is_too_small :: proc(t: ^testing.T) {
    // a square and a triangle, given with the inside on the right (y down), as StrokePath and FillPath give them
    square: [4]Segment = {
        {p0 = {100, 100}, p1 = {300, 100}, p2 = {500, 100}, line = true},
        {p0 = {500, 100}, p1 = {500, 300}, p2 = {500, 500}, line = true},
        {p0 = {500, 500}, p1 = {300, 500}, p2 = {100, 500}, line = true},
        {p0 = {100, 500}, p1 = {100, 300}, p2 = {100, 100}, line = true},
    }
    bowl: [2]Segment = {
        {p0 = {0, 0}, p1 = {400, 800}, p2 = {800, 0}},
        {p0 = {800, 0}, p1 = {400, 0}, p2 = {0, 0}, line = true},
    }
    square_ends: [1]int = {4}
    bowl_ends: [1]int = {2}
    glyphs: [2]FontGlyph = {{segments = square[:], ends = square_ends[:]}, {segments = bowl[:], ends = bowl_ends[:]}}
    description: FontDescription = {family = "Test", version = "1", units_per_em = 1000, ascent = 800, descent = -200, first_character = 'a'}
    file: [4096]u8
    points: [64]FontPoint
    contour_ends: [8]int
    size, ok := FontWrite(glyphs[:], description, file[:], points[:], contour_ends[:])
    testing.expect(t, ok && size > 400 && size % 4 == 0)
    testing.expect_value(t, fontChecksum(file[:size]), u32(0xB1B0AFBA))

    font: ^vector_font.Font = new(vector_font.Font)
    defer free(font)
    testing.expect(t, vector_font.FontInit(font, file[:size]))
    testing.expect_value(t, font.glyph_count, 3)
    testing.expect_value(t, vector_font.FontGlyph(font, 'a'), 1)
    testing.expect_value(t, vector_font.FontGlyph(font, 'b'), 2)
    testing.expect_value(t, vector_font.FontGlyph(font, 'c'), 0)
    low, high, has_box := vector_font.FontGlyphBox(font, 1)
    testing.expect(t, has_box)
    testing.expect_value(t, low, vector_font.Vec2{0.1, 0.1})
    testing.expect_value(t, high, vector_font.Vec2{0.5, 0.5})
    curves: [16]vector_font.Curve
    count, curves_ok := vector_font.FontGlyphCurves(font, 2, curves[:])
    testing.expect(t, curves_ok)
    testing.expect_value(t, count, 2)                           // the curve and the line, the other way round
    testing.expect(t, curves[0].p1 == vector_font.Vec2{0.4, 0.8} || curves[1].p1 == vector_font.Vec2{0.4, 0.8}, "the control point of the curve")
    _, _, empty_box := vector_font.FontGlyphBox(font, 0)
    testing.expect(t, !empty_box, "the missing glyph has no outline")

    // bytes or working room that do not fit are told
    _, ok = FontWrite(glyphs[:], description, file[:300], points[:], contour_ends[:])
    testing.expect(t, !ok)
    _, ok = FontWrite(glyphs[:], description, file[:], points[:3], contour_ends[:])
    testing.expect(t, !ok)
}
