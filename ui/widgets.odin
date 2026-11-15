package ui

// The widgets: immediate mode. A widget is a call in the frame, it says what it is and gets back what the person did with it.
//
//     if ui.UiButton(&ctx, "Save") { Save() }
//     ui.UiSlider(&ctx, "Volume", &volume, 0, 100)
//     if ui.UiPanel(&ctx, "Options") {          // everything in the block is inside of the panel
//         ui.UiToggle(&ctx, "Music", &music)
//     }
//
// A widget does not draw: it declares an element with a `StyleKind` and the values the style needs (see DrawInfo). Interaction is tested
// against the layout of the last frame, so a widget reacts to what the person saw.
//
// Names are ids: the same name in the same container is the same widget. "Save##slot2" shows "Save" and hashes the whole string.
// Sizes: a zero `Size` takes what the style metrics say, a given axis (Grow(), Fixed(200), Percent(0.5)) is used as it is.

import "core:unicode/utf8"

// What a person did with a widget in this frame
Interaction :: struct {
    hovered: bool,
    pressed: bool,      // holds the mouse press
    clicked: bool,      // the press ended on it
    rect: Rect,         // where it was at the end of the last frame (0 the first time)
}

// The id a widget with this name has in the open container (after UiEnd: directly in the root)
UiId :: proc(ctx: ^Context, name: string) -> Id {
    seed: Id = ROOT_ID
    if ctx.open_count > 0 { seed = ctx.seed_stack[ctx.open_count - 1] }
    return IdFromString(name, seed)
}

// The id of a widget inside of containers, from the outside of a frame (tests, tools): UiIdPath("Settings", "Volume") is the Volume
// slider declared in the window Settings
UiIdPath :: proc(names: ..string) -> Id {
    id: Id = ROOT_ID
    for name in names {
        id = IdFromString(name, id)
    }
    return id
}

// The pointer is over this widget (and no other widget holds the press)
UiIsHovered :: proc(ctx: ^Context, id: Id) -> bool {
    return ctx.hover == id && (ctx.active == 0 || ctx.active == id)
}

// The widget holds the mouse press (a button that is down, a slider that is dragged)
UiIsPressed :: proc(ctx: ^Context, id: Id) -> bool {
    return ctx.active == id
}

@(private)
widgetBehavior :: proc(ctx: ^Context, id: Id, disabled: bool = false) -> Interaction {
    result: Interaction
    state: ^WidgetState = stateFind(ctx, id)
    if state != nil { result.rect = state.rect }
    if disabled { return result }
    result.hovered = ctx.hover == id && (ctx.active == 0 || ctx.active == id)
    if result.hovered && ctx.input.mouse_pressed {
        ctx.active = id
    }
    result.pressed = ctx.active == id
    if ctx.active == id && ctx.input.mouse_released {
        result.clicked = ctx.hover == id
        ctx.active = 0
    }
    return result
}

// An axis that was not set (fit, no minimum) takes the default, one that was set stays
@(private)
axisOrDefault :: proc(axis: SizingAxis, default: f32) -> SizingAxis {
    if axis.kind == .FIT && axis.min == 0 && axis.max == 0 {
        return Fit(default)
    }
    return axis
}

@(private)
widgetSize :: proc(size: Size, default_width: f32, default_height: f32) -> Size {
    return {axisOrDefault(size.width, default_width), axisOrDefault(size.height, default_height)}
}

@(private)
textWidth :: proc(ctx: ^Context, text: string) -> f32 {
    return ctx.measure(ctx, text, ctx.style.metrics.font_size).x
}

// ------------------------------------------------------------------------------------------------------------------------
// Containers: `if UiPanel(...) { children }`. The block closes the element when it ends.

// A background with children. A zero layout is a column with the padding and the gap of the style.
@(deferred_in = UiPanelEnd)
UiPanel :: proc(ctx: ^Context, name: string = "", layout: Layout = {}, blocks_pointer: bool = true) -> bool {
    id: Id = UiId(ctx, name) if name != "" else 0
    if id != 0 { _ = stateGet(ctx, id) }
    hit: HitKinds = {.BLOCKER} if blocks_pointer else {}
    return ElementOpen(ctx, {
        id = id,
        layout = layoutOrDefault(ctx, layout),
        hit = hit,
        draw = {kind = .PANEL, name = IdSplitName(name), font_size = ctx.style.metrics.font_size},
    })
}

