package ui

import "core:unicode/utf8"

// A screen of cells for programs that move the cursor (a pager, a progress bar that redraws its line, a full screen tool): the caller gives the cells, bytes go in
// with `AnsiScreenWrite` in any pieces (an escape sequence or a letter may be cut between two writes), `UiAnsiScreen` draws the grid. Nothing is allocated; the grid never
// grows. The lines that scroll off the top go to a history the caller gives (a ring of rows: the oldest is lost when it is full); the view is scrolled back by the wheel
// over the screen or by `AnsiScreenScroll`.
//
//     cells: [24 * 80]ui.AnsiCell
//     history: [1000 * 80]ui.AnsiCell                           // optional
//     alternate: [24 * 80]ui.AnsiCell                           // optional: room for the alternate screen
//     screen := ui.AnsiScreenMake(cells[:], 80, 24, history[:], alternate[:])
//     ui.AnsiScreenWrite(&screen, output)
//     ui.UiAnsiScreen(&ctx, &screen)
//
// What is read: the printable characters (UTF-8; a wide letter (Chinese, Japanese, Korean, emoji) takes two cells, a combining mark goes on the cell before it: see
// `AnsiRuneWidth`), \r \n \b \t, the cursor moves (A B C D E F G H f d, s u, ESC 7 and
// ESC 8), erasing (J, K, X, P, @), inserting and deleting lines (L, M), reverse index (ESC M), reset (ESC c), and the same SGR styles as UiAnsiText. The alternate
// screen (`ESC [ ? 1049 h` and `l`, and the older 47 and 1047) is read when the caller gave room for it: a full screen program (an editor, a pager) draws on a clean
// screen and the screen as it was comes back when it quits; while it is shown the history is not fed and the view cannot be scrolled back. Every other mode (the
// hidden cursor, the mouse) and every other sequence is skipped.
//
// Limits: a fixed grid (no resize: make another screen and write the output again), no scroll regions (DECSTBM), no origin or wrap modes, no tab stops that are set
//     the width of a character is a table of the ranges that matter: ambiguous widths are 1, no grapheme clusters, no emoji sequences, no right-to-left text; a mark goes on the cell before it and one mark only
//     the history and the second buffer for the alternate screen are the caller's memory, and without the second buffer the alternate screen is skipped; no selection of cells, no mouse or paste modes, no cursor shapes or hiding
//     it only draws: nothing reads the keyboard or talks to a process; a cell is as wide as the code face's M, and a wide letter takes two of them whatever the font does
//
// Baldr's terminal screen (examples/25_terminal) was the reason to have it; the code is written for this library.

AnsiCell :: struct {
    character: rune,            // 0: empty
    mark: rune,                 // a combining mark that follows the character (0: none)
    style: AnsiState,
    wide: bool,                 // the character takes this cell and the next one, which is its continuation
    continuation: bool,         // the second cell of a wide character (it has no character of its own)
}

AnsiScreen :: struct {
    cells: []AnsiCell,          // columns * rows, row by row
    columns: int,
    rows: int,
    column: int,                // the cursor; column == columns is the cursor after the last cell, a letter then wraps first
    row: int,
    style: AnsiState,           // what the next letters are drawn in
    saved_column: int,
    saved_row: int,
    saved_style: AnsiState,
    palette: ^[16]Color,        // nil: ANSI_COLORS_DARK
    sequence: [48]u8,           // an escape sequence that is not whole yet
    sequence_length: int,
    letter: [4]u8,              // a UTF-8 letter that is not whole yet
    letter_length: int,
    letter_needed: int,
    history: []AnsiCell,        // the lines that scrolled off the top: a ring of history_rows rows
    history_rows: int,          // how many rows the ring has room for (0: no history)
    history_count: int,         // how many of them are filled
    history_head: int,          // the row of the ring the next line goes to
    back: int,                  // the rows the view is scrolled back into the history (0: the live screen)
    alternate: []AnsiCell,      // while the alternate screen is not shown, the cells of the other buffer (the two swap places); empty: no alternate screen
    alternate_active: bool,     // the alternate screen is shown: `cells` is its grid
    alternate_column: int,      // the cursor of the screen it replaced (ESC [ ? 1049 h saves it, the `l` puts it back)
    alternate_row: int,
    alternate_style: AnsiState,
}

