package ui_default

// Lines that are no boxes, for a draw proc of the program's own (a CUSTOM element): what an editor draws over a picture. A dashed line, a dashed path whose
// pattern goes on around its corners (the "marching ants" of a selection: give it a phase that grows with the time), a frame turned by an angle.
//
// Baldr's line overlays (examples/28_lines) were the reason to have them; the code is written for this library.

import "core:math"
import ui ".."

// A line of dashes: `dash` long with `gap` between them. `phase` moves the pattern along the line (a dash starts `phase` before `from`). Returns the phase at the
// end of the line: pass it to the next piece of a path so that the pattern goes on around the corner.
LineDashed :: proc(painter: ^Painter, from: ui.Vec2, to: ui.Vec2, thickness: f32, dash: f32, gap: f32, color: ui.Color, phase: f32 = 0) -> (phase_after: f32) {
    delta: ui.Vec2 = to - from
    length: f32 = math.sqrt(delta.x * delta.x + delta.y * delta.y)
    period: f32 = dash + gap
    if length < 0.001 || dash <= 0 || period <= 0 { return phase }
    direction: ui.Vec2 = delta / length
    start: f32 = -math.mod(phase, period)
    if start > 0 { start -= period }                        // a negative phase: the dash before the line
    for start < length {
        a: f32 = max(start, 0)
        b: f32 = min(start + dash, length)
        if b > a { Line(painter, from + direction * a, from + direction * b, thickness, color) }
        start += period
    }
    return phase + length
}

// A path of dashes through `points` (back to the first one when `closed`), the pattern unbroken at the corners
PathDashed :: proc(painter: ^Painter, points: []ui.Vec2, closed: bool, thickness: f32, dash: f32, gap: f32, color: ui.Color, phase: f32 = 0) {
    along: f32 = phase
    count: int = len(points) if closed else len(points) - 1
    for i in 0 ..< count {
        along = LineDashed(painter, points[i], points[(i + 1) % len(points)], thickness, dash, gap, color, along)
    }
}

// The corners of a rectangle turned by `angle` (radians, clockwise on the screen) around its middle: top left, top right, bottom right, bottom left
RectCorners :: proc(rect: ui.Rect, angle: f32) -> (corners: [4]ui.Vec2) {
    center: ui.Vec2 = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    half: ui.Vec2 = {rect.z * 0.5, rect.w * 0.5}
    sine, cosine: f32 = math.sin(angle), math.cos(angle)
    for sign, i in ([4]ui.Vec2{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
        local: ui.Vec2 = {sign.x * half.x, sign.y * half.y}
        corners[i] = {center.x + local.x * cosine - local.y * sine, center.y + local.x * sine + local.y * cosine}
    }
    return
}

// A closed path of solid lines
PathLines :: proc(painter: ^Painter, points: []ui.Vec2, closed: bool, thickness: f32, color: ui.Color) {
    count: int = len(points) if closed else len(points) - 1
    for i in 0 ..< count { Line(painter, points[i], points[(i + 1) % len(points)], thickness, color) }
}
