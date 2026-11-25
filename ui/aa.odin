package ui

// Anti-aliased shapes as geometry. No shader, no texture, no multisampling: every shape is a few triangles whose edge vertices carry a coverage that falls from 1 to 0 over one
// pixel (the "fringe" of NanoVG, which this follows), so the GPU interpolates the soft edge, and the same vertices, with the color of the shape and the alpha scaled by
// the coverage, are drawn by the ordinary alpha blended triangle path of any framework. Everything drawn with it lands in the batch that is open: a whole window of rounded
// boxes, lines and cables is one draw call together with the rectangles and the text around it.
//
// The mesh is a triangle list in a storage of the caller (a fixed slice: when it is full the rest of the shapes is dropped and `overflow` says so, nothing is allocated).
// Coordinates are the logical ones of the ui; `pixel` is the size of a screen pixel in them (1 / scale) and sets the width of the fringe.
//
//   AaFillConvex       any convex polygon (a corner, an arrow, a handle)
//   AaRounded          a rounded rectangle, one radius per corner
//   AaRoundedRing      its outline, inside of the rectangle, `width` wide
//   AaDisc             a circle
//   AaStroke           a line of any width through points: round, square or butt ends, mitered joins (closed or open)
//   AaFlattenCubic     a Bezier curve as points, as many as its curvature needs; AaFlattenRoute does a whole cable route
//
// A stroke thinner than a pixel is drawn one pixel wide and fainter by the ratio, which is what the coverage of a thin line is.

import "core:math"

AaVertex :: struct {
    position: Vec2,
    coverage: f32,                  // 0 .. 1: what the alpha of the color is multiplied by
}

AaMesh :: struct {
    vertices: []AaVertex,           // the storage, the caller's
    count: int,                     // vertices written, a multiple of 3
    overflow: bool,                 // something did not fit and was left out
}

AaCap :: enum u8 {
    BUTT,
    SQUARE,
    ROUND,
}

AA_MITER_LIMIT :: 2.5               // a joint is never longer than this times half the width: a sharper turn is cut
AA_DISC_MAX_POINTS :: 128
AA_TOLERANCE :: 0.1                 // how far (in pixels) a flattened curve or circle may be from the real one

AaMeshInit :: proc(mesh: ^AaMesh, storage: []AaVertex) {
    mesh^ = {vertices = storage}
}

AaMeshClear :: proc(mesh: ^AaMesh) {
    mesh.count = 0
    mesh.overflow = false
}

AaMeshTriangles :: proc(mesh: ^AaMesh) -> []AaVertex {
    return mesh.vertices[:mesh.count]
}

@(private)
aaTriangle :: proc(mesh: ^AaMesh, a: AaVertex, b: AaVertex, c: AaVertex) {
    if mesh.count + 3 > len(mesh.vertices) {
        mesh.overflow = true
        return
    }
    mesh.vertices[mesh.count] = a
    mesh.vertices[mesh.count + 1] = b
    mesh.vertices[mesh.count + 2] = c
    mesh.count += 3
}

@(private)
aaNormalize :: proc(v: Vec2) -> (unit: Vec2, ok: bool) {
    length: f32 = math.sqrt(v.x * v.x + v.y * v.y)
    if length < 1e-6 { return {}, false }
    return v / length, true
}

// ------------------------------------------------------------------------------------------------------------------------
// Filled shapes

