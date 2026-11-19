package ui

import "core:mem"

// Undo and redo for the text field and the text area that has the focus (Ctrl + Z, Ctrl + Y or Ctrl + Shift + Z, the actions UNDO and REDO): the whole text is kept as it was after each edit, in a
// fixed pool of the context (UI_TEXT_UNDO_BYTES, UI_TEXT_UNDO_STEPS), so nothing allocates. Only the field with the focus has a history: another field getting the focus starts a new one, and a
// text that the program changed by itself while the field had the focus starts it again. Typing a word is one step (a run of typed characters ends after a space or when the cursor moves away),
// so is a run of backspaces; every other edit (paste, cut, delete, a typed character over a selection) is a step of its own. A text bigger than half of the pool has no history.

UI_TEXT_UNDO_BYTES :: #config(UI_TEXT_UNDO_BYTES, 16384)
UI_TEXT_UNDO_STEPS :: #config(UI_TEXT_UNDO_STEPS, 64)

TextUndoKind :: enum u8 {
    NONE,
    TYPING,
    BACKSPACE,
}

@(private)
TextUndoState :: struct {
    offset: int,                // in the pool
    length: int,
    cursor: int,
    anchor: int,
}

TextUndo :: struct {
    owner: Id,                  // the field the history is of (0: none)
    states: [UI_TEXT_UNDO_STEPS]TextUndoState,
    count: int,
    current: int,
    pool: [UI_TEXT_UNDO_BYTES]u8,
    used: int,
    kind: TextUndoKind,         // what the last edit was, so a run of the same kind is one step
    last_cursor: int,           // where the cursor was after it
    closed: bool,               // the last typed character was a space: the next one starts a step
}

@(private)
textUndoText :: proc(undo: ^TextUndo, index: int) -> []u8 {
    entry: ^TextUndoState = &undo.states[index]
    return undo.pool[entry.offset:entry.offset + entry.length]
}

@(private)
textUndoReset :: proc(undo: ^TextUndo) {
    undo.count, undo.current, undo.used, undo.kind, undo.closed = 0, 0, 0, .NONE, false
}

// Keeps the text as the newest state (the ones after `current` are dropped: a new edit ends what a redo would bring). When the pool or the list is full the oldest states go; the offsets
// are contiguous (a state starts where the one before it ends), so a drop moves the pool down by the size of the oldest.
@(private)
textUndoPush :: proc(undo: ^TextUndo, text: []u8, cursor: int, anchor: int) {
    undo.count = undo.current + 1 if undo.count > 0 else 0
    undo.used = 0
    if undo.count > 0 { undo.used = undo.states[undo.count - 1].offset + undo.states[undo.count - 1].length }
    for undo.count > 1 && (undo.count == len(undo.states) || undo.used + len(text) > len(undo.pool)) {
        shift: int = undo.states[0].length
        mem.copy(&undo.pool[0], &undo.pool[shift], undo.used - shift)
        for i in 1 ..< undo.count {
            undo.states[i - 1] = undo.states[i]
            undo.states[i - 1].offset -= shift
        }
        undo.count -= 1
        undo.used -= shift
    }
    entry: ^TextUndoState = &undo.states[undo.count]
    entry^ = {offset = undo.used, length = len(text), cursor = cursor, anchor = anchor}
    copy(undo.pool[entry.offset:], text)
    undo.used += len(text)
    undo.count += 1
    undo.current = undo.count - 1
}

// What the keyboard does to a focused field (textFieldEditKeys), with its history around it.
@(private)
textFieldEdit :: proc(ctx: ^Context, state: ^WidgetState, buffer: []u8, length: ^int, multiline: bool = false) -> (changed: bool, submitted: bool) {
    undo: ^TextUndo = &ctx.text_undo
    fits: bool = length^ * 2 <= len(undo.pool)
    if undo.owner != ctx.focus || (undo.count > 0 && string(buffer[:length^]) != string(textUndoText(undo, undo.current))) {
        // another field, or a text that the program changed: a new history from what is there now
        textUndoReset(undo)
        undo.owner = ctx.focus
        if fits { textUndoPush(undo, buffer[:length^], state.cursor, state.anchor) }
    }
    actions: Actions = ctx.input.actions
    if undo.count > 0 && (.UNDO in actions || .REDO in actions) {
        target: int = undo.current - 1 if .UNDO in actions else undo.current + 1
        if target >= 0 && target < undo.count {
            undo.current = target
            entry: ^TextUndoState = &undo.states[target]
            copy(buffer, textUndoText(undo, target))
            length^ = entry.length
            state.cursor, state.anchor = entry.cursor, entry.anchor
            undo.kind = .NONE
            return true, false
        }
        return false, false
    }
    low, high: int = textSelection(state)
    had_selection: bool = high > low
    cursor_before: int = state.cursor
    input: ^Input = &ctx.input
    typed: bool = input.text_count > 0 && .PASTE not_in input.actions && .CUT not_in input.actions && .BACKSPACE not_in input.keys && .DELETE not_in input.keys
    erased: bool = input.text_count == 0 && .BACKSPACE in input.keys && .DELETE not_in input.keys && .PASTE not_in input.actions && .CUT not_in input.actions
    changed, submitted = textFieldEditKeys(ctx, state, buffer, length, multiline)
    if changed && undo.count > 0 {
        kind: TextUndoKind = .NONE
        if typed && !had_selection { kind = .TYPING }
        if erased && !had_selection { kind = .BACKSPACE }
        joins: bool = kind != .NONE && kind == undo.kind && cursor_before == undo.last_cursor && !(kind == .TYPING && undo.closed) && undo.current > 0
        if joins { undo.count, undo.current = undo.current, undo.current - 1 }          // the run is one step: the state it made is replaced
        if fits {
            textUndoPush(undo, buffer[:length^], state.cursor, state.anchor)
        } else {
            textUndoReset(undo)
        }
        undo.kind, undo.last_cursor = kind, state.cursor
        if kind == .TYPING {
            last: u8 = input.text[input.text_count - 1]
            undo.closed = last <= 32                                                    // a space, a tab or a new line ends the word
        }
    }
    return
}
