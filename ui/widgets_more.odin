package ui

// More widgets, the ones a tool needs next to the basics of widgets.odin: collapsing headers and tree nodes, radio buttons, selectables and
// list boxes, tabs, drag values and number inputs, arrow buttons (that repeat), plots, color edits, tooltips, menus, modal dialogs and
// windows with a title bar that moves. Same rules: a call is a widget, names are ids, the style draws (new StyleKinds), the pointer and the
// keyboard are the ones of the last frame.

import "core:math"

// ------------------------------------------------------------------------------------------------------------------------
// Sections

// A header that opens and closes its body: `if UiCollapsing(&ctx, "Basic") { ...the body... }`. `tree` is the quieter kind (an arrow, no frame).
// The open state is kept by the ui, `default_open` is where it starts. Ids inside of the body are scoped by the header.
@(deferred_in = UiCollapsingEnd)
UiCollapsing :: proc(ctx: ^Context, name: string, default_open: bool = false, tree: bool = false) -> bool {
    return collapsingBegin(ctx, name, default_open, tree)
}

@(private)
collapsingBegin :: proc(ctx: ^Context, name: string, default_open: bool, tree: bool) -> bool {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    if !state.initialized {
        state.initialized = true
        state.open = default_open
    }
    interaction: Interaction = widgetBehavior(ctx, id)
    if interaction.clicked {
        state.open = !state.open
        if state.open { ctx.reveal_open = IdFromString("body", id) }
    }
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .TOP_TO_BOTTOM}})
    flags: Flags = {.OPEN} if state.open else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Grow(), Fixed(metrics.control_height)}},
        hit = {.INTERACTIVE},
        draw = {kind = .COLLAPSING, name = IdSplitName(name), actual = 1 if tree else 0, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    if ctx.fold_count < len(ctx.fold_stack) {
        ctx.fold_stack[ctx.fold_count] = id
        ctx.fold_count += 1
    }
    if state.open {
        _ = stateGet(ctx, IdFromString("body", id))        // so that its place is known after the layout
        ElementOpen(ctx, {
            id = IdFromString("body", id),
            layout = {size = {Grow(), Fit()}, padding = {left = metrics.padding.x * 1.5, top = 4, bottom = 6}, gap = metrics.gap, direction = .TOP_TO_BOTTOM},
        })
    }
    return state.open
}

UiCollapsingEnd :: proc(ctx: ^Context, name: string, default_open: bool = false, tree: bool = false) {
    if ctx.fold_count > 0 { ctx.fold_count -= 1 }
    state: ^WidgetState = stateFind(ctx, ctx.fold_stack[ctx.fold_count])
    if state != nil && state.open { ElementClose(ctx) }
    ElementClose(ctx)
}

// Is the section of this header open (an id from UiId or UiIdPath)
UiIsOpen :: proc(ctx: ^Context, id: Id) -> bool {
    state: ^WidgetState = stateFind(ctx, id)
    return state != nil && state.open
}

// The id that the widgets in the body of a header (or a menu popup) are scoped by: UiIdPath cannot name it, it is not a widget
UiBodyId :: proc(header: Id) -> Id {
    return IdFromString("body", header)
}

// The id of the popup of a menu
UiMenuPopupId :: proc(menu: Id) -> Id {
    return IdFromString("menu", menu)
}

// A tree node: a collapsing header without the frame
@(deferred_in = UiTreeNodeEnd)
UiTreeNode :: proc(ctx: ^Context, name: string, default_open: bool = false) -> bool {
    return collapsingBegin(ctx, name, default_open, true)
}

UiTreeNodeEnd :: proc(ctx: ^Context, name: string, default_open: bool = false) {
    UiCollapsingEnd(ctx, name, default_open, true)
}

// A line with a name in it
UiSeparatorText :: proc(ctx: ^Context, name: string) {
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {
        layout = {size = {Grow(), Fixed(metrics.control_height * 0.8)}},
        draw = {kind = .SEPARATOR_TEXT, name = IdSplitName(name), font_size = metrics.font_size},
    })
    ElementClose(ctx)
}

// ------------------------------------------------------------------------------------------------------------------------
// Choices