// A convex polygon (either winding): the inside is a fan of full coverage, inset by half a pixel, and a band of quads from there to half a pixel outside, where the
// coverage is 0: the edge is half covered on the line of the polygon, as it is for a pixel that the edge cuts in half.
AaFillConvex :: proc(mesh: ^AaMesh, points: []Vec2, pixel: f32) {
    count: int = len(points)
    if count < 3 { return }
    twice_area: f32
    for i in 0 ..< count {
        a, b: Vec2 = points[i], points[(i + 1) % count]
        twice_area += a.x * b.y - b.x * a.y
    }
    if abs(twice_area) < 1e-9 { return }
    // y points down: with a positive sum the inside is on the (-dy, dx) side of an edge
    inward: f32 = 1 if twice_area > 0 else -1
    half: f32 = pixel * 0.5
    inner, outer: [AA_FILL_MAX_POINTS]Vec2
    used: int = min(count, AA_FILL_MAX_POINTS)
    for i in 0 ..< used {
        previous: Vec2 = points[(i + used - 1) % used]
        next: Vec2 = points[(i + 1) % used]
        n_previous, _ := aaNormalize(points[i] - previous)
        n_next, _ := aaNormalize(next - points[i])
        a: Vec2 = {-n_previous.y, n_previous.x} * inward
        b: Vec2 = {-n_next.y, n_next.x} * inward
        miter, ok := aaNormalize(a + b)
        if !ok { miter = b }
        scale: f32 = 1 / max(miter.x * b.x + miter.y * b.y, 0.4)
        offset: Vec2 = miter * (half * scale)
        inner[i] = points[i] + offset
        outer[i] = points[i] - offset
    }
    for i in 1 ..< used - 1 {
        aaTriangle(mesh, {inner[0], 1}, {inner[i], 1}, {inner[i + 1], 1})
    }
    for i in 0 ..< used {
        j: int = (i + 1) % used
        aaTriangle(mesh, {inner[i], 1}, {inner[j], 1}, {outer[j], 0})
        aaTriangle(mesh, {inner[i], 1}, {outer[j], 0}, {outer[i], 0})
    }
}

AA_FILL_MAX_POINTS :: 4 * (ROUNDED_MAX_SEGMENTS + 1) + 8

// A rounded rectangle, radius per corner (top left, top right, bottom right, bottom left)
AaRounded :: proc(mesh: ^AaMesh, rect: Rect, radii: [4]f32, pixel: f32) {
    if rect.z <= 0 || rect.w <= 0 { return }
    biggest: f32 = max(max(radii[0], radii[1]), max(radii[2], radii[3]))
    buffer: RoundedBuffer
    points: []Vec2 = RoundedPoints(rect, radii, RoundedSegments(biggest / pixel), buffer[:])
    AaFillConvex(mesh, aaDistinct(points, buffer[:]), pixel)
}

// The outline of a rounded rectangle, `width` wide, inside of `rect`
AaRoundedRing :: proc(mesh: ^AaMesh, rect: Rect, radius: f32, width: f32, pixel: f32) {
    if rect.z <= 0 || rect.w <= 0 || width <= 0 { return }
    middle: Rect = RectShrink(rect, width * 0.5)
    if middle.z <= 0 || middle.w <= 0 { return }
    reach: f32 = max(radius - width * 0.5, 0)
    buffer: RoundedBuffer
    points: []Vec2 = RoundedPoints(middle, {reach, reach, reach, reach}, RoundedSegments(reach / pixel), buffer[:])
    AaStroke(mesh, aaDistinct(points, buffer[:]), true, width, pixel)
}

// The points without the ones that repeat the one before (a sharp corner makes two): done in place, the front of `storage` is returned
@(private)
aaDistinct :: proc(points: []Vec2, storage: []Vec2) -> []Vec2 {
    count: int = 0
    for point in points {
        if count > 0 {
            last: Vec2 = storage[count - 1]
            if abs(last.x - point.x) < 1e-4 && abs(last.y - point.y) < 1e-4 { continue }
        }
        storage[count] = point
        count += 1
    }
    for count > 1 && abs(storage[0].x - storage[count - 1].x) < 1e-4 && abs(storage[0].y - storage[count - 1].y) < 1e-4 { count -= 1 }
    return storage[:count]
}

// A circle: as many corners as keep it within AA_TOLERANCE of a pixel from the real one
AaDisc :: proc(mesh: ^AaMesh, center: Vec2, radius: f32, pixel: f32) {
    if radius <= 0 { return }
    points: [AA_DISC_MAX_POINTS]Vec2
    count: int = aaCircleCorners(radius / pixel)
    for i in 0 ..< count {
        angle: f32 = f32(i) / f32(count) * math.TAU
        points[i] = center + Vec2{math.cos(angle), math.sin(angle)} * radius
    }
    AaFillConvex(mesh, points[:count], pixel)
}

