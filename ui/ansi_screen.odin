package ui

import "core:unicode"
import "core:unicode/utf8"
import ud "../unicode_data"
import su "../simd"

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
// Speed: printable ASCII goes into a row in one loop (`screenPutRun`), and the rows are a ring, so scrolling the whole screen copies nothing: 780 MB/s on long lines, 300 on `ls` like
// output, 430 with colors (`odin run ui/tool/ansi_bench -o:speed`; `AnsiScreen.bytewise` is the byte at a time reference the fast path is tested against).
//
// What is read: the printable characters (UTF-8; a wide letter (Chinese, Japanese, Korean, emoji) takes two cells, a combining mark goes on the cell before it: see
// `AnsiRuneWidth`), \r \n \b \t, the cursor moves (A B C D E F G H f d, s u, ESC 7 and
// ESC 8), erasing (J, K, X, P, @), scroll regions (`ESC [ top ; bottom r`: a line feed, a reverse index, inserting and deleting lines and `S` / `T` work inside of the
// region, so a header and a footer stay where they are), inserting and deleting lines (L, M), reverse index (ESC M), reset (ESC c), and the same SGR styles as UiAnsiText. The alternate
// screen (`ESC [ ? 1049 h` and `l`, and the older 47 and 1047) is read when the caller gave room for it: a full screen program (an editor, a pager) draws on a clean
// screen and the screen as it was comes back when it quits; while it is shown the history is not fed and the view cannot be scrolled back. Every other mode (the
// hidden cursor, the mouse) and every other sequence is skipped.
//
// Limits: a fixed grid (no resize: make another screen and write the output again), no origin or wrap modes, no tab stops that are set; a scroll region feeds no history unless it is the whole screen
//     the width and the clusters come from the unicode_data library (Unicode 18), ambiguous widths are 1 unless `ambiguous_wide`, a cell keeps ANSI_EXTRA (2) characters besides its own so a longer emoji sequence loses its tail, a flag or a family is one cell group only when its parts arrive in order, no right-to-left text; marks go on the cell before it and one mark only
//     the history and the second buffer for the alternate screen are the caller's memory, and without the second buffer the alternate screen is skipped; a selection is by cells (a press and a drag), by words (a double click, then a drag goes on by words) or by lines (a triple click); a word is a run of letters and digits, of spaces or of other characters, no mouse or paste modes, no cursor shapes or hiding
//     it only draws: nothing reads the keyboard or talks to a process; a cell is as wide as the code face's M, and a wide letter takes two of them whatever the font does
//
// Selection: a press on the screen and a drag select the cells between the two ends (the ends are included, a wide letter whole), the highlight is a TEXT_SELECTION per row, a drag past the
// top or bottom edge scrolls the view, Copy (the action, with the screen focused) puts the text on the clipboard: the rows with a line feed between them, the empty end of a row left out.
// The ends are named by the number of their row, which stays with the text when the screen scrolls or goes into the history (`AnsiScreenSelect`, `AnsiScreenSelected`,
// `AnsiScreenSelectionOfRow`, `AnsiScreenSelectClear`); the alternate screen lets it go.
//
// Baldr's terminal screen (examples/25_terminal) was the reason to have it; the code is written for this library.

// How many characters a cell keeps besides its own
ANSI_EXTRA :: 2

// One cell: 16 bytes (it was 36). The character and two more (a combining mark, a joiner and the emoji it joins, a skin tone, a flag's second letter: 21 bits each, the size of a
// code point), the colors as three bytes each (a color that is not set has its flag cleared), the attributes and the two flags of a wide letter. A scroll of a region, the history
// and a write all move or store cells, so the size is the speed (ghostty's cell is 8 bytes: its style is a number into a table of the styles in use, here the style is in the cell).
// Make one with `AnsiCellMake`, read the style with `AnsiCellStyle`; the fields that are not the packed ones (`character`, the flags) are read and written as they are.
AnsiCell :: struct {
    using characters: bit_field u64 {
        character: u32 | 21,        // 0: empty
        extra0: u32 | 21,           // what is drawn with the character in this cell, in order (0: none)
        extra1: u32 | 21,
    },
    color: [3]u8,
    ground: [3]u8,
    using attributes: bit_field u16 {
        bold: bool | 1,
        dim: bool | 1,
        italic: bool | 1,
        underline: bool | 1,
        reverse: bool | 1,
        color_set: bool | 1,        // the text has a color of its own (else the style's)
        ground_set: bool | 1,       // there is a ground
        wide: bool | 1,             // the character takes this cell and the next one, which is its continuation
        continuation: bool | 1,     // the second cell of a wide character (it has no character of its own)
    },
}

#assert(size_of(AnsiCell) == 16 && align_of(AnsiCell) == 8)       // screenPutRun writes a cell as two words

ANSI_CELL_STYLE_BITS :: u16(0x7f)       // the attribute bits that are the style: the wide flags are not

// A cell with a character and a style
AnsiCellMake :: proc "contextless" (character: rune, style: AnsiState) -> (cell: AnsiCell) {
    cell.character = u32(character)
    AnsiCellSetStyle(&cell, style)
    return
}

