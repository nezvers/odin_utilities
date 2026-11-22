package ui

// Editing the text of a field: the selection (anchor and cursor, in bytes), moving by a rune or a word, replacing the selection by what is typed or pasted,
// and the clipboard. All of it works on the buffer of the program, nothing allocates.

import "core:unicode"
import "core:unicode/utf8"
import su "../simd"

CLIPBOARD_LOCAL :: 1024

// Where copied text goes. A glue that knows the clipboard of the system sets `get` and `set`; without them the text stays in a buffer of the context, so copy
// and paste work inside of the program (and in the tests).
Clipboard :: struct {
    get: proc(ctx: ^Context, buffer: []u8) -> int,          // writes the text into `buffer` (cut when it does not fit), returns how many bytes
    set: proc(ctx: ^Context, text: string),
    local: [CLIPBOARD_LOCAL]u8,
    local_length: int,
}

// Puts a text on the clipboard (the system's and the local one).
UiClipboardSet :: proc(ctx: ^Context, text: string) {
    count: int = min(len(text), CLIPBOARD_LOCAL)
    for count > 0 && count < len(text) && !utf8.rune_start(text[count]) { count -= 1 }          // not in the middle of a rune
    copy(ctx.clipboard.local[:count], text[:count])
    ctx.clipboard.local_length = count
    if ctx.clipboard.set != nil { ctx.clipboard.set(ctx, text[:count]) }
}

// The text on the clipboard, into `buffer`: how many bytes.
UiClipboardGet :: proc(ctx: ^Context, buffer: []u8) -> int {
    if ctx.clipboard.get != nil { return ctx.clipboard.get(ctx, buffer) }
    count: int = min(ctx.clipboard.local_length, len(buffer))
    copy(buffer[:count], ctx.clipboard.local[:count])
    return count
}

@(private)
textSelection :: proc(state: ^WidgetState) -> (low: int, high: int) {
    return min(state.anchor, state.cursor), max(state.anchor, state.cursor)
}

@(private)
textIsWordRune :: proc(character: rune) -> bool {
    return character == '_' || unicode.is_letter(character) || unicode.is_digit(character)
}

// The start of the word before `from` (over the spaces, then over the word)
@(private)
textWordLeft :: proc(text: string, from: int) -> int {
    at: int = from
    for at > 0 {
        character, width := utf8.decode_last_rune_in_string(text[:at])
        if textIsWordRune(character) { break }
        at -= width
    }
    for at > 0 {
        character, width := utf8.decode_last_rune_in_string(text[:at])
        if !textIsWordRune(character) { break }
        at -= width
    }
    return at
}

// The end of the word after `from` (over the spaces, then over the word)
@(private)
textWordRight :: proc(text: string, from: int) -> int {
    at: int = from
    for at < len(text) {
        character, width := utf8.decode_rune_in_string(text[at:])
        if textIsWordRune(character) { break }
        at += width
    }
    for at < len(text) {
        character, width := utf8.decode_rune_in_string(text[at:])
        if !textIsWordRune(character) { break }
        at += width
    }
    return at
}

// The word that holds `at` (a run of spaces or signs when it is on one), for a double click
@(private)
textWordAt :: proc(text: string, at: int) -> (low: int, high: int) {
    low, high = at, at
    if at < len(text) {
        character, _ := utf8.decode_rune_in_string(text[at:])
        kind: bool = textIsWordRune(character)
        for low > 0 {
            previous, width := utf8.decode_last_rune_in_string(text[:low])
            if textIsWordRune(previous) != kind { break }
            low -= width
        }
        for high < len(text) {
            next, width := utf8.decode_rune_in_string(text[high:])
            if textIsWordRune(next) != kind { break }
            high += width
        }
    } else {
        low = textWordLeft(text, at)
    }
    return
}

// Removes the selection. True when there was one.
@(private)
textDeleteSelection :: proc(state: ^WidgetState, buffer: []u8, length: ^int) -> bool {
    low, high: int = textSelection(state)
    if high <= low { return false }
    copy(buffer[low:], buffer[high:length^])
    length^ -= high - low
    state.cursor, state.anchor = low, low
    return true
}

// Replaces the selection (or inserts at the cursor) by `text`, as much of it as the buffer holds (never a part of a rune). True when the buffer changed.
@(private)
textInsert :: proc(state: ^WidgetState, buffer: []u8, length: ^int, text: string) -> bool {
    changed: bool = textDeleteSelection(state, buffer, length)
    count: int = min(len(text), len(buffer) - length^)
    for count > 0 && count < len(text) && !utf8.rune_start(text[count]) { count -= 1 }
    if count <= 0 { return changed }
    copy(buffer[state.cursor + count:length^ + count], buffer[state.cursor:length^])
    copy(buffer[state.cursor:], text[:count])
    length^ += count
    state.cursor += count
    state.anchor = state.cursor
    return true
}

