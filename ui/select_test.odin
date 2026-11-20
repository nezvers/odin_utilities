#+build !js
package ui

import "core:strings"
import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(private = "file")
Test :: struct {
    storage: Storage(128, 256, 64, 2048),
    ctx: Context,
    style: Style,
    clicks: int,
    field: [32]u8,
    field_length: int,
}

@(private = "file")
frame :: proc(test: ^Test, input: Input) {
    UiBegin(&test.ctx, input, 1.0 / 60, {1000, 700}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(700), {}}) {
        UiLabel(&test.ctx, "outside text")
        if UiTagged(&test.ctx, TEXT_SELECTABLE) {
            UiLabel(&test.ctx, "hello world")
            UiLabel(&test.ctx, "second line here")
            UiRichText(&test.ctx, "rich", "plain **bold** end")
            // a paragraph that takes three lines: 12 letters fit
            ElementOpen(&test.ctx, {layout = {size = {Fixed(DEFAULT_METRICS.font_size * 6), Fit()}, direction = .TOP_TO_BOTTOM}})
            UiRichText(&test.ctx, "narrow", "one two **three four** five six")
            ElementClose(&test.ctx)
            ElementOpen(&test.ctx, {layout = {size = {Fixed(DEFAULT_METRICS.font_size * 4), Fit()}}})
            UiLabel(&test.ctx, "aaaa bbbb cccc##wrapped", .WORDS)
            ElementClose(&test.ctx)
        }
        if UiButton(&test.ctx, "Button") { test.clicks += 1 }
        UiTextField(&test.ctx, "field", test.field[:], &test.field_length, {Fixed(200), {}})
    }
    UiEnd(&test.ctx)
}

// The place of a letter of a drawn text on the screen: a little after the start of the letter `offset`
@(private = "file")
letter :: proc(test: ^Test, text: string, offset: int) -> Vec2 {
    for command in UiCommands(&test.ctx) {
        info: DrawInfo = command.info
        if command.kind == .DRAW && info.kind == .LABEL && info.text == text {
            return {info.rect.x + f32(offset) * DEFAULT_METRICS.font_size * 0.5 + 1, info.rect.y + info.rect.w * 0.5}
        }
    }
    return {-1, -1}
}

@(private = "file")
drag :: proc(test: ^Test, from: Vec2, to: Vec2) {
    frame(test, {mouse_position = from})
    frame(test, {mouse_position = from, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = to, mouse_down = true})
    frame(test, {mouse_position = to, mouse_down = true})
    frame(test, {mouse_position = to, mouse_released = true})
    frame(test, {mouse_position = {-100, -100}})
}

@(private = "file")
selections :: proc(test: ^Test) -> (count: int, first: Rect) {
    for command in UiCommands(&test.ctx) {
        if command.kind != .DRAW || command.info.kind != .TEXT_SELECTION { continue }
        if count == 0 { first = command.info.rect }
        count += 1
    }
    return
}

@(test)
test_text_is_selected_over_lines_and_texts_and_copied :: proc(t: ^testing.T) {
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 3 { frame(test, away) }
    text, whole := UiTextSelected(&test.ctx)
    testing.expect(t, text == "" && whole)
    count, _ := selections(test)
    testing.expect_value(t, count, 0)

    // from inside of one text to inside of the next: the rest of the first, a new line, the start of the second
    drag(test, letter(test, "hello world", 3), letter(test, "second line here", 6))
    text, whole = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "lo world\nsecond")
    testing.expect(t, whole)
    first: Rect
    count, first = selections(test)
    testing.expect_value(t, count, 2)
    hello: Vec2 = letter(test, "hello world", 3)
    testing.expect_value(t, first.x, hello.x - 1)
    testing.expect_value(t, first.z, DEFAULT_METRICS.font_size * 4)        // eight letters
    // the copy action puts it on the clipboard
    frame(test, {mouse_position = {-100, -100}, actions = {.COPY}})
    testing.expect_value(t, string(test.ctx.clipboard.local[:test.ctx.clipboard.local_length]), "lo world\nsecond")

    // backwards is the same selection
    drag(test, letter(test, "second line here", 6), letter(test, "hello world", 3))
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "lo world\nsecond")

    // the runs of a paragraph stand in one row: no new line between them
    drag(test, letter(test, "plain ", 2), letter(test, " end", 2))
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "ain bold e")
    count, _ = selections(test)
    testing.expect_value(t, count, 3)

    // a wrapped text: the lines of one text are copied as the text is, with the space the wrap took
    drag(test, letter(test, "aaaa", 2), letter(test, "cccc", 2))
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "aa bbbb cc")
    count, _ = selections(test)
    testing.expect_value(t, count, 3)

    // the lines of a paragraph are one text: a space where the line was broken, not a new line
    drag(test, letter(test, "one two", 4), letter(test, "five six", 4))
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "two three four five")

    // a press and no drag: nothing is selected, nothing is drawn
    drag(test, letter(test, "hello world", 3), letter(test, "hello world", 3))
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "")
    count, _ = selections(test)
    testing.expect_value(t, count, 0)

    // a drag that ends below the texts: up to the end of the last one
    drag(test, letter(test, "second line here", 7), letter(test, "cccc", 4) + {300, 300})
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "line here\nplain bold end\none two three four five six\naaaa bbbb cccc")
}