// The style of a cell as the state the ui draws (colors with the alpha of a color that is set)
AnsiCellStyle :: proc "contextless" (cell: ^AnsiCell) -> AnsiState {
    state: AnsiState = {bold = cell.bold, dim = cell.dim, italic = cell.italic, underline = cell.underline, reverse = cell.reverse}
    if cell.color_set { state.color = {cell.color[0], cell.color[1], cell.color[2], 255} }
    if cell.ground_set { state.background = {cell.ground[0], cell.ground[1], cell.ground[2], 255} }
    return state
}

AnsiCellSetStyle :: proc "contextless" (cell: ^AnsiCell, style: AnsiState) {
    cell.color = {style.color.r, style.color.g, style.color.b}
    cell.ground = {style.background.r, style.background.g, style.background.b}
    cell.bold, cell.dim, cell.italic, cell.underline, cell.reverse = style.bold, style.dim, style.italic, style.underline, style.reverse
    cell.color_set, cell.ground_set = style.color.a > 0, style.background.a > 0
}

// Two cells in the same style (the wide flags do not count)
AnsiCellSameStyle :: proc "contextless" (a: ^AnsiCell, b: ^AnsiCell) -> bool {
    return a.color == b.color && a.ground == b.ground && transmute(u16)a.attributes & ANSI_CELL_STYLE_BITS == transmute(u16)b.attributes & ANSI_CELL_STYLE_BITS
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
    decoder: su.Utf8Decoder,    // a UTF-8 letter that is not whole yet (a write may end in the middle of one)
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
    margin_top: int,            // the scroll region: the first and the last row of it (the whole screen unless a program sets it)
    margin_bottom: int,
    grapheme: ud.GraphemeState, // what the cluster rules remember of the text just written (the cursor moving or a control character starts it afresh)
    top: int,                   // the row of `cells` that is row 0 of the screen: the rows are a ring, so a scroll of the whole screen moves this number and clears a row, it does not copy
    alternate_top: int,         // the same for the buffer that is not shown
    bytewise: bool,             // every byte goes through the state machine, even printable ASCII runs (the reference the fast path is tested against; a program has no reason to set it)
    ambiguous_wide: bool,       // characters of ambiguous width (box drawing, Greek, Cyrillic, arrows ...) take two cells, as in a terminal of an East Asian locale
    pushed: int,                // the lines the whole screen scrolled up (down: fewer): `pushed + row` is the number of a live row that stays with its text, see AnsiScreenSelect
    select_active: bool,        // a selection of cells exists
    select_dragging: bool,      // the pointer holds it
    select_from_row: int,       // where it began: the number of the row (history rows are negative) and the column
    select_from_column: int,
    select_to_row: int,         // and where it ends now (either may come first)
    select_to_column: int,
    press_time: f64,            // the last press on the screen: a second one soon after at the same cell selects a word, a third one a line
    press_row: int,
    press_column: int,
    presses: int,
    unit: int,                  // 0 cells, 1 words, 2 lines: what a drag after a double or triple click goes by
    unit_row: int,              // the word or line that was pressed (the number of its row, its first and last column)
    unit_first: int,
    unit_last: int,
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
    screen.top, screen.alternate_top = 0, 0
    screen.column, screen.row = 0, 0
    screen.style, screen.saved_style = {}, {}
    screen.saved_column, screen.saved_row = 0, 0
    screen.sequence_length, screen.decoder = 0, {}
    screen.history_count, screen.history_head, screen.back = 0, 0, 0
    screen.alternate_active = false
    screen.pushed, screen.select_active, screen.select_dragging, screen.grapheme = 0, false, false, {}
    for &cell in screen.alternate { cell = {} }
    screen.margin_top, screen.margin_bottom = 0, screen.rows - 1
}

// The cells of a row of the screen: the row is a ring (`top`), each row is contiguous
@(private)
screenRowCells :: proc "contextless" (screen: ^AnsiScreen, row: int) -> []AnsiCell {
    physical: int = screen.top + row
    if physical >= screen.rows { physical -= screen.rows }
    return screen.cells[physical * screen.columns:(physical + 1) * screen.columns]
}

@(private)
screenCell :: proc "contextless" (screen: ^AnsiScreen, column: int, row: int) -> ^AnsiCell {
    physical: int = screen.top + row
    if physical >= screen.rows { physical -= screen.rows }
    return &screen.cells[physical * screen.columns + column]
}

// An empty cell keeps the ground of the style that erased it (a cleared line in a colored ground stays colored)
@(private)
screenBlank :: proc "contextless" (screen: ^AnsiScreen) -> AnsiCell {
    return AnsiCellMake(0, {background = screen.style.background})
}

@(private)
screenClearRange :: proc "contextless" (screen: ^AnsiScreen, from_row: int, from_column: int, to_row: int, to_column: int) {
    // [from, to) as cell numbers of the screen (row by row): a row at a time, the rows are where the ring has them
    columns: int = screen.columns
    from: int = clamp(from_row * columns + from_column, 0, screen.rows * columns)
    to: int = clamp(to_row * columns + to_column, 0, screen.rows * columns)
    blank: AnsiCell = screenBlank(screen)
    for from < to {
        row: int = from / columns
        first: int = from - row * columns
        last: int = min(to - row * columns, columns)
        cells: []AnsiCell = screenRowCells(screen, row)
        screenFillCells(cells[first:last], blank)
        from = (row + 1) * columns
    }
}

