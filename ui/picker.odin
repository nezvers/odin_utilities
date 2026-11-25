package ui

// A searchable list popup: the parameter picker of a device (a list of parameters under the control that asks for one) and the command palette of a program (a list of commands over the whole
// window). One widget, two placements. The person types words; the items that have every word in their name or detail are listed, the best first (the name starts with the word, then the
// word starts a part of the name, then it is somewhere in it, then it is only in the detail); the arrows choose, Enter or a click picks, Escape or a click outside closes.
//
//   items: []ui.PickerItem = {{"Cutoff", "Filter"}, {"Resonance", "Filter"}, {"Gain", "Output"}}
//   if open { chosen := ui.UiPicker(&ctx, "Parameters", &open, items, query[:], &query_length, matches[:], anchor = button_rect) ; if chosen >= 0 { ... } }
//   chosen := ui.UiPicker(&ctx, "Commands", &open, commands, query[:], &length, matches[:])            // no anchor: a palette at the top of the window
//
// What the widget keeps is the row that is chosen and the first row in view (in its state); the query text and the match list are the program's buffers (no allocation). Call it every
// frame (it does nothing while `open` is false); on the frame `open` turns true the query is cleared and the search field has the focus.
//
// Limits: the match list holds at most PICKER_MATCHES (128) items, the best ones; PICKER_ROWS (10) rows are in view and the list scrolls with the arrows and the wheel; ASCII letters match
// without regard to case (other letters must match exactly); no fuzzy matching of letters that are apart, no groups or headings between rows, no icons or shortcuts drawn as keys (the
// detail is plain text); an anchored picker opens under its anchor and does not flip above it.

PICKER_ROWS :: 10
PICKER_MATCHES :: 128

PickerItem :: struct {
    name: string,
    detail: string,                 // a category or a shortcut, shown dim at the right and searched too
}

// The words of a query: split at spaces
@(private)
pickerNextWord :: proc(query: string, from: int) -> (word: string, next: int) {
    start: int = from
    for start < len(query) && query[start] == ' ' { start += 1 }
    end: int = start
    for end < len(query) && query[end] != ' ' { end += 1 }
    return query[start:end], end
}

// How well an item matches the query, the lower the better; -1 when a word is in neither the name nor the detail
PickerScore :: proc(item: PickerItem, query: string) -> int {
    score: int
    at: int
    for {
        word: string
        word, at = pickerNextWord(query, at)
        if word == "" { break }
        tier: int = completeTier(item.name, word)
        if tier < 0 {
            if completeFind(item.detail, word) < 0 { return -1 }
            tier = 3
        }
        score += tier
    }
    return score
}

// Fills `matches` with the indices of the items that match, the best first (the order of the items within a score); returns how many. The list is cut at its capacity.
PickerFilter :: proc(items: []PickerItem, query: string, matches: []int) -> int {
    capacity: int = min(len(matches), PICKER_MATCHES)
    scores: [PICKER_MATCHES]int
    count: int
    for item, i in items {
        score: int = PickerScore(item, query)
        if score < 0 { continue }
        if count == capacity && score >= scores[count - 1] { continue }
        // insert after the last item that is as good, so the order of the items stays inside a score
        place: int = min(count, capacity - 1)
        for place > 0 && scores[place - 1] > score { place -= 1 }
        if count < capacity { count += 1 }
        for move := count - 1; move > place; move -= 1 {
            scores[move], matches[move] = scores[move - 1], matches[move - 1]
        }
        scores[place], matches[place] = score, i
    }
    return count
}