@(test)
test_a_selection_is_let_go_and_leaves_widgets_alone :: proc(t: ^testing.T) {
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 3 { frame(test, away) }
    select :: proc(test: ^Test) -> string {
        // some time since the press before: a press at the same place right after another is a double click
        for _ in 0 ..< 40 { frame(test, {mouse_position = {-100, -100}}) }
        drag(test, letter(test, "hello world", 0), letter(test, "hello world", 5))
        text, _ := UiTextSelected(&test.ctx)
        return text
    }
    testing.expect_value(t, select(test), "hello")
    // a text that is not inside of the tag: a drag on it selects nothing and lets the selection go
    drag(test, letter(test, "outside text", 1), letter(test, "outside text", 6))
    text, _ := UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "")
    // the cancel action lets it go
    testing.expect_value(t, select(test), "hello")
    frame(test, {mouse_position = {-100, -100}, actions = {.CANCEL}})
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "")
    // the program lets it go
    testing.expect_value(t, select(test), "hello")
    UiTextSelectionClear(&test.ctx)
    frame(test, away)
    count, _ := selections(test)
    testing.expect_value(t, count, 0)
    // a press on a button is the button's: it clicks, and a selection that was there is gone
    testing.expect_value(t, select(test), "hello")
    rect, _ := UiElementRect(&test.ctx, UiIdPath("window", "Button"))
    point: Vec2 = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    frame(test, {mouse_position = point})
    frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = point, mouse_released = true})
    frame(test, away)
    testing.expect_value(t, test.clicks, 1)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "")
    // a text field that is edited keeps the copy action: the clipboard gets its selection, not the one of the texts
    testing.expect_value(t, select(test), "hello")
    test.field_length = copy(test.field[:], "field text")
    UiFocus(&test.ctx, UiIdPath("window", "field"))
    frame(test, away)
    frame(test, {mouse_position = {-100, -100}, actions = {.SELECT_ALL}})
    frame(test, {mouse_position = {-100, -100}, actions = {.COPY}})
    testing.expect_value(t, string(test.ctx.clipboard.local[:test.ctx.clipboard.local_length]), "field text")
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_a_double_click_selects_a_word_and_a_third_the_text :: proc(t: ^testing.T) {
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    for _ in 0 ..< 3 { frame(test, {mouse_position = {-100, -100}}) }
    click :: proc(test: ^Test, point: Vec2) {
        frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
        frame(test, {mouse_position = point, mouse_released = true})
        frame(test, {mouse_position = point})
    }
    point: Vec2 = letter(test, "second line here", 9)                   // in "line"
    click(test, point)
    text, _ := UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "")
    click(test, point)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "line")
    click(test, point)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "second line here")
    // the pointer moves with the button up: the selection of the word stays
    frame(test, {mouse_position = point + {40, 0}})
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "second line here")
    // two clicks with a long time between them are two clicks
    for _ in 0 ..< 60 { frame(test, {mouse_position = {-100, -100}}) }
    click(test, point)
    for _ in 0 ..< 60 { frame(test, {mouse_position = point}) }
    click(test, point)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "")
    // two clicks at two places are two clicks
    for _ in 0 ..< 60 { frame(test, {mouse_position = {-100, -100}}) }
    click(test, point)
    click(test, letter(test, "second line here", 2))
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "")
    // a word of a run of a paragraph, and with a third click the paragraph: all of its runs
    for _ in 0 ..< 60 { frame(test, {mouse_position = {-100, -100}}) }
    bold: Vec2 = letter(test, "bold", 2)
    click(test, bold)
    click(test, bold)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "bold")
    click(test, bold)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "plain bold end")
    // a paragraph of three lines: all of its lines, from a click in the middle one, and nothing of the texts around it
    for _ in 0 ..< 60 { frame(test, {mouse_position = {-100, -100}}) }
    middle: Vec2 = letter(test, "three four", 7)
    click(test, middle)
    click(test, middle)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "four")
    click(test, middle)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "one two three four five six")
}

@(test)
test_a_selection_is_extended_with_shift_and_takes_everything_with_select_all :: proc(t: ^testing.T) {
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 3 { frame(test, away) }
    drag(test, letter(test, "hello world", 0), letter(test, "hello world", 5))
    text, _ := UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "hello")
    // Shift and a click further on: from the start of the selection to there
    for _ in 0 ..< 40 { frame(test, away) }
    point: Vec2 = letter(test, "second line here", 6)
    frame(test, {mouse_position = point, modifiers = {.SHIFT}})
    frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true, modifiers = {.SHIFT}})
    frame(test, {mouse_position = point, mouse_released = true, modifiers = {.SHIFT}})
    frame(test, away)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "hello world\nsecond")
    // select all while a part is selected: every selectable text, and not the one outside of the tag
    frame(test, {mouse_position = {-100, -100}, actions = {.SELECT_ALL}})
    frame(test, away)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "hello world\nsecond line here\nplain bold end\none two three four five six\naaaa bbbb cccc")
    frame(test, {mouse_position = {-100, -100}, actions = {.COPY}})
    testing.expect_value(t, test.ctx.clipboard.local_length, len(text))
    // nothing selected and the pointer somewhere else: select all is not for the texts
    frame(test, {mouse_position = {-100, -100}, actions = {.CANCEL}})
    frame(test, {mouse_position = {-100, -100}, actions = {.SELECT_ALL}})
    frame(test, away)
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "")
    // the pointer over a text: it is
    over: Vec2 = letter(test, "hello world", 2)
    frame(test, {mouse_position = over})
    frame(test, {mouse_position = over, actions = {.SELECT_ALL}})
    frame(test, {mouse_position = over})
    text, _ = UiTextSelected(&test.ctx)
    testing.expect(t, len(text) > 60)
    // a text field that is edited keeps select all for itself
    frame(test, {mouse_position = {-100, -100}, actions = {.CANCEL}})
    test.field_length = copy(test.field[:], "field")
    UiFocus(&test.ctx, UiIdPath("window", "field"))
    frame(test, {mouse_position = over})
    frame(test, {mouse_position = over, actions = {.SELECT_ALL}})
    frame(test, {mouse_position = over})
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "")
}

