package game


import "../../../karl2d"

import "core:math"
PI :: math.PI

Slider :: proc(state: ^f32, value: ^f32, from:f32, to:f32, rect:Rect, pos:Vec2, active:bool)->(hover:bool) {
    state^ = NormalizeRange(value^, from, to)
    hover = IsHovering(pos, rect)
    if (hover && active){
        if karl2d.mouse_button_is_held(.Left) {
            state^ = (pos.x - rect.x) / rect.w
            value^ = Lerpf(from, to, state^)
        }
    }
    karl2d.draw_rect_outline(
        rect,
        1,
        karl2d.GRAY,
    )
    slider_val:Rect = rect
    slider_val.w *= state^
    karl2d.draw_rect(slider_val, karl2d.LIGHT_GRAY)
    return
}

NormalizeRange :: proc(value:f32, from:f32, to:f32)->f32 {
    return math.abs(value - from) / math.abs(to - from)
}

Lerpf :: proc(a:f32, b:f32, t:f32)->f32 {
    return a + (b - a) * t
}

IsHovering :: proc(p:Vec2, r:Rect)->bool {
    return p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h
}