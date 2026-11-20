#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(private = "file")
row :: proc(screen: ^AnsiScreen, index: int) -> string {
    @(thread_local) buffer: [256]u8
    return AnsiScreenRow(screen, index, buffer[:])
}

@(private = "file")
write :: proc(screen: ^AnsiScreen, text: string) {
    AnsiScreenWrite(screen, transmute([]u8)text)
}

@(test)
test_letters_lines_and_the_end_of_the_screen :: proc(t: ^testing.T) {
    cells: [10 * 4]AnsiCell
    screen: AnsiScreen = AnsiScreenMake(cells[:], 10, 4)
    write(&screen, "hello\r\nworld")
    testing.expect_value(t, row(&screen, 0), "hello")
    testing.expect_value(t, row(&screen, 1), "world")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{5, 1})
    // a line feed alone keeps the column
    write(&screen, "\n!")
    testing.expect_value(t, row(&screen, 2), "     !")
    // a letter after the last cell wraps; the cursor after the last cell waits
    write(&screen, "\r\n0123456789")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{10, 3})
    write(&screen, "X")
    // that was the last row: everything scrolled up, the X is on the new last row
    testing.expect_value(t, row(&screen, 2), "0123456789")
    testing.expect_value(t, row(&screen, 3), "X")
    testing.expect_value(t, row(&screen, 0), "world")
    // backspace and tab
    write(&screen, "\bY\t")
    testing.expect_value(t, row(&screen, 3), "Y")
    testing.expect_value(t, screen.column, 8)
    write(&screen, "\t\t")
    testing.expect_value(t, screen.column, 9)
    // UTF-8 is a cell a letter, also when it comes in pieces
    AnsiScreenClear(&screen)
    bytes: []u8 = transmute([]u8)string("aé€\U0001F600b")
    for byte in bytes { AnsiScreenWrite(&screen, {byte}) }
    testing.expect_value(t, row(&screen, 0), "aé€\U0001F600b")
    testing.expect_value(t, screen.column, 5)
    // a cut letter that is not finished: the next byte starts over
    write(&screen, "\xe2\x82x")
    testing.expect_value(t, row(&screen, 0), "aé€\U0001F600bx")
}

@(test)
test_the_cursor_moves_and_erases :: proc(t: ^testing.T) {
    cells: [10 * 5]AnsiCell
    screen: AnsiScreen = AnsiScreenMake(cells[:], 10, 5)
    write(&screen, "\x1b[3;4Habc")
    testing.expect_value(t, row(&screen, 2), "   abc")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{6, 2})
    // relative moves stay inside of the screen
    write(&screen, "\x1b[2A\x1b[3D")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{3, 0})
    write(&screen, "\x1b[99B\x1b[99C")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{9, 4})
    write(&screen, "\x1b[A\x1b[1;1H")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{0, 0})
    write(&screen, "\x1b[2E\x1b[F")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{0, 1})
    write(&screen, "\x1b[5G\x1b[4d")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{4, 3})
    // save and restore, both ways
    write(&screen, "\x1b[s\x1b[1;1H\x1b[u")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{4, 3})
    write(&screen, "\x1b7\x1b[1;1H\x1b8")
    testing.expect_value(t, [2]int{screen.column, screen.row}, [2]int{4, 3})
    // erase the line: to the end, to the start (with the cursor's cell), all
    AnsiScreenClear(&screen)
    write(&screen, "0123456789\x1b[1;5H\x1b[K")
    testing.expect_value(t, row(&screen, 0), "0123")
    write(&screen, "\x1b[1;1H0123456789\x1b[1;5H\x1b[1K")
    testing.expect_value(t, row(&screen, 0), "     56789")
    write(&screen, "\x1b[2K")
    testing.expect_value(t, row(&screen, 0), "")
    // erase the screen: below the cursor, above it, all
    AnsiScreenClear(&screen)
    for line in 0 ..< 5 { write(&screen, "\x1b[1;1H"); screen.row = line; screen.column = 0; write(&screen, "abcde") }
    write(&screen, "\x1b[3;3H\x1b[J")
    testing.expect_value(t, row(&screen, 1), "abcde")
    testing.expect_value(t, row(&screen, 2), "ab")
    testing.expect_value(t, row(&screen, 3), "")
    write(&screen, "\x1b[1J")
    testing.expect_value(t, row(&screen, 0), "")
    testing.expect_value(t, row(&screen, 1), "")
    testing.expect_value(t, row(&screen, 2), "")
    write(&screen, "\x1b[2J")
    testing.expect_value(t, row(&screen, 2), "")
    // letters: erase, delete, insert
    AnsiScreenClear(&screen)
    write(&screen, "0123456789\x1b[1;3H\x1b[2X")
    testing.expect_value(t, row(&screen, 0), "01  456789")
    write(&screen, "\x1b[2P")
    testing.expect_value(t, row(&screen, 0), "01456789")
    write(&screen, "\x1b[2@")
    testing.expect_value(t, row(&screen, 0), "01  456789")
    // lines: insert and delete from the cursor's row, reverse index
    AnsiScreenClear(&screen)
    for line in 0 ..< 5 {
        screen.row, screen.column = line, 0
        write(&screen, string([]u8{u8('a' + line)}))
    }
    write(&screen, "\x1b[2;1H\x1b[L")
    testing.expect_value(t, row(&screen, 1), "")
    testing.expect_value(t, row(&screen, 2), "b")
    testing.expect_value(t, row(&screen, 4), "d")
    write(&screen, "\x1b[2M")
    testing.expect_value(t, row(&screen, 1), "c")
    testing.expect_value(t, row(&screen, 2), "d")
    testing.expect_value(t, row(&screen, 3), "")
    write(&screen, "\x1b[1;1H\x1bM")
    testing.expect_value(t, row(&screen, 0), "")
    testing.expect_value(t, row(&screen, 1), "a")
    // reset
    write(&screen, "\x1b[31mx\x1bc")
    testing.expect_value(t, row(&screen, 1), "")
    testing.expect_value(t, screen.style, AnsiState{})
}