// The lines `top` to `bottom` (inclusive) move up (`count` > 0) or down (`count` < 0); the lines that come in are empty. The whole screen is a turn of the ring (the first row
// moves, one row is cleared: ghostty never copies the rows of a full scroll either); a region copies the rows that move.
@(private)
screenScroll :: proc "contextless" (screen: ^AnsiScreen, top: int, bottom: int, count: int) {
    height: int = bottom - top + 1
    shift: int = min(abs(count), height)
    if shift <= 0 { return }
    blank: AnsiCell = screenBlank(screen)
    if top == 0 && bottom == screen.rows - 1 {
        screen.pushed += shift if count > 0 else -shift
        if count > 0 {
            screen.top = (screen.top + shift) % screen.rows
            for i in screen.rows - shift ..< screen.rows { screenFillCells(screenRowCells(screen, i), blank) }
        } else {
            screen.top = (screen.top - shift + screen.rows) % screen.rows
            for i in 0 ..< shift { screenFillCells(screenRowCells(screen, i), blank) }
        }
        return
    }
    if count > 0 {
        for row in top ..< bottom + 1 - shift { copy(screenRowCells(screen, row), screenRowCells(screen, row + shift)) }
        for row in bottom + 1 - shift ..< bottom + 1 { screenFillCells(screenRowCells(screen, row), blank) }
    } else {
        for row := bottom; row >= top + shift; row -= 1 { copy(screenRowCells(screen, row), screenRowCells(screen, row - shift)) }
        for row in top ..< top + shift { screenFillCells(screenRowCells(screen, row), blank) }
    }
}

// The lines that scroll off the top are kept (the oldest of a full history is lost); a view that is scrolled back stays on what it shows. Only a scroll region that is
// the whole screen feeds it.
@(private)
screenHistoryPush :: proc "contextless" (screen: ^AnsiScreen) {
    if screen.history_rows == 0 || screen.alternate_active { return }
    columns: int = screen.columns
    copy(screen.history[screen.history_head * columns:(screen.history_head + 1) * columns], screenRowCells(screen, 0))
    screen.history_head = (screen.history_head + 1) % screen.history_rows
    screen.history_count = min(screen.history_count + 1, screen.history_rows)
    if screen.back > 0 { screen.back = min(screen.back + 1, screen.history_count) }
}

@(private)
screenLineFeed :: proc "contextless" (screen: ^AnsiScreen) {
    if screen.row == screen.margin_bottom {
        if screen.margin_top == 0 && screen.margin_bottom == screen.rows - 1 { screenHistoryPush(screen) }
        screenScroll(screen, screen.margin_top, screen.margin_bottom, 1)
    } else if screen.row < screen.rows - 1 {
        screen.row += 1
    }
}

// How many cells a character takes on the screen: 0 for what goes with the character before it (a combining mark, a joiner, a variation selector, a control character), 2 for a wide
// one (Hangul, Chinese and Japanese characters, fullwidth forms, emoji, a regional indicator), else 1; characters of ambiguous width (box drawing, Greek, Cyrillic, arrows ...) are 2 when
// `ambiguous_wide` is true. From the Unicode data (the `unicode_data` library: the tables are generated from the files of the Unicode Character Database).
AnsiRuneWidth :: proc "contextless" (character: rune, ambiguous_wide: bool = false) -> int {
    width: int = ud.RuneWidth(character)
    if width == 1 && ambiguous_wide && ud.RuneAmbiguous(character) { return 2 }
    return width
}

// An empty cell with the ground that the cell had
@(private)
ansiCellCleared :: proc "contextless" (cell: ^AnsiCell) -> (result: AnsiCell) {
    result.ground, result.ground_set = cell.ground, cell.ground_set
    return
}

// A cell that is the half of a wide character, or has one, loses its other half when it is written over or cut
@(private)
screenBreakPair :: proc "contextless" (screen: ^AnsiScreen, column: int, row: int) {
    cell: ^AnsiCell = screenCell(screen, column, row)
    if cell.continuation && column > 0 {
        previous: ^AnsiCell = screenCell(screen, column - 1, row)
        if previous.wide { previous^ = ansiCellCleared(previous) }
    }
    if cell.wide && column + 1 < screen.columns {
        next: ^AnsiCell = screenCell(screen, column + 1, row)
        if next.continuation { next^ = ansiCellCleared(next) }
    }
}

// A wide character without its other half is an empty cell (the ground stays): the repair of one cell
@(private)
screenFixCell :: proc "contextless" (screen: ^AnsiScreen, column: int, row: int) {
    if column < 0 || column >= screen.columns { return }
    cell: ^AnsiCell = screenCell(screen, column, row)
    if cell.continuation && (column == 0 || !screenCell(screen, column - 1, row).wide) { cell^ = ansiCellCleared(cell) }
    if cell.wide && (column == screen.columns - 1 || !screenCell(screen, column + 1, row).continuation) { cell^ = ansiCellCleared(cell) }
}

