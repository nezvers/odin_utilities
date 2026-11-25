package ui

// The smaller controls of an audio program that the base widgets lack:
//
//   UiRangeSlider     two handles on one track (a low and a high value, never crossing)
//   UiXYPad           a square with a point that two values follow, an optional ghost for the value that actually arrives (after modulation)
//   UiWheel           a vertical wheel: a pitch bend that springs back to its rest value when let go, or a modulation wheel that stays
//   UiScrollBar       a thin scroll bar for views that scroll by their own data (a pill: thumb length is the visible part)
//   UiKeyboard        a piano keyboard: lit notes, the root outlined, a press plays a key (a glide over the keys plays each one)
//   UiStepGrid        a grid of steps (a drum pattern, an arpeggiator): press and drag paint steps on or off, a playhead column
//
// The pointer arithmetic of each is a pure proc (`KeyboardKeyAt`, `StepGridCellAt`, `ScrollBarThumb`), so the style and the tests agree with it. Every widget writes through the pointers it is
// given and returns true in the frame the person changed something.
//
// Limits: the range slider, wheel and scroll bar lie or stand as their name says (the range slider is horizontal, the wheel vertical, the scroll bar either); no keyboard control of the
// handles of a range slider (use two `UiSlider`s for that); the XY pad is 0..1 on both axes (the program maps it); the keyboard has no velocity from the press position and no
// multitouch; the step grid keeps one value per step (0 off, above 0 on: the program may use the number as a velocity), no per step lengths or ratchets.

import "core:math"

// ------------------------------------------------------------------------------------------------------------------------
// Range slider

RANGE_HANDLE :: 7                       // half the width of a handle, the track starts this far from the edge

