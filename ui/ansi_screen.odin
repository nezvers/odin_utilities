package ui

import "core:unicode/utf8"

// A screen of cells for programs that move the cursor (a pager, a progress bar that redraws its line, a full screen tool): the caller gives the cells, bytes go in
// with `AnsiScreenWrite` in any pieces (an escape sequence or a letter may be cut between two writes), `UiAnsiScreen` draws the grid. Nothing is allocated; there is no
// scrollback (a line that scrolls off the top is gone), the grid never grows.
//
//     cells: [24 * 80]ui.AnsiCell
//     screen := ui.AnsiScreenMake(cells[:], 80, 24)
//     ui.AnsiScreenWrite(&screen, output)
//     ui.UiAnsiScreen(&ctx, &screen)
//
// What is read: the printable characters (UTF-8, one cell each: wide characters are not handled), \r \n \b \t, the cursor moves (A B C D E F G H f d, s u, ESC 7 and
// ESC 8), erasing (J, K, X, P, @), inserting and deleting lines (L, M), reverse index (ESC M), reset (ESC c), and the same SGR styles as UiAnsiText. Modes (the
// alternate screen, the hidden cursor, the mouse) and every other sequence are skipped.
//
// Baldr's terminal screen (examples/25_terminal) was the reason to have it; the code is written for this library.

AnsiCell :: struct {
    character: rune,            // 0: empty
    style: AnsiState,
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
}

// A screen over `cells` (at least columns * rows of them), cleared
AnsiScreenMake :: proc(cells: []AnsiCell, columns: int, rows: int) -> AnsiScreen {
    assert(columns > 0 && rows > 0 && len(cells) >= columns * rows, "a screen needs its cells")
    screen: AnsiScreen = {cells = cells[:columns * rows], columns = columns, rows = rows}
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

@(private)
screenLineFeed :: proc "contextless" (screen: ^AnsiScreen) {
    if screen.row == screen.rows - 1 {
        screenScroll(screen, 0, screen.rows - 1, 1)
    } else {
        screen.row += 1
    }
}

@(private)
screenPut :: proc "contextless" (screen: ^AnsiScreen, character: rune) {
    if screen.column >= screen.columns {
        // the cursor stood after the last cell: the letter starts the next line
        screen.column = 0
        screenLineFeed(screen)
    }
    screenCell(screen, screen.column, screen.row)^ = {character = character, style = screen.style}
    screen.column += 1
}

@(private)
screenParameter :: proc "contextless" (numbers: []int, index: int, default: int) -> int {
    if index >= len(numbers) || numbers[index] == 0 { return default }
    return numbers[index]
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
    if private { return }                                                   // modes and reports: nothing of a screen of cells
    parameters: []int = numbers[:count]
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
        case 2, 3: screenClearRange(screen, 0, 0, rows, 0)
        }
    case 'K':
        mode: int = parameters[0] if len(parameters) > 0 else 0
        column: int = min(screen.column, columns)
        switch mode {
        case 0: screenClearRange(screen, screen.row, column, screen.row, columns)
        case 1: screenClearRange(screen, screen.row, 0, screen.row, min(column + 1, columns))
        case 2: screenClearRange(screen, screen.row, 0, screen.row, columns)
        }
    case 'X':
        column: int = min(screen.column, columns)
        screenClearRange(screen, screen.row, column, screen.row, min(column + screenParameter(parameters, 0, 1), columns))
    case 'P':
        // delete letters: the rest of the row moves left
        column: int = min(screen.column, columns)
        amount: int = min(screenParameter(parameters, 0, 1), columns - column)
        row: []AnsiCell = screen.cells[screen.row * columns:(screen.row + 1) * columns]
        copy(row[column:columns - amount], row[column + amount:columns])
        blank: AnsiCell = screenBlank(screen)
        for i in columns - amount ..< columns { row[i] = blank }
    case '@':
        // insert blanks: the rest of the row moves right
        column: int = min(screen.column, columns)
        amount: int = min(screenParameter(parameters, 0, 1), columns - column)
        row: []AnsiCell = screen.cells[screen.row * columns:(screen.row + 1) * columns]
        copy(row[column + amount:columns], row[column:columns - amount])
        blank: AnsiCell = screenBlank(screen)
        for i in column ..< column + amount { row[i] = blank }
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
        character: rune = screenCell(screen, column, row).character
        if character == 0 { character = ' ' }
        encoded, width := utf8.encode_rune(character)
        if count + width > len(out) { break }
        copy(out[count:], encoded[:width])
        count += width
    }
    return string(out[:count])
}

// The screen as texts in the code face: a row at a time, the cells of one style in a row are one text, the empty cells take their room, a ground is a FILL behind its
// cells. The cursor is drawn as a block over its cell while `cursor` is true (a program that blinks it passes the phase). The text lives in the text memory of the frame:
// a screen of 24 x 80 needs about 2 KB of it.
UiAnsiScreen :: proc(ctx: ^Context, screen: ^AnsiScreen, cursor: bool = true) {
    metrics: ^Metrics = &ctx.style.metrics
    // the size of a cell: the code face's letter and the height of a line
    outer_tags: [DRAW_TAGS]Id = ctx.measure_tags
    ctx.measure_tags = {}
    UiPushTag(ctx, "mono")
    for i in 0 ..< min(ctx.tag_count, DRAW_TAGS) { ctx.measure_tags[i] = ctx.tag_stack[ctx.tag_count - 1 - i] }
    cell: Vec2 = measureText(ctx, "M", metrics.font_size)
    ctx.measure_tags = outer_tags
    ElementOpen(ctx, {layout = {size = {Fixed(cell.x * f32(screen.columns)), Fixed(cell.y * f32(screen.rows))}, direction = .TOP_TO_BOTTOM}})
    for row in 0 ..< screen.rows {
        ElementOpen(ctx, {layout = {size = {Grow(), Fixed(cell.y)}, direction = .LEFT_TO_RIGHT}})
        // the end of the row: after the last cell that has anything, the empty cells with no ground are not declared
        end: int = screen.columns
        for end > 0 {
            last: ^AnsiCell = screenCell(screen, end - 1, row)
            if last.character != 0 || last.style.background.a != 0 { break }
            end -= 1
        }
        column: int
        for column < end {
            first: AnsiCell = screenCell(screen, column, row)^
            stop: int = column + 1
            for stop < end {
                next: AnsiCell = screenCell(screen, stop, row)^
                if next.style != first.style { break }
                stop += 1
            }
            // the cells as one text; empty ones are spaces
            start: int = ctx.text_used
            for at in column ..< stop {
                character: rune = screenCell(screen, at, row).character
                if character == 0 { character = ' ' }
                encoded, width := utf8.encode_rune(character)
                if ctx.text_used + width > len(ctx.text_buffer) {
                    ctx.problems += {.TEXT_FULL}
                    break
                }
                copy(ctx.text_buffer[ctx.text_used:], encoded[:width])
                ctx.text_used += width
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
            if style.background.a != 0 {
                ElementOpen(ctx, {layout = {size = {Fixed(width), Fixed(cell.y)}}, draw = {kind = .FILL, color = style.background}})
            } else {
                ElementOpen(ctx, {layout = {size = {Fixed(width), Fixed(cell.y)}}})
            }
            TextOpen(ctx, run, {wrap = .NONE, color = style.color})
            ElementClose(ctx)
            for _ in 0 ..< pushed { UiPopTag(ctx) }
            column = stop
        }
        ElementClose(ctx)
    }
    if cursor {
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