// A row after something cut it (erasing, deleting, inserting): a wide character without its other half is an empty cell
@(private)
screenFixRow :: proc "contextless" (screen: ^AnsiScreen, row: int) {
    for column in 0 ..< screen.columns { screenFixCell(screen, column, row) }
}

// After the cells [first, last) of a row were cleared: only the two cells next to the cleared part can have lost a half
@(private)
screenFixEdges :: proc "contextless" (screen: ^AnsiScreen, row: int, first: int, last: int) {
    screenFixCell(screen, first - 1, row)
    screenFixCell(screen, last, row)
}

// The cell that the next character would join: the one before the cursor (the letter of a wide one)
@(private)
screenBefore :: proc "contextless" (screen: ^AnsiScreen) -> ^AnsiCell {
    column: int = min(screen.column, screen.columns) - 1
    if column < 0 { return nil }
    cell: ^AnsiCell = screenCell(screen, column, screen.row)
    if cell.continuation && column > 0 { cell = screenCell(screen, column - 1, screen.row) }
    if cell.character == 0 { return nil }
    return cell
}

@(private)
cellAddExtra :: proc "contextless" (cell: ^AnsiCell, character: rune) {
    if cell.extra0 == 0 {
        cell.extra0 = u32(character)
    } else if cell.extra1 == 0 {
        cell.extra1 = u32(character)
    }
}

