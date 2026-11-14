package box2d_odin

import "core:strconv"
import "core:strings"
import b2 "vendor:box2d"
import "core:sync"
import "core:testing"

// Parse a simple SVG path (M L H V m l h v z with space separated tokens) into points.
// Port of Sample::ParsePath. Points are scaled, y is flipped. Returns the point count.
ParsePath :: proc(svg_path: string, offset: Vec2, points: []Vec2, scale: f32, reverse_order: bool) -> int {
    count: int
    current: Vec2
    command: u8 = 0

    remaining: string = svg_path
    for token in strings.split_iterator(&remaining, " ") {
        if len(token) == 0 { continue }
        first: u8 = token[0]
        is_number: bool = (first >= '0' && first <= '9') || first == '-'
        if !is_number {
            command = first
            if command == 'z' { break }
            continue
        }

        x, y: f32
        switch command {
        case 'M', 'L', 'm', 'l':
            comma: int = strings.index_byte(token, ',')
            if comma < 0 { return count }
            x, _ = strconv.parse_f32(token[:comma])
            y, _ = strconv.parse_f32(token[comma + 1:])
            if command == 'M' || command == 'L' {
                current = {x, y}
            } else {
                current += {x, y}
            }
        case 'H', 'h':
            x, _ = strconv.parse_f32(token)
            current.x = x if command == 'H' else current.x + x
        case 'V', 'v':
            y, _ = strconv.parse_f32(token)
            current.y = y if command == 'V' else current.y + y
        case:
            return count
        }

        if count >= len(points) { break }
        points[count] = {scale * (current.x + offset.x), -scale * (current.y + offset.y)}
        count += 1
    }

    if reverse_order {
        for i in 0..<count / 2 {
            points[i], points[count - 1 - i] = points[count - 1 - i], points[i]
        }
    }
    return count
}

// Random convex polygon from the C++ samples (shared/utils.c)
RandomPolygon :: proc(extent: f32) -> b2.Polygon {
    points: [b2.MAX_POLYGON_VERTICES]Vec2
    count: int = 3 + int(RandomInt() % 6)
    for i in 0..<count {
        points[i] = RandomVec2(-extent, extent)
    }
    hull: b2.Hull = b2.ComputeHull(points[:count])
    if hull.count > 0 {
        return b2.MakePolygon(hull, 0)
    }
    return b2.MakeSquare(extent)
}

// --- Tests ---

@(test)
test_parse_path_absolute_and_relative :: proc(t: ^testing.T) {
    points: [8]Vec2
    count: int = ParsePath("M 0,0 L 10,0 V 5 H 2 h -2 z", {}, points[:], 1, false)
    testing.expect_value(t, count, 5)
    testing.expect_value(t, points[0], Vec2{0, 0})
    testing.expect_value(t, points[1], Vec2{10, 0})
    testing.expect_value(t, points[2], Vec2{10, -5})                                       // the y axis is flipped
    testing.expect_value(t, points[3], Vec2{2, -5})
    testing.expect_value(t, points[4], Vec2{0, -5})

    relative: int = ParsePath("m 1,1 l 2,0 v 3", {}, points[:], 1, false)                  // relative moves add up
    testing.expect_value(t, relative, 3)
    testing.expect_value(t, points[2], Vec2{3, -4})
}

@(test)
test_parse_path_scale_offset_reverse_and_capacity :: proc(t: ^testing.T) {
    points: [8]Vec2
    count: int = ParsePath("M 1,2 L 3,4", {10, 20}, points[:], 0.5, false)
    testing.expect_value(t, count, 2)
    testing.expect_value(t, points[0], Vec2{5.5, -11})                                     // scale * (point + offset)
    testing.expect_value(t, points[1], Vec2{6.5, -12})

    reversed: int = ParsePath("M 1,0 L 2,0 L 3,0", {}, points[:], 1, true)
    testing.expect_value(t, reversed, 3)
    testing.expect_value(t, points[0].x, f32(3))
    testing.expect_value(t, points[2].x, f32(1))

    tiny: [2]Vec2
    testing.expect_value(t, ParsePath("M 0,0 L 1,0 L 2,0 L 3,0", {}, tiny[:], 1, false), 2)   // stops at the buffer end
    testing.expect_value(t, ParsePath("", {}, points[:], 1, false), 0)
    testing.expect_value(t, ParsePath("Q 1,1", {}, points[:], 1, false), 0)                // unsupported command
}

@(test)
test_random_polygon_is_convex_and_valid :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    RandomReset()
    for _ in 0 ..< 50 {
        polygon: b2.Polygon = RandomPolygon(2)
        testing.expect(t, polygon.count >= 3 && polygon.count <= b2.MAX_POLYGON_VERTICES)
        testing.expect(t, b2.ComputePolygonMass(polygon, 1).mass > 0, "a real polygon with area")
    }
    RandomReset()
}