UiPanelEnd :: proc(ctx: ^Context, name: string = "", layout: Layout = {}, blocks_pointer: bool = true) {
    ElementClose(ctx)
}

// A panel that floats at `position` of the screen (above the rest of the frame, the pointer over it is not for what is below).
// `z_index` orders windows: the higher is on top.
@(deferred_in = UiWindowEnd)
UiWindow :: proc(ctx: ^Context, name: string, position: Vec2, size: Size = {}, layout: Layout = {}, z_index: i16 = 0) -> bool {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    result: Layout = layoutOrDefault(ctx, layout)
    result.size = size
    return ElementOpen(ctx, {
        id = id,
        layout = result,
        floating = {attach_to = .ROOT, parent_point = .LEFT_TOP, element_point = .LEFT_TOP, offset = position, z_index = z_index, capture = true},
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = IdSplitName(name), font_size = ctx.style.metrics.font_size},
    })
}

UiWindowEnd :: proc(ctx: ^Context, name: string, position: Vec2, size: Size = {}, layout: Layout = {}, z_index: i16 = 0) {
    ElementClose(ctx)
}

// The padding and the gap of the style for a layout that has none
@(private)
layoutOrDefault :: proc(ctx: ^Context, layout: Layout) -> Layout {
    result: Layout = layout
    if layout.padding == {} && layout.gap == 0 {
        result.padding = PaddingAll(ctx.style.metrics.gap + 4)
        result.gap = ctx.style.metrics.gap
    }
    return result
}

// A group of widgets side by side, nothing drawn
@(deferred_in = UiRowEnd)
UiRow :: proc(ctx: ^Context, layout: Layout = {}) -> bool {
    result: Layout = layout
    result.direction = .LEFT_TO_RIGHT
    if result.gap == 0 { result.gap = ctx.style.metrics.gap }
    return ElementOpen(ctx, {layout = result})
}

UiRowEnd :: proc(ctx: ^Context, layout: Layout = {}) {
    ElementClose(ctx)
}

// A group of widgets one under the other, nothing drawn
@(deferred_in = UiColumnEnd)
UiColumn :: proc(ctx: ^Context, layout: Layout = {}) -> bool {
    result: Layout = layout
    result.direction = .TOP_TO_BOTTOM
    if result.gap == 0 { result.gap = ctx.style.metrics.gap }
    return ElementOpen(ctx, {layout = result})
}

UiColumnEnd :: proc(ctx: ^Context, layout: Layout = {}) {
    ElementClose(ctx)
}

// Any element of the user's design: its layout, a style kind (or a custom draw proc), nothing else is assumed
@(deferred_in = UiBoxEnd)
UiBox :: proc(ctx: ^Context, decl: Decl) -> bool {
    return ElementOpen(ctx, decl)
}

UiBoxEnd :: proc(ctx: ^Context, decl: Decl) {
    ElementClose(ctx)
}

// A container that cuts its children at its edge and scrolls them with the mouse wheel. Give it a height (Fixed, Percent or Grow inside of
// something that has one): a Fit height grows to the content and there is nothing to scroll.
@(deferred_in = UiScrollEnd)
UiScroll :: proc(ctx: ^Context, name: string, size: Size = {}, layout: Layout = {}) -> bool {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    if ctx.hover_scroll == id && ctx.input.wheel.y != 0 {
        state.scroll.y += ctx.input.wheel.y * ctx.style.metrics.font_size * 2.5
    }
    // limits from the last frame: how much the content is bigger than the view
    limit: f32 = max(state.content_size.y - state.rect.w, 0)
    state.scroll.y = clamp(state.scroll.y, -limit, 0)

    result: Layout = layoutOrDefault(ctx, layout)
    result.size = {
        size.width if size.width != {} else Grow(),
        size.height if size.height != {} else Grow(),
    }
    return ElementOpen(ctx, {
        id = id,
        layout = result,
        clip = {vertical = true, offset = state.scroll},
        hit = {.SCROLL, .BLOCKER},
        draw = {kind = .SCROLL_AREA, name = IdSplitName(name), font_size = ctx.style.metrics.font_size},
    })
}

