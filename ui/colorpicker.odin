package ui

import "core:math"

// A color picker: a square for saturation and brightness, a bar for the hue, an optional bar for the alpha, a swatch of the result and the three channels as drag values. The program owns the
// color (`[3]f32`, 0..1, and the alpha as a `f32`); the picker keeps the hue and the saturation that the person chose in its own state, because a gray or a black has none in RGB and
// dragging down to black would lose the hue for good. A color that the program changes meanwhile is taken at once.
//
//     color: [3]f32 = {0.9, 0.4, 0.1}
//     alpha: f32 = 1
//     if ui.UiColorPicker(&ctx, "Tint", &color, &alpha) { ... }          // true in the frames the person changes it
//
// ColorHsvToRgb, ColorRgbToHsv, ColorToHex and ColorFromHex are plain helpers for a program that has its own hex field or its own palette.

COLOR_PICKER_BAR :: f32(22)                 // the width of the hue and alpha bars

// h, s and v are 0..1 (the hue wraps)
ColorHsvToRgb :: proc(h: f32, s: f32, v: f32) -> [3]f32 {
    hue: f32 = (h - math.floor(h)) * 6
    sector: int = int(hue)
    fraction: f32 = hue - f32(sector)
    p: f32 = v * (1 - s)
    q: f32 = v * (1 - s * fraction)
    t: f32 = v * (1 - s * (1 - fraction))
    switch sector % 6 {
    case 0: return {v, t, p}
    case 1: return {q, v, p}
    case 2: return {p, v, t}
    case 3: return {p, q, v}
    case 4: return {t, p, v}
    }
    return {v, p, q}
}

ColorRgbToHsv :: proc(rgb: [3]f32) -> (h: f32, s: f32, v: f32) {
    high: f32 = max(rgb.r, rgb.g, rgb.b)
    low: f32 = min(rgb.r, rgb.g, rgb.b)
    delta: f32 = high - low
    v = high
    s = delta / high if high > 0 else 0
    if delta <= 0 { return 0, s, v }
    if high == rgb.r {
        h = (rgb.g - rgb.b) / delta
    } else if high == rgb.g {
        h = 2 + (rgb.b - rgb.r) / delta
    } else {
        h = 4 + (rgb.r - rgb.g) / delta
    }
    h /= 6
    if h < 0 { h += 1 }
    return
}

// "#rrggbb", or "#rrggbbaa" when `with_alpha`: written into `buffer` (9 bytes hold both)
ColorToHex :: proc(rgb: [3]f32, alpha: f32, buffer: []u8, with_alpha: bool = false) -> string {
    digits: string = "0123456789abcdef"
    count: int = 9 if with_alpha else 7
    assert(len(buffer) >= count)
    channels: [4]f32 = {rgb.r, rgb.g, rgb.b, alpha}
    buffer[0] = '#'
    for channel in 0 ..< (4 if with_alpha else 3) {
        byte_value: int = int(clamp(channels[channel], 0, 1) * 255 + 0.5)
        buffer[1 + channel * 2] = digits[byte_value >> 4]
        buffer[2 + channel * 2] = digits[byte_value & 15]
    }
    return string(buffer[:count])
}

@(private)
hexDigit :: proc(character: u8) -> (value: int, ok: bool) {
    switch character {
    case '0' ..= '9': return int(character - '0'), true
    case 'a' ..= 'f': return int(character - 'a') + 10, true
    case 'A' ..= 'F': return int(character - 'A') + 10, true
    }
    return 0, false
}

// "#rgb", "#rrggbb" or "#rrggbbaa", the "#" is optional. Not ok for anything else (the color is then 0).
ColorFromHex :: proc(text: string) -> (rgb: [3]f32, alpha: f32, ok: bool) {
    body: string = text[1:] if len(text) > 0 && text[0] == '#' else text
    values: [4]int = {0, 0, 0, 255}
    switch len(body) {
    case 3:
        for i in 0 ..< 3 {
            d, valid := hexDigit(body[i])
            if !valid { return {}, 0, false }
            values[i] = d * 17
        }
    case 6, 8:
        for i in 0 ..< len(body) / 2 {
            high, valid_high := hexDigit(body[i * 2])
            low, valid_low := hexDigit(body[i * 2 + 1])
            if !valid_high || !valid_low { return {}, 0, false }
            values[i] = high * 16 + low
        }
    case:
        return {}, 0, false
    }
    return {f32(values[0]) / 255, f32(values[1]) / 255, f32(values[2]) / 255}, f32(values[3]) / 255, true
}