@(private)
aaCircleCorners :: proc(radius_in_pixels: f32) -> int {
    if radius_in_pixels <= AA_TOLERANCE { return 6 }
    step: f32 = math.acos(clamp(1 - AA_TOLERANCE / radius_in_pixels, -1, 1))
    return clamp(int(math.ceil(math.TAU / max(step, 0.001))), 8, AA_DISC_MAX_POINTS)
}

// ------------------------------------------------------------------------------------------------------------------------
// Strokes

// One cross section of a stroke: four vertices across it, the two outer ones (coverage 0) half a pixel outside of the edge, the two inner ones half a pixel inside.
@(private)
Section :: [4]AaVertex

@(private)
aaSection :: proc(center: Vec2, side: Vec2, half_width: f32, half_pixel: f32, strength: f32) -> Section {
    inside: f32 = max(half_width - half_pixel, 0)
    outside: f32 = half_width + half_pixel
    return {
        {center - side * outside, 0},
        {center - side * inside, strength},
        {center + side * inside, strength},
        {center + side * outside, 0},
    }
}

@(private)
aaJoin :: proc(mesh: ^AaMesh, a: Section, b: Section) {
    for j in 0 ..< 3 {
        aaTriangle(mesh, a[j], a[j + 1], b[j + 1])
        aaTriangle(mesh, a[j], b[j + 1], b[j])
    }
}

// The direction of the line at a point going one way (`step` +1 or -1) to the nearest point that is somewhere else; the zero vector when there is none
@(private)
aaDirection :: proc(points: []Vec2, index: int, step: int, closed: bool) -> Vec2 {
    count: int = len(points)
    at: int = index
    for _ in 0 ..< count {
        at += step
        if closed {
            at = (at + count) % count
        } else if at < 0 || at >= count {
            return {}
        }
        delta: Vec2 = points[at] - points[index]
        if abs(delta.x) > 1e-5 || abs(delta.y) > 1e-5 {
            unit, _ := aaNormalize(delta)
            return unit * f32(step)             // always along the line, from the start to the end
        }
    }
    return {}
}

// What a stroke keeps while it is built: the section before, and the first one (a closed line joins to it at the end)
@(private)
StrokeState :: struct {
    mesh: ^AaMesh,
    first: Section,
    previous: Section,
    started: bool,
}

@(private)
aaEmit :: proc(state: ^StrokeState, section: Section) {
    if state.started {
        aaJoin(state.mesh, state.previous, section)
    } else {
        state.first = section
        state.started = true
    }
    state.previous = section
}

// A line through `points`, `width` wide (a closed one joins its last point to its first). The joints are mitered up to AA_MITER_LIMIT, the ends of an open line follow `cap`.
// Points that repeat the one before are skipped. A line of less than a pixel is a pixel wide and fainter.
AaStroke :: proc(mesh: ^AaMesh, points: []Vec2, closed: bool, width: f32, pixel: f32, cap: AaCap = .BUTT) {
    count: int = len(points)
    if count < 2 || width <= 0 { return }
    half_pixel: f32 = pixel * 0.5
    strength: f32 = 1
    half_width: f32 = width * 0.5
    if width < pixel {
        strength = width / pixel
        half_width = half_pixel
    }
    state: StrokeState = {mesh = mesh}
    last_index: int = count - 1
    for !closed && last_index > 0 && aaDirection(points, last_index, -1, false) == {} { last_index -= 1 }
    for i in 0 ..< count {
        if !closed && i > last_index { break }
        if i > 0 && abs(points[i].x - points[i - 1].x) < 1e-5 && abs(points[i].y - points[i - 1].y) < 1e-5 { continue }
        incoming: Vec2 = aaDirection(points, i, -1, closed)         // along the line, arriving
        outgoing: Vec2 = aaDirection(points, i, 1, closed)          // along the line, leaving
        if incoming == {} && outgoing == {} { return }
        if incoming == {} { incoming = outgoing }
        if outgoing == {} { outgoing = incoming }
        normal_in: Vec2 = {-incoming.y, incoming.x}
        normal_out: Vec2 = {-outgoing.y, outgoing.x}
        side, ok := aaNormalize(normal_in + normal_out)
        if !ok { side = normal_out }
        stretch: f32 = 1 / max(side.x * normal_out.x + side.y * normal_out.y, 1 / AA_MITER_LIMIT)
        if !closed && i == 0 { aaCap(&state, points[i], -outgoing, half_width, half_pixel, strength, cap, true) }
        aaEmit(&state, aaSection(points[i], side * stretch, half_width, half_pixel, strength))
        if !closed && i == last_index { aaCap(&state, points[i], incoming, half_width, half_pixel, strength, cap, false) }
    }
    if closed && state.started { aaJoin(mesh, state.previous, state.first) }
}