UiScrollEnd :: proc(ctx: ^Context, name: string, size: Size = {}, layout: Layout = {}) {
    ElementClose(ctx)
}

// Where a scrolling container is scrolled to (0 at the top, positive downwards, in pixels)
UiScrollGet :: proc(ctx: ^Context, id: Id) -> f32 {
    state: ^WidgetState = stateFind(ctx, id)
    if state == nil { return 0 }
    return -state.scroll.y
}

// Moves a scrolling container to `offset` pixels from the top (it is limited to the content in the next frame)
UiScrollSet :: proc(ctx: ^Context, id: Id, offset: f32) {
    state: ^WidgetState = stateFind(ctx, id)
    if state != nil { state.scroll.y = -offset }
}

// ------------------------------------------------------------------------------------------------------------------------
// Text and decoration

// A text. It is wrapped when `wrap` is .WORDS and the width it gets is smaller than the text.
UiLabel :: proc(ctx: ^Context, text: string, wrap: TextWrap = .NONE, align: TextAlign = .LEFT) {
    TextOpen(ctx, IdSplitName(text), {wrap = wrap, align = align})
}

// A text made like fmt.tprintf, in memory of the frame
UiLabelf :: proc(ctx: ^Context, format: string, args: ..any) {
    UiLabel(ctx, UiFormat(ctx, format, ..args))
}

// A line across the container it is in
UiSeparator :: proc(ctx: ^Context) {
    horizontal: bool = true
    if ctx.open_count > 0 {
        horizontal = ctx.elements[ctx.open_stack[ctx.open_count - 1]].decl.layout.direction == .TOP_TO_BOTTOM
    }
    size: Size = {Grow(), Fixed(2)} if horizontal else {Fixed(2), Grow()}
    ElementOpen(ctx, {layout = {size = size}, draw = {kind = .SEPARATOR}})
    ElementClose(ctx)
}

// Room: grows to take what is left unless the size says otherwise
UiSpacer :: proc(ctx: ^Context, size: Size = {}) {
    sized: Size = {
        size.width if size.width != {} else Grow(),
        size.height if size.height != {} else Grow(),
    }
    ElementOpen(ctx, {layout = {size = sized}})
    ElementClose(ctx)
}

// ------------------------------------------------------------------------------------------------------------------------
// Controls

// True in the frame the button was clicked (pressed on it and let go on it)
UiButton :: proc(ctx: ^Context, name: string, size: Size = {}, disabled: bool = false) -> (clicked: bool) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    shown: string = IdSplitName(name)
    flags: Flags = {.DISABLED} if disabled else {}
    hit: HitKinds = {} if disabled else {.INTERACTIVE}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, textWidth(ctx, shown) + metrics.padding.x * 2, metrics.control_height)},
        hit = hit,
        draw = {kind = .BUTTON, name = shown, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    return interaction.clicked
}

// A box that is on or off. True in the frame it was flipped.
UiToggle :: proc(ctx: ^Context, name: string, value: ^bool, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    if interaction.clicked {
        value^ = !value^
        changed = true
    }
    metrics: ^Metrics = &ctx.style.metrics
    shown: string = IdSplitName(name)
    flags: Flags = {}
    if value^ { flags += {.ON} }
    if disabled { flags += {.DISABLED} }
    hit: HitKinds = {} if disabled else {.INTERACTIVE}
    // a square for the box, then the name
    width: f32 = metrics.control_height + metrics.padding.x + textWidth(ctx, shown)
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, width, metrics.control_height)},
        hit = hit,
        draw = {kind = .TOGGLE, name = shown, value = 1 if value^ else 0, actual = 1 if value^ else 0, minimum = 0, maximum = 1, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    return
}