// One of several options: `value` is the chosen one, this button is `option`. True in the frame it was chosen.
UiRadio :: proc(ctx: ^Context, name: string, value: ^int, option: int, size: Size = {}) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    if interaction.clicked && value^ != option {
        value^ = option
        changed = true
    }
    metrics: ^Metrics = &ctx.style.metrics
    shown: string = IdSplitName(name)
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_height + metrics.padding.x + textWidth(ctx, shown), metrics.control_height)},
        hit = {.INTERACTIVE},
        draw = {kind = .RADIO, name = shown, font_size = metrics.font_size, flags = {.ON} if value^ == option else {}},
    })
    ElementClose(ctx)
    return
}

// A row of a list that can be selected: as wide as its container unless the size says otherwise. True when it was clicked.
UiSelectable :: proc(ctx: ^Context, name: string, selected: bool, size: Size = {}, disabled: bool = false) -> (clicked: bool) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    flags: Flags = {}
    if selected { flags += {.SELECTED} }
    if disabled { flags += {.DISABLED} }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Fixed(metrics.control_height * 0.85)}},
        hit = {} if disabled else {.INTERACTIVE},
        draw = {kind = .SELECTABLE, name = IdSplitName(name), font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    return interaction.clicked
}

// A box with a column of selectable rows that scrolls: `selected` is the index chosen, `visible_items` is how many rows are shown
UiListBox :: proc(ctx: ^Context, name: string, items: []string, selected: ^int, visible_items: int = 5) -> (changed: bool) {
    metrics: ^Metrics = &ctx.style.metrics
    height: f32 = (metrics.control_height * 0.85 + metrics.gap) * f32(visible_items) + metrics.gap * 2
    if UiScroll(ctx, name, {Fixed(metrics.control_width * 1.4), Fixed(height)}, {padding = PaddingAll(4), gap = 2}) {
        for item, i in items {
            if UiSelectable(ctx, UiFormat(ctx, "%s##%d", item, i), selected^ == i) {
                selected^ = i
                changed = true
            }
        }
    }
    return
}

// A strip of tabs: `selected` is the index of the one that is on, the program shows its content. True in the frame it changed.
UiTabBar :: proc(ctx: ^Context, name: string, labels: []string, selected: ^int) -> (changed: bool) {
    bar: Id = UiId(ctx, name)
    metrics: ^Metrics = &ctx.style.metrics
    selected^ = clamp(selected^, 0, max(len(labels) - 1, 0))
    ElementOpen(ctx, {id = bar, layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = 2}})
    for label, i in labels {
        tab: Id = IdFromIndex(u32(i), bar)
        _ = stateGet(ctx, tab)
        interaction: Interaction = widgetBehavior(ctx, tab)
        if interaction.clicked && selected^ != i {
            selected^ = i
            changed = true
        }
        shown: string = IdSplitName(label)
        ElementOpen(ctx, {
            id = tab,
            layout = {size = {Fit(textWidth(ctx, shown) + metrics.padding.x * 2), Fixed(metrics.control_height)}},
            hit = {.INTERACTIVE},
            draw = {kind = .TAB, name = shown, font_size = metrics.font_size, flags = {.SELECTED} if selected^ == i else {}},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
    return
}

// An arrow button (`direction` UP, DOWN, LEFT or RIGHT). With `repeat` it acts when pressed and again every 0.1 s after 0.4 s of holding.
UiArrowButton :: proc(ctx: ^Context, name: string, direction: Direction, repeat: bool = false) -> (clicked: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    keyboard: bool = ctx.activate && ctx.focus == id
    interaction: Interaction = widgetBehavior(ctx, id)
    clicked = interaction.clicked
    if repeat {
        clicked = keyboard
        if interaction.pressed && ctx.input.mouse_down {
            if ctx.input.mouse_pressed {
                clicked = true
            } else {
                before: f32 = state.press_time
                state.press_time += ctx.delta_time
                if state.press_time > 0.4 && int((state.press_time - 0.4) / 0.1) != int((before - 0.4) / 0.1) { clicked = true }
            }
        } else if !interaction.pressed {
            state.press_time = 0
        }
    }
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(metrics.control_height), Fixed(metrics.control_height)}},
        hit = {.INTERACTIVE},
        draw = {kind = .ARROW, name = IdSplitName(name), actual = f32(int(direction)), font_size = metrics.font_size},
    })
    ElementClose(ctx)
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Numbers