@(private)
screenPut :: proc "contextless" (screen: ^AnsiScreen, character: rune) {
    // the cluster rules of Unicode (UAX 29) say whether this character goes with the one before it: a mark, a joiner and the emoji it joins (a family, a person with a profession), the
    // second letter of a flag, the vowels of a Hangul syllable, an Indic conjunct. What goes with a cell is kept in the cell (two characters), the rest of a long sequence is dropped.
    boundary: bool = ud.GraphemeBreak(&screen.grapheme, character)
    before: ^AnsiCell = screenBefore(screen)
    if !boundary && before != nil {
        // the variation selector 16 asks for the picture of an emoji: a narrow one takes the next cell
        if character == 0xFE0F && !before.wide && ud.RuneEmojiText(rune(before.character)) && before.extra0 == 0 && screen.column < screen.columns {
            before.wide = true
            screenBreakPair(screen, screen.column, screen.row)
            continuation: AnsiCell = AnsiCellMake(0, AnsiCellStyle(before))
            continuation.continuation = true
            screenCell(screen, screen.column, screen.row)^ = continuation
            screen.column += 1
        }
        cellAddExtra(before, character)
        return
    }
    width: int = AnsiRuneWidth(character, screen.ambiguous_wide)
    if width == 0 { return }                                // a mark with nothing to join, a control character: nothing is drawn
    if screen.column + width > screen.columns {
        // the cursor stood after the last cell, or a wide letter does not fit in the one that is left (it stays empty): the letter starts the next line
        screen.column = 0
        screenLineFeed(screen)
    }
    for offset in 0 ..< width { screenBreakPair(screen, screen.column + offset, screen.row) }
    put: AnsiCell = AnsiCellMake(character, screen.style)
    put.wide = width == 2
    screenCell(screen, screen.column, screen.row)^ = put
    if width == 2 {
        second: AnsiCell = AnsiCellMake(0, screen.style)
        second.continuation = true
        screenCell(screen, screen.column + 1, screen.row)^ = second
    }
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
        screen.top, screen.alternate_top = screen.alternate_top, screen.top
    }
    screen.select_active, screen.select_dragging = false, false          // the cells it was on are another screen now
    if enter {
        if mode == 1049 { screen.alternate_column, screen.alternate_row, screen.alternate_style = screen.column, screen.row, screen.style }
        swap(screen)
        if mode == 1049 { for &cell in screen.cells { cell = {} } }
        screen.alternate_active = true
        screen.back = 0
        screen.margin_top, screen.margin_bottom = 0, screen.rows - 1
    } else {
        if mode == 1047 || mode == 1049 { for &cell in screen.cells { cell = {} } }
        swap(screen)
        screen.alternate_active = false
        screen.margin_top, screen.margin_bottom = 0, screen.rows - 1
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
    numbers: [16]int = ---                          // not zeroed: a number is cleared when it starts
    numbers[0] = 0
    count: int
    any_digit: bool
    private: bool
    for character in text[1:len(text) - 1] {
        switch {
        case character >= '0' && character <= '9':
            if count < len(numbers) { numbers[count] = min(numbers[count] * 10 + int(character - '0'), 100000) }
            any_digit = true
        case character == ';' || character == ':':
            if count < len(numbers) {
                count += 1
                if count < len(numbers) { numbers[count] = 0 }
            }
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
        // the cells of the row of the cursor next to the cleared part (the other rows were cleared whole)
        switch mode {
        case 0: screenFixEdges(screen, screen.row, column, columns)
        case 1: screenFixEdges(screen, screen.row, 0, min(column + 1, columns))
        }
    case 'K':
        mode: int = parameters[0] if len(parameters) > 0 else 0
        column: int = min(screen.column, columns)
        switch mode {
        case 0: screenClearRange(screen, screen.row, column, screen.row, columns)
        case 1: screenClearRange(screen, screen.row, 0, screen.row, min(column + 1, columns))
        case 2: screenClearRange(screen, screen.row, 0, screen.row, columns)
        }
        switch mode {
        case 0: screenFixEdges(screen, screen.row, column, columns)
        case 1: screenFixEdges(screen, screen.row, 0, min(column + 1, columns))
        }
    case 'X':
        column: int = min(screen.column, columns)
        last: int = min(column + screenParameter(parameters, 0, 1), columns)
        screenClearRange(screen, screen.row, column, screen.row, last)
        screenFixEdges(screen, screen.row, column, last)
    case 'P':
        // delete letters: the rest of the row moves left
        column: int = min(screen.column, columns)
        amount: int = min(screenParameter(parameters, 0, 1), columns - column)
        row: []AnsiCell = screenRowCells(screen, screen.row)
        copy(row[column:columns - amount], row[column + amount:columns])
        blank: AnsiCell = screenBlank(screen)
        for i in columns - amount ..< columns { row[i] = blank }
        screenFixRow(screen, screen.row)
    case '@':
        // insert blanks: the rest of the row moves right
        column: int = min(screen.column, columns)
        amount: int = min(screenParameter(parameters, 0, 1), columns - column)
        row: []AnsiCell = screenRowCells(screen, screen.row)
        copy(row[column + amount:columns], row[column:columns - amount])
        blank: AnsiCell = screenBlank(screen)
        for i in column ..< column + amount { row[i] = blank }
        screenFixRow(screen, screen.row)
    case 'L':
        // insert lines at the cursor: the lines below it down to the bottom of the region move down; outside of the region nothing happens
        if screen.row >= screen.margin_top && screen.row <= screen.margin_bottom { screenScroll(screen, screen.row, screen.margin_bottom, -screenParameter(parameters, 0, 1)) }
    case 'M':
        if screen.row >= screen.margin_top && screen.row <= screen.margin_bottom { screenScroll(screen, screen.row, screen.margin_bottom, screenParameter(parameters, 0, 1)) }
    case 'S': screenScroll(screen, screen.margin_top, screen.margin_bottom, screenParameter(parameters, 0, 1))
    case 'T': screenScroll(screen, screen.margin_top, screen.margin_bottom, -screenParameter(parameters, 0, 1))
    case 'r':
        // the scroll region (1 based, a missing number is the first and the last row); one that is not two rows at least is not taken. The cursor goes home.
        top: int = screenParameter(parameters, 0, 1) - 1
        bottom: int = screenParameter(parameters, 1, rows) - 1
        if top >= 0 && bottom < rows && top < bottom {
            screen.margin_top, screen.margin_bottom = top, bottom
            screen.row, screen.column = 0, 0
        }
    }
}

// One byte through the state machine: an escape sequence, a letter of several bytes, a control character or a printable ASCII character. The slow path, and the reference that the
// fast path of AnsiScreenWrite is tested against.
@(private)
screenByte :: proc(screen: ^AnsiScreen, byte: u8) {
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
                if screen.row == screen.margin_top { screenScroll(screen, screen.margin_top, screen.margin_bottom, -1) } else if screen.row > 0 { screen.row -= 1 }
                screen.sequence_length = 0
            case 'c':
                AnsiScreenClear(screen)
            case:
                screen.sequence_length = 0                              // another escape: skipped with its letter
            }
            return
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
        return
    }
    // inside of a letter of several bytes: the decoder of the simd library keeps the bytes and the rule (a bad part is one replacement character)
    if su.Utf8DecoderPending(&screen.decoder) {
        character, status := su.Utf8DecoderPush(&screen.decoder, byte)
        switch status {
        case .MORE: return
        case .CHARACTER:
            screenPut(screen, character)
            return
        case .CUT: screenPut(screen, utf8.RUNE_ERROR)                         // the byte cannot go on with it: one replacement for the part, and the byte starts over
        case .ASCII, .ERROR:
        }
    }
    if byte < 0x20 || byte == 0x7f { screen.grapheme = {} }          // the cursor moves or a sequence starts: the text before is not a cluster to join
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
    case:
        // a lead byte starts a letter; a byte that starts nothing (a lone continuation byte, C0, C1, F5 and above) is one replacement character
        character, status := su.Utf8DecoderPush(&screen.decoder, byte)
        if status == .ERROR { screenPut(screen, character) }
    }
}

