package ui

// The value bar of an audio program: a number shown as a bar that fills, with the value written in it. Dragging sideways changes it (relative to where the press was: the bar
// does not jump to the pointer), Shift makes it ten times finer, a double click (or Enter on the focused bar) types the number, Ctrl + click or Delete resets it to the default,
// the arrows of the navigation step it. A bipolar bar (a pan) fills from its middle. Under the tag "modulation" the style hatches the fill: how an amount of modulation reads
// apart from a live value.
//
// Limits: one bar is typed into at a time (the text is kept in the context, 24 bytes); the typed text is read as a number (leading digits, sign, point, exponent) unless
// the spec has its own `from_text`; no unit conversion; the drag is horizontal only; no automation gestures (begin / end of a drag): `changed` is true on every frame it moves.

import "core:fmt"
import "core:math"
import "core:strconv"

// Writes a value the way the bar shows it ("30L") into `buffer` and returns the text
ValueBarToText :: proc(value: f32, buffer: []u8) -> string

// Reads what was typed ("30L"): the value and whether it made sense
ValueBarFromText :: proc(text: string) -> (value: f32, ok: bool)

ValueBarSpec :: struct {
    minimum: f32,                   // minimum and maximum both 0: the range is 0 .. 1
    maximum: f32,
    default_value: f32,             // Ctrl + click, Delete and the middle of a bipolar bar
    format: string,                 // "%.2f" when empty
    snap: f32,                      // above 0: the value lands on multiples of it while it is dragged (typing stays exact)
    bipolar: bool,                  // the fill grows from the default value, to the left or to the right
    to_text: ValueBarToText,        // nil: `format`
    from_text: ValueBarFromText,    // nil: a plain number
}

VALUE_BAR_FINE :: 0.1               // how much of a pixel of drag Shift keeps

// A pan: -1 (left) .. 1 (right), written "30L", "C", "12R" in percent
ValueBarPan :: proc() -> ValueBarSpec {
    return {minimum = -1, maximum = 1, bipolar = true, to_text = valueBarPanText, from_text = valueBarPanParse}
}

@(private)
valueBarPanText :: proc(value: f32, buffer: []u8) -> string {
    percent: int = int(math.round(abs(value) * 100))
    if percent == 0 { return fmt.bprintf(buffer, "C") }
    return fmt.bprintf(buffer, "%d%s", percent, "L" if value < 0 else "R")
}

@(private)
valueBarPanParse :: proc(text: string) -> (value: f32, ok: bool) {
    if len(text) == 0 { return 0, false }
    if text[0] == 'c' || text[0] == 'C' { return 0, true }
    number, _ := valueBarNumber(text)
    parsed, found := strconv.parse_f32(number)
    if !found { return 0, false }
    side: f32 = -1 if (text[len(text) - 1] | 0x20) == 'l' else 1
    return clamp(abs(parsed) / 100 * side, -1, 1), true
}

// The leading part of the text that is a number: sign, digits, a point, an exponent
@(private)
valueBarNumber :: proc(text: string) -> (number: string, rest: string) {
    end: int = 0
    for end < len(text) {
        c: u8 = text[end]
        digit: bool = c >= '0' && c <= '9'
        exponent: bool = (c == 'e' || c == 'E') && end > 0 && text[end - 1] >= '0' && text[end - 1] <= '9'
        if digit || c == '.' || c == '+' || c == '-' || exponent {
            end += 1
        } else {
            break
        }
    }
    return text[:end], text[end:]
}

@(private)
valueBarSnap :: proc(value: f32, spec: ValueBarSpec, minimum: f32, maximum: f32) -> f32 {
    result: f32 = value
    if spec.snap > 0 { result = math.round((value - minimum) / spec.snap) * spec.snap + minimum }
    return clamp(result, min(minimum, maximum), max(minimum, maximum))
}