// The box of a drag value: pressed on it, the value follows the pointer by `speed` per pixel (limited to minimum .. maximum when that is a range)
@(private)
dragBox :: proc(ctx: ^Context, id: Id, value: ^f32, speed: f32, minimum: f32, maximum: f32, format: string, size: Size, disabled: bool) -> (changed: bool) {
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    ranged: bool = maximum > minimum
    if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        if ctx.input.mouse_pressed {
            state.drag = ctx.input.mouse_position
        } else {
            moved: f32 = ctx.input.mouse_position.x - state.drag.x
            state.drag = ctx.input.mouse_position
            new_value: f32 = value^ + moved * speed
            if ranged { new_value = clamp(new_value, minimum, maximum) }
            if new_value != value^ {
                value^ = new_value
                changed = true
            }
        }
    }
    // left and right of the navigation: ten times the speed
    state.adjustable = true
    if state.pending_adjust != 0 {
        new_value: f32 = value^ + f32(state.pending_adjust) * speed * 10
        if ranged { new_value = clamp(new_value, minimum, maximum) }
        if new_value != value^ {
            value^ = new_value
            changed = true
        }
    }
    state.pending_adjust = 0
    metrics: ^Metrics = &ctx.style.metrics
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_width, metrics.control_height)},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .RESIZE_HORIZONTAL,
        draw = {
            kind = .DRAG, text = UiFormat(ctx, format, value^), value = clamp((value^ - minimum) / (maximum - minimum), 0, 1) if ranged else 0.5,
            actual = value^, minimum = minimum, maximum = maximum, font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

@(private)
rowOpen :: proc(ctx: ^Context) {
    ElementOpen(ctx, {layout = {direction = .LEFT_TO_RIGHT, gap = ctx.style.metrics.gap, align = {y = .CENTER}}})
}

// A number that is dragged sideways. The name is on the right of the box.
UiDrag :: proc(ctx: ^Context, name: string, value: ^f32, speed: f32 = 0.01, minimum: f32 = 0, maximum: f32 = 0, format: string = "%.3f", size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    rowOpen(ctx)
    changed = dragBox(ctx, id, value, speed, minimum, maximum, format, size, disabled)
    TextOpen(ctx, IdSplitName(name))
    ElementClose(ctx)
    return
}

UiDragInt :: proc(ctx: ^Context, name: string, value: ^int, speed: f32 = 0.2, minimum: int = 0, maximum: int = 0, format: string = "%.0f", size: Size = {}) -> (changed: bool) {
    number: f32 = f32(value^)
    if UiDrag(ctx, name, &number, speed, f32(minimum), f32(maximum), format, size) {
        value^ = int(math.round(number))
        changed = true
    }
    return
}

// A slider of whole numbers
UiSliderInt :: proc(ctx: ^Context, name: string, value: ^int, minimum: int, maximum: int, size: Size = {}) -> (changed: bool) {
    number: f32 = f32(value^)
    if UiSlider(ctx, name, &number, f32(minimum), f32(maximum), size, "%.0f") {
        value^ = int(math.round(number))
        changed = true
    }
    return
}

// A slider of an angle: the value is in radians, the style shows degrees
UiSliderAngle :: proc(ctx: ^Context, name: string, radians: ^f32, minimum_degrees: f32 = -360, maximum_degrees: f32 = 360, size: Size = {}) -> (changed: bool) {
    degrees: f32 = math.to_degrees(radians^)
    if UiSlider(ctx, name, &degrees, minimum_degrees, maximum_degrees, size, "%.0f deg") {
        radians^ = math.to_radians(degrees)
        changed = true
    }
    return
}

// A whole number with a button on each side that steps it (they repeat while held)
UiInputInt :: proc(ctx: ^Context, name: string, value: ^int, step: int = 1) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {id = id, layout = {direction = .LEFT_TO_RIGHT, gap = 2, align = {y = .CENTER}}})
    if UiArrowButton(ctx, "-##minus", .LEFT, true) { value^ -= step; changed = true }
    ElementOpen(ctx, {
        layout = {size = {Fixed(metrics.control_width * 0.5), Fixed(metrics.control_height)}},
        draw = {kind = .TEXT_FIELD, text = UiFormat(ctx, "%d", value^), font_size = metrics.font_size},
    })
    ElementClose(ctx)
    if UiArrowButton(ctx, "+##plus", .RIGHT, true) { value^ += step; changed = true }
    TextOpen(ctx, IdSplitName(name))
    ElementClose(ctx)
    return
}

