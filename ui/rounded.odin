package ui

// Rounded rectangles for styles. Pure geometry: the radius of a corner and the polygon of the shape, written to a buffer of the caller.
// Rounding is a part of the shortest side: 0 is a sharp rectangle, 1 is the full round (a circle for a square, a pill for a bar), and the
// radius never goes over half of the shortest side or over the limit in pixels the caller gives.

import "core:math"

ROUNDED_MAX_SEGMENTS :: 16

// Radius of the corners from `rounding` (0 .. 1 of half the shortest side). `max_radius` (pixels) limits it, 0 or less means no limit.
RoundedRadius :: proc(rect: Rect, rounding: f32, max_radius: f32 = 0) -> f32 {
    half: f32 = min(rect.z, rect.w) * 0.5
    radius: f32 = half * clamp(rounding, 0, 1)
    if max_radius > 0 { radius = min(radius, max_radius) }
    return max(radius, 0)
}

// Radius per corner: top left, top right, bottom right, bottom left. Each is clamped so two corners on one side never overlap.
RoundedRadii :: proc(rect: Rect, radii: [4]f32) -> [4]f32 {
    half: f32 = min(rect.z, rect.w) * 0.5
    result: [4]f32
    for i in 0 ..< 4 {
        result[i] = clamp(radii[i], 0, half)
    }
    return result
}

// How many segments a corner of this radius needs to look round: more for a big radius, 1 for a sharp corner
RoundedSegments :: proc(radius: f32) -> int {
    if radius <= 0.5 { return 1 }
    return clamp(int(math.sqrt(radius) * 1.6) + 2, 2, ROUNDED_MAX_SEGMENTS)
}

// The most points RoundedPoints writes
RoundedPointCount :: proc(segments: int) -> int {
    return 4 * (segments + 1)
}

// A buffer for the points of any rounded rectangle: `buffer: ui.RoundedBuffer` then `ui.RoundedPointsUniform(rect, 0.3, buffer[:])`
RoundedBuffer :: [4 * (ROUNDED_MAX_SEGMENTS + 1)]Vec2

// The outline of the rounded rectangle, clockwise from the top left, as points of a convex polygon: a triangle fan around any point inside
// of it fills the shape. The points are written to `out` (it must hold RoundedPointCount(segments)), the used part is returned.
RoundedPoints :: proc(rect: Rect, radii: [4]f32, segments: int, out: []Vec2) -> []Vec2 {
    assert(segments >= 1 && segments <= ROUNDED_MAX_SEGMENTS)
    assert(len(out) >= RoundedPointCount(segments))
    clamped: [4]f32 = RoundedRadii(rect, radii)
    // the center of each corner arc, and the angle where it starts (radians, y down: 0 is right, a quarter turn goes clockwise)
    centers: [4]Vec2 = {
        {rect.x + clamped[0], rect.y + clamped[0]},
        {rect.x + rect.z - clamped[1], rect.y + clamped[1]},
        {rect.x + rect.z - clamped[2], rect.y + rect.w - clamped[2]},
        {rect.x + clamped[3], rect.y + rect.w - clamped[3]},
    }
    starts: [4]f32 = {math.PI, math.PI * 1.5, 0, math.PI * 0.5}
    count: int = 0
    for corner in 0 ..< 4 {
        for step in 0 ..= segments {
            angle: f32 = starts[corner] + f32(step) / f32(segments) * math.PI * 0.5
            out[count] = centers[corner] + Vec2{math.cos(angle), math.sin(angle)} * clamped[corner]
            count += 1
        }
    }
    return out[:count]
}

// The same radius on all corners from a rounding part, the common case
RoundedPointsUniform :: proc(rect: Rect, rounding: f32, out: []Vec2, max_radius: f32 = 0) -> []Vec2 {
    radius: f32 = RoundedRadius(rect, rounding, max_radius)
    return RoundedPoints(rect, {radius, radius, radius, radius}, RoundedSegments(radius), out)
}