// A screen over `cells` (at least columns * rows of them), cleared. `history`: room for the lines that scroll off the top, as many rows as it has room for (nil: none).
// `alternate`: room for the other buffer of a full screen program, as many cells as the screen has (nil: that program draws on the screen as it is).
AnsiScreenMake :: proc(cells: []AnsiCell, columns: int, rows: int, history: []AnsiCell = nil, alternate: []AnsiCell = nil) -> AnsiScreen {
    assert(columns > 0 && rows > 0 && len(cells) >= columns * rows, "a screen needs its cells")
    screen: AnsiScreen = {cells = cells[:columns * rows], columns = columns, rows = rows}
    if len(alternate) >= columns * rows { screen.alternate = alternate[:columns * rows] }
    screen.history_rows = len(history) / columns
    screen.history = history[:screen.history_rows * columns]
    AnsiScreenClear(&screen)
    return screen
}

// Every cell empty, the cursor at the top left, the style reset
AnsiScreenClear :: proc(screen: ^AnsiScreen) {
    for &cell in screen.cells { cell = {} }
    screen.column, screen.row = 0, 0
    screen.style, screen.saved_style = {}, {}
    screen.saved_column, screen.saved_row = 0, 0
    screen.sequence_length, screen.letter_length = 0, 0
    screen.history_count, screen.history_head, screen.back = 0, 0, 0
    screen.alternate_active = false
    for &cell in screen.alternate { cell = {} }
}

@(private)
screenCell :: proc "contextless" (screen: ^AnsiScreen, column: int, row: int) -> ^AnsiCell {
    return &screen.cells[row * screen.columns + column]
}

// An empty cell keeps the ground of the style that erased it (a cleared line in a colored ground stays colored)
@(private)
screenBlank :: proc "contextless" (screen: ^AnsiScreen) -> AnsiCell {
    return {style = {background = screen.style.background}}
}

@(private)
screenClearRange :: proc "contextless" (screen: ^AnsiScreen, from_row: int, from_column: int, to_row: int, to_column: int) {
    // [from, to) as cell numbers
    from: int = clamp(from_row * screen.columns + from_column, 0, len(screen.cells))
    to: int = clamp(to_row * screen.columns + to_column, 0, len(screen.cells))
    blank: AnsiCell = screenBlank(screen)
    for i in from ..< to { screen.cells[i] = blank }
}

// The lines `top` to `bottom` (inclusive) move up (`count` > 0) or down (`count` < 0); the lines that come in are empty
@(private)
screenScroll :: proc "contextless" (screen: ^AnsiScreen, top: int, bottom: int, count: int) {
    height: int = bottom - top + 1
    shift: int = min(abs(count), height)
    if shift <= 0 { return }
    columns: int = screen.columns
    blank: AnsiCell = screenBlank(screen)
    if count > 0 {
        copy(screen.cells[top * columns:(bottom + 1 - shift) * columns], screen.cells[(top + shift) * columns:(bottom + 1) * columns])
        for i in (bottom + 1 - shift) * columns ..< (bottom + 1) * columns { screen.cells[i] = blank }
    } else {
        copy(screen.cells[(top + shift) * columns:(bottom + 1) * columns], screen.cells[top * columns:(bottom + 1 - shift) * columns])
        for i in top * columns ..< (top + shift) * columns { screen.cells[i] = blank }
    }
}

// The lines that scroll off the top are kept (the oldest of a full history is lost); a view that is scrolled back stays on what it shows
@(private)
screenHistoryPush :: proc "contextless" (screen: ^AnsiScreen) {
    if screen.history_rows == 0 || screen.alternate_active { return }
    columns: int = screen.columns
    copy(screen.history[screen.history_head * columns:(screen.history_head + 1) * columns], screen.cells[:columns])
    screen.history_head = (screen.history_head + 1) % screen.history_rows
    screen.history_count = min(screen.history_count + 1, screen.history_rows)
    if screen.back > 0 { screen.back = min(screen.back + 1, screen.history_count) }
}

@(private)
screenLineFeed :: proc "contextless" (screen: ^AnsiScreen) {
    if screen.row == screen.rows - 1 {
        screenHistoryPush(screen)
        screenScroll(screen, 0, screen.rows - 1, 1)
    } else {
        screen.row += 1
    }
}