// What the keyboard does to a focused field. Shift extends the selection, Ctrl moves and deletes by words, the actions copy, cut, paste and select all.
// `read_only`: the text is looked at, not changed: the caret moves, the selection grows and Copy works; cut, paste, typing, backspace and delete do nothing.
@(private)
textFieldEditKeys :: proc(ctx: ^Context, state: ^WidgetState, buffer: []u8, length: ^int, multiline: bool = false, read_only: bool = false) -> (changed: bool, submitted: bool) {
    input: ^Input = &ctx.input
    shift: bool = .SHIFT in input.modifiers
    ctrl: bool = .CTRL in input.modifiers
    state.anchor = clamp(state.anchor, 0, length^)
    state.cursor = clamp(state.cursor, 0, length^)

    if .SELECT_ALL in input.actions { state.anchor, state.cursor = 0, length^ }
    low, high: int = textSelection(state)
    if (.COPY in input.actions || .CUT in input.actions) && high > low {
        UiClipboardSet(ctx, string(buffer[low:high]))
        if .CUT in input.actions && !read_only { changed = textDeleteSelection(state, buffer, length) || changed }
    }
    if .PASTE in input.actions && !read_only {
        pasted: [CLIPBOARD_LOCAL]u8
        count: int = UiClipboardGet(ctx, pasted[:])
        kept: int
        for i in 0 ..< count {
            character: u8 = pasted[i]
            if character == '\r' && multiline { continue }                                // a new line is one byte
            if character == '\t' || (!multiline && (character == '\n' || character == '\r')) { character = ' ' }       // a field is one line
            pasted[kept] = character
            kept += 1
        }
        // text from outside is checked once, here, at the edge: a bad part (a cut character, a stray byte) becomes U+FFFD, so the buffer of a text widget holds well formed UTF-8 and the
        // cursor never lands inside of a character
        cleaned: [CLIPBOARD_LOCAL * 3]u8
        written: int = su.Utf8Clean(pasted[:kept], cleaned[:])
        changed = textInsert(state, buffer, length, string(cleaned[:written])) || changed
    }
    // typed text goes in at the cursor, in place of the selection
    if input.text_count > 0 && !read_only {
        changed = textInsert(state, buffer, length, string(input.text[:input.text_count])) || changed
    }

    move :: proc(state: ^WidgetState, to: int, extend: bool) {
        state.cursor = to
        if !extend { state.anchor = to }
    }
    text: string = string(buffer[:length^])
    low, high = textSelection(state)
    if .LEFT in input.keys {
        if high > low && !shift {
            move(state, low, false)                 // the selection closes at its start
        } else if state.cursor > 0 {
            _, width := utf8.decode_last_rune_in_string(text[:state.cursor])
            move(state, textWordLeft(text, state.cursor) if ctrl else state.cursor - width, shift)
        }
    }
    if .RIGHT in input.keys {
        if high > low && !shift {
            move(state, high, false)
        } else if state.cursor < length^ {
            _, width := utf8.decode_rune_in_string(text[state.cursor:])
            move(state, textWordRight(text, state.cursor) if ctrl else state.cursor + width, shift)
        }
    }
    if .HOME in input.keys && !multiline { move(state, 0, shift) }
    if .END in input.keys && !multiline { move(state, length^, shift) }

    text = string(buffer[:length^])
    if .BACKSPACE in input.keys && !read_only {
        removed: bool = textDeleteSelection(state, buffer, length)
        if !removed && state.cursor > 0 {
            _, width := utf8.decode_last_rune_in_string(text[:state.cursor])
            from: int = textWordLeft(text, state.cursor) if ctrl else state.cursor - width
            copy(buffer[from:], buffer[state.cursor:length^])
            length^ -= state.cursor - from
            move(state, from, false)
            removed = true
        }
        changed = changed || removed
    }
    text = string(buffer[:length^])
    if .DELETE in input.keys && !read_only {
        removed: bool = textDeleteSelection(state, buffer, length)
        if !removed && state.cursor < length^ {
            _, width := utf8.decode_rune_in_string(text[state.cursor:])
            to: int = textWordRight(text, state.cursor) if ctrl else state.cursor + width
            copy(buffer[state.cursor:], buffer[to:length^])
            length^ -= to - state.cursor
            removed = true
        }
        changed = changed || removed
    }
    if .ENTER in input.keys && !multiline {
        submitted = true
    }
    if ctx.cancel_pending {
        ctx.focus = 0                   // cancel leaves the field
        ctx.cancel_pending = false
    }
    return
}

// Where the cursor and the other end of the selection of a text field or area are (byte offsets in its buffer), for a program that shows them or acts on them (find, line and column).
UiTextCursor :: proc(ctx: ^Context, id: Id) -> (cursor: int, anchor: int, found: bool) {
    state: ^WidgetState = stateFind(ctx, id)
    if state == nil { return 0, 0, false }
    return state.cursor, state.anchor, true
}