// The picker. `anchor` (a rectangle on the screen, width and height above 0) puts it under that rectangle, else it is a palette at the top centre of the window; `width` 0 is a size
// from the style. Returns the index in `items` of the item that was picked in this frame, -1 for none; `open` is false after a pick, Escape, or a click outside.
UiPicker :: proc(ctx: ^Context, name: string, open: ^bool, items: []PickerItem, query: []u8, query_length: ^int, matches: []int, anchor: Rect = {}, width: f32 = 0) -> (chosen: int) {
    chosen = -1
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    if !open^ {
        state.open = false
        return
    }
    field: Id = IdFromString("##query", id)               // the field is inside of the panel, whose id is the seed of its children
    field_state: ^WidgetState = stateGet(ctx, field)
    if !state.open {
        state.open = true
        state.cursor, state.scroll.y = 0, 0
        query_length^ = 0
        field_state.cursor, field_state.anchor = 0, 0
        ctx.focus = field
    }
    // up and down are the list's while this is open (the field would give them to the navigation)
    field_state.own_vertical = true
    input: ^Input = &ctx.input
    if ctx.cancel_pending || .ESCAPE in input.keys {
        ctx.cancel_pending = false
        input.keys -= {.ESCAPE}
        input.actions -= {.CANCEL}
        open^, state.open = false, false
        return
    }
    metrics: ^Metrics = &ctx.style.metrics
    text: string = string(query[:clamp(query_length^, 0, len(query))])
    count: int = PickerFilter(items, text, matches)
    state.cursor = clamp(state.cursor, 0, max(count - 1, 0))
    rows: int = min(count, PICKER_ROWS)
    first: int = clamp(int(state.scroll.y), 0, max(count - rows, 0))
    if count > 0 {
        if .UP in input.actions { state.cursor = (state.cursor + count - 1) % count }
        if .DOWN in input.actions { state.cursor = (state.cursor + 1) % count }
    }
    input.actions -= {.UP, .DOWN}
    if input.wheel.y != 0 { first = clamp(first - (1 if input.wheel.y > 0 else -1), 0, max(count - rows, 0)) }
    if state.cursor < first { first = state.cursor }
    if state.cursor >= first + rows { first = state.cursor - rows + 1 }
    state.scroll.y = f32(first)
    if .ENTER in input.keys && count > 0 { chosen = matches[state.cursor] }
    input.keys -= {.ENTER}

    // a click outside closes it: the backdrop under the panel takes the press (a palette dims the window, an anchored picker does not)
    anchored: bool = anchor.z > 0 && anchor.w > 0
    back: Id = IdFromString("backdrop", id)
    _ = stateGet(ctx, back)
    back_behavior: Interaction = widgetBehavior(ctx, back)
    if back_behavior.clicked {
        open^, state.open = false, false
        return
    }
    ElementOpen(ctx, {
        id = back,
        layout = {size = {Grow(), Grow()}},
        floating = {attach_to = .ROOT, z_index = 500, capture = true},
        hit = {.INTERACTIVE, .NO_FOCUS},
        draw = {kind = .BACKDROP if !anchored else .NONE},
    })
    ElementClose(ctx)
    panel_width: f32 = width if width > 0 else metrics.control_width * 3
    floating: Floating = {attach_to = .ROOT, z_index = 501, capture = true}
    if anchored {
        floating.parent_point, floating.element_point = .LEFT_TOP, .LEFT_TOP
        floating.offset = {anchor.x, anchor.y + anchor.w}
    } else {
        floating.parent_point, floating.element_point = .CENTER_TOP, .CENTER_TOP
        floating.offset = {0, ctx.screen.y * 0.12}
    }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(panel_width), Fit()}, direction = .TOP_TO_BOTTOM, padding = PaddingAll(6), gap = 4},
        floating = floating,
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = IdSplitName(name), font_size = metrics.font_size},
    })
    UiTextField(ctx, "##query", query, query_length, {Grow(), {}})
    if count == 0 {
        UiLabelDim(ctx, "No match")
    } else {
        for view in 0 ..< rows {
            row: int = first + view
            item: PickerItem = items[matches[row]]
            row_id: Id = IdFromIndex(u32(view), id)
            _ = stateGet(ctx, row_id)
            interaction: Interaction = widgetBehavior(ctx, row_id)
            if interaction.clicked { chosen = matches[row] }
            // the part of the name that matched the first word is marked (the style draws cursor .. anchor in the strong face)
            word, _ := pickerNextWord(text, 0)
            found: int = completeFind(item.name, word) if word != "" else -1
            ElementOpen(ctx, {
                id = row_id,
                layout = {size = {Grow(), Fixed(metrics.control_height)}, direction = .LEFT_TO_RIGHT, padding = PaddingXY(metrics.padding.x, 0), align = {y = .CENTER}},
                hit = {.INTERACTIVE, .NO_FOCUS},            // a click on a row leaves the focus in the field
                draw = {kind = .DROPDOWN_ITEM, name = item.name, font_size = metrics.font_size, flags = {.SELECTED} if row == state.cursor else {}, value = f32(view), actual = f32(row), cursor = max(found, 0), anchor = max(found, 0) + len(word) if found >= 0 else 0},
            })
            UiSpacer(ctx)
            if item.detail != "" { UiLabelDim(ctx, item.detail) }
            ElementClose(ctx)
        }
    }
    ElementClose(ctx)
    if chosen >= 0 { open^, state.open = false, false }
    return
}
