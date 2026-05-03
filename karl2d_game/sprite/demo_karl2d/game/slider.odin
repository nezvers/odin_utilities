package game


import "../../../karl2d"

import "core:math"
PI :: math.PI

// TODO: Handle hold & release outside Rect
Slider :: proc(
    state: ^f32, 
    value: ^f32, 
    from:f32, 
    to:f32, 
    rect:Rect, 
    input_pos:Vec2={}, 
    active:bool=false, 
    text:string="", 
    text_size: f32 = 20,
    font:karl2d.Font = karl2d.FONT_DEFAULT,
)->(hover:bool) {
    state^ = NormalizeRange(value^, from, to)
    hover = IsHovering(input_pos, rect)
    if (hover && active){
        if karl2d.mouse_button_is_held(.Left) {
            state^ = (input_pos.x - rect.x) / rect.w
            value^ = Lerpf(from, to, state^)
        }
    }
    slider_val:Rect = rect
    slider_val.w *= state^
    karl2d.draw_rect(slider_val, karl2d.LIGHT_GRAY)
    karl2d.draw_rect_outline(
        rect,
        1,
        karl2d.GRAY,
    )

    if (len(text) > 0) {
        // TODO: auto font sizing?
        FONT_COLOR :: karl2d.BLACK
        measure:Vec2 = karl2d.measure_text(text, text_size, font)
        label_pos:Vec2 = ({rect.w, rect.h} - measure) * 0.5 + {rect.x, rect.y}
        karl2d.draw_text(text, label_pos, text_size, FONT_COLOR, font)
    }
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