// How many cells a character takes on the screen: 0 for a combining mark (it goes on the cell before), 2 for a wide one (Hangul, Chinese and Japanese characters,
// fullwidth forms, emoji), else 1. A table of the ranges that matter, not all of Unicode.
AnsiRuneWidth :: proc "contextless" (character: rune) -> int {
    if character < 0x300 { return 1 }
    switch character {
    case 0x300 ..= 0x36F, 0x483 ..= 0x489, 0x591 ..= 0x5BD, 0x610 ..= 0x61A, 0x64B ..= 0x65F, 0x1AB0 ..= 0x1AFF, 0x1DC0 ..= 0x1DFF, 0x200B ..= 0x200F, 0x20D0 ..= 0x20FF,
         0xFE00 ..= 0xFE0F, 0xFE20 ..= 0xFE2F, 0xE0100 ..= 0xE01EF:
        return 0
    case 0x1100 ..= 0x115F, 0x2E80 ..= 0x303E, 0x3041 ..= 0x33FF, 0x3400 ..= 0x4DBF, 0x4E00 ..= 0x9FFF, 0xA000 ..= 0xA4CF, 0xA960 ..= 0xA97F, 0xAC00 ..= 0xD7A3,
         0xF900 ..= 0xFAFF, 0xFE30 ..= 0xFE6F, 0xFF00 ..= 0xFF60, 0xFFE0 ..= 0xFFE6, 0x1F300 ..= 0x1F64F, 0x1F680 ..= 0x1F6FF, 0x1F900 ..= 0x1F9FF, 0x1FA70 ..= 0x1FAFF,
         0x20000 ..= 0x3FFFD:
        return 2
    }
    return 1
}

// A cell that is the half of a wide character, or has one, loses its other half when it is written over or cut
@(private)
screenBreakPair :: proc "contextless" (screen: ^AnsiScreen, column: int, row: int) {
    cell: ^AnsiCell = screenCell(screen, column, row)
    if cell.continuation && column > 0 {
        previous: ^AnsiCell = screenCell(screen, column - 1, row)
        if previous.wide { previous^ = {style = {background = previous.style.background}} }
    }
    if cell.wide && column + 1 < screen.columns {
        next: ^AnsiCell = screenCell(screen, column + 1, row)
        if next.continuation { next^ = {style = {background = next.style.background}} }
    }
}

// A row after something cut it (erasing, deleting, inserting): a wide character without its other half is an empty cell
@(private)
screenFixRow :: proc "contextless" (screen: ^AnsiScreen, row: int) {
    for column in 0 ..< screen.columns {
        cell: ^AnsiCell = screenCell(screen, column, row)
        if cell.continuation && (column == 0 || !screenCell(screen, column - 1, row).wide) { cell^ = {style = {background = cell.style.background}} }
        if cell.wide && (column == screen.columns - 1 || !screenCell(screen, column + 1, row).continuation) { cell^ = {style = {background = cell.style.background}} }
    }
}

@(private)
screenPut :: proc "contextless" (screen: ^AnsiScreen, character: rune) {
    width: int = AnsiRuneWidth(character)
    if width == 0 {
        // a combining mark: it goes on the letter before the cursor
        column: int = min(screen.column, screen.columns) - 1
        if column < 0 { return }
        cell: ^AnsiCell = screenCell(screen, column, screen.row)
        if cell.continuation && column > 0 { cell = screenCell(screen, column - 1, screen.row) }
        if cell.character != 0 && cell.mark == 0 { cell.mark = character }
        return
    }
    if screen.column + width > screen.columns {
        // the cursor stood after the last cell, or a wide letter does not fit in the one that is left (it stays empty): the letter starts the next line
        screen.column = 0
        screenLineFeed(screen)
    }
    for offset in 0 ..< width { screenBreakPair(screen, screen.column + offset, screen.row) }
    screenCell(screen, screen.column, screen.row)^ = {character = character, style = screen.style, wide = width == 2}
    if width == 2 { screenCell(screen, screen.column + 1, screen.row)^ = {style = screen.style, continuation = true} }
    screen.column += width
}

@(private)
screenParameter :: proc "contextless" (numbers: []int, index: int, default: int) -> int {
    if index >= len(numbers) || numbers[index] == 0 { return default }
    return numbers[index]
}