@(test)
test_the_end_of_a_selection_moves_with_shift_and_the_arrows :: proc(t: ^testing.T) {
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 3 { frame(test, away) }
    key :: proc(test: ^Test, action: Action, shift: bool = true) -> string {
        frame(test, {mouse_position = {-100, -100}, actions = {action}, modifiers = {.SHIFT} if shift else {}})
        frame(test, {mouse_position = {-100, -100}})
        text, _ := UiTextSelected(&test.ctx)
        return text
    }
    // "lo" of hello is selected: the end is after the o
    drag(test, letter(test, "hello world", 3), letter(test, "hello world", 5))
    text, _ := UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "lo")
    testing.expect_value(t, key(test, .RIGHT), "lo ")
    testing.expect_value(t, key(test, .RIGHT), "lo w")
    testing.expect_value(t, key(test, .LEFT), "lo ")
    // without Shift an arrow is not for the selection
    testing.expect_value(t, key(test, .RIGHT, false), "lo ")
    // the end of the line, then on: into the next text, over the new line between them, and back
    testing.expect_value(t, key(test, .END), "lo world")
    testing.expect_value(t, key(test, .RIGHT), "lo world\ns")
    testing.expect_value(t, key(test, .LEFT), "lo world")
    // down: the line below, at the same place sideways (10 letters in), and up again
    testing.expect_value(t, key(test, .LEFT), "lo worl")
    testing.expect_value(t, key(test, .DOWN), "lo world\nsecond lin")
    testing.expect_value(t, key(test, .UP), "lo worl")
    // the end goes before the start: the selection turns around
    testing.expect_value(t, key(test, .HOME), "hel")
    testing.expect_value(t, key(test, .LEFT), "hel")                // nothing before the first text
    testing.expect_value(t, key(test, .UP), "hel")
    // through the runs of a paragraph: a step from one run into the next is one letter, not a stop at the border
    drag(test, letter(test, "plain ", 4), letter(test, "plain ", 5))
    text, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, text, "n")
    testing.expect_value(t, key(test, .RIGHT), "n ")
    testing.expect_value(t, key(test, .RIGHT), "n b")
    testing.expect_value(t, key(test, .RIGHT), "n bo")
    testing.expect_value(t, key(test, .LEFT), "n b")
    testing.expect_value(t, key(test, .LEFT), "n ")
    // down from the paragraph of one line into the paragraph of three lines, and through its lines
    testing.expect_value(t, key(test, .DOWN), "n bold end\none tw")
    testing.expect_value(t, key(test, .DOWN), "n bold end\none two three ")
    testing.expect_value(t, key(test, .END), "n bold end\none two three four")
    // the arrows with Shift did not move the focus, and a text field that is edited keeps them
    testing.expect_value(t, UiFocused(&test.ctx), Id(0))
    test.field_length = copy(test.field[:], "field")
    UiFocus(&test.ctx, UiIdPath("window", "field"))
    frame(test, away)
    before, _ := UiTextSelected(&test.ctx)
    testing.expect_value(t, key(test, .RIGHT), before)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

// The rows of a list that declares only the rows in view: row 7 is "row 07 text"
@(private = "file")
ListTest :: struct {
    storage: Storage(128, 256, 64, 2048),
    ctx: Context,
    style: Style,
    first: int,                 // the first row in view; four rows are
    shown: bool,                // the list is declared
    lines: [20][16]u8,
}

@(private = "file")
rowOf :: proc(test: ^ListTest, row: int) -> string {
    line: ^[16]u8 = &test.lines[row]
    copy(line[:], "row 00 text")
    line[4], line[5] = u8('0' + row / 10), u8('0' + row % 10)
    return string(line[:11])
}

@(private = "file")
listRowText :: proc(user: rawptr, row: int, cell: int) -> string {
    return rowOf(cast(^ListTest)user, row)
}

@(private = "file")
listFrame :: proc(test: ^ListTest, input: Input) {
    UiBegin(&test.ctx, input, 1.0 / 60, {1000, 700}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(700), {}}) {
        if UiTagged(&test.ctx, TEXT_SELECTABLE) {
            UiLabel(&test.ctx, "before")
            if test.shown {
                group: Id = UiSelectRows(&test.ctx, "rows", 20, listRowText, test)
                for row in test.first ..< test.first + 4 {
                    if UiSelectRow(&test.ctx, group, row) { UiLabel(&test.ctx, rowOf(test, row)) }
                }
            }
            UiLabel(&test.ctx, "after")
        }
    }
    UiEnd(&test.ctx)
}

@(private = "file")
listLetter :: proc(test: ^ListTest, text: string, offset: int) -> Vec2 {
    for command in UiCommands(&test.ctx) {
        info: DrawInfo = command.info
        if command.kind == .DRAW && info.kind == .LABEL && info.text == text {
            return {info.rect.x + f32(offset) * DEFAULT_METRICS.font_size * 0.5 + 1, info.rect.y + info.rect.w * 0.5}
        }
    }
    return {-1, -1}
}