UiInputFloat :: proc(ctx: ^Context, name: string, value: ^f32, step: f32 = 0.1, format: string = "%.3f") -> (changed: bool) {
    id: Id = UiId(ctx, name)
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {id = id, layout = {direction = .LEFT_TO_RIGHT, gap = 2, align = {y = .CENTER}}})
    if UiArrowButton(ctx, "-##minus", .LEFT, true) { value^ -= step; changed = true }
    ElementOpen(ctx, {
        layout = {size = {Fixed(metrics.control_width * 0.5), Fixed(metrics.control_height)}},
        draw = {kind = .TEXT_FIELD, text = UiFormat(ctx, format, value^), font_size = metrics.font_size},
    })
    ElementClose(ctx)
    if UiArrowButton(ctx, "+##plus", .RIGHT, true) { value^ += step; changed = true }
    TextOpen(ctx, IdSplitName(name))
    ElementClose(ctx)
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Plots and colors

@(private)
plot :: proc(ctx: ^Context, name: string, values: []f32, histogram: bool, overlay: string, minimum: f32, maximum: f32, size: Size) {
    low, high: f32 = minimum, maximum
    if !(high > low) && len(values) > 0 {
        // no range given: the numbers decide
        low, high = values[0], values[0]
        for value in values {
            low = min(low, value)
            high = max(high, value)
        }
        if high == low { high = low + 1 }
    }
    metrics: ^Metrics = &ctx.style.metrics
    rowOpen(ctx)
    ElementOpen(ctx, {
        id = UiId(ctx, name),
        layout = {size = widgetSize(size, metrics.control_width * 1.6, metrics.control_height * 2.5)},
        draw = {kind = .PLOT, name = IdSplitName(name), text = overlay, values = values, minimum = low, maximum = high, actual = 1 if histogram else 0, font_size = metrics.font_size},
    })
    ElementClose(ctx)
    TextOpen(ctx, IdSplitName(name))
    ElementClose(ctx)
}

// A line through the numbers (they have to live until the frame is rendered); with no minimum and maximum the range of the numbers is used
UiPlotLines :: proc(ctx: ^Context, name: string, values: []f32, overlay: string = "", minimum: f32 = 0, maximum: f32 = 0, size: Size = {}) {
    plot(ctx, name, values, false, overlay, minimum, maximum, size)
}

UiPlotHistogram :: proc(ctx: ^Context, name: string, values: []f32, overlay: string = "", minimum: f32 = 0, maximum: f32 = 0, size: Size = {}) {
    plot(ctx, name, values, true, overlay, minimum, maximum, size)
}

@(private)
colorBytes :: proc(color: [3]f32) -> Color {
    return {u8(clamp(color.r, 0, 1) * 255 + 0.5), u8(clamp(color.g, 0, 1) * 255 + 0.5), u8(clamp(color.b, 0, 1) * 255 + 0.5), 255}
}

// A color: three drag values and a swatch. True while a channel changes.
UiColorEdit3 :: proc(ctx: ^Context, name: string, color: ^[3]f32) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {id = id, layout = {direction = .LEFT_TO_RIGHT, gap = 2, align = {y = .CENTER}}})
    for channel in 0 ..< 3 {
        if dragBox(ctx, IdFromIndex(u32(channel), id), &color[channel], 0.005, 0, 1, "%.2f", {Fixed(metrics.control_width * 0.4), {}}, false) { changed = true }
    }
    ElementOpen(ctx, {
        layout = {size = {Fixed(metrics.control_height), Fixed(metrics.control_height)}},
        draw = {kind = .SWATCH, color = colorBytes(color^)},
    })
    ElementClose(ctx)
    TextOpen(ctx, IdSplitName(name))
    ElementClose(ctx)
    return
}