// A bar that edits `value`. True in every frame the value changed.
UiValueBar :: proc(ctx: ^Context, name: string, value: ^f32, spec: ValueBarSpec = {}, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    minimum, maximum: f32 = spec.minimum, spec.maximum
    if minimum == 0 && maximum == 0 { maximum = 1 }
    range: f32 = maximum - minimum
    low, high: f32 = min(minimum, maximum), max(minimum, maximum)
    value^ = clamp(value^, low, high)

    typing: bool = ctx.entry_id == id
    start_typing: bool = false
    if !disabled && !typing {
        if interaction.double_clicked && interaction.pressed { start_typing = true }
        if interaction.clicked && !ctx.input.mouse_released { start_typing = true }        // the confirm key of the focused bar
    }
    if !typing && !start_typing {
        // press: Ctrl resets, else the drag starts from the value that is now
        if interaction.pressed && ctx.input.mouse_pressed && interaction.hovered {
            state.cursor = 0
            state.anim = value^
            state.drag.x = ctx.input.mouse_position.x
            if .CTRL in ctx.input.modifiers {
                state.cursor = 1                            // this press was a reset: moving afterwards does not drag
                if value^ != spec.default_value {
                    value^ = clamp(spec.default_value, low, high)
                    changed = true
                }
            }
        } else if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && state.cursor == 0 && state.rect.z > 0 && range != 0 {
            delta: f32 = ctx.input.mouse_position.x - state.drag.x
            state.drag.x = ctx.input.mouse_position.x
            if .SHIFT in ctx.input.modifiers { delta *= VALUE_BAR_FINE }
            state.anim = clamp(state.anim + delta / state.rect.z * range, low, high)
            moved: f32 = valueBarSnap(state.anim, spec, minimum, maximum)
            if moved != value^ {
                value^ = moved
                changed = true
            }
        }
        // the arrows step it by a twentieth of the range (a snap step when there is one), Delete puts the default back
        state.adjustable = true
        if state.pending_adjust != 0 && range != 0 {
            step: f32 = spec.snap if spec.snap > 0 else abs(range) / 20
            moved: f32 = valueBarSnap(value^ + f32(state.pending_adjust) * step, spec, minimum, maximum)
            if moved != value^ {
                value^ = moved
                changed = true
            }
        }
        state.pending_adjust = 0
        if ctx.focus == id && (.DELETE in ctx.input.keys || .BACKSPACE in ctx.input.keys) && value^ != spec.default_value {
            value^ = clamp(spec.default_value, low, high)
            changed = true
        }
    }

    if typing || start_typing {
        return valueBarType(ctx, id, value, spec, size, start_typing, low, high, disabled)
    }

    normalized: f32 = 0
    origin: f32 = 0
    if range != 0 {
        normalized = clamp((value^ - minimum) / range, 0, 1)
        if spec.bipolar { origin = clamp((spec.default_value - minimum) / range, 0, 1) }
    }
    text: string
    if spec.to_text != nil {
        buffer: [32]u8
        text = UiFormat(ctx, "%s", spec.to_text(value^, buffer[:]))
    } else {
        text = UiFormat(ctx, spec.format if spec.format != "" else "%.2f", value^)
    }
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_width, metrics.control_height)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .RESIZE_HORIZONTAL,
        draw = {
            kind = .VALUE_BAR, name = IdSplitName(name), text = text,
            value = normalized, ratio = origin, actual = value^, minimum = minimum, maximum = maximum,
            font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// The bar while its number is typed: a text field in the place of the bar. Enter or a click elsewhere keeps what was typed (when it is a number), Escape leaves the value alone.
@(private)
valueBarType :: proc(ctx: ^Context, id: Id, value: ^f32, spec: ValueBarSpec, size: Size, start: bool, low: f32, high: f32, disabled: bool) -> (changed: bool) {
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {id = id, layout = {size = widgetSize(size, metrics.control_width, metrics.control_height)}})
    defer ElementClose(ctx)
    field: Id = UiId(ctx, "##entry")
    if start {
        text: string
        if spec.to_text != nil {
            text = spec.to_text(value^, ctx.entry_buffer[:])
        } else {
            text = fmt.bprintf(ctx.entry_buffer[:], "%g", value^)
        }
        ctx.entry_id = id
        ctx.entry_length = len(text)
        field_state: ^WidgetState = stateGet(ctx, field)
        field_state.anchor, field_state.cursor = 0, ctx.entry_length          // everything selected: typing replaces it
        ctx.focus = field
    }
    _, submitted := UiTextField(ctx, "##entry", ctx.entry_buffer[:], &ctx.entry_length, {Grow(), Grow()}, disabled)
    cancelled: bool = .ESCAPE in ctx.input.keys || .CANCEL in ctx.input.actions
    if cancelled || submitted || (ctx.focus != field && !start) {
        if !cancelled {
            typed: string = string(ctx.entry_buffer[:ctx.entry_length])
            parsed: f32
            ok: bool
            if spec.from_text != nil {
                parsed, ok = spec.from_text(typed)
            } else {
                number, _ := valueBarNumber(typed)
                parsed, ok = strconv.parse_f32(number)
            }
            if ok {
                parsed = clamp(parsed, low, high)
                if parsed != value^ {
                    value^ = parsed
                    changed = true
                }
            }
        }
        ctx.entry_id = 0
        ctx.focus = id
    }
    return
}