@(private = "file")
listDrag :: proc(test: ^ListTest, from: Vec2, to: Vec2) {
    for _ in 0 ..< 40 { listFrame(test, {mouse_position = {-100, -100}}) }         // a press at the same place right after another would be a double click
    listFrame(test, {mouse_position = from})
    listFrame(test, {mouse_position = from, mouse_down = true, mouse_pressed = true})
    listFrame(test, {mouse_position = to, mouse_down = true})
    listFrame(test, {mouse_position = to, mouse_down = true})
    listFrame(test, {mouse_position = to, mouse_released = true})
    listFrame(test, {mouse_position = {-100, -100}})
}

@(test)
test_a_selection_in_a_list_that_declares_only_its_rows_in_view :: proc(t: ^testing.T) {
    test: ^ListTest = new(ListTest)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    test.first, test.shown = 2, true
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 3 { listFrame(test, away) }
    selection :: proc(test: ^ListTest) -> string {
        text, _ := UiTextSelected(&test.ctx)
        return text
    }
    joined :: proc(test: ^ListTest, from: int, to: int) -> string {
        // the rows from..to as a copy has them: a new line between them
        builder: strings.Builder
        strings.builder_init(&builder, context.temp_allocator)
        for row in from ..= to {
            if row > from { strings.write_byte(&builder, '\n') }
            strings.write_string(&builder, rowOf(test, row))
        }
        return strings.to_string(builder)
    }
    // from the middle of row 2 to the start of row 4: the end of the first, the whole row between them, the start of the last
    listDrag(test, listLetter(test, "row 02 text", 4), listLetter(test, "row 04 text", 3))
    text := selection(test)
    testing.expect_value(t, text, "02 text\nrow 03 text\nrow")
    rects: int
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.kind == .TEXT_SELECTION { rects += 1 }
    }
    testing.expect_value(t, rects, 3)

    // the list scrolls away: the rows of the selection are not declared, the selection is as it was
    test.first = 10
    for _ in 0 ..< 3 { listFrame(test, away) }
    testing.expect_value(t, selection(test), "02 text\nrow 03 text\nrow")
    rects = 0
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.kind == .TEXT_SELECTION { rects += 1 }
    }
    testing.expect_value(t, rects, 0)
    // Shift and a click in row 11: the end moves there, the start stays in row 2, the rows in between come from the program
    for _ in 0 ..< 40 { listFrame(test, away) }
    point: Vec2 = listLetter(test, "row 11 text", 5)
    listFrame(test, {mouse_position = point, modifiers = {.SHIFT}})
    listFrame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true, modifiers = {.SHIFT}})
    listFrame(test, {mouse_position = point, mouse_released = true, modifiers = {.SHIFT}})
    listFrame(test, away)
    text = selection(test)
    testing.expect(t, len(text) > 0 && text[:7] == "02 text")
    rest: string = text[7:]
    testing.expect(t, len(rest) > 0 && rest[0] == '\n')
    testing.expect_value(t, rest, strings.concatenate({"\n", joined(test, 3, 10), "\nrow 1"}, context.temp_allocator))
    // the rows that are in view have their part drawn
    rects = 0
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.kind == .TEXT_SELECTION { rects += 1 }
    }
    testing.expect_value(t, rects, 2)                           // rows 10 (all) and 11 (up to the click)

    // the list between two texts: from "before" to "after" it is all of it, also what is out of view
    test.first = 0
    for _ in 0 ..< 3 { listFrame(test, away) }
    listDrag(test, listLetter(test, "before", 2), listLetter(test, "after", 3))
    text = selection(test)
    testing.expect_value(t, text, strings.concatenate({"fore\n", joined(test, 0, 19), "\naft"}, context.temp_allocator))

    // select all with the pointer over a text: the same, from the start of the first to the end of the last
    test.first = 8
    for _ in 0 ..< 3 { listFrame(test, away) }
    UiTextSelectionClear(&test.ctx)
    over: Vec2 = listLetter(test, "row 09 text", 2)
    listFrame(test, {mouse_position = over})
    listFrame(test, {mouse_position = over, actions = {.SELECT_ALL}})
    listFrame(test, {mouse_position = over})
    text = selection(test)
    testing.expect_value(t, text, strings.concatenate({"before\n", joined(test, 0, 19), "\nafter"}, context.temp_allocator))
    // the copy action takes it all
    listFrame(test, {mouse_position = over, actions = {.COPY}})
    testing.expect_value(t, test.ctx.clipboard.local_length, len(text))
    // the ends are texts of their own: the list may go and the selection stays, as the two texts
    test.shown = false
    for _ in 0 ..< 3 { listFrame(test, away) }
    testing.expect_value(t, selection(test), "before\nafter")
    // a selection with an end in a list that is not there any more is gone
    test.shown = true
    for _ in 0 ..< 3 { listFrame(test, away) }
    listDrag(test, listLetter(test, "row 09 text", 1), listLetter(test, "row 11 text", 4))
    testing.expect_value(t, selection(test), "ow 09 text\nrow 10 text\nrow ")
    test.shown = false
    for _ in 0 ..< 3 { listFrame(test, away) }
    testing.expect_value(t, selection(test), "")
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

// Rows of three cells, like a table: the cell c of the row r is "0r.c-xyz" with the letter a, b or c
@(private = "file")
CellTest :: struct {
    storage: Storage(128, 256, 64, 2048),
    ctx: Context,
    style: Style,
    first: int,
    lines: [20][3][12]u8,
}

@(private = "file")
cellOf :: proc(test: ^CellTest, row: int, cell: int) -> string {
    line: ^[12]u8 = &test.lines[row][cell]
    copy(line[:], "00.a-xyz")
    line[0], line[1], line[3] = u8('0' + row / 10), u8('0' + row % 10), u8('a' + cell)
    return string(line[:8])
}

