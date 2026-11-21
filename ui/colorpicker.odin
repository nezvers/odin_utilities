package ui

import "core:math"

// A color picker: a square for saturation and brightness, a bar for the hue, an optional bar for the alpha, a swatch of the result and the three channels as drag values; a row of modes below
// (a dropdown) changes the square into bars of the channels of HSV, HSL, RGB or OKLCH (lightness, chroma, hue: the one whose steps look even), every bar drawn at the resolution of the screen (no cells). The program owns the
// color (`[3]f32`, 0..1, and the alpha as a `f32`); the picker keeps the hue and the saturation that the person chose in its own state, because a gray or a black has none in RGB and
// dragging down to black would lose the hue for good. A color that the program changes meanwhile is taken at once. Each part takes the keyboard: Tab reaches the square and the bars, the arrow keys move the focused one.
//
//     color: [3]f32 = {0.9, 0.4, 0.1}
//     alpha: f32 = 1
//     if ui.UiColorPicker(&ctx, "Tint", &color, &alpha) { ... }          // true in the frames the person changes it
//
// ColorHsvToRgb, ColorRgbToHsv, ColorToHex and ColorFromHex are plain helpers for a program that has its own hex field or its own palette.

COLOR_PICKER_BAR :: f32(22)                 // the width of the hue and alpha bars
COLOR_PICKER_STEP :: f32(0.02)              // what an arrow key moves a focused part of the picker

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

COLOR_BAR_HEIGHT :: f32(20)                 // a channel bar of the bar modes

// What the picker shows: a square (saturation and brightness at the hue) with a hue bar, or one bar for each channel of a color space.
ColorMode :: enum u8 {
    SQUARE,
    HSV,
    HSL,
    RGB,
    OKLCH,
}

COLOR_MODE_LABELS :: [?]string{"Field", "HSV", "HSL", "RGB", "OKLCH"}

// The largest value of a channel of a mode (the bar is 0 .. this): hue in degrees for OKLCH, a chroma that sRGB reaches (about 0.32) rounded up.
ColorChannelMax :: proc(mode: ColorMode, channel: int) -> f32 {
    if mode == .OKLCH {
        switch channel {
        case 1: return 0.4
        case 2: return 360
        }
    }
    return 1
}

ColorChannelName :: proc(mode: ColorMode, channel: int) -> string {
    names: [ColorMode][3]string = {
        .SQUARE = {"H", "S", "V"}, .HSV = {"H", "S", "V"}, .HSL = {"H", "S", "L"}, .RGB = {"R", "G", "B"}, .OKLCH = {"L", "C", "H"},
    }
    return names[mode][clamp(channel, 0, 2)]
}

// The color of a mode's channel bar at the place `t` (0 .. 1) of its width, the other two channels as they are in `values` (the units of ColorChannelMax). For a style: one call per strip of the bar.
ColorChannelColor :: proc(mode: ColorMode, channel: int, t: f32, values: [3]f32) -> [3]f32 {
    v: [3]f32 = values
    v[channel] = clamp(t, 0, 1) * ColorChannelMax(mode, channel)
    switch mode {
    case .SQUARE, .HSV: return ColorHsvToRgb(v[0], v[1], v[2])
    case .HSL: return ColorHslToRgb(v[0], v[1], v[2])
    case .RGB: return v
    case .OKLCH: return ColorOklchToRgb(v[0], v[1], v[2])
    }
    return v
}

// HSL: the hue as in HSV, then saturation and lightness. A gray has no hue: the caller keeps its own.
ColorHslToRgb :: proc(h: f32, s: f32, l: f32) -> [3]f32 {
    value: f32 = l + s * min(l, 1 - l)
    saturation: f32 = 0 if value <= 0 else 2 * (1 - l / value)
    return ColorHsvToRgb(h, clamp(saturation, 0, 1), clamp(value, 0, 1))
}

ColorRgbToHsl :: proc(rgb: [3]f32) -> (h: f32, s: f32, l: f32) {
    hue, saturation, value := ColorRgbToHsv(rgb)
    l = value * (1 - saturation * 0.5)
    divisor: f32 = min(l, 1 - l)
    s = 0 if divisor <= 0.00001 else (value - l) / divisor
    return hue, clamp(s, 0, 1), l
}

@(private)
srgbToLinear :: proc(x: f32) -> f32 {
    return x / 12.92 if x <= 0.04045 else math.pow((x + 0.055) / 1.055, 2.4)
}