// Writes bytes to the screen. The bytes may be cut anywhere: what is not whole yet waits for the next call.
AnsiScreenWrite :: proc(screen: ^AnsiScreen, bytes: []u8) {
    i: int
    for i < len(bytes) {
        byte: u8 = bytes[i]
        // in the ground state (no escape sequence and no letter of several bytes under way) a run of printable ASCII needs no state machine: it goes into the cells of a row in one loop.
        // Text is mostly this (ghostty finds the run with a vector scan and fills a row at a time: batching is most of its speed)
        if byte >= 0x20 && byte < 0x7f && screen.sequence_length == 0 && !su.Utf8DecoderPending(&screen.decoder) && !screen.bytewise && screen.grapheme.previous != .PREPEND {
            end: int = i + su.AsciiRun(bytes[i:])
            screenPutRun(screen, bytes[i:end])
            i = end
            continue
        }
        // a letter of several bytes that is whole in this slice is decoded at once; a bad sequence is one replacement character for its maximal subpart (Unicode table 3-7); a sequence that
        // reaches the end of the slice goes through the byte machine, which keeps it for the next write when it is valid so far (and replaces it at once when it is not)
        if byte >= 0x80 && screen.sequence_length == 0 && !su.Utf8DecoderPending(&screen.decoder) && !screen.bytewise {
            character, size, valid := su.Utf8Decode(bytes, i)
            if valid {
                screenPut(screen, character)
                i += size
                continue
            }
            if i + size < len(bytes) {
                screenPut(screen, utf8.RUNE_ERROR)
                i += size
                continue
            }
        }
        screenByte(screen, byte)
        i += 1
    }
}

// Every cell of `cells` set to `value`, written as two words each
@(private)
screenFillCells :: proc "contextless" (cells: []AnsiCell, value: AnsiCell) {
    words: [2]u64 = transmute([2]u64)value
    for &cell in cells {
        target: ^[2]u64 = cast(^[2]u64)&cell
        target[0], target[1] = words[0], words[1]
    }
}

// A run of printable ASCII (0x20 to 0x7e) written at the cursor: the same cells as one `screenPut` per character, without the join test, the width and the wrap test per
// character. The cursor after the last cell of a row waits (the next character wraps first), as it does for a single character.
@(private)
screenPutRun :: proc "contextless" (screen: ^AnsiScreen, run: []u8) {
    columns: int = screen.columns
    prototype: AnsiCell = AnsiCellMake(0, screen.style)          // the style packed once for the whole run
    prototype_words: [2]u64 = transmute([2]u64)prototype
    i: int
    for i < len(run) {
        if screen.column >= columns {
            screen.column = 0
            screenLineFeed(screen)
        }
        count: int = min(len(run) - i, columns - screen.column)
        row_cells: []AnsiCell = screenRowCells(screen, screen.row)
        at: int = screen.column
        for k in 0 ..< count {
            cell: ^AnsiCell = &row_cells[at + k]
            // half of a wide letter that this character lands on: the other half becomes empty (screenBreakPair does it for a single character)
            if cell.wide || cell.continuation { screenBreakPair(screen, at + k, screen.row) }
            // two whole words, no read after the write (setting the character of a cell that was just stored waits for the store)
            words: ^[2]u64 = cast(^[2]u64)cell
            words[0] = u64(run[i + k])
            words[1] = prototype_words[1]
        }
        screen.column += count
        i += count
    }
    screen.grapheme = {previous = .OTHER, started = true}      // printable ASCII: every character is a cluster of its own
}