// A square of a color that can be clicked
UiColorButton :: proc(ctx: ^Context, name: string, color: [3]f32, size: f32 = 0) -> (clicked: bool) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    side: f32 = size if size > 0 else ctx.style.metrics.control_height * 1.4
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(side), Fixed(side)}},
        hit = {.INTERACTIVE},
        draw = {kind = .SWATCH, name = IdSplitName(name), color = colorBytes(color)},
    })
    ElementClose(ctx)
    return interaction.clicked
}

// ------------------------------------------------------------------------------------------------------------------------
// Text

// A text in a color of its own
UiLabelColored :: proc(ctx: ^Context, text: string, color: Color, wrap: TextWrap = .NONE) {
    TextOpen(ctx, IdSplitName(text), {color = color, wrap = wrap})
}

// A line of text with a dot in front of it
UiBullet :: proc(ctx: ^Context, text: string, wrap: TextWrap = .NONE) {
    metrics: ^Metrics = &ctx.style.metrics
    rowOpen(ctx)
    ElementOpen(ctx, {layout = {size = {Fixed(metrics.font_size * 0.6), Fixed(metrics.font_size)}}, draw = {kind = .BULLET}})
    ElementClose(ctx)
    TextOpen(ctx, IdSplitName(text), {wrap = wrap})
    ElementClose(ctx)
}

// A value and the name of what it is: "Value  label"
UiLabelText :: proc(ctx: ^Context, name: string, value: string) {
    rowOpen(ctx)
    TextOpen(ctx, value)
    TextOpen(ctx, IdSplitName(name))
    ElementClose(ctx)
}

// A text that ends in "..." when its container is too narrow for it, and shows the whole text in a tooltip while the pointer is on it
UiLabelTruncated :: proc(ctx: ^Context, text: string, width: SizingAxis = {}) {
    shown: string = IdSplitName(text)
    id: Id = UiId(ctx, text)
    state: ^WidgetState = stateGet(ctx, id)
    ElementOpen(ctx, {id = id, layout = {size = {width if width != {} else Grow(), Fit()}}, hit = {.HOVER}})
    TextOpen(ctx, shown, {wrap = .TRUNCATE})
    ElementClose(ctx)
    if state.open && ctx.hover_info == id { tooltipBox(ctx, shown) }
}

// A box with a text that appears at the pointer while the widget declared just before is hovered
UiTooltip :: proc(ctx: ^Context, text: string) {
    if !UiIsHovered(ctx, ctx.last_id) { return }
    tooltipBox(ctx, text)
}

@(private)
tooltipBox :: proc(ctx: ^Context, text: string) {
    ElementOpen(ctx, {
        layout = {padding = PaddingXY(8, 5)},
        floating = {attach_to = .ROOT, offset = ctx.input.mouse_position + {14, 18}, z_index = 400},
        draw = {kind = .PANEL, name = "tooltip", font_size = ctx.style.metrics.font_size},
    })
    TextOpen(ctx, text)
    ElementClose(ctx)
}

// ------------------------------------------------------------------------------------------------------------------------
// Menus

// The strip of a menu bar: UiMenu entries go in it
@(deferred_in = UiMenuBarEnd)
UiMenuBar :: proc(ctx: ^Context) -> bool {
    metrics: ^Metrics = &ctx.style.metrics
    return ElementOpen(ctx, {
        layout = {size = {Grow(), Fixed(metrics.control_height)}, direction = .LEFT_TO_RIGHT, padding = PaddingXY(4, 2), gap = 2, align = {y = .CENTER}},
        draw = {kind = .MENU_BAR},
    })
}

UiMenuBarEnd :: proc(ctx: ^Context) {
    ElementClose(ctx)
}