AA_ROUND_CAP_STEPS :: 5

// The sections beyond the section of the end point, from the point outwards (`away` is the way the line would go on); at the start they are emitted from the outside in.
// The last of them has coverage 0: the soft end of the line.
@(private)
aaCap :: proc(state: ^StrokeState, point: Vec2, away: Vec2, half_width: f32, half_pixel: f32, strength: f32, cap: AaCap, at_start: bool) {
    side: Vec2 = {-away.y, away.x}
    sections: [AA_ROUND_CAP_STEPS + 2]Section
    count: int = 0
    switch cap {
    case .BUTT:
        sections[0] = aaSection(point + away * half_pixel, side, half_width, half_pixel, 0)
        count = 1
    case .SQUARE:
        sections[0] = aaSection(point + away * half_width, side, half_width, half_pixel, strength)
        sections[1] = aaSection(point + away * (half_width + half_pixel), side, half_width, half_pixel, 0)
        count = 2
    case .ROUND:
        for step in 1 ..< AA_ROUND_CAP_STEPS {
            angle: f32 = f32(step) / f32(AA_ROUND_CAP_STEPS) * (math.PI * 0.5)
            sections[count] = aaSection(point + away * (half_width * math.sin(angle)), side, half_width * math.cos(angle), half_pixel, strength)
            count += 1
        }
        sections[count] = aaSection(point + away * half_width, side, 0, half_pixel, strength)
        sections[count + 1] = aaSection(point + away * (half_width + half_pixel), side, 0, half_pixel, 0)
        count += 2
    }
    if at_start {
        for i := count - 1; i >= 0; i -= 1 { aaEmit(state, sections[i]) }
    } else {
        for i in 0 ..< count { aaEmit(state, sections[i]) }
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// Curves

// A cubic Bezier as points: the start is written first when `with_start`, then as many more as the curvature of the curve needs to stay within `tolerance` of it
// (Wang's formula for the count). Returns how many points were written to `out`, never more than its length.
AaFlattenCubic :: proc(p: [4]Vec2, tolerance: f32, out: []Vec2, with_start: bool = true) -> int {
    written: int = 0
    if with_start && written < len(out) {
        out[written] = p[0]
        written += 1
    }
    d0: Vec2 = p[0] - p[1] * 2 + p[2]
    d1: Vec2 = p[1] - p[2] * 2 + p[3]
    bend: f32 = max(math.sqrt(d0.x * d0.x + d0.y * d0.y), math.sqrt(d1.x * d1.x + d1.y * d1.y))
    pieces: int = clamp(int(math.ceil(math.sqrt(0.75 * bend / max(tolerance, 1e-4)))), 1, 128)
    for i in 1 ..= pieces {
        if written >= len(out) { break }
        t: f32 = f32(i) / f32(pieces)
        u: f32 = 1 - t
        out[written] = p[0] * (u * u * u) + p[1] * (3 * u * u * t) + p[2] * (3 * u * t * t) + p[3] * (t * t * t)
        written += 1
    }
    return written
}

// The whole route of a cable as points
AaFlattenRoute :: proc(route: ^CableRoute, tolerance: f32, out: []Vec2) -> []Vec2 {
    written: int = 0
    for i in 0 ..< route.count {
        written += AaFlattenCubic(route.segments[i].p, tolerance, out[written:], i == 0)
    }
    return out[:written]
}
