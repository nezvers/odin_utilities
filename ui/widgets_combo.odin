package ui

// A dropdown with a search: the list opens under the box with a field on top, and typing narrows the options to those that contain the text (any case). Up and down walk the matches,
// Enter takes the highlighted one, a click takes the one that is clicked, Escape or a click anywhere else closes it. At most `max_rows` matches are shown, the wheel and the keys scroll the rest.
// Only one list is open at a time, so the text of the field is a fixed buffer of the context (UI_COMBO_FILTER bytes).
//
//     if ui.UiCombo(&ctx, "Font", fonts, &selected) { ... }

UI_COMBO_FILTER :: 48

// Does `text` contain `filter`, ignoring the case of ASCII letters? An empty filter matches everything.
UiMatchText :: proc(text: string, filter: string) -> bool {
    if len(filter) == 0 { return true }
    if len(filter) > len(text) { return false }
    lower :: proc(character: u8) -> u8 {
        return character + 32 if character >= 'A' && character <= 'Z' else character
    }
    for start in 0 ..= len(text) - len(filter) {
        matched: bool = true
        for i in 0 ..< len(filter) {
            if lower(text[start + i]) != lower(filter[i]) {
                matched = false
                break
            }
        }
        if matched { return true }
    }
    return false
}

// `selected` is an index of `options`, true in the frame it changed. The box looks like the one of UiDropdown.
UiCombo :: proc(ctx: ^Context, name: string, options: []string, selected: ^int, size: Size = {}, max_rows: int = 8, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    selected^ = clamp(selected^, 0, max(len(options) - 1, 0))
    popup_id: Id = IdFromString("popup", id)
    filter_name: string = UiFormat(ctx, "##%s_filter", name)
    rows: int = max(max_rows, 1)

    opened: bool
    if interaction.clicked {
        state.open = !state.open
        if state.open {
            ctx.combo_filter_length = 0
            ctx.combo_owner = id
            state.cursor, state.anchor = selected^, 0           // the highlighted option, and the first one that is shown
            opened = true
        }
    }
    if state.open && ctx.cancel_pending {
        state.open = false
        ctx.cancel_pending = false
        ctx.focus = id
    }
    if state.open && ctx.combo_owner != id { state.open = false }       // another list was opened: this one closes

    current: string = options[selected^] if len(options) > 0 else ""
    widest: f32 = 0
    for option in options { widest = max(widest, textWidth(ctx, option)) }
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

    ctx.last_id = id
    if !state.open { return }
    _ = stateGet(ctx, popup_id)
    ElementOpen(ctx, {
        id = popup_id,
        layout = {size = {Grow(), Fit()}, padding = PaddingAll(2), direction = .TOP_TO_BOTTOM, gap = 2},
        floating = {attach_to = .ELEMENT_WITH_ID, parent = id, parent_point = .LEFT_BOTTOM, element_point = .LEFT_TOP, z_index = 100, capture = true},
        hit = {.INTERACTIVE, .BLOCKER},
        draw = {kind = .PANEL, name = "combo", font_size = metrics.font_size},
    })
    over_popup: bool = ctx.hover == popup_id

    // the field (its id is inside of the popup: the ids are scoped by the elements that hold them)
    filter_id: Id = UiId(ctx, filter_name)
    if opened { ctx.focus = filter_id }
    // its up and down are the list's, not the navigation's
    before: int = ctx.combo_filter_length
    _, submitted := UiTextField(ctx, filter_name, ctx.combo_filter[:], &ctx.combo_filter_length, {Grow(), {}})
    if field_state := stateFind(ctx, filter_id); field_state != nil { field_state.own_vertical = true }
    if ctx.hover == filter_id { over_popup = true }
    filter: string = string(ctx.combo_filter[:ctx.combo_filter_length])

    // the matches, in the order of the options
    matches: [dynamic]int
    matches.allocator = context.temp_allocator
    for option, i in options {
        if UiMatchText(option, filter) { append(&matches, i) }
    }
    if ctx.combo_filter_length != before { state.cursor, state.anchor = 0, 0 }          // a new text: the first match is the highlighted one
    state.cursor = clamp(state.cursor, 0, max(len(matches) - 1, 0))
    if UiActionPressed(ctx, .DOWN) { state.cursor = min(state.cursor + 1, len(matches) - 1) }
    if UiActionPressed(ctx, .UP) { state.cursor = max(state.cursor - 1, 0) }
    if UiActionPressed(ctx, .PAGE_DOWN) { state.cursor = min(state.cursor + rows, len(matches) - 1) }
    if UiActionPressed(ctx, .PAGE_UP) { state.cursor = max(state.cursor - rows, 0) }
    state.cursor = max(state.cursor, 0)
    if over_popup && ctx.input.wheel.y != 0 { state.anchor -= int(ctx.input.wheel.y) }
    // the window of the list follows the highlighted match
    if state.cursor < state.anchor { state.anchor = state.cursor }
    if state.cursor >= state.anchor + rows { state.anchor = state.cursor - rows + 1 }
    state.anchor = clamp(state.anchor, 0, max(len(matches) - rows, 0))

    if submitted && len(matches) > 0 {
        chosen: int = matches[state.cursor]
        if selected^ != chosen { changed = true }
        selected^ = chosen
        state.open = false
        ctx.focus = id
    }
    for position in state.anchor ..< min(state.anchor + rows, len(matches)) {
        i: int = matches[position]
        item_id: Id = IdFromIndex(u32(i), popup_id)
        _ = stateGet(ctx, item_id)
        item: Interaction = widgetBehavior(ctx, item_id)
        if item.hovered { over_popup = true }
        if item.clicked && state.open {
            if selected^ != i { changed = true }
            selected^ = i
            state.open = false
            ctx.focus = id
        }
        item_flags: Flags = {}
        if i == selected^ { item_flags += {.SELECTED} }
        if position == state.cursor { item_flags += {.FOCUSED} }
        ElementOpen(ctx, {
            id = item_id,
            layout = {size = {Grow(), Fixed(metrics.control_height)}},
            hit = {.INTERACTIVE, .NO_FOCUS},
            draw = {kind = .DROPDOWN_ITEM, name = options[i], font_size = metrics.font_size, flags = item_flags, value = f32(i), actual = f32(i)},
        })
        ElementClose(ctx)
    }
    if len(matches) == 0 {
        TextOpen(ctx, "no match", {color = {150, 150, 160, 255}})
    }
    ElementClose(ctx)
    if ctx.input.mouse_pressed && !over_popup && ctx.hover != id { state.open = false }
    return
}