@(private = "file")
cellText :: proc(user: rawptr, row: int, cell: int) -> string {
    return cellOf(cast(^CellTest)user, row, cell)
}

@(private = "file")
cellFrame :: proc(test: ^CellTest, input: Input) {
    UiBegin(&test.ctx, input, 1.0 / 60, {1000, 700}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(700), {}}) {
        if UiTagged(&test.ctx, TEXT_SELECTABLE) {
            group: Id = UiSelectRows(&test.ctx, "cells", 20, cellText, test, 3)
            for row in test.first ..< test.first + 4 {
                if UiRow(&test.ctx) {
                    if UiSelectRow(&test.ctx, group, row) {
                        for cell in 0 ..< 3 {
                            // a column of its own width, so that the cells stand apart
                            ElementOpen(&test.ctx, {layout = {size = {Fixed(DEFAULT_METRICS.font_size * 6), Fit()}}})
                            UiLabel(&test.ctx, cellOf(test, row, cell))
                            ElementClose(&test.ctx)
                        }
                    }
                }
            }
        }
    }
    UiEnd(&test.ctx)
}

@(private = "file")
cellLetter :: proc(test: ^CellTest, row: int, cell: int, offset: int) -> Vec2 {
    text: string = cellOf(test, row, cell)
    for command in UiCommands(&test.ctx) {
        info: DrawInfo = command.info
        if command.kind == .DRAW && info.kind == .LABEL && info.text == text {
            return {info.rect.x + f32(offset) * DEFAULT_METRICS.font_size * 0.5 + 1, info.rect.y + info.rect.w * 0.5}
        }
    }
    return {-1, -1}
}

@(private = "file")
cellDrag :: proc(test: ^CellTest, from: Vec2, to: Vec2) {
    for _ in 0 ..< 40 { cellFrame(test, {mouse_position = {-100, -100}}) }
    cellFrame(test, {mouse_position = from})
    cellFrame(test, {mouse_position = from, mouse_down = true, mouse_pressed = true})
    cellFrame(test, {mouse_position = to, mouse_down = true})
    cellFrame(test, {mouse_position = to, mouse_down = true})
    cellFrame(test, {mouse_position = to, mouse_released = true})
    cellFrame(test, {mouse_position = {-100, -100}})
}

@(test)
test_a_selection_over_the_cells_of_the_rows_of_a_list :: proc(t: ^testing.T) {
    test: ^CellTest = new(CellTest)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    test.first = 2
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 3 { cellFrame(test, away) }
    selection :: proc(test: ^CellTest) -> string {
        text, _ := UiTextSelected(&test.ctx)
        return text
    }
    // within a row: from the second letter of the first cell to the second of the last: the cells between whole, a tab between the cells
    cellDrag(test, cellLetter(test, 2, 0, 1), cellLetter(test, 2, 2, 2))
    testing.expect_value(t, selection(test), "2.a-xyz\t02.b-xyz\t02")
    // over rows: from the middle of the second cell of a row to the start of the first cell of a row two further on
    cellDrag(test, cellLetter(test, 2, 1, 3), cellLetter(test, 4, 0, 4))
    testing.expect_value(t, selection(test), "b-xyz\t02.c-xyz\n03.a-xyz\t03.b-xyz\t03.c-xyz\n04.a")
    rects: int
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.kind == .TEXT_SELECTION { rects += 1 }
    }
    testing.expect_value(t, rects, 2 + 3 + 1)               // two cells of the first row, the three of the next, the first of the last
    // the list scrolls: the same selection, none of its rows is in view
    test.first = 12
    for _ in 0 ..< 3 { cellFrame(test, away) }
    testing.expect_value(t, selection(test), "b-xyz\t02.c-xyz\n03.a-xyz\t03.b-xyz\t03.c-xyz\n04.a")
    // Shift and a click in the second cell of a row that is there: the cells before it in that row too
    for _ in 0 ..< 40 { cellFrame(test, away) }
    point: Vec2 = cellLetter(test, 13, 1, 5)
    cellFrame(test, {mouse_position = point, modifiers = {.SHIFT}})
    cellFrame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true, modifiers = {.SHIFT}})
    cellFrame(test, {mouse_position = point, mouse_released = true, modifiers = {.SHIFT}})
    cellFrame(test, away)
    text := selection(test)
    testing.expect(t, len(text) > 0 && text[:5] == "b-xyz")
    testing.expect_value(t, text[len(text) - 14:], "13.a-xyz\t13.b-")
    lines: int
    for character in transmute([]u8)text {
        if character == '\n' { lines += 1 }
    }
    testing.expect_value(t, lines, 11)                      // rows 2 to 13
    // keys among the cells of rows that are in view: the end goes into the next cell
    key :: proc(test: ^CellTest, action: Action) -> string {
        cellFrame(test, {mouse_position = {-100, -100}, actions = {action}, modifiers = {.SHIFT}})
        cellFrame(test, {mouse_position = {-100, -100}})
        text, _ := UiTextSelected(&test.ctx)
        return text
    }
    cellDrag(test, cellLetter(test, 12, 0, 1), cellLetter(test, 12, 0, 8))
    testing.expect_value(t, selection(test), "2.a-xyz")
    testing.expect_value(t, key(test, .RIGHT), "2.a-xyz\t1")   // one letter into the next cell
    testing.expect_value(t, key(test, .RIGHT), "2.a-xyz\t12")
    // select all: every cell of every row of the list, in order
    test.first = 5
    for _ in 0 ..< 3 { cellFrame(test, away) }
    over: Vec2 = cellLetter(test, 6, 1, 2)
    cellFrame(test, {mouse_position = over})
    cellFrame(test, {mouse_position = over, actions = {.SELECT_ALL}})
    cellFrame(test, {mouse_position = over})
    text = selection(test)
    testing.expect_value(t, len(text), 20 * (3 * 8 + 2) + 19)     // 20 rows of three cells and two tabs, a new line between the rows
    testing.expect_value(t, text[:8], "00.a-xyz")
    testing.expect_value(t, text[len(text) - 8:], "19.c-xyz")
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(private = "file")
RevealTest :: struct {
    storage: Storage(256, 512, 128, 4096),
    ctx: Context,
    style: Style,
    list: VirtualList,
    lines: [100][16]u8,
    list_id: Id,
}