// Enters or leaves the alternate screen: the two buffers swap places. 1049 also saves the cursor and the style on the way in (and puts them back on the way out) and
// starts with a clean screen; 1047 leaves a clean screen behind it; 47 keeps what the alternate screen had.
@(private)
screenAlternate :: proc "contextless" (screen: ^AnsiScreen, mode: int, enter: bool) {
    if len(screen.alternate) < len(screen.cells) || enter == screen.alternate_active { return }
    swap :: proc "contextless" (screen: ^AnsiScreen) {
        for i in 0 ..< len(screen.cells) { screen.cells[i], screen.alternate[i] = screen.alternate[i], screen.cells[i] }
    }
    if enter {
        if mode == 1049 { screen.alternate_column, screen.alternate_row, screen.alternate_style = screen.column, screen.row, screen.style }
        swap(screen)
        if mode == 1049 { for &cell in screen.cells { cell = {} } }
        screen.alternate_active = true
        screen.back = 0
    } else {
        if mode == 1047 || mode == 1049 { for &cell in screen.cells { cell = {} } }
        swap(screen)
        screen.alternate_active = false
        if mode == 1049 { screen.column, screen.row, screen.style = screen.alternate_column, screen.alternate_row, screen.alternate_style }
    }
}

// The alternate screen is shown
AnsiScreenAlternate :: proc(screen: ^AnsiScreen) -> bool {
    return screen.alternate_active
}

// One whole sequence: ESC [ parameters final
@(private)
screenSequence :: proc(screen: ^AnsiScreen, text: []u8) {
    // text[0] is '[', the last byte is the final one
    final: u8 = text[len(text) - 1]
    numbers: [16]int
    count: int
    any_digit: bool
    private: bool
    for character in text[1:len(text) - 1] {
        switch {
        case character >= '0' && character <= '9':
            if count < len(numbers) { numbers[count] = min(numbers[count] * 10 + int(character - '0'), 100000) }
            any_digit = true
        case character == ';' || character == ':':
            if count < len(numbers) { count += 1 }
            any_digit = false
        case character == '?' || character == '>' || character == '<' || character == '=':
            private = true
        }
    }
    if any_digit && count < len(numbers) { count += 1 }
    parameters: []int = numbers[:count]
    if private {
        // the modes of the alternate screen; the others (the cursor, the mouse, reports) are nothing of a screen of cells
        if final == 'h' || final == 'l' {
            for mode in parameters {
                if mode == 47 || mode == 1047 || mode == 1049 { screenAlternate(screen, mode, final == 'h') }
            }
        }
        return
    }
    columns, rows: int = screen.columns, screen.rows
    switch final {
    case 'm':
        palette: ^[16]Color = screen.palette if screen.palette != nil else &ANSI_COLORS_DARK
        ansiApply(&screen.style, parameters, palette)
    case 'A': screen.row = max(screen.row - screenParameter(parameters, 0, 1), 0)
    case 'B': screen.row = min(screen.row + screenParameter(parameters, 0, 1), rows - 1)
    case 'C': screen.column = min(screen.column + screenParameter(parameters, 0, 1), columns - 1)
    case 'D': screen.column = max(min(screen.column, columns - 1) - screenParameter(parameters, 0, 1), 0)
    case 'E':
        screen.row, screen.column = min(screen.row + screenParameter(parameters, 0, 1), rows - 1), 0
    case 'F':
        screen.row, screen.column = max(screen.row - screenParameter(parameters, 0, 1), 0), 0
    case 'G': screen.column = clamp(screenParameter(parameters, 0, 1) - 1, 0, columns - 1)
    case 'd': screen.row = clamp(screenParameter(parameters, 0, 1) - 1, 0, rows - 1)
    case 'H', 'f':
        screen.row = clamp(screenParameter(parameters, 0, 1) - 1, 0, rows - 1)
        screen.column = clamp(screenParameter(parameters, 1, 1) - 1, 0, columns - 1)
    case 's': screen.saved_column, screen.saved_row, screen.saved_style = screen.column, screen.row, screen.style
    case 'u': screen.column, screen.row, screen.style = screen.saved_column, screen.saved_row, screen.saved_style
    case 'J':
        mode: int = parameters[0] if len(parameters) > 0 else 0
        column: int = min(screen.column, columns)
        switch mode {
        case 0: screenClearRange(screen, screen.row, column, rows, 0)
        case 1: screenClearRange(screen, 0, 0, screen.row, 0); screenClearRange(screen, screen.row, 0, screen.row, min(column + 1, columns))
        case 2: screenClearRange(screen, 0, 0, rows, 0)
        case 3:
            screenClearRange(screen, 0, 0, rows, 0)
            screen.history_count, screen.history_head, screen.back = 0, 0, 0       // the history too
        }
        for row in 0 ..< rows { screenFixRow(screen, row) }
    case 'K':
        mode: int = parameters[0] if len(parameters) > 0 else 0
        column: int = min(screen.column, columns)
        switch mode {
        case 0: screenClearRange(screen, screen.row, column, screen.row, columns)
        case 1: screenClearRange(screen, screen.row, 0, screen.row, min(column + 1, columns))
        case 2: screenClearRange(screen, screen.row, 0, screen.row, columns)
        }
        screenFixRow(screen, screen.row)
    case 'X':
        column: int = min(screen.column, columns)
        screenClearRange(screen, screen.row, column, screen.row, min(column + screenParameter(parameters, 0, 1), columns))
        screenFixRow(screen, screen.row)
    case 'P':
        // delete letters: the rest of the row moves left
        column: int = min(screen.column, columns)
        amount: int = min(screenParameter(parameters, 0, 1), columns - column)
        row: []AnsiCell = screen.cells[screen.row * columns:(screen.row + 1) * columns]
        copy(row[column:columns - amount], row[column + amount:columns])
        blank: AnsiCell = screenBlank(screen)
        for i in columns - amount ..< columns { row[i] = blank }
        screenFixRow(screen, screen.row)
    case '@':
        // insert blanks: the rest of the row moves right
        column: int = min(screen.column, columns)
        amount: int = min(screenParameter(parameters, 0, 1), columns - column)
        row: []AnsiCell = screen.cells[screen.row * columns:(screen.row + 1) * columns]
        copy(row[column + amount:columns], row[column:columns - amount])
        blank: AnsiCell = screenBlank(screen)
        for i in column ..< column + amount { row[i] = blank }
        screenFixRow(screen, screen.row)
    case 'L': screenScroll(screen, screen.row, rows - 1, -screenParameter(parameters, 0, 1))
    case 'M': screenScroll(screen, screen.row, rows - 1, screenParameter(parameters, 0, 1))
    }
}