@(private)
linearToSrgb :: proc(x: f32) -> f32 {
    return x * 12.92 if x <= 0.0031308 else 1.055 * math.pow(x, 1 / 2.4) - 0.055
}

@(private)
cubeRoot :: proc(x: f32) -> f32 {
    return -math.pow(-x, 1.0 / 3.0) if x < 0 else math.pow(x, 1.0 / 3.0)
}

// OKLCH (Bjorn Ottosson's Oklab): lightness 0..1, chroma 0 (gray) to about 0.32, hue in degrees. A color that sRGB cannot show loses chroma until it can, the lightness and the hue are kept.
ColorOklchToRgb :: proc(lightness: f32, chroma: f32, hue: f32) -> [3]f32 {
    radians: f32 = hue * math.PI / 180
    c: f32 = max(chroma, 0)
    linear: [3]f32
    for _ in 0 ..< 25 {
        a: f32 = c * math.cos(radians)
        b: f32 = c * math.sin(radians)
        l: f32 = lightness + 0.3963377774 * a + 0.2158037573 * b
        m: f32 = lightness - 0.1055613458 * a - 0.0638541728 * b
        n: f32 = lightness - 0.0894841775 * a - 1.2914855480 * b
        l, m, n = l * l * l, m * m * m, n * n * n
        linear = {4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * n, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * n, -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * n}
        LIMIT :: 0.0005
        if linear.x >= -LIMIT && linear.x <= 1 + LIMIT && linear.y >= -LIMIT && linear.y <= 1 + LIMIT && linear.z >= -LIMIT && linear.z <= 1 + LIMIT { break }
        c *= 0.85
    }
    return {linearToSrgb(clamp(linear.x, 0, 1)), linearToSrgb(clamp(linear.y, 0, 1)), linearToSrgb(clamp(linear.z, 0, 1))}
}

