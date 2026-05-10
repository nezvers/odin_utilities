package element_ui

LerpSize :: proc(size:vec2, lerp:vec2)->vec2 {
    return size * lerp
}

// pos_lerp - interpolate position on view_rect
// offset_lerp - interplate offset by element_size
LerpPosition :: proc(view_rect:rectf, elem_size:vec2, pos_lerp:vec2, offset_lerp:vec2 = {0.5, 0.5})->vec2 {
    return view_rect.xy + view_rect.zw * pos_lerp - (elem_size * offset_lerp)
}


IsHover :: proc(p: vec2, r: rectf)->bool {
    return p.x >= r.x && p.x <= r.x + r.z && p.y >= r.y && p.y <= r.y + r.w
}