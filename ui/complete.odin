package ui

// A list of words to pick from while typing in a text area or a text field: after the trigger (`@` for the names of people or files, any character) at the start of a word, the
// items that contain what was typed since are offered under the caret; the arrows choose, Enter or a click writes the item in, Escape closes the list.
//
//     ui.UiComplete(&ctx, "Message", buffer[:], &length, files[:])        // before the area: it takes the keys of the list before the area sees them
//     ui.UiTextArea(&ctx, "Message", buffer[:], &length)             // or ui.UiTextField
//
// Nothing is kept but the row that is chosen and where the list was closed; the items are the program's, looked through every frame the list is open (a list of
// thousands wants a search of its own that gives the few that match).
//
// Baldr's completion (examples/34_mentions, editor_complete) was the reason to have one; the code is written for this library.

// The rows of the list at most
COMPLETE_ROWS :: 8

@(private)
completeLower :: proc "contextless" (character: u8) -> u8 {
    return character + 32 if character >= 'A' && character <= 'Z' else character
}

// `text` has `part` in it, whatever the case of the letters (ASCII)
@(private)
completeContains :: proc "contextless" (text: string, part: string) -> bool {
    if len(part) == 0 { return true }
    if len(part) > len(text) { return false }
    for start in 0 ..= len(text) - len(part) {
        same: bool = true
        for i in 0 ..< len(part) {
            if completeLower(text[start + i]) != completeLower(part[i]) {
                same = false
                break
            }
        }
        if same { return true }
    }
    return false
}

// The word that is completed: the text from a trigger at the start of a word up to `cursor`, without a space in it. `start` is where it begins (after the trigger).
CompleteQuery :: proc(text: string, cursor: int, trigger: u8) -> (query: string, start: int, found: bool) {
    i: int = min(cursor, len(text))
    for i > 0 {
        character: u8 = text[i - 1]
        if character == trigger {
            // a trigger inside of a word is a letter of it (an address: name@host)
            if i - 1 > 0 && text[i - 2] != ' ' && text[i - 2] != '\n' && text[i - 2] != '\t' { return "", 0, false }
            return text[i:cursor], i, true
        }
        if character == ' ' || character == '\n' || character == '\t' { return "", 0, false }
        i -= 1
    }
    return "", 0, false
}

// The completion of the text area or the text field `area_name` (declare it right before that widget, in the same container, with the same name, buffer and
// length). An inserted item is a step of the undo history of the widget. `inserted` is true
// in the frame an item was written into the text: `item` is its place in `items`. The item replaces the typed word and a space follows it; the trigger stays.
UiComplete :: proc(ctx: ^Context, area_name: string, buffer: []u8, length: ^int, items: []string, trigger: u8 = '@') -> (inserted: bool, item: int) {
    area: Id = UiId(ctx, area_name)
    list: Id = IdFromIndex(0xC0FFEE, area)
    own: ^WidgetState = stateGet(ctx, list)
    state: ^WidgetState = stateFind(ctx, area)
    if state == nil { return }
    // while the list is open up and down are its own: the navigation does not take them from a text field (a text area keeps them anyway and says so after this)
    open: bool
    defer state.own_vertical = open
    if ctx.focus != area {
        // a press on a row of the list took the focus from the area: it comes back, the list is still its own
        on_row: bool
        for row in 0 ..< COMPLETE_ROWS {
            row_id: Id = IdFromIndex(u32(row), list)
            if ctx.hover == row_id || ctx.active == row_id { on_row = true }
        }
        if !on_row { return }
        ctx.focus = area
    }
    if state.cursor != state.anchor { return }
    text: string = string(buffer[:clamp(length^, 0, len(buffer))])
    query, start, found := CompleteQuery(text, state.cursor, trigger)
    if !found {
        own.anchor = -1                     // a new word may open the list again
        return
    }
    // closed by Escape: it stays closed for this word
    if own.anchor == start { return }
    matches: [COMPLETE_ROWS]int
    count: int
    for candidate, i in items {
        if count == COMPLETE_ROWS { break }
        if completeContains(candidate, query) {
            matches[count] = i
            count += 1
        }
    }
    if count == 0 { return }
    own.cursor = clamp(own.cursor, 0, count - 1)
    open = true
    // the keys of the list are taken out of the input: the area after this does not move its caret, break the line or lose the focus by them
    input: ^Input = &ctx.input
    if .UP in input.actions { own.cursor = (own.cursor + count - 1) % count }
    if .DOWN in input.actions { own.cursor = (own.cursor + 1) % count }
    input.actions -= {.UP, .DOWN}
    picked: int = -1
    if .ENTER in input.keys { picked = own.cursor }
    input.keys -= {.ENTER}
    if ctx.cancel_pending || .ESCAPE in input.keys {
        own.anchor = start
        ctx.cancel_pending = false
        input.keys -= {.ESCAPE}
        input.actions -= {.CANCEL}
        return
    }
    // the list, under the caret of the last frame. It is placed on the screen by the rectangle the area had then: the area is declared after this, an element
    // cannot be attached to one that comes later.
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {
        id = list,
        layout = {size = {Fit(metrics.control_width), Fit()}, direction = .TOP_TO_BOTTOM, padding = PaddingAll(2)},
        floating = {attach_to = .ROOT, parent_point = .LEFT_TOP, element_point = .LEFT_TOP, offset = {state.rect.x + state.caret.x, state.rect.y + state.caret.y}, z_index = 100, capture = true},
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = "dropdown", font_size = metrics.font_size},
    })
    for row in 0 ..< count {
        row_id: Id = IdFromIndex(u32(row), list)
        _ = stateGet(ctx, row_id)
        interaction: Interaction = widgetBehavior(ctx, row_id)
        if interaction.clicked { picked = row }
        ElementOpen(ctx, {
            id = row_id,
            layout = {size = {Grow(), Fixed(metrics.control_height)}},
            hit = {.INTERACTIVE, .NO_FOCUS},            // a click on a row leaves the focus in the area
            draw = {kind = .DROPDOWN_ITEM, name = items[matches[row]], font_size = metrics.font_size, flags = {.SELECTED} if row == own.cursor else {}, value = f32(row), actual = f32(row)},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
    if picked < 0 { return }
    // the typed word becomes the item, a space after it
    item = matches[picked]
    state.anchor = start
    textInsert(state, buffer, length, items[item])
    textInsert(state, buffer, length, " ")
    own.cursor = 0
    open = false
    // a step of the history of the widget: undo gives the typed word back (without it the history would start again, the text changed outside of the widget)
    undo: ^TextUndo = &ctx.text_undo
    if undo.owner == area && undo.count > 0 {
        if length^ * 2 <= len(undo.pool) {
            textUndoPush(undo, buffer[:length^], state.cursor, state.anchor)
        } else {
            textUndoReset(undo)
        }
        undo.kind = .NONE
    }
    return true, item
}