ColorRgbToOklch :: proc(rgb: [3]f32) -> (lightness: f32, chroma: f32, hue: f32) {
    r, g, b: f32 = srgbToLinear(rgb.r), srgbToLinear(rgb.g), srgbToLinear(rgb.b)
    l: f32 = cubeRoot(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m: f32 = cubeRoot(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    n: f32 = cubeRoot(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * n
    a: f32 = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * n
    c: f32 = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * n
    chroma = math.sqrt(a * a + c * c)
    hue = math.atan2(c, a) * 180 / math.PI
    if hue < 0 { hue += 360 }
    return
}

// The channels of a mode as the picker keeps them (the units of ColorChannelMax): the hue and the lightness / chroma that the person set where the color cannot say (a gray has no hue).
@(private)
pickerChannels :: proc(state: ^WidgetState, mode: ColorMode, color: [3]f32) -> [3]f32 {
    switch mode {
    case .SQUARE, .HSV: return state.hsv
    case .HSL:
        _, s, l := ColorRgbToHsl(color)
        return {state.hsv[0], s, l}
    case .RGB: return color
    case .OKLCH: return state.lch
    }
    return color
}

// The picker takes a new color: both of its color spaces are brought to it, keeping the hue where the color has none.
@(private)
pickerSync :: proc(state: ^WidgetState, color: [3]f32, keep_lch: bool = false) {
    h, s, v := ColorRgbToHsv(color)
    if state.initialized {
        if s < 0.0001 || v < 0.0001 { h = state.hsv[0] }
        if v < 0.0001 { s = state.hsv[1] }
    }
    state.hsv = {h, s, v}
    if !keep_lch {
        lightness, chroma, hue := ColorRgbToOklch(color)
        if state.initialized && chroma < 0.002 { hue = state.lch[2] }
        state.lch = {lightness, chroma, hue}
    }
    state.held = color
    state.initialized = true
}

// A channel was set to `values` in `mode`: the new color.
@(private)
pickerCommit :: proc(state: ^WidgetState, mode: ColorMode, values: [3]f32) -> [3]f32 {
    color: [3]f32
    switch mode {
    case .SQUARE, .HSV:
        color = ColorHsvToRgb(values[0], values[1], values[2])
        pickerSync(state, color, false)
        state.hsv = values
    case .HSL:
        color = ColorHslToRgb(values[0], values[1], values[2])
        pickerSync(state, color, false)
        if state.hsv[1] > 0.0001 && state.hsv[2] > 0.0001 { state.hsv[0] = values[0] }
    case .RGB:
        color = values
        pickerSync(state, color, false)
    case .OKLCH:
        color = ColorOklchToRgb(values[0], values[1], values[2])
        pickerSync(state, color, true)
        state.lch = values
    }
    state.held = color
    return color
}

@(private)
colorsDiffer :: proc(a: [3]f32, b: [3]f32) -> bool {
    return abs(a.r - b.r) > 0.002 || abs(a.g - b.g) > 0.002 || abs(a.b - b.b) > 0.002
}

// The picker. `alpha` nil: no bar for it. `size`: the side of the square in pixels (0: a little more than a slider is wide).
UiColorPicker :: proc(ctx: ^Context, name: string, color: ^[3]f32, alpha: ^f32 = nil, size: f32 = 0) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    metrics: ^Metrics = &ctx.style.metrics
    side: f32 = size if size > 0 else metrics.control_width * 1.2
    mode: ColorMode = ColorMode(clamp(state.mode, 0, int(max(ColorMode))))

    // what the person chose, unless the program set another color since
    if !state.initialized || colorsDiffer(state.held, color^) { pickerSync(state, color^) }

    field_id: Id = IdFromString("field", id)
    hue_id: Id = IdFromString("hue", id)
    alpha_id: Id = IdFromString("alpha", id)
    if mode == .SQUARE {
        field_state: ^WidgetState = stateGet(ctx, field_id)
        field: Interaction = widgetBehavior(ctx, field_id)
        field_state.adjust_both = true
        if field_state.pending_adjust != 0 || field_state.pending_adjust_y != 0 {
            // the arrow keys of a focused square: right is more saturation, down is less brightness
            values: [3]f32 = state.hsv
            values[1] = clamp(values[1] + f32(field_state.pending_adjust) * COLOR_PICKER_STEP, 0, 1)
            values[2] = clamp(values[2] - f32(field_state.pending_adjust_y) * COLOR_PICKER_STEP, 0, 1)
            field_state.pending_adjust, field_state.pending_adjust_y = 0, 0
            color^ = pickerCommit(state, .SQUARE, values)
            changed = true
        }
        if field.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && field.rect.z > 0 && field.rect.w > 0 {
            values: [3]f32 = state.hsv
            values[1] = clamp((ctx.input.mouse_position.x - field.rect.x) / field.rect.z, 0, 1)
            values[2] = 1 - clamp((ctx.input.mouse_position.y - field.rect.y) / field.rect.w, 0, 1)
            color^ = pickerCommit(state, .SQUARE, values)
            changed = true
        }
        hue_state: ^WidgetState = stateGet(ctx, hue_id)
        hue_state.adjust_vertical = true
        if hue_state.pending_adjust != 0 {
            values: [3]f32 = state.hsv
            values[0] = clamp(values[0] + f32(hue_state.pending_adjust) * COLOR_PICKER_STEP, 0, 0.9999)
            hue_state.pending_adjust = 0
            color^ = pickerCommit(state, .SQUARE, values)
            changed = true
        }
        hue: Interaction = widgetBehavior(ctx, hue_id)
        if hue.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && hue.rect.w > 0 {
            values: [3]f32 = state.hsv
            values[0] = min(clamp((ctx.input.mouse_position.y - hue.rect.y) / hue.rect.w, 0, 1), 0.9999)
            color^ = pickerCommit(state, .SQUARE, values)
            changed = true
        }
    } else {
        // a bar for each channel: the pointer sets the place along it, left and right of the navigation step it
        for channel in 0 ..< 3 {
            bar_id: Id = IdFromIndex(u32(channel), hue_id)
            bar_state: ^WidgetState = stateGet(ctx, bar_id)
            bar_state.adjustable = true
            bar: Interaction = widgetBehavior(ctx, bar_id)
            maximum: f32 = ColorChannelMax(mode, channel)
            top: f32 = maximum * (0.9999 if channel == 0 && (mode == .HSV || mode == .HSL) else 1)
            values: [3]f32 = pickerChannels(state, mode, color^)
            moved: bool
            if bar_state.pending_adjust != 0 {
                values[channel] = clamp(values[channel] + f32(bar_state.pending_adjust) * COLOR_PICKER_STEP * maximum, 0, top)
                bar_state.pending_adjust = 0
                moved = true
            }
            if bar.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && bar.rect.z > 0 {
                values[channel] = min(clamp((ctx.input.mouse_position.x - bar.rect.x) / bar.rect.z, 0, 1) * maximum, top)
                moved = true
            }
            if moved {
                color^ = pickerCommit(state, mode, values)
                changed = true
            }
        }
    }
    if alpha != nil {
        alpha_state: ^WidgetState = stateGet(ctx, alpha_id)
        bar: Interaction = widgetBehavior(ctx, alpha_id)
        if mode == .SQUARE {
            alpha_state.adjust_vertical = true
            if alpha_state.pending_adjust != 0 {
                alpha^ = clamp(alpha^ - f32(alpha_state.pending_adjust) * COLOR_PICKER_STEP, 0, 1)
                alpha_state.pending_adjust = 0
                changed = true
            }
            if bar.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && bar.rect.w > 0 {
                alpha^ = 1 - clamp((ctx.input.mouse_position.y - bar.rect.y) / bar.rect.w, 0, 1)
                changed = true
            }
        } else {
            alpha_state.adjustable = true
            if alpha_state.pending_adjust != 0 {
                alpha^ = clamp(alpha^ + f32(alpha_state.pending_adjust) * COLOR_PICKER_STEP, 0, 1)
                alpha_state.pending_adjust = 0
                changed = true
            }
            if bar.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && bar.rect.z > 0 {
                alpha^ = clamp((ctx.input.mouse_position.x - bar.rect.x) / bar.rect.z, 0, 1)
                changed = true
            }
        }
    }

    channels: [3]f32 = pickerChannels(state, mode, color^)
    ElementOpen(ctx, {id = id, layout = {direction = .TOP_TO_BOTTOM, gap = metrics.gap}})
    if mode == .SQUARE {
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
    } else {
        ElementOpen(ctx, {layout = {direction = .TOP_TO_BOTTOM, gap = 8}})
        width: f32 = side + COLOR_PICKER_BAR + 4 + (COLOR_PICKER_BAR + 4 if alpha != nil else 0)
        for channel in 0 ..< 3 {
            maximum: f32 = ColorChannelMax(mode, channel)
            ElementOpen(ctx, {
                id = IdFromIndex(u32(channel), hue_id),
                layout = {size = {Fixed(width), Fixed(COLOR_BAR_HEIGHT)}},
                hit = {.INTERACTIVE},
                draw = {kind = .COLOR_STRIP, actual = 2, value = channels[channel] / maximum, cursor = int(mode), anchor = channel, minimum = channels[0], maximum = channels[1], ratio = channels[2], name = ColorChannelName(mode, channel)},
            })
            ElementClose(ctx)
        }
        if alpha != nil {
            ElementOpen(ctx, {
                id = alpha_id,
                layout = {size = {Fixed(width), Fixed(COLOR_BAR_HEIGHT)}},
                hit = {.INTERACTIVE},
                draw = {kind = .COLOR_STRIP, actual = 3, value = clamp(alpha^, 0, 1), color = colorBytes(color^), name = "A"},
            })
            ElementClose(ctx)
        }
        ElementClose(ctx)
    }
    // the result and its channels
    ElementOpen(ctx, {layout = {direction = .LEFT_TO_RIGHT, gap = 2, align = {y = .CENTER}}})
    preview: Color = colorBytes(color^)
    if alpha != nil { preview.a = u8(clamp(alpha^, 0, 1) * 255 + 0.5) }
    ElementOpen(ctx, {
        layout = {size = {Fixed(metrics.control_height), Fixed(metrics.control_height)}},
        draw = {kind = .SWATCH, color = preview},
    })
    ElementClose(ctx)
    shown: ColorMode = .RGB if mode == .SQUARE else mode
    box_values: [3]f32 = pickerChannels(state, shown, color^)
    formats: [3]string = {"%.2f", "%.2f", "%.2f"}
    if shown == .OKLCH { formats = {"%.2f", "%.3f", "%.0f"} }
    for channel in 0 ..< 3 {
        edited: f32 = box_values[channel]
        if dragBox(ctx, IdFromIndex(u32(channel), id), &edited, 0.005 * ColorChannelMax(shown, channel), 0, ColorChannelMax(shown, channel), formats[channel], {Fixed(metrics.control_width * 0.4), {}}, false) {
            box_values[channel] = edited
            color^ = pickerCommit(state, shown, box_values)
            changed = true
        }
    }
    ElementClose(ctx)
    modes: [len(COLOR_MODE_LABELS)]string = COLOR_MODE_LABELS
    selected: int = int(mode)
    if UiDropdown(ctx, "##mode", modes[:], &selected, {Grow(), {}}) { state.mode = selected }
    ElementClose(ctx)
    return
}