// Writes bytes to the screen. The bytes may be cut anywhere: what is not whole yet waits for the next call.
AnsiScreenWrite :: proc(screen: ^AnsiScreen, bytes: []u8) {
    for byte in bytes {
        // inside of an escape sequence
        if screen.sequence_length > 0 {
            if screen.sequence_length == 1 {
                // the byte after ESC
                switch byte {
                case '[', ']', '(', ')', '*', '+':
                    // CSI; OSC (a string up to BEL or ESC, skipped); a character set (one more byte, skipped)
                    screen.sequence[1] = byte
                    screen.sequence_length = 2
                case '7':
                    screen.saved_column, screen.saved_row, screen.saved_style = screen.column, screen.row, screen.style
                    screen.sequence_length = 0
                case '8':
                    screen.column, screen.row, screen.style = screen.saved_column, screen.saved_row, screen.saved_style
                    screen.sequence_length = 0
                case 'M':
                    if screen.row == 0 { screenScroll(screen, 0, screen.rows - 1, -1) } else { screen.row -= 1 }
                    screen.sequence_length = 0
                case 'c':
                    AnsiScreenClear(screen)
                case:
                    screen.sequence_length = 0                              // another escape: skipped with its letter
                }
                continue
            }
            if screen.sequence[1] == ']' {
                // a string: ends at BEL, or at an ESC that starts the next sequence (the \ after it is skipped)
                if byte == 0x07 {
                    screen.sequence_length = 0
                } else if byte == 0x1b {
                    screen.sequence_length = 1
                }
            } else if screen.sequence[1] != '[' {
                screen.sequence_length = 0
            } else if byte >= 0x40 && byte <= 0x7e {
                screen.sequence[screen.sequence_length] = byte
                screenSequence(screen, screen.sequence[1:screen.sequence_length + 1])
                screen.sequence_length = 0
            } else if screen.sequence_length < len(screen.sequence) - 1 {
                screen.sequence[screen.sequence_length] = byte
                screen.sequence_length += 1
            } else {
                screen.sequence_length = 0                                  // too long to be anything we know
            }
            continue
        }
        // inside of a letter of several bytes
        if screen.letter_length > 0 {
            if byte & 0xC0 != 0x80 {
                screen.letter_length = 0                                    // it was cut: the new byte starts over
            } else {
                screen.letter[screen.letter_length] = byte
                screen.letter_length += 1
                if screen.letter_length == screen.letter_needed {
                    character, _ := utf8.decode_rune(screen.letter[:screen.letter_length])
                    screenPut(screen, character)
                    screen.letter_length = 0
                }
                continue
            }
        }
        switch {
        case byte == 0x1b:
            screen.sequence[0] = byte
            screen.sequence_length = 1
        case byte == '\r': screen.column = 0
        case byte == '\n': screenLineFeed(screen)
        case byte == '\b': screen.column = max(min(screen.column, screen.columns - 1) - 1, 0)
        case byte == '\t': screen.column = min((min(screen.column, screen.columns - 1) / 8 + 1) * 8, screen.columns - 1)
        case byte < 0x20 || byte == 0x7f:
        case byte < 0x80: screenPut(screen, rune(byte))
        case byte >= 0xC0:
            screen.letter[0] = byte
            screen.letter_length = 1
            screen.letter_needed = 2 if byte < 0xE0 else (3 if byte < 0xF0 else 4)
        }
    }
}

