package ui

// Basic types of the ui library. They are plain arrays on purpose: the same layout as `[4]f32` / `[4]u8` of Karl2D, raylib and demo_kit,
// so a style or a glue can cast or pass them without conversion code.

Vec2 :: [2]f32
Rect :: [4]f32          // x, y, width, height
Color :: [4]u8

// An id of an element: the hash of its name inside of the element that holds it. 0 means "no id".
Id :: distinct u32

INFINITE :: f32(1e30)
RECT_INFINITE :: Rect{-INFINITE * 0.5, -INFINITE * 0.5, INFINITE, INFINITE}

RectContains :: proc(rect: Rect, point: Vec2) -> bool {
    return point.x >= rect.x && point.x < rect.x + rect.z && point.y >= rect.y && point.y < rect.y + rect.w
}

// The overlap of two rectangles, width or height 0 when they only touch or do not meet
RectIntersect :: proc(a: Rect, b: Rect) -> Rect {
    left: f32 = max(a.x, b.x)
    top: f32 = max(a.y, b.y)
    right: f32 = min(a.x + a.z, b.x + b.z)
    bottom: f32 = min(a.y + a.w, b.y + b.w)
    return {left, top, max(right - left, 0), max(bottom - top, 0)}
}

RectOverlaps :: proc(a: Rect, b: Rect) -> bool {
    return a.x < b.x + b.z && b.x < a.x + a.z && a.y < b.y + b.w && b.y < a.y + a.w
}

// A smaller rectangle (a bigger one for a negative amount), never below zero size
RectShrink :: proc(rect: Rect, amount: f32) -> Rect {
    return {rect.x + amount, rect.y + amount, max(rect.z - amount * 2, 0), max(rect.w - amount * 2, 0)}
}

RectCenter :: proc(rect: Rect) -> Vec2 {
    return {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
}

// `a` towards `b` by `t` (0..1)
Lerp :: proc(a: f32, b: f32, t: f32) -> f32 {
    return a + (b - a) * t
}

ColorLerp :: proc(a: Color, b: Color, t: f32) -> Color {
    result: Color
    for i in 0 ..< 4 {
        result[i] = u8(clamp(Lerp(f32(a[i]), f32(b[i]), clamp(t, 0, 1)), 0, 255))
    }
    return result
}
