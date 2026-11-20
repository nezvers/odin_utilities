package ui

// Changes to the text of a text field or a text area from outside of it: the buttons of an editor ("bold" puts marks around the selection, "list" a mark at the
// start of the line). They work on the selection the widget keeps, on the buffer of the program, and leave the widget with the focus so that the typing goes
// on. A change is a step of the undo history of the widget.
//
//     if ui.UiButton(&ctx, "Bold") { ui.UiTextWrap(&ctx, ui.UiId(&ctx, "Notes"), buffer[:], &length, "**", "**") }
//     ui.UiTextArea(&ctx, "Notes", buffer[:], &length)
//
// Baldr's rich text editor (examples/08_rich) was the reason to have them: there the document is a tree of blocks, here the document is the Markdown text and
// these are the commands that write its marks.

// The selection of the text widget `id`: bytes `low` to `high` of its text (the same: only a cursor). `found` is false when the widget was never declared.
UiTextSelectionOf :: proc(ctx: ^Context, id: Id) -> (low: int, high: int, found: bool) {
    state: ^WidgetState = stateFind(ctx, id)
    if state == nil { return 0, 0, false }
    low, high = textSelection(state)
    return low, high, true
}

// After a change from outside: the widget has the focus, and the change is a step of its history when it has one
@(private)
textFormatDone :: proc(ctx: ^Context, id: Id, state: ^WidgetState, buffer: []u8, length: ^int) {
    ctx.focus = id
    undo: ^TextUndo = &ctx.text_undo
    if undo.owner != id || undo.count == 0 { return }
    if length^ * 2 <= len(undo.pool) {
        textUndoPush(undo, buffer[:length^], state.cursor, state.anchor)
    } else {
        textUndoReset(undo)
    }
    undo.kind = .NONE
}

// Puts `before` and `after` around the selection of the text widget `id` (around the cursor when nothing is selected: the cursor is between them then, ready
// for the text). When the selection already stands between exactly these marks they are taken away instead: the same button turns a style on and off.
// False when the widget is not known or the buffer has no room.
UiTextWrap :: proc(ctx: ^Context, id: Id, buffer: []u8, length: ^int, before: string, after: string) -> bool {
    state: ^WidgetState = stateFind(ctx, id)
    if state == nil { return false }
    length^ = clamp(length^, 0, len(buffer))
    state.cursor, state.anchor = clamp(state.cursor, 0, length^), clamp(state.anchor, 0, length^)
    low, high := textSelection(state)
    text: string = string(buffer[:length^])
    wrapped: bool = low >= len(before) && high + len(after) <= length^ && text[low - len(before):low] == before && text[high:high + len(after)] == after
    if wrapped {
        // the mark after the selection first: the places before it stay
        state.anchor, state.cursor = high, high + len(after)
        textDeleteSelection(state, buffer, length)
        state.anchor, state.cursor = low - len(before), low
        textDeleteSelection(state, buffer, length)
        state.anchor, state.cursor = low - len(before), high - len(before)
    } else {
        if length^ + len(before) + len(after) > len(buffer) { return false }
        state.anchor, state.cursor = high, high
        textInsert(state, buffer, length, after)
        state.anchor, state.cursor = low, low
        textInsert(state, buffer, length, before)
        state.anchor, state.cursor = low + len(before), high + len(before)
    }
    textFormatDone(ctx, id, state, buffer, length)
    return true
}

// Puts `prefix` at the start of the line the cursor of the text widget `id` is in ("- " for a list, "# " for a heading, "> " for a quote), or takes it away
// when the line starts with it. The cursor and the selection stay on their letters. False when the widget is not known or the buffer has no room.
UiTextLinePrefix :: proc(ctx: ^Context, id: Id, buffer: []u8, length: ^int, prefix: string) -> bool {
    state: ^WidgetState = stateFind(ctx, id)
    if state == nil || len(prefix) == 0 { return false }
    length^ = clamp(length^, 0, len(buffer))
    cursor, anchor: int = clamp(state.cursor, 0, length^), clamp(state.anchor, 0, length^)
    line: int = cursor
    for line > 0 && buffer[line - 1] != '\n' { line -= 1 }
    has: bool = line + len(prefix) <= length^ && string(buffer[line:line + len(prefix)]) == prefix
    if has {
        state.anchor, state.cursor = line, line + len(prefix)
        textDeleteSelection(state, buffer, length)
        state.cursor = max(cursor - len(prefix), line) if cursor >= line else cursor
        state.anchor = max(anchor - len(prefix), line) if anchor >= line else anchor
    } else {
        if length^ + len(prefix) > len(buffer) { return false }
        state.anchor, state.cursor = line, line
        textInsert(state, buffer, length, prefix)
        state.cursor = cursor + len(prefix) if cursor >= line else cursor
        state.anchor = anchor + len(prefix) if anchor >= line else anchor
    }
    textFormatDone(ctx, id, state, buffer, length)
    return true
}