// A menu: a title in a bar (or an entry that opens a submenu inside of another menu) and a popup of items, UiMenuItem, UiSeparator, more
// menus, when it is open: `if UiMenu(&ctx, "File") { ... }`. A click on a title opens it, moving along the bar switches menus, a click
// elsewhere, Escape or the use of an item closes them.
@(deferred_in = UiMenuEnd)
UiMenu :: proc(ctx: ^Context, name: string, enabled: bool = true) -> bool {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, !enabled)
    popup: Id = IdFromString("menu", id)
    top: bool = ctx.menu_depth == 0
    open: bool
    if top {
        if interaction.clicked {
            ctx.open_menu = 0 if ctx.open_menu == id else id
        } else if enabled && ctx.open_menu != 0 && ctx.open_menu != id && UiIsHovered(ctx, id) {
            ctx.open_menu = id          // along the bar
        }
        open = ctx.open_menu == id
        if open && ctx.cancel_pending {
            ctx.open_menu = 0
            ctx.cancel_pending = false
            ctx.focus = id
            open = false
        }
        if open && ctx.input.mouse_pressed && ctx.hover != id && ctx.hover_root != popup {
            ctx.open_menu = 0
            open = false
        }
    } else {
        // a submenu opens under the pointer and closes when the pointer is on something else
        if interaction.clicked || UiIsHovered(ctx, id) { state.open = true }
        else if state.open && ctx.hover != 0 && ctx.hover_root != popup { state.open = false }
        open = state.open && enabled
    }
    metrics: ^Metrics = &ctx.style.metrics
    shown: string = IdSplitName(name)
    width: SizingAxis = Fit(textWidth(ctx, shown) + metrics.padding.x * 2) if top else Grow(textWidth(ctx, shown) + metrics.padding.x * 3)
    flags: Flags = {.OPEN} if open else {}
    if !enabled { flags += {.DISABLED} }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {width, Fixed(metrics.control_height * (1.0 if top else 0.9))}},
        hit = {} if !enabled else {.INTERACTIVE},
        draw = {kind = .MENU, name = shown, actual = 0 if top else 1, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    if ctx.menu_depth < len(ctx.menu_opened) { ctx.menu_opened[ctx.menu_depth] = open }
    if open {
        ElementOpen(ctx, {
            id = popup,
            layout = {size = {Fit(metrics.control_width), Fit()}, padding = PaddingAll(3), gap = 1, direction = .TOP_TO_BOTTOM},
            floating = {
                attach_to = .ELEMENT_WITH_ID, parent = id, parent_point = .LEFT_BOTTOM if top else .RIGHT_TOP, element_point = .LEFT_TOP,
                z_index = i16(300 + ctx.menu_depth), capture = true,
            },
            hit = {.INTERACTIVE, .BLOCKER},
            draw = {kind = .PANEL, name = "menu", font_size = metrics.font_size},
        })
    }
    ctx.menu_depth += 1
    return open
}

UiMenuEnd :: proc(ctx: ^Context, name: string, enabled: bool = true) {
    ctx.menu_depth -= 1
    if ctx.menu_depth < len(ctx.menu_opened) && ctx.menu_opened[ctx.menu_depth] { ElementClose(ctx) }
    // an item was used somewhere below: this menu closes too
    if ctx.menu_close {
        if ctx.menu_depth == 0 {
            ctx.open_menu = 0
        } else if state: ^WidgetState = stateFind(ctx, UiId(ctx, name)); state != nil {
            state.open = false
        }
    }
}