// A track with two handles. `low` never goes above `high` and the other way round. The press takes the handle that is nearest, and the pointer sets it.
UiRangeSlider :: proc(ctx: ^Context, name: string, low: ^f32, high: ^f32, minimum: f32 = 0, maximum: f32 = 1, size: Size = {}, format: string = "%.2f", disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    range: f32 = maximum - minimum
    low^ = clamp(low^, min(minimum, maximum), max(minimum, maximum))
    high^ = clamp(high^, low^, max(minimum, maximum))
    if range != 0 && state.rect.z > RANGE_HANDLE * 2 {
        x0: f32 = state.rect.x + RANGE_HANDLE
        run: f32 = state.rect.z - RANGE_HANDLE * 2
        mouse_x: f32 = ctx.input.mouse_position.x
        if interaction.pressed && ctx.input.mouse_pressed && interaction.hovered {
            low_x: f32 = x0 + run * (low^ - minimum) / range
            high_x: f32 = x0 + run * (high^ - minimum) / range
            // the nearer handle; when they are on top of each other the pointer's side decides
            state.cursor = 0 if abs(mouse_x - low_x) < abs(mouse_x - high_x) || (low_x == high_x && mouse_x < low_x) else 1
        }
        if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
            value: f32 = minimum + clamp((mouse_x - x0) / run, 0, 1) * range
            if state.cursor == 0 {
                moved: f32 = min(value, high^)
                if moved != low^ { low^, changed = moved, true }
            } else {
                moved: f32 = max(value, low^)
                if moved != high^ { high^, changed = moved, true }
            }
        }
    }
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_width, metrics.control_height)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .RESIZE_HORIZONTAL,
        draw = {
            kind = .RANGE_SLIDER, name = IdSplitName(name), text = UiFormat(ctx, "%s - %s", UiFormat(ctx, format, low^), UiFormat(ctx, format, high^)),
            value = normalizedOf(low^, minimum, maximum), ratio = normalizedOf(high^, minimum, maximum), actual = low^, minimum = minimum, maximum = maximum,
            cursor = state.cursor, font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// XY pad

// A square pad: `x` and `y` are 0..1 (y up). A press sets the point where the pointer is and a drag follows it; with Shift the point moves a tenth as far as the pointer. A double click
// sets `default`. `ghost` (optional, x and y 0..1, alive until UiRender) is drawn as a second, hollow point: where the value arrives after modulation.
UiXYPad :: proc(ctx: ^Context, name: string, x: ^f32, y: ^f32, default: Vec2 = {0.5, 0.5}, ghost: ^[2]f32 = nil, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    set :: proc(x: ^f32, y: ^f32, new_x: f32, new_y: f32) -> bool {
        nx, ny: f32 = clamp(new_x, 0, 1), clamp(new_y, 0, 1)
        if nx == x^ && ny == y^ { return false }
        x^, y^ = nx, ny
        return true
    }
    x^, y^ = clamp(x^, 0, 1), clamp(y^, 0, 1)
    mouse: Vec2 = ctx.input.mouse_position
    if interaction.double_clicked && !disabled {
        changed = set(x, y, default.x, default.y) || changed
    } else if interaction.pressed && state.rect.z > 0 && state.rect.w > 0 && (ctx.input.mouse_down || ctx.input.mouse_released || ctx.input.mouse_pressed) {
        fine: bool = .SHIFT in ctx.input.modifiers
        if fine {
            if !ctx.input.mouse_pressed {
                delta: Vec2 = mouse - state.drag
                changed = set(x, y, x^ + delta.x / state.rect.z * 0.1, y^ - delta.y / state.rect.w * 0.1) || changed
            }
        } else {
            changed = set(x, y, (mouse.x - state.rect.x) / state.rect.z, 1 - (mouse.y - state.rect.y) / state.rect.w) || changed
        }
        state.drag = mouse
    }
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_height * 5, metrics.control_height * 5)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .HAND,
        draw = {
            kind = .XY_PAD, name = IdSplitName(name), text = UiFormat(ctx, "%.2f, %.2f", x^, y^), value = x^, ratio = y^, actual = x^,
            values = ghost[:] if ghost != nil else nil, font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Wheel

// A wheel that stands up. The drag changes the value by the distance travelled (the whole height of the wheel is the whole range); `spring`: when it is let go the value returns to `rest`
// at once (a pitch bend: -1 .. 1, rest 0), otherwise it stays (a modulation wheel). A double click sets `rest`.
UiWheel :: proc(ctx: ^Context, name: string, value: ^f32, minimum: f32 = -1, maximum: f32 = 1, rest: f32 = 0, spring: bool = true, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    range: f32 = maximum - minimum
    low, high: f32 = min(minimum, maximum), max(minimum, maximum)
    value^ = clamp(value^, low, high)
    set :: proc(value: ^f32, moved: f32, low: f32, high: f32) -> bool {
        clamped: f32 = clamp(moved, low, high)
        if clamped == value^ { return false }
        value^ = clamped
        return true
    }
    if range != 0 && state.rect.w > 0 && !disabled {
        if interaction.double_clicked {
            changed = set(value, rest, low, high) || changed
        } else if interaction.pressed && ctx.input.mouse_pressed && interaction.hovered {
            state.drag.y = ctx.input.mouse_position.y
            state.anim = value^
        } else if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
            state.anim = clamp(state.anim + (state.drag.y - ctx.input.mouse_position.y) / state.rect.w * range, low, high)
            state.drag.y = ctx.input.mouse_position.y
            changed = set(value, state.anim, low, high) || changed
        }
        if spring && !interaction.pressed && value^ != rest {
            changed = set(value, rest, low, high) || changed
        }
    }
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_height * 1.2, metrics.control_height * 4)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .RESIZE_VERTICAL,
        draw = {
            kind = .WHEEL, name = IdSplitName(name), value = normalizedOf(value^, minimum, maximum), ratio = normalizedOf(rest, minimum, maximum), actual = value^,
            minimum = minimum, maximum = maximum, font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Scroll bar

SCROLL_BAR_THICKNESS :: 10
SCROLL_BAR_MIN_THUMB :: 24

// The thumb of a scroll bar on a track of `length` pixels: where it starts and how long it is
ScrollBarThumb :: proc(length: f32, offset: f32, content: f32, visible: f32) -> (start: f32, size: f32) {
    if content <= visible || content <= 0 { return 0, length }
    size = clamp(length * visible / content, min(SCROLL_BAR_MIN_THUMB, length), length)
    start = (length - size) * clamp(offset / (content - visible), 0, 1)
    return
}

// A scroll bar for a view of `visible` units of `content` units whose first visible unit is `offset`. Dragging the thumb scrolls; a press on the track beside the thumb pages by `visible`;
// the wheel over it scrolls a tenth of a page. Nothing is drawn as active when everything is visible. Default size: thin and as long as the container (`horizontal`: across).
UiScrollBar :: proc(ctx: ^Context, name: string, offset: ^f32, content: f32, visible: f32, horizontal: bool = false, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    max_offset: f32 = max(content - visible, 0)
    set :: proc(offset: ^f32, moved: f32, max_offset: f32) -> bool {
        clamped: f32 = clamp(moved, 0, max_offset)
        if clamped == offset^ { return false }
        offset^ = clamped
        return true
    }
    offset^ = clamp(offset^, 0, max_offset)
    length: f32 = state.rect.z if horizontal else state.rect.w
    if max_offset > 0 && length > 0 && !disabled {
        mouse: f32 = ctx.input.mouse_position.x if horizontal else ctx.input.mouse_position.y
        origin: f32 = state.rect.x if horizontal else state.rect.y
        start, thumb := ScrollBarThumb(length, offset^, content, visible)
        if interaction.pressed && ctx.input.mouse_pressed && interaction.hovered {
            relative: f32 = mouse - origin
            if relative >= start && relative <= start + thumb {
                state.cursor = 1
                state.anim = relative - start               // where on the thumb it was grabbed
            } else {
                state.cursor = 0
                changed = set(offset, offset^ + (visible if relative > start else -visible), max_offset) || changed
            }
        } else if interaction.pressed && state.cursor == 1 && (ctx.input.mouse_down || ctx.input.mouse_released) && length > thumb {
            changed = set(offset, (mouse - origin - state.anim) / (length - thumb) * max_offset, max_offset) || changed
        }
        if interaction.hovered && ctx.input.wheel.y != 0 {
            changed = set(offset, offset^ - ctx.input.wheel.y * visible * 0.1, max_offset) || changed
        }
    }
    thickness: f32 = SCROLL_BAR_THICKNESS
    flags: Flags = {.DISABLED} if disabled || max_offset <= 0 else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSizeOr(size, Grow() if horizontal else Fixed(thickness), Fixed(thickness) if horizontal else Grow())},
        hit = {} if disabled else {.INTERACTIVE},
        draw = {
            kind = .SCROLL_BAR_THIN, name = IdSplitName(name), value = offset^ / max_offset if max_offset > 0 else 0,
            ratio = clamp(visible / content, 0, 1) if content > 0 else 1, cursor = 1 if horizontal else 0, actual = offset^, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

@(private)
widgetSizeOr :: proc(size: Size, width: SizingAxis, height: SizingAxis) -> Size {
    return {size.width if size.width != {} else width, size.height if size.height != {} else height}
}

// ------------------------------------------------------------------------------------------------------------------------
// Piano keyboard

@(private)
keyboardIsBlack :: proc(pitch: int) -> bool {
    pitch_class: int = ((pitch % 12) + 12) % 12
    return pitch_class == 1 || pitch_class == 3 || pitch_class == 6 || pitch_class == 8 || pitch_class == 10
}

KeyboardIsBlack :: proc(pitch: int) -> bool { return keyboardIsBlack(pitch) }

// The number of white keys from `first` to `last` (both included)
KeyboardWhiteCount :: proc(first: int, last: int) -> (count: int) {
    for pitch in first ..= last {
        if !keyboardIsBlack(pitch) { count += 1 }
    }
    return
}

// The rectangle of a key. A black key is narrower and shorter and sits across the edge of its two white neighbours; one at either end of the range is cut to the keyboard.
KeyboardKeyRect :: proc(rect: Rect, first: int, last: int, pitch: int) -> Rect {
    whites: int = KeyboardWhiteCount(first, last)
    if whites == 0 || pitch < first || pitch > last { return {} }
    width: f32 = rect.z / f32(whites)
    before: int = KeyboardWhiteCount(first, pitch - 1)         // white keys to the left of this pitch
    if !keyboardIsBlack(pitch) { return {rect.x + f32(before) * width, rect.y, width, rect.w} }
    black: f32 = width * 0.6
    x: f32 = rect.x + f32(before) * width - black * 0.5
    left: f32 = max(x, rect.x)
    right: f32 = min(x + black, rect.x + rect.z)
    return {left, rect.y, max(right - left, 0), rect.w * 0.62}
}

// The pitch of the key under a point, -1 for none (the black keys are on top)
KeyboardKeyAt :: proc(rect: Rect, first: int, last: int, point: Vec2) -> int {
    if point.x < rect.x || point.x >= rect.x + rect.z || point.y < rect.y || point.y >= rect.y + rect.w { return -1 }
    for pass in 0 ..< 2 {
        for pitch in first ..= last {
            if keyboardIsBlack(pitch) != (pass == 0) { continue }
            key: Rect = KeyboardKeyRect(rect, first, last, pitch)
            if RectContains(key, point) { return pitch }
        }
    }
    return -1
}

// A piano keyboard from the pitch `first` to `last` (MIDI numbers). `lit` (optional, 128 flags, alive until UiRender) lights keys, `root` (a pitch class 0..11, -1: none) outlines its keys.
// A press plays a key and a drag glides over the next ones: `pressed` is the pitch that went down in this frame and `released` the one that went up (-1 for none), so a program can send
// note on and off. Pressing is off for a disabled keyboard.
UiKeyboard :: proc(ctx: ^Context, name: string, first: int, last: int, lit: ^[128]bool = nil, root: int = -1, size: Size = {}, disabled: bool = false) -> (pressed: int, released: int) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    pressed, released = -1, -1
    held: int = state.cursor - 1               // the key that is down, -1 for none
    if !disabled {
        if interaction.pressed && (ctx.input.mouse_pressed || ctx.input.mouse_down) {
            key: int = KeyboardKeyAt(state.rect, first, last, ctx.input.mouse_position)
            if key != held && (key >= 0 || ctx.input.mouse_pressed) {
                if held >= 0 { released = held }
                if key >= 0 { pressed = key }
                held = key
            }
        }
        if (!interaction.pressed || ctx.input.mouse_released) && held >= 0 {
            released = held if released < 0 || released == held else released
            held = -1
        }
    }
    state.cursor = held + 1
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_height * 12, metrics.control_height * 3)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .HAND,
        draw = {
            kind = .KEYBOARD, name = IdSplitName(name), minimum = f32(first), maximum = f32(last), anchor = root, cursor = held, user = lit, font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Step grid

// The cell (row, step) under a point, false outside. Row 0 is the top row.
StepGridCellAt :: proc(rect: Rect, rows: int, steps: int, point: Vec2) -> (row: int, step: int, ok: bool) {
    if rows <= 0 || steps <= 0 || rect.z <= 0 || rect.w <= 0 { return 0, 0, false }
    if point.x < rect.x || point.x >= rect.x + rect.z || point.y < rect.y || point.y >= rect.y + rect.w { return 0, 0, false }
    return int((point.y - rect.y) / rect.w * f32(rows)), int((point.x - rect.x) / rect.z * f32(steps)), true
}

// A grid of `rows` x `steps` cells, `cells` row after row (length rows * steps; the program's, alive until UiRender). A press on a cell turns it on (to `on_value`) or off, and a drag paints the
// cells it passes with the same. `playhead` is the step that is playing (-1: none), `beat` marks every n-th step column stronger (0: 4).
UiStepGrid :: proc(ctx: ^Context, name: string, cells: []f32, rows: int, steps: int, playhead: int = -1, beat: int = 4, on_value: f32 = 1, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    assert(len(cells) >= rows * steps, "UiStepGrid: cells has to hold rows * steps values")
    if !disabled && interaction.pressed && (ctx.input.mouse_pressed || ctx.input.mouse_down) {
        if row, step, ok := StepGridCellAt(state.rect, rows, steps, ctx.input.mouse_position); ok {
            index: int = row * steps + step
            if ctx.input.mouse_pressed {
                state.cursor = 0 if cells[index] > 0 else 1         // what this drag paints
                state.anim = -1
            }
            if f32(index) != state.anim {
                // every cell on the line from the last one to this one, so a fast drag leaves no gaps
                from_row, from_step: int = row, step
                if state.anim >= 0 { from_row, from_step = int(state.anim) / steps, int(state.anim) % steps }
                count: int = max(abs(row - from_row), abs(step - from_step))
                for i in 0 ..= count {
                    along: f32 = f32(i) / f32(max(count, 1))
                    r, s: int = from_row + int(math.round(f32(row - from_row) * along)), from_step + int(math.round(f32(step - from_step) * along))
                    target: f32 = on_value if state.cursor == 1 else 0
                    if cells[r * steps + s] != target {
                        cells[r * steps + s] = target
                        changed = true
                    }
                }
                state.anim = f32(index)
            }
        }
    }
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_height * 12, metrics.control_height * 4)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .HAND,
        draw = {
            kind = .STEP_GRID, name = IdSplitName(name), values = cells[:rows * steps], cursor = steps, anchor = rows, actual = f32(playhead), minimum = f32(beat if beat > 0 else 4),
            font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}