// The text of a row of the screen without the empty cells at its end (for a test or a copy)
AnsiScreenRow :: proc(screen: ^AnsiScreen, row: int, out: []u8) -> string {
    count: int
    last: int = -1
    for column in 0 ..< screen.columns {
        if screenCell(screen, column, row).character != 0 { last = column }
    }
    for column in 0 ..= last {
        cell: AnsiCell = screenCell(screen, column, row)^
        if cell.continuation { continue }                     // the second half of a wide letter
        character: rune = cell.character
        if character == 0 { character = ' ' }
        encoded, width := utf8.encode_rune(character)
        if count + width > len(out) { break }
        copy(out[count:], encoded[:width])
        count += width
        if cell.mark != 0 {
            encoded, width = utf8.encode_rune(cell.mark)
            if count + width > len(out) { break }
            copy(out[count:], encoded[:width])
            count += width
        }
    }
    return string(out[:count])
}

// How many lines of history there are to scroll back through
AnsiScreenHistory :: proc(screen: ^AnsiScreen) -> int {
    return screen.history_count
}

// Scrolls the view back into the history (`rows` > 0) or forward (< 0), as far as there are lines. UiAnsiScreen does it for the wheel.
AnsiScreenScroll :: proc(screen: ^AnsiScreen, rows: int) {
    screen.back = 0 if screen.alternate_active else clamp(screen.back + rows, 0, screen.history_count)       // there is no history behind the alternate screen
}

// The view is the live screen again
AnsiScreenFollow :: proc(screen: ^AnsiScreen) {
    screen.back = 0
}

// The cell of the view (the history and the screen below it, `back` rows up from the live screen): `row` counts from the top of the view
AnsiScreenViewCell :: proc(screen: ^AnsiScreen, column: int, row: int) -> ^AnsiCell {
    absolute: int = screen.history_count - screen.back + row
    if absolute < screen.history_count {
        ring: int = (screen.history_head + screen.history_rows - screen.history_count + absolute) % screen.history_rows
        return &screen.history[ring * screen.columns + column]
    }
    return screenCell(screen, column, absolute - screen.history_count)
}