// The picker. `alpha` nil: no bar for it. `size`: the side of the square in pixels (0: a little more than a slider is wide).
UiColorPicker :: proc(ctx: ^Context, name: string, color: ^[3]f32, alpha: ^f32 = nil, size: f32 = 0) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    metrics: ^Metrics = &ctx.style.metrics
    side: f32 = size if size > 0 else metrics.control_width * 1.2

    // what the person chose, unless the program set another color since
    held: [3]f32 = ColorHsvToRgb(state.hsv[0], state.hsv[1], state.hsv[2])
    if !state.initialized || abs(held.r - color.r) > 0.002 || abs(held.g - color.g) > 0.002 || abs(held.b - color.b) > 0.002 {
        h, s, v := ColorRgbToHsv(color^)
        if state.initialized {
            if s < 0.0001 || v < 0.0001 { h = state.hsv[0] }                    // a gray has no hue: keep the one there was
            if v < 0.0001 { s = state.hsv[1] }
        }
        state.hsv = {h, s, v}
        state.initialized = true
    }

    field_id: Id = IdFromString("field", id)
    hue_id: Id = IdFromString("hue", id)
    alpha_id: Id = IdFromString("alpha", id)
    _ = stateGet(ctx, field_id)
    field: Interaction = widgetBehavior(ctx, field_id)
    if field.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && field.rect.z > 0 && field.rect.w > 0 {
        state.hsv[1] = clamp((ctx.input.mouse_position.x - field.rect.x) / field.rect.z, 0, 1)
        state.hsv[2] = 1 - clamp((ctx.input.mouse_position.y - field.rect.y) / field.rect.w, 0, 1)
        changed = true
    }
    _ = stateGet(ctx, hue_id)
    hue: Interaction = widgetBehavior(ctx, hue_id)
    if hue.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && hue.rect.w > 0 {
        state.hsv[0] = min(clamp((ctx.input.mouse_position.y - hue.rect.y) / hue.rect.w, 0, 1), 0.9999)
        changed = true
    }
    if alpha != nil {
        _ = stateGet(ctx, alpha_id)
        bar: Interaction = widgetBehavior(ctx, alpha_id)
        if bar.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && bar.rect.w > 0 {
            alpha^ = 1 - clamp((ctx.input.mouse_position.y - bar.rect.y) / bar.rect.w, 0, 1)
            changed = true
        }
    }
    if changed { color^ = ColorHsvToRgb(state.hsv[0], state.hsv[1], state.hsv[2]) }

    ElementOpen(ctx, {id = id, layout = {direction = .TOP_TO_BOTTOM, gap = metrics.gap}})
    ElementOpen(ctx, {layout = {direction = .LEFT_TO_RIGHT, gap = 4}})
    ElementOpen(ctx, {
        id = field_id,
        layout = {size = {Fixed(side), Fixed(side)}},
        hit = {.INTERACTIVE},
        draw = {kind = .COLOR_FIELD, name = IdSplitName(name), actual = state.hsv[0], value = state.hsv[1], ratio = state.hsv[2], color = colorBytes(ColorHsvToRgb(state.hsv[0], 1, 1))},
    })
    ElementClose(ctx)
    ElementOpen(ctx, {
        id = hue_id,
        layout = {size = {Fixed(COLOR_PICKER_BAR), Fixed(side)}},
        hit = {.INTERACTIVE},
        draw = {kind = .COLOR_STRIP, actual = 0, value = state.hsv[0]},
    })
    ElementClose(ctx)
    if alpha != nil {
        ElementOpen(ctx, {
            id = alpha_id,
            layout = {size = {Fixed(COLOR_PICKER_BAR), Fixed(side)}},
            hit = {.INTERACTIVE},
            draw = {kind = .COLOR_STRIP, actual = 1, value = 1 - clamp(alpha^, 0, 1), color = colorBytes(color^)},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
    // the result and its channels
    ElementOpen(ctx, {layout = {direction = .LEFT_TO_RIGHT, gap = 2, align = {y = .CENTER}}})
    preview: Color = colorBytes(color^)
    if alpha != nil { preview.a = u8(clamp(alpha^, 0, 1) * 255 + 0.5) }
    ElementOpen(ctx, {
        layout = {size = {Fixed(metrics.control_height), Fixed(metrics.control_height)}},
        draw = {kind = .SWATCH, color = preview},
    })
    ElementClose(ctx)
    for channel in 0 ..< 3 {
        if dragBox(ctx, IdFromIndex(u32(channel), id), &color[channel], 0.005, 0, 1, "%.2f", {Fixed(metrics.control_width * 0.4), {}}, false) { changed = true }
    }
    ElementClose(ctx)
    ElementClose(ctx)
    return
}
