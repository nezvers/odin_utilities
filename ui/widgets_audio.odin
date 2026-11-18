package ui

// Controls of a mixing desk or a plugin: a knob, a fader, a level meter. They are plain widgets like the slider (one element, a StyleKind, the value as 0..1
// and as the real number), so a style draws them any way it wants and nothing of them allocates.

// How far the pointer has to go for the knob to turn through its whole range (dragging up turns it up).
KNOB_DRAG_PIXELS :: 160
// The part of the range one step of the wheel moves a knob or a fader.
WHEEL_STEP :: 0.02

@(private)
normalizedOf :: proc(value: f32, minimum: f32, maximum: f32) -> f32 {
    range: f32 = maximum - minimum
    if range == 0 { return 0 }
    return clamp((value - minimum) / range, 0, 1)
}

// A round control that is turned by dragging up and down (the wheel and the keys of the navigation also turn it, a double click sets `default_value`).
// The style gets value 0..1, the real number (`actual`) and its text made with `format`; the size is a square (the height of two controls by default).
UiKnob :: proc(ctx: ^Context, name: string, value: ^f32, minimum: f32 = 0, maximum: f32 = 1, default_value: f32 = 0, size: Size = {}, format: string = "%.2f", disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    range: f32 = maximum - minimum
    set :: proc(value: ^f32, new_value: f32, minimum: f32, maximum: f32) -> bool {
        clamped: f32 = clamp(new_value, min(minimum, maximum), max(minimum, maximum))
        if clamped == value^ { return false }
        value^ = clamped
        return true
    }
    if interaction.double_clicked {
        changed = set(value, default_value, minimum, maximum) || changed
    } else if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        if ctx.input.mouse_pressed {
            state.drag = ctx.input.mouse_position
        } else {
            moved: f32 = state.drag.y - ctx.input.mouse_position.y
            state.drag = ctx.input.mouse_position
            changed = set(value, value^ + moved * range / KNOB_DRAG_PIXELS, minimum, maximum) || changed
        }
    }
    if interaction.hovered && ctx.input.wheel.y != 0 {
        changed = set(value, value^ + ctx.input.wheel.y * range * WHEEL_STEP, minimum, maximum) || changed
    }
    // left and right of the navigation: a twentieth of the range per step
    state.adjustable = true
    if state.pending_adjust != 0 {
        changed = set(value, value^ + f32(state.pending_adjust) * range / 20, minimum, maximum) || changed
    }
    state.pending_adjust = 0
    metrics: ^Metrics = &ctx.style.metrics
    flags: Flags = {.DISABLED} if disabled else {}
    side: f32 = metrics.control_height * 2
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, side, side)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .RESIZE_VERTICAL,
        draw = {
            kind = .KNOB, name = IdSplitName(name), text = UiFormat(ctx, format, value^),
            value = normalizedOf(value^, minimum, maximum), actual = value^, minimum = minimum, maximum = maximum,
            ratio = normalizedOf(default_value, minimum, maximum),          // where the notch of the default is
            font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// The height of the handle of a fader that is `width` wide: the pointer sets the value by the middle of the handle, which travels the height of the fader minus this.
// A style draws its handle this high (or the pointer and the handle part ways at the ends).
FaderHandleHeight :: proc(width: f32) -> f32 {
    return max(width * 0.7, 10)
}

// A slider that stands up (the top is the maximum): the pointer sets the value where it is, the wheel and the up and down keys step it, a double click sets
// `default_value`. The style gets value 0..1, the real number and its text.
UiFader :: proc(ctx: ^Context, name: string, value: ^f32, minimum: f32 = 0, maximum: f32 = 1, default_value: f32 = 0, size: Size = {}, format: string = "%.2f", disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    range: f32 = maximum - minimum
    set :: proc(value: ^f32, new_value: f32, minimum: f32, maximum: f32) -> bool {
        clamped: f32 = clamp(new_value, min(minimum, maximum), max(minimum, maximum))
        if clamped == value^ { return false }
        value^ = clamped
        return true
    }
    if interaction.double_clicked {
        changed = set(value, default_value, minimum, maximum) || changed
    } else if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && state.rect.w > 0 && range != 0 {
        handle: f32 = FaderHandleHeight(state.rect.z)
        run: f32 = max(state.rect.w - handle, 1)
        t: f32 = clamp(1 - (ctx.input.mouse_position.y - state.rect.y - handle * 0.5) / run, 0, 1)
        changed = set(value, minimum + t * range, minimum, maximum) || changed
    }
    if interaction.hovered && ctx.input.wheel.y != 0 {
        changed = set(value, value^ + ctx.input.wheel.y * range * WHEEL_STEP, minimum, maximum) || changed
    }
    // up and down of the navigation (up turns it up): a twentieth of the range per step
    state.adjustable = true
    state.adjust_vertical = true
    if state.pending_adjust != 0 {
        changed = set(value, value^ - f32(state.pending_adjust) * range / 20, minimum, maximum) || changed
    }
    state.pending_adjust = 0
    metrics: ^Metrics = &ctx.style.metrics
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_height * 1.2, metrics.control_height * 5)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .RESIZE_VERTICAL,
        draw = {
            kind = .FADER, name = IdSplitName(name), text = UiFormat(ctx, format, value^),
            value = normalizedOf(value^, minimum, maximum), actual = value^, minimum = minimum, maximum = maximum,
            ratio = normalizedOf(default_value, minimum, maximum),
            font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// A level meter: `level` between `minimum` and `maximum` (any unit, a program that wants decibels gives them), and `peak`, a mark that the program holds and
// lets fall (a number outside of the range shows none). Standing (the default) or lying. Nothing to click. The style gets value 0..1 for the level and
// `ratio` 0..1 for the peak (negative: none); `cursor` is 1 for a meter that lies.
UiMeter :: proc(ctx: ^Context, name: string, level: f32, peak: f32 = -INFINITE, minimum: f32 = 0, maximum: f32 = 1, size: Size = {}, horizontal: bool = false) {
    metrics: ^Metrics = &ctx.style.metrics
    long: f32 = metrics.control_height * 5
    thin: f32 = metrics.control_height * 0.6
    peak_value: f32 = -1
    if peak >= minimum && peak <= maximum { peak_value = normalizedOf(peak, minimum, maximum) }
    ElementOpen(ctx, {
        id = UiId(ctx, name),
        layout = {size = widgetSize(size, long if horizontal else thin, thin if horizontal else long)},
        draw = {
            kind = .METER, name = IdSplitName(name), value = normalizedOf(level, minimum, maximum), actual = level,
            minimum = minimum, maximum = maximum, ratio = peak_value, cursor = 1 if horizontal else 0, font_size = metrics.font_size,
        },
    })
    ElementClose(ctx)
}