@(test)
test_sequences_may_be_cut_anywhere_and_unknown_ones_are_skipped :: proc(t: ^testing.T) {
    cells: [10 * 3]AnsiCell
    whole: AnsiScreen = AnsiScreenMake(cells[:], 10, 3)
    text: string = "\x1b[2J\x1b[1;1H\x1b[1;31mred\x1b[0m \x1b[?25l\x1b[?1049hok\x1b[2;3Hmid\x1b]0;title\x07 \x1b(Bx"
    write(&whole, text)
    other: [10 * 3]AnsiCell
    cut: AnsiScreen = AnsiScreenMake(other[:], 10, 3)
    bytes: []u8 = transmute([]u8)text
    for byte in bytes { AnsiScreenWrite(&cut, {byte}) }
    for i in 0 ..< len(cells) { testing.expectf(t, cells[i] == other[i], "cell %d is the same cut or whole", i) }
    testing.expect_value(t, row(&whole, 0), "red ok")
    testing.expect_value(t, row(&whole, 1), "  mid x")
    testing.expect_value(t, [2]int{whole.column, whole.row}, [2]int{whole.column, whole.row})
    // a sequence that never ends does not eat the screen
    AnsiScreenClear(&whole)
    write(&whole, "\x1b[1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1xabc")
    testing.expect(t, row(&whole, 0) != "")
}

@(test)
test_styles_and_erasing_with_a_ground :: proc(t: ^testing.T) {
    cells: [8 * 2]AnsiCell
    screen: AnsiScreen = AnsiScreenMake(cells[:], 8, 2)
    dark: [16]Color = ANSI_COLORS_DARK
    write(&screen, "\x1b[1;32mab\x1b[0mc\x1b[41md")
    testing.expect_value(t, cells[0].style, AnsiState{color = dark[2], bold = true})
    testing.expect_value(t, cells[2].style, AnsiState{})
    testing.expect_value(t, cells[3].style, AnsiState{background = dark[1]})
    // erasing a line keeps the ground that is set, not the colors of the text
    write(&screen, "\x1b[33m\x1b[2K")
    testing.expect_value(t, cells[0].character, rune(0))
    testing.expect_value(t, cells[0].style, AnsiState{background = dark[1]})
    // the style is saved with the cursor
    AnsiScreenClear(&screen)
    write(&screen, "\x1b[4m\x1b[s\x1b[0mx\x1b[u")
    testing.expect_value(t, screen.style, AnsiState{underline = true})
    // a palette of the program
    light: [16]Color = ANSI_COLORS_LIGHT
    screen.palette = &light
    write(&screen, "\x1b[32mq")
    testing.expect_value(t, cells[0].style.color, light[2])
}

@(test)
test_a_screen_is_shown_as_rows_of_runs :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(256, 512, 128, 4096),
        ctx: Context,
        style: Style,
        cells: [12 * 3]AnsiCell,
        screen: AnsiScreen,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    test.screen = AnsiScreenMake(test.cells[:], 12, 3)
    write(&test.screen, "plain \x1b[1;32mgreen\x1b[0m\r\n\x1b[41m  \x1b[0m x\x1b[3;1Hlast")
    for _ in 0 ..< 2 {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(400), {}}) { UiAnsiScreen(&test.ctx, &test.screen) }
        UiEnd(&test.ctx)
    }
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
    find :: proc(ctx: ^Context, text: string) -> (info: DrawInfo, found: bool) {
        for command in UiCommands(ctx) {
            if command.kind == .DRAW && command.info.kind == .LABEL && command.info.text == text { return command.info, true }
        }
        return
    }
    size: f32 = DEFAULT_METRICS.font_size
    plain, plain_found := find(&test.ctx, "plain ")
    green, green_found := find(&test.ctx, "green")
    spaces, spaces_found := find(&test.ctx, "  ")
    x, x_found := find(&test.ctx, " x")
    last, last_found := find(&test.ctx, "last")
    testing.expect(t, plain_found && green_found && spaces_found && x_found && last_found, "the runs are texts")
    testing.expect(t, DrawInfoHasTag(&green, "strong") && DrawInfoHasTag(&green, "mono") && !DrawInfoHasTag(&plain, "strong"))
    // a cell is half a size wide in this measure and a size high: runs are where their cells are
    testing.expect_value(t, green.rect.x - plain.rect.x, size * 3)
    testing.expect_value(t, x.rect.x - spaces.rect.x, size)
    testing.expect_value(t, last.rect.y - plain.rect.y, size * 2)
    testing.expect_value(t, x.rect.y - plain.rect.y, size)
    // the ground of the two cells is a rectangle of their size; the empty cells at the end of rows are not declared; the cursor is a rectangle too
    fills: int
    for command in UiCommands(&test.ctx) {
        if command.kind != .DRAW || command.info.kind != .FILL { continue }
        fills += 1
        if command.info.color.a == 255 { testing.expect(t, command.info.rect.z == size && command.info.rect.w == size) }
    }
    testing.expect_value(t, fills, 2)
}