@(private = "file")
revealRow :: proc(test: ^RevealTest, row: int) -> string {
    line: ^[16]u8 = &test.lines[row]
    copy(line[:], "row 000 text")
    line[4], line[5], line[6] = u8('0' + row / 100), u8('0' + row / 10 % 10), u8('0' + row % 10)
    return string(line[:12])
}

@(private = "file")
revealText :: proc(user: rawptr, row: int, cell: int) -> string {
    return revealRow(cast(^RevealTest)user, row)
}

@(private = "file")
revealFrame :: proc(test: ^RevealTest, input: Input) {
    UiBegin(&test.ctx, input, 1.0 / 60, {1000, 700}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(500), {}}) {
        test.list_id = UiId(&test.ctx, "list")
        group: Id = UiSelectRows(&test.ctx, "rows", 100, revealText, test, 1, test.list_id, 20)
        if UiTagged(&test.ctx, TEXT_SELECTABLE) {
            if UiVirtual(&test.ctx, "list", &test.list, 100, 20, {Fixed(400), Fixed(100)}) {
                for row in test.list.first ..< test.list.last {
                    if UiVirtualRow(&test.ctx, &test.list, row) {
                        if UiSelectRow(&test.ctx, group, row) { UiLabel(&test.ctx, revealRow(test, row)) }
                    }
                }
            }
        }
    }
    UiEnd(&test.ctx)
}

@(test)
test_the_end_of_a_selection_moves_out_of_view_and_the_list_follows :: proc(t: ^testing.T) {
    test: ^RevealTest = new(RevealTest)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    test.list = {selected = VIRTUAL_NONE, text = true}
    UiInit(&test.ctx, &test.storage, measure)
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 4 { revealFrame(test, away) }
    // a drag inside of the first row: the end is at its fourth letter
    text := "row 000 text"
    point: Vec2
    for command in UiCommands(&test.ctx) {
        info: DrawInfo = command.info
        if command.kind == .DRAW && info.kind == .LABEL && info.text == text { point = {info.rect.x + 1, info.rect.y + info.rect.w * 0.5} }
    }
    revealFrame(test, {mouse_position = point})
    revealFrame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    revealFrame(test, {mouse_position = point + {4 * DEFAULT_METRICS.font_size * 0.5, 0}, mouse_down = true})
    revealFrame(test, {mouse_position = point + {4 * DEFAULT_METRICS.font_size * 0.5, 0}, mouse_released = true})
    revealFrame(test, away)
    selected, _ := UiTextSelected(&test.ctx)
    testing.expect_value(t, selected, "row ")
    testing.expect_value(t, UiScrollGet(&test.ctx, test.list_id), f32(0))
    // Shift and down, again and again: the end goes down the rows, one at a time, past the five that are in view, and the list scrolls after it
    down :: proc(test: ^RevealTest) {
        revealFrame(test, {mouse_position = {-100, -100}, actions = {.DOWN}, modifiers = {.SHIFT}})
        revealFrame(test, {mouse_position = {-100, -100}})
        revealFrame(test, {mouse_position = {-100, -100}})
    }
    for _ in 0 ..< 12 { down(test) }
    selected, _ = UiTextSelected(&test.ctx)
    lines: int
    for character in transmute([]u8)selected {
        if character == '\n' { lines += 1 }
    }
    testing.expect_value(t, lines, 12)
    testing.expect(t, len(selected) > 12 * 12)
    testing.expect_value(t, selected[len(selected) - 4:], "row ")                  // the end is in row 12, at the fourth letter as the start was
    offset: f32 = UiScrollGet(&test.ctx, test.list_id)
    testing.expect(t, offset >= 12 * 20 + 20 - 100 - 0.5, "the list scrolled so that row 12 is the last of the view")
    testing.expect(t, test.list.first >= 8 && test.list.last > 12)
    // the list is scrolled away from the end by the wheel: up and down still move the end by a row and bring it back
    UiScrollSet(&test.ctx, test.list_id, 1000)
    for _ in 0 ..< 4 { revealFrame(test, away) }
    testing.expect(t, test.list.first > 40)
    down(test)
    selected, _ = UiTextSelected(&test.ctx)
    lines = 0
    for character in transmute([]u8)selected {
        if character == '\n' { lines += 1 }
    }
    testing.expect_value(t, lines, 13)
    testing.expect(t, test.list.last > 12 && test.list.first < 14, "the list came back to row 13")
    // up goes back, the other way, and not past the first row
    up :: proc(test: ^RevealTest) {
        revealFrame(test, {mouse_position = {-100, -100}, actions = {.UP}, modifiers = {.SHIFT}})
        revealFrame(test, {mouse_position = {-100, -100}})
        revealFrame(test, {mouse_position = {-100, -100}})
    }
    for _ in 0 ..< 30 { up(test) }
    selected, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, selected, "row ")                // the end is in the first row again, at the fourth letter, and went no further up
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_letters_and_pages_move_the_end_of_a_selection_through_the_rows_of_a_list :: proc(t: ^testing.T) {
    test: ^RevealTest = new(RevealTest)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    test.list = {selected = VIRTUAL_NONE, text = true}
    UiInit(&test.ctx, &test.storage, measure)
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 4 { revealFrame(test, away) }
    point: Vec2
    for command in UiCommands(&test.ctx) {
        info: DrawInfo = command.info
        if command.kind == .DRAW && info.kind == .LABEL && info.text == "row 000 text" { point = {info.rect.x + 1, info.rect.y + info.rect.w * 0.5} }
    }
    to: Vec2 = point + {4 * DEFAULT_METRICS.font_size * 0.5, 0}
    revealFrame(test, {mouse_position = point})
    revealFrame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    revealFrame(test, {mouse_position = to, mouse_down = true})
    revealFrame(test, {mouse_position = to, mouse_released = true})
    revealFrame(test, away)
    key :: proc(test: ^RevealTest, action: Action) -> string {
        revealFrame(test, {mouse_position = {-100, -100}, actions = {action}, modifiers = {.SHIFT}})
        revealFrame(test, {mouse_position = {-100, -100}})
        revealFrame(test, {mouse_position = {-100, -100}})
        text, _ := UiTextSelected(&test.ctx)
        return text
    }
    testing.expect_value(t, key(test, .RIGHT), "row 0")
    for _ in 0 ..< 7 { key(test, .RIGHT) }                  // the end of the row: 12 letters
    testing.expect_value(t, key(test, .RIGHT), "row 000 text\nr")   // over the border into the next row, one letter in
    testing.expect_value(t, key(test, .LEFT), "row 000 text\n")
    testing.expect_value(t, key(test, .LEFT), "row 000 tex")        // back over the border: one letter in from the end of the row before
    // a page: a view of five rows is four rows, from where the end is
    testing.expect_value(t, key(test, .PAGE_DOWN), "row 000 text\nrow 001 text\nrow 002 text\nrow 003 text\nrow 004 tex")
    for _ in 0 ..< 5 { key(test, .PAGE_DOWN) }
    selected, _ := UiTextSelected(&test.ctx)
    lines: int
    for character in transmute([]u8)selected {
        if character == '\n' { lines += 1 }
    }
    testing.expect_value(t, lines, 24)
    testing.expect(t, UiScrollGet(&test.ctx, test.list_id) >= 20 * 20 - 0.5, "the list followed the end down the pages")
    // out of view: the keys still move the end
    UiScrollSet(&test.ctx, test.list_id, 0)
    for _ in 0 ..< 4 { revealFrame(test, away) }
    testing.expect_value(t, test.list.first, 0)
    selected, _ = UiTextSelected(&test.ctx)
    before: int = len(selected)
    selected = key(test, .LEFT)
    testing.expect_value(t, len(selected), before - 1)
    testing.expect(t, test.list.first > 15, "and the list came back")
    for _ in 0 ..< 10 { key(test, .PAGE_UP) }
    selected, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, selected, "row 000 te")         // the first row again (a letter less: the Left of before), and no further
    testing.expect_value(t, test.list.first, 0)
    // when the end is not in a list a page is the focus's
    UiTextSelectionClear(&test.ctx)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(private = "file")