// The screen as texts in the code face: a row at a time, the cells of one style in a row are one text, the empty cells take their room, a ground is a FILL behind its
// cells. The cursor is drawn as a block over its cell while `cursor` is true (a program that blinks it passes the phase) and the view is the live screen. The wheel over
// the screen scrolls the view through the history. A wide letter is a text of its own, two cells wide, so that what follows it stays on the grid. The text lives in the
// text memory of the frame: a screen of 24 x 80 needs about 2 KB of it. `name` makes the id of the element (the wheel needs it): two screens in a container need two names.
UiAnsiScreen :: proc(ctx: ^Context, screen: ^AnsiScreen, cursor: bool = true, name: string = "ansi screen") {
    metrics: ^Metrics = &ctx.style.metrics
    // the size of a cell: the code face's letter and the height of a line
    outer_tags: [DRAW_TAGS]Id = ctx.measure_tags
    ctx.measure_tags = {}
    UiPushTag(ctx, "mono")
    for i in 0 ..< min(ctx.tag_count, DRAW_TAGS) { ctx.measure_tags[i] = ctx.tag_stack[ctx.tag_count - 1 - i] }
    cell: Vec2 = measureText(ctx, "M", metrics.font_size)
    ctx.measure_tags = outer_tags
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    if ctx.hover_scroll == id && ctx.input.wheel.y != 0 {
        steps: int = int(ctx.input.wheel.y * 3)
        if steps == 0 { steps = 1 if ctx.input.wheel.y > 0 else -1 }
        AnsiScreenScroll(screen, steps)
    }
    ElementOpen(ctx, {id = id, layout = {size = {Fixed(cell.x * f32(screen.columns)), Fixed(cell.y * f32(screen.rows))}, direction = .TOP_TO_BOTTOM}, hit = {.SCROLL}})
    for row in 0 ..< screen.rows {
        ElementOpen(ctx, {layout = {size = {Grow(), Fixed(cell.y)}, direction = .LEFT_TO_RIGHT}})
        // the end of the row: after the last cell that has anything, the empty cells with no ground are not declared
        end: int = screen.columns
        for end > 0 {
            last: ^AnsiCell = AnsiScreenViewCell(screen, end - 1, row)
            if last.character != 0 || last.continuation || last.style.background.a != 0 { break }
            end -= 1
        }
        column: int
        for column < end {
            first: AnsiCell = AnsiScreenViewCell(screen, column, row)^
            stop: int = column + 1
            if first.wide && column + 1 < end {
                stop = column + 2                                           // a wide letter and its continuation: a run of its own
            } else {
                for stop < end {
                    next: AnsiCell = AnsiScreenViewCell(screen, stop, row)^
                    if next.style != first.style || next.wide { break }
                    stop += 1
                }
            }
            // the cells as one text; empty ones are spaces, the second half of a wide letter has no text, a mark follows its letter
            start: int = ctx.text_used
            for at in column ..< stop {
                cell: AnsiCell = AnsiScreenViewCell(screen, at, row)^
                if cell.continuation && at > column { continue }
                character: rune = cell.character
                if character == 0 { character = ' ' }
                encoded, width := utf8.encode_rune(character)
                extra, extra_width := utf8.encode_rune(cell.mark)
                if ctx.text_used + width + (extra_width if cell.mark != 0 else 0) > len(ctx.text_buffer) {
                    ctx.problems += {.TEXT_FULL}
                    break
                }
                copy(ctx.text_buffer[ctx.text_used:], encoded[:width])
                ctx.text_used += width
                if cell.mark != 0 {
                    copy(ctx.text_buffer[ctx.text_used:], extra[:extra_width])
                    ctx.text_used += extra_width
                }
            }
            run: string = string(ctx.text_buffer[start:ctx.text_used])
            style: AnsiState = first.style
            pushed: int
            if style.bold {
                UiPushTag(ctx, "strong")
                pushed += 1
            }
            if style.italic {
                UiPushTag(ctx, "italic")
                pushed += 1
            }
            if style.dim {
                UiPushTag(ctx, "dim")
                pushed += 1
            }
            if style.underline {
                UiPushTag(ctx, "underline")
                pushed += 1
            }
            width: f32 = cell.x * f32(stop - column)
            // the element has the width of its cells, so that a font that is not exactly the measured width does not move the next run
            if style.reverse {
                UiPushTag(ctx, "reverse")
                pushed += 1
            }
            ground, ink, grounded := AnsiColorsOf(style)
            if grounded {
                ElementOpen(ctx, {layout = {size = {Fixed(width), Fixed(cell.y)}}, draw = {kind = .FILL, color = ground}})
            } else {
                ElementOpen(ctx, {layout = {size = {Fixed(width), Fixed(cell.y)}}})
            }
            TextOpen(ctx, run, {wrap = .NONE, color = ink})
            ElementClose(ctx)
            for _ in 0 ..< pushed { UiPopTag(ctx) }
            column = stop
        }
        ElementClose(ctx)
    }
    if cursor && screen.back == 0 {
        column: int = min(screen.column, screen.columns - 1)
        ElementOpen(ctx, {
            layout = {size = {Fixed(cell.x), Fixed(cell.y)}},
            absolute = {enabled = true, offset = {cell.x * f32(column), cell.y * f32(screen.row)}},
            draw = {kind = .FILL, color = {128, 128, 128, 110}},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
    UiPopTag(ctx)
}
