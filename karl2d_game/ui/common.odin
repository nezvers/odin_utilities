package ui

// Array alows swizzling
vec2 :: [2]f32
Rect :: [4]f32

GetElementSize :: proc(view_rect:Rect, size_lerp:vec2)->vec2 {
    return {view_rect.z * size_lerp.x, view_rect.w * size_lerp.y}
}

GetElementPosition :: proc(view_rect:Rect, elem_size:vec2, pos_lerp:vec2, offset_lerp:vec2 = {0.5, 0.5})->vec2 {
    return {view_rect.z, view_rect.w} * pos_lerp - (elem_size * offset_lerp)
}