// An entry of a menu. `shortcut` is shown on the right, `checked` makes it a check item. True in the frame it was used.
UiMenuItem :: proc(ctx: ^Context, name: string, shortcut: string = "", checked: ^bool = nil, enabled: bool = true) -> (clicked: bool) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, !enabled)
    if interaction.clicked {
        clicked = true
        if checked != nil { checked^ = !checked^ }
        ctx.menu_close = true
    }
    metrics: ^Metrics = &ctx.style.metrics
    shown: string = IdSplitName(name)
    flags: Flags = {}
    if checked != nil && checked^ { flags += {.ON} }
    if !enabled { flags += {.DISABLED} }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Grow(textWidth(ctx, shown) + textWidth(ctx, shortcut) + metrics.padding.x * 4), Fixed(metrics.control_height * 0.9)}},
        hit = {} if !enabled else {.INTERACTIVE},
        draw = {kind = .MENU_ITEM, name = shown, text = shortcut, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Windows and dialogs

// A dialog over a dimmed screen: `if UiModal(&ctx, "Delete?", &open) { ... }`. Nothing under it reacts while it is open (the pointer and the
// keyboard focus stay in it), Escape closes it.
@(deferred_in = UiModalEnd)
UiModal :: proc(ctx: ^Context, name: string, open: ^bool, size: Size = {}, layout: Layout = {}) -> bool {
    return modalOpen(ctx, name, open, size, layout)
}

// The opening of a modal without the deferred close, for a widget that is a modal itself and closes it in its own end (UiPreferences)
@(private)
modalOpen :: proc(ctx: ^Context, name: string, open: ^bool, size: Size, layout_in: Layout = {}) -> bool {
    if open^ && ctx.cancel_pending {
        open^ = false
        ctx.cancel_pending = false
    }
    if !open^ {
        ElementOpen(ctx, {})                // UiModalEnd closes one element either way
        return false
    }
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    ElementOpen(ctx, {
        layout = {size = {Grow(), Grow()}},
        floating = {attach_to = .ROOT, z_index = 500, capture = true},
        hit = {.BLOCKER},
        draw = {kind = .BACKDROP},
    })
    ElementClose(ctx)
    layout: Layout = layoutOrDefault(ctx, layout_in)
    layout.size = size
    ctx.modal_next = id
    return ElementOpen(ctx, {
        id = id,
        layout = layout,
        floating = {attach_to = .ROOT, parent_point = .CENTER_CENTER, element_point = .CENTER_CENTER, z_index = 501, capture = true},
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = IdSplitName(name), font_size = ctx.style.metrics.font_size},
    })
}

UiModalEnd :: proc(ctx: ^Context, name: string, open: ^bool, size: Size = {}, layout: Layout = {}) {
    ElementClose(ctx)
}

// A window with a title bar that is dragged: `position` is where it is (the program keeps it). The body is padded like a panel.
@(deferred_in = UiWindowTitledEnd)
UiWindowTitled :: proc(ctx: ^Context, title: string, position: ^Vec2, size: Size = {}, layout: Layout = {}, z_index: i16 = 0) -> bool {
    id: Id = UiId(ctx, title)
    _ = stateGet(ctx, id)
    title_id: Id = IdFromString("title", id)
    state: ^WidgetState = stateGet(ctx, title_id)
    interaction: Interaction = widgetBehavior(ctx, title_id)
    if interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        if ctx.input.mouse_pressed {
            state.drag = ctx.input.mouse_position
        } else {
            position^ += ctx.input.mouse_position - state.drag
            state.drag = ctx.input.mouse_position
            position.y = max(position.y, 0)
        }
    }
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {
        id = id,
        layout = {size = size, direction = .TOP_TO_BOTTOM},
        floating = {attach_to = .ROOT, parent_point = .LEFT_TOP, element_point = .LEFT_TOP, offset = position^, z_index = z_index, capture = true},
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = IdSplitName(title), font_size = metrics.font_size},
    })
    ElementOpen(ctx, {
        id = title_id,
        layout = {size = {Grow(), Fixed(metrics.control_height)}},
        hit = {.INTERACTIVE},
        draw = {kind = .WINDOW_TITLE, name = IdSplitName(title), font_size = metrics.font_size, flags = {.FOCUSED} if ctx.focus == title_id else {}},
    })
    ElementClose(ctx)
    body: Layout = layoutOrDefault(ctx, layout)
    body.size = {Grow(), Grow() if size.height != {} else Fit()}
    return ElementOpen(ctx, {layout = body})
}

UiWindowTitledEnd :: proc(ctx: ^Context, title: string, position: ^Vec2, size: Size = {}, layout: Layout = {}, z_index: i16 = 0) {
    ElementClose(ctx)       // the body
    ElementClose(ctx)       // the window
}
