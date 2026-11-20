#+build !js
package ui

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