TableTest :: struct {
    storage: Storage(256, 512, 128, 4096),
    ctx: Context,
    style: Style,
    table: Table,
    text: [10][3][8]u8,
}

// The cell of the column c of the row r is "r2c1": by column, whatever the order of the columns on the screen
@(private = "file")
tableCell :: proc(test: ^TableTest, row: int, column: int) -> string {
    line: ^[8]u8 = &test.text[row][column]
    copy(line[:], "r0c0")
    line[1], line[3] = u8('0' + row), u8('0' + column)
    return string(line[:4])
}

@(private = "file")
tableCellText :: proc(user: rawptr, row: int, cell: int) -> string {
    return tableCell(cast(^TableTest)user, row, cell)
}

@(private = "file")
tableFrame :: proc(test: ^TableTest, input: Input) {
    UiBegin(&test.ctx, input, 1.0 / 60, {1000, 700}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(600), {}}) {
        group: Id = UiSelectRows(&test.ctx, "rows", 10, tableCellText, test, 3, UiId(&test.ctx, "table"), 20)
        if UiTagged(&test.ctx, TEXT_SELECTABLE) {
            if UiTable(&test.ctx, "table", &test.table, 10, 20, {Fixed(400), Fixed(100)}) {
                for row in test.table.list.first ..< test.table.list.last {
                    if UiTableRow(&test.ctx, &test.table, row) {
                        if UiSelectRow(&test.ctx, group, row) {
                            for place in 0 ..< 3 {
                                column: int = TableColumnAt(&test.table, place)
                                UiTableText(&test.ctx, &test.table, column, tableCell(test, row, column))
                            }
                        }
                    }
                }
            }
        }
    }
    UiEnd(&test.ctx)
}