// A bar that sets `value` between `minimum` and `maximum` while the mouse is dragged on it. True while it changes.
// The style gets value 0..1, the real number (`actual`) and its text made with `format`.
UiSlider :: proc(ctx: ^Context, name: string, value: ^f32, minimum: f32 = 0, maximum: f32 = 1, size: Size = {}, format: string = "%.2f", disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    range: f32 = maximum - minimum
    // the frame the button goes up still counts: the pointer may have moved since the last one
    if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && state.rect.z > 0 && range != 0 {
        t: f32 = clamp((ctx.input.mouse_position.x - state.rect.x) / state.rect.z, 0, 1)
        new_value: f32 = minimum + t * range
        if new_value != value^ {
            value^ = new_value
            changed = true
        }
    }
    metrics: ^Metrics = &ctx.style.metrics
    normalized: f32 = 0
    if range != 0 { normalized = clamp((value^ - minimum) / range, 0, 1) }
    flags: Flags = {.DISABLED} if disabled else {}
    hit: HitKinds = {} if disabled else {.INTERACTIVE}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_width, metrics.control_height)},
        hit = hit,
        draw = {
            kind = .SLIDER, name = IdSplitName(name), text = UiFormat(ctx, format, value^),
            value = normalized, actual = value^, minimum = minimum, maximum = maximum,
            font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// Shows how far something is: `value` between `minimum` and `maximum`. Nothing to click.
UiProgress :: proc(ctx: ^Context, name: string, value: f32, minimum: f32 = 0, maximum: f32 = 1, size: Size = {}, format: string = "%.0f") {
    metrics: ^Metrics = &ctx.style.metrics
    range: f32 = maximum - minimum
    normalized: f32 = 0
    if range != 0 { normalized = clamp((value - minimum) / range, 0, 1) }
    ElementOpen(ctx, {
        id = UiId(ctx, name),
        layout = {size = widgetSize(size, metrics.control_width, metrics.control_height * 0.75)},
        draw = {
            kind = .PROGRESS, name = IdSplitName(name), text = UiFormat(ctx, format, value),
            value = normalized, actual = value, minimum = minimum, maximum = maximum,
            font_size = metrics.font_size,
        },
    })
    ElementClose(ctx)
}

// A line of text the person edits. The text lives in `buffer` (`length` bytes of it are used): no allocations. `changed` when the
// content changed, `submitted` in the frame Enter was pressed. The text starts `metrics.padding.x` from the left edge of the rect.
UiTextField :: proc(ctx: ^Context, name: string, buffer: []u8, length: ^int, size: Size = {}, disabled: bool = false) -> (changed: bool, submitted: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    length^ = clamp(length^, 0, len(buffer))
    state.cursor = clamp(state.cursor, 0, length^)

    if interaction.hovered && ctx.input.mouse_pressed {
        ctx.focus = id
        state.cursor = textFieldCursorAt(ctx, string(buffer[:length^]), ctx.input.mouse_position.x - state.rect.x - metrics.padding.x)
    }
    if ctx.focus == id {
        changed, submitted = textFieldEdit(ctx, state, buffer, length)
    }

    flags: Flags = {.DISABLED} if disabled else {}
    hit: HitKinds = {} if disabled else {.INTERACTIVE}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_width, metrics.control_height)},
        hit = hit,
        draw = {
            kind = .TEXT_FIELD, name = IdSplitName(name), text = string(buffer[:length^]),
            cursor = state.cursor, font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// The byte offset in the text that is the nearest to a point `x` pixels from where the text starts
@(private)
textFieldCursorAt :: proc(ctx: ^Context, text: string, x: f32) -> int {
    best: int = 0
    best_distance: f32 = abs(x)
    offset: int = 0
    for offset < len(text) {
        _, width := utf8.decode_rune_in_string(text[offset:])
        offset += width
        distance: f32 = abs(x - ctx.measure(ctx, text[:offset], ctx.style.metrics.font_size).x)
        if distance < best_distance {
            best_distance = distance
            best = offset
        }
    }
    return best
}

@(private)
textFieldEdit :: proc(ctx: ^Context, state: ^WidgetState, buffer: []u8, length: ^int) -> (changed: bool, submitted: bool) {
    input: ^Input = &ctx.input
    // typed text goes in at the cursor
    typed: int = int(input.text_count)
    if typed > 0 && length^ + typed <= len(buffer) {
        copy(buffer[state.cursor + typed:length^ + typed], buffer[state.cursor:length^])
        copy(buffer[state.cursor:], input.text[:typed])
        length^ += typed
        state.cursor += typed
        changed = true
    }
    text: string = string(buffer[:length^])
    if .LEFT in input.keys && state.cursor > 0 {
        _, width := utf8.decode_last_rune_in_string(text[:state.cursor])
        state.cursor -= width
    }
    if .RIGHT in input.keys && state.cursor < length^ {
        _, width := utf8.decode_rune_in_string(text[state.cursor:])
        state.cursor += width
    }
    if .HOME in input.keys { state.cursor = 0 }
    if .END in input.keys { state.cursor = length^ }
    if .BACKSPACE in input.keys && state.cursor > 0 {
        _, width := utf8.decode_last_rune_in_string(text[:state.cursor])
        copy(buffer[state.cursor - width:], buffer[state.cursor:length^])
        state.cursor -= width
        length^ -= width
        changed = true
    }
    if .DELETE in input.keys && state.cursor < length^ {
        _, width := utf8.decode_rune_in_string(text[state.cursor:])
        copy(buffer[state.cursor:], buffer[state.cursor + width:length^])
        length^ -= width
        changed = true
    }
    if .ENTER in input.keys {
        submitted = true
    }
    if .ESCAPE in input.keys {
        ctx.focus = 0
    }
    return
}

// A box that opens a list of options below it. `selected` is an index of `options`, true in the frame it changed.
// The list is a floating element: it is above everything and closes with a click anywhere else or Escape.
UiDropdown :: proc(ctx: ^Context, name: string, options: []string, selected: ^int, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    selected^ = clamp(selected^, 0, max(len(options) - 1, 0))
    if interaction.clicked {
        state.open = !state.open
    }
    if .ESCAPE in ctx.input.keys {
        state.open = false
    }

    current: string = options[selected^] if len(options) > 0 else ""
    widest: f32 = 0
    for option in options {
        widest = max(widest, textWidth(ctx, option))
    }
    flags: Flags = {.DISABLED} if disabled else {}
    if state.open { flags += {.OPEN} }
    hit: HitKinds = {} if disabled else {.INTERACTIVE}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, widest + metrics.padding.x * 2 + metrics.control_height, metrics.control_height)},
        hit = hit,
        draw = {kind = .DROPDOWN, name = IdSplitName(name), text = current, value = 1 if state.open else 0, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)

    if !state.open { return }
    popup_id: Id = IdFromString("popup", id)
    _ = stateGet(ctx, popup_id)
    ElementOpen(ctx, {
        id = popup_id,
        layout = {size = {Grow(), Fit()}, padding = PaddingAll(2)},
        floating = {attach_to = .ELEMENT_WITH_ID, parent = id, parent_point = .LEFT_BOTTOM, element_point = .LEFT_TOP, z_index = 100, capture = true},
        hit = {.INTERACTIVE, .BLOCKER},
        draw = {kind = .PANEL, name = "dropdown", font_size = metrics.font_size},
    })
    over_popup: bool = ctx.hover == popup_id
    for option, i in options {
        item_id: Id = IdFromIndex(u32(i), popup_id)
        _ = stateGet(ctx, item_id)
        item: Interaction = widgetBehavior(ctx, item_id)
        if item.hovered { over_popup = true }
        if item.clicked {
            if selected^ != i { changed = true }
            selected^ = i
            state.open = false
        }
        item_flags: Flags = {.SELECTED} if i == selected^ else {}
        ElementOpen(ctx, {
            id = item_id,
            layout = {size = {Grow(), Fixed(metrics.control_height)}},
            hit = {.INTERACTIVE},
            draw = {kind = .DROPDOWN_ITEM, name = option, font_size = metrics.font_size, flags = item_flags, value = f32(i), actual = f32(i)},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
    // a press anywhere else closes the list
    if ctx.input.mouse_pressed && !over_popup && ctx.hover != id {
        state.open = false
    }
    return
}

// An element drawn by a proc of the user, in whatever way: the proc gets the rect and `user`. It reacts to the pointer when `interactive`.
UiCustom :: proc(ctx: ^Context, name: string, draw: StyleProc, size: Size, user: rawptr = nil, value: f32 = 0, interactive: bool = false) -> Interaction {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction
    hit: HitKinds = {}
    if interactive {
        interaction = widgetBehavior(ctx, id)
        hit = {.INTERACTIVE}
    }
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, ctx.style.metrics.control_width, ctx.style.metrics.control_height)},
        hit = hit,
        draw = {kind = .CUSTOM, name = IdSplitName(name), value = value, actual = value, custom = draw, user = user, font_size = ctx.style.metrics.font_size},
    })
    ElementClose(ctx)
    return interaction
}