// A cell as UTF-8 at `out[count^:]`: its character (`character`: a space for an empty cell) and what goes with it. False when it does not fit (nothing of it is written).
@(private)
cellEncode :: proc(cell: ^AnsiCell, character: rune, out: []u8, count: ^int) -> bool {
    needed: int = utf8.rune_size(character)
    if cell.extra0 != 0 { needed += utf8.rune_size(rune(cell.extra0)) }
    if cell.extra1 != 0 { needed += utf8.rune_size(rune(cell.extra1)) }
    if count^ + needed > len(out) { return false }
    encoded, width := utf8.encode_rune(character)
    copy(out[count^:], encoded[:width])
    count^ += width
    for extra in ([ANSI_EXTRA]u32{cell.extra0, cell.extra1}) {
        if extra == 0 { break }
        encoded, width = utf8.encode_rune(rune(extra))
        copy(out[count^:], encoded[:width])
        count^ += width
    }
    return true
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
        character: rune = rune(cell.character)
        if character == 0 { character = ' ' }
        if !cellEncode(&cell, character, out, &count) { break }
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

// ---- selection of cells ---------------------------------------------------------------------------------------------------------------------------------
// A selection is two cells, named by the number of their row, which does not change when the screen scrolls (the live rows are `pushed + row`, the history rows are
// before them: a text that scrolls up into the history keeps its selection), and their columns. The pointer makes one in UiAnsiScreen (press and drag, the wheel
// and a drag past the edge scroll the view); a program makes one with `AnsiScreenSelect`.

// The number of a row of the view
@(private)
screenRowId :: proc "contextless" (screen: ^AnsiScreen, view_row: int) -> int {
    return screen.pushed - screen.back + view_row
}

// The cell of a row number, nil when that row is gone (scrolled out of the history) or not there
@(private)
screenIdCell :: proc "contextless" (screen: ^AnsiScreen, row_id: int, column: int) -> ^AnsiCell {
    if column < 0 || column >= screen.columns { return nil }
    live: int = row_id - screen.pushed
    if live >= 0 {
        if live >= screen.rows { return nil }
        return screenCell(screen, column, live)
    }
    behind: int = -live                                  // rows above the live screen
    if behind > screen.history_count || screen.alternate_active { return nil }
    ring: int = (screen.history_head + screen.history_rows - behind) % screen.history_rows
    return &screen.history[ring * screen.columns + column]
}

// The two ends in reading order, the first column on a continuation moved to its letter and the last one to the end of its wide letter
@(private)
screenSelectionOrdered :: proc(screen: ^AnsiScreen) -> (from_row: int, from_column: int, to_row: int, to_column: int) {
    from_row, from_column, to_row, to_column = screen.select_from_row, screen.select_from_column, screen.select_to_row, screen.select_to_column
    if from_row > to_row || (from_row == to_row && from_column > to_column) {
        from_row, from_column, to_row, to_column = to_row, to_column, from_row, from_column
    }
    if cell: ^AnsiCell = screenIdCell(screen, from_row, from_column); cell != nil && cell.continuation && from_column > 0 { from_column -= 1 }
    if cell: ^AnsiCell = screenIdCell(screen, to_row, to_column); cell != nil && cell.wide && to_column < screen.columns - 1 { to_column += 1 }
    return
}

// Selects the cells from one place of the view to another (the ends are included); the cells are named by column and row of the view.
AnsiScreenSelect :: proc(screen: ^AnsiScreen, from_column: int, from_row: int, to_column: int, to_row: int) {
    screen.select_from_row, screen.select_from_column = screenRowId(screen, clamp(from_row, 0, screen.rows - 1)), clamp(from_column, 0, screen.columns - 1)
    screen.select_to_row, screen.select_to_column = screenRowId(screen, clamp(to_row, 0, screen.rows - 1)), clamp(to_column, 0, screen.columns - 1)
    screen.select_active = true
}

AnsiScreenSelectClear :: proc(screen: ^AnsiScreen) {
    screen.select_active, screen.select_dragging = false, false
}

// The columns of a row of the view that are selected: [first, last], or last < first when none are
AnsiScreenSelectionOfRow :: proc(screen: ^AnsiScreen, view_row: int) -> (first: int, last: int) {
    if !screen.select_active { return 0, -1 }
    from_row, from_column, to_row, to_column := screenSelectionOrdered(screen)
    id: int = screenRowId(screen, view_row)
    if id < from_row || id > to_row { return 0, -1 }
    first = from_column if id == from_row else 0
    last = to_column if id == to_row else screen.columns - 1
    return
}

// The selected text into `out`: the rows one after the other with a line feed between them, the empty cells at the end of a row left out, the second half of a wide
// letter skipped. A row that is gone from the history is skipped. Empty when nothing is selected.
AnsiScreenSelected :: proc(screen: ^AnsiScreen, out: []u8) -> string {
    if !screen.select_active { return "" }
    from_row, from_column, to_row, to_column := screenSelectionOrdered(screen)
    count: int
    for id in from_row ..= to_row {
        first: int = from_column if id == from_row else 0
        last: int = to_column if id == to_row else screen.columns - 1
        end: int = -1
        for column in first ..= last {
            cell: ^AnsiCell = screenIdCell(screen, id, column)
            if cell != nil && cell.character != 0 { end = column }
        }
        if id > from_row && count < len(out) {
            out[count] = '\n'
            count += 1
        }
        for column in first ..= end {
            cell: ^AnsiCell = screenIdCell(screen, id, column)
            if cell == nil || cell.continuation { continue }
            character: rune = rune(cell.character) if cell.character != 0 else ' '
            if !cellEncode(cell, character, out, &count) { return string(out[:count]) }
        }
    }
    return string(out[:count])
}

// The first and last column of the word (unit 1) or of the line (unit 2) at a place of the view. A word is a run of letters and digits (and the underscore), a run of spaces, or a run of
// other characters; the second half of a wide letter belongs to its first half.
@(private)
screenUnitBounds :: proc(screen: ^AnsiScreen, view_row: int, column: int, unit: int) -> (first: int, last: int) {
    if unit == 2 { return 0, screen.columns - 1 }
    classOf :: proc(screen: ^AnsiScreen, view_row: int, column: int) -> int {
        cell: ^AnsiCell = AnsiScreenViewCell(screen, column, view_row)
        if cell.continuation && column > 0 { return classOf(screen, view_row, column - 1) }
        character: rune = rune(cell.character)
        switch {
        case character == 0 || character == ' ': return 0
        case unicode.is_letter(character) || unicode.is_digit(character) || character == '_': return 1
        }
        return 2
    }
    wanted: int = classOf(screen, view_row, column)
    first, last = column, column
    for first > 0 && classOf(screen, view_row, first - 1) == wanted { first -= 1 }
    for last < screen.columns - 1 && classOf(screen, view_row, last + 1) == wanted { last += 1 }
    return
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
    // the pointer selects cells: a press starts it, a drag extends it (past the edge it scrolls the view), Copy takes the text
    interaction: Interaction = widgetBehavior(ctx, id)
    area: Rect = interaction.rect                  // where it was at the end of the last frame (0 the first time)
    if area.z > 0 {
        point: Vec2 = ctx.input.mouse_position
        column: int = clamp(int((point.x - area.x) / cell.x), 0, screen.columns - 1)
        view_row: int = clamp(int((point.y - area.y) / cell.y), 0, screen.rows - 1)
        if interaction.pressed && ctx.input.mouse_pressed {
            AnsiScreenSelectClear(screen)
            screen.select_dragging = true
            row_id: int = screenRowId(screen, view_row)
            again: bool = ctx.time - screen.press_time <= ctx.settings.double_click_seconds && screen.press_row == row_id && screen.press_column == column
            screen.presses = screen.presses + 1 if again else 1
            if screen.presses > max(ctx.settings.multi_click_limit, 1) { screen.presses = 1 }
            screen.press_time, screen.press_row, screen.press_column = ctx.time, row_id, column
            screen.select_from_row, screen.select_from_column = row_id, column
            screen.select_to_row, screen.select_to_column = row_id, column
            screen.unit = 0 if screen.presses < 2 else (1 if screen.presses == 2 else 2)
            if screen.unit != 0 {
                first, last := screenUnitBounds(screen, view_row, column, screen.unit)
                screen.unit_row, screen.unit_first, screen.unit_last = row_id, first, last
                screen.select_from_column, screen.select_to_column = first, last
                screen.select_active = true
            }
        } else if screen.select_dragging && ctx.active == id && ctx.input.mouse_down {
            if point.y < area.y { AnsiScreenScroll(screen, 1) }
            if point.y > area.y + area.w { AnsiScreenScroll(screen, -1) }
            view_row = clamp(int((point.y - area.y) / cell.y), 0, screen.rows - 1)
            if screen.unit != 0 {
                // by words or lines: the pressed unit stays whole and the one under the pointer is added to it, in whichever direction
                row_id: int = screenRowId(screen, view_row)
                first, last := screenUnitBounds(screen, view_row, column, screen.unit)
                if row_id < screen.unit_row || (row_id == screen.unit_row && first < screen.unit_first) {
                    screen.select_from_row, screen.select_from_column = screen.unit_row, screen.unit_last
                    screen.select_to_row, screen.select_to_column = row_id, first
                } else {
                    screen.select_from_row, screen.select_from_column = screen.unit_row, screen.unit_first
                    screen.select_to_row, screen.select_to_column = row_id, last
                }
                screen.select_active = true
            } else {
                screen.select_to_row, screen.select_to_column = screenRowId(screen, view_row), column
                screen.select_active = screen.select_to_row != screen.select_from_row || screen.select_to_column != screen.select_from_column
            }
        } else if screen.select_dragging {
            screen.select_dragging = false
        }
    }
    if screen.select_active && ctx.focus == id && .COPY in ctx.input.actions {
        free_space: []u8 = ctx.text_buffer[ctx.text_used:]
        UiClipboardSet(ctx, AnsiScreenSelected(screen, free_space))
    }
    ElementOpen(ctx, {id = id, layout = {size = {Fixed(cell.x * f32(screen.columns)), Fixed(cell.y * f32(screen.rows))}, direction = .TOP_TO_BOTTOM}, hit = {.SCROLL, .INTERACTIVE, .NO_FOCUS}})
    for row in 0 ..< screen.rows {
        ElementOpen(ctx, {layout = {size = {Grow(), Fixed(cell.y)}, direction = .LEFT_TO_RIGHT}})
        // the end of the row: after the last cell that has anything, the empty cells with no ground are not declared
        end: int = screen.columns
        for end > 0 {
            last: ^AnsiCell = AnsiScreenViewCell(screen, end - 1, row)
            if last.character != 0 || last.continuation || last.ground_set { break }
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
                    if !AnsiCellSameStyle(&next, &first) || next.wide { break }
                    stop += 1
                }
            }
            // the cells as one text; empty ones are spaces, the second half of a wide letter has no text, a mark follows its letter
            start: int = ctx.text_used
            for at in column ..< stop {
                cell: AnsiCell = AnsiScreenViewCell(screen, at, row)^
                if cell.continuation && at > column { continue }
                character: rune = rune(cell.character)
                if character == 0 { character = ' ' }
                if !cellEncode(&cell, character, ctx.text_buffer[:], &ctx.text_used) {
                    ctx.problems += {.TEXT_FULL}
                    break
                }
            }
            run: string = string(ctx.text_buffer[start:ctx.text_used])
            style: AnsiState = AnsiCellStyle(&first)
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
    if screen.select_active {
        for view_row in 0 ..< screen.rows {
            first, last := AnsiScreenSelectionOfRow(screen, view_row)
            if last < first { continue }
            ElementOpen(ctx, {
                layout = {size = {Fixed(cell.x * f32(last - first + 1)), Fixed(cell.y)}},
                absolute = {enabled = true, offset = {cell.x * f32(first), cell.y * f32(view_row)}},
                draw = {kind = .TEXT_SELECTION},
            })
            ElementClose(ctx)
        }
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