@(test)
test_a_selection_in_a_table_stays_while_a_header_is_dragged_and_a_bar_is_pressed :: proc(t: ^testing.T) {
    test: ^TableTest = new(TableTest)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    TableInit(&test.table, {{name = "A", width = 100, unsortable = true}, {name = "B", width = 100, unsortable = true}, {name = "C", width = 100, unsortable = true}})
    test.table.reorderable = true
    test.table.list.text = true
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 4 { tableFrame(test, away) }
    label :: proc(test: ^TableTest, text: string) -> Vec2 {
        for command in UiCommands(&test.ctx) {
            info: DrawInfo = command.info
            if command.kind == .DRAW && info.kind == .LABEL && info.text == text { return {info.rect.x + 2, info.rect.y + info.rect.w * 0.5} }
        }
        return {-1, -1}
    }
    selection :: proc(test: ^TableTest) -> string {
        text, _ := UiTextSelected(&test.ctx)
        return text
    }
    centre :: proc(test: ^TableTest, id: Id) -> Vec2 {
        state: ^WidgetState = stateFind(&test.ctx, id)
        if state == nil { return {-1, -1} }
        return {state.rect.x + state.rect.z * 0.5, state.rect.y + state.rect.w * 0.5}
    }
    drag :: proc(test: ^TableTest, from: Vec2, to: Vec2, steps: int = 6) {
        tableFrame(test, {mouse_position = from})
        tableFrame(test, {mouse_position = from, mouse_down = true, mouse_pressed = true})
        for step in 1 ..= steps {
            tableFrame(test, {mouse_position = from + (to - from) * (f32(step) / f32(steps)), mouse_down = true})
        }
        tableFrame(test, {mouse_position = to, mouse_released = true})
        tableFrame(test, {mouse_position = {-100, -100}})
        tableFrame(test, {mouse_position = {-100, -100}})
    }
    // from the start of a cell of the first row to the start of a cell of the second: the three cells of the first row and the first two of the next
    drag(test, label(test, "r1c0"), label(test, "r2c2"), 2)
    before: string = strings.clone(selection(test), context.temp_allocator)
    testing.expect_value(t, before, "r1c0\tr1c1\tr1c2\nr2c0\tr2c1\t")

    // the header of the first column is dragged to the place of the last: the columns are moved, and the selection is where it was, on the same columns
    header :: proc(test: ^TableTest, column: int) -> Id {
        return IdFromIndex(u32(column), IdFromString("header", UiIdPath("window", "table")))
    }
    drag(test, centre(test, header(test, 0)), centre(test, header(test, 2)) + {20, 0})
    testing.expect_value(t, test.table.order[0], 1)
    testing.expect_value(t, test.table.order[2], 0)
    testing.expect_value(t, selection(test), before)
    rects: int
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.kind == .TEXT_SELECTION { rects += 1 }
    }
    testing.expect_value(t, rects, 3 + 2)                    // the three cells of a row and two of the next: drawn where the columns are now
    // and the selection of cells follows the columns: the text under the highlight is the text of the cell
    first: Vec2 = label(test, "r1c0")
    testing.expect(t, first.x > label(test, "r1c1").x, "the first column is the last now")

    // a press on the edge of a column (to widen it) keeps the selection
    edge: Id = IdFromIndex(1, IdFromString("edge", UiIdPath("window", "table")))
    drag(test, centre(test, edge), centre(test, edge) + {10, 0}, 2)
    testing.expect_value(t, selection(test), before)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
    // a press elsewhere, on a text that is not selected, starts another selection; on nothing, lets it go
    tableFrame(test, {mouse_position = {900, 600}, mouse_down = true, mouse_pressed = true})
    tableFrame(test, {mouse_position = {900, 600}, mouse_released = true})
    testing.expect_value(t, selection(test), "")
}

@(test)
test_a_selection_stays_while_the_scroll_bar_of_its_list_is_dragged :: proc(t: ^testing.T) {
    test: ^RevealTest = new(RevealTest)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    test.list = {selected = VIRTUAL_NONE, text = true}
    UiInit(&test.ctx, &test.storage, measure)
    away: Input = {mouse_position = {-100, -100}}
    for _ in 0 ..< 4 { revealFrame(test, away) }
    point: Vec2
    for command in UiCommands(&test.ctx) {
        info: DrawInfo = command.info
        if command.kind == .DRAW && info.kind == .LABEL && info.text == "row 001 text" { point = {info.rect.x + 1, info.rect.y + info.rect.w * 0.5} }
    }
    // a selection over two rows
    to: Vec2 = point + {0, 20}
    revealFrame(test, {mouse_position = point})
    revealFrame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    revealFrame(test, {mouse_position = to, mouse_down = true})
    revealFrame(test, {mouse_position = to, mouse_released = true})
    revealFrame(test, away)
    selected, _ := UiTextSelected(&test.ctx)
    testing.expect_value(t, selected, "row 001 text\n")
    // the thumb of the bar is held and pulled down: the list scrolls and the selection is not let go
    // (the bar is a strip at the right edge of the list: the thumb is at the top while the list is not scrolled)
    area, found := UiElementRect(&test.ctx, test.list_id)
    testing.expect(t, found && area.z > 0)
    if !found { return }
    grab: Vec2 = {area.x + area.z - 2, area.y + 5}
    revealFrame(test, {mouse_position = grab})
    revealFrame(test, {mouse_position = grab, mouse_down = true, mouse_pressed = true})
    for step in 1 ..= 5 { revealFrame(test, {mouse_position = grab + {0, f32(step) * 12}, mouse_down = true}) }
    revealFrame(test, {mouse_position = grab + {0, 60}, mouse_released = true})
    revealFrame(test, away)
    testing.expect(t, UiScrollGet(&test.ctx, test.list_id) > 100, "the list scrolled by its bar")
    selected, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, selected, "row 001 text\n")
    // a press on nothing else lets it go, as before
    revealFrame(test, {mouse_position = {900, 600}, mouse_down = true, mouse_pressed = true})
    revealFrame(test, {mouse_position = {900, 600}, mouse_released = true})
    selected, _ = UiTextSelected(&test.ctx)
    testing.expect_value(t, selected, "")
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}
