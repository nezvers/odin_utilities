package box2d_odin

import "core:strconv"
import "core:strings"
import b2 "vendor:box2d"

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
