#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(test)
test_marks_are_put_around_a_selection_and_taken_away :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(64, 128, 32, 1024),
        ctx: Context,
        style: Style,
        text: [32]u8,
        length: int,
        area: Id,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    frame :: proc(test: ^Test, input: Input = {mouse_position = {-100, -100}}) {
        UiBegin(&test.ctx, input, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(500), {}}) {
            test.area = UiId(&test.ctx, "Notes")
            UiButton(&test.ctx, "Bold")
            UiTextArea(&test.ctx, "Notes", test.text[:], &test.length, {Fixed(400), Fixed(100)})
        }
        UiEnd(&test.ctx)
    }
    select :: proc(test: ^Test, low: int, high: int) {
        state: ^WidgetState = stateFind(&test.ctx, test.area)
        state.anchor, state.cursor = low, high
    }
    text :: proc(test: ^Test) -> string { return string(test.text[:test.length]) }
    // a widget that was never declared
    testing.expect(t, !UiTextWrap(&test.ctx, 12345, test.text[:], &test.length, "**", "**"))
    _, _, known := UiTextSelectionOf(&test.ctx, 12345)
    testing.expect(t, !known)
    test.length = copy(test.text[:], "one two three")
    frame(test)
    UiFocus(&test.ctx, test.area)
    frame(test)

    // around a selection: the selection stays on its word
    select(test, 4, 7)
    testing.expect(t, UiTextWrap(&test.ctx, test.area, test.text[:], &test.length, "**", "**"))
    testing.expect_value(t, text(test), "one **two** three")
    low, high, found := UiTextSelectionOf(&test.ctx, test.area)
    testing.expect(t, found && low == 6 && high == 9)
    testing.expect_value(t, UiFocused(&test.ctx), test.area)
    frame(test)
    // the same again takes the marks away
    testing.expect(t, UiTextWrap(&test.ctx, test.area, test.text[:], &test.length, "**", "**"))
    testing.expect_value(t, text(test), "one two three")
    low, high, _ = UiTextSelectionOf(&test.ctx, test.area)
    testing.expect(t, low == 4 && high == 7)
    frame(test)
    // undo and redo go through the two changes
    frame(test, {mouse_position = {-100, -100}, actions = {.UNDO}})
    testing.expect_value(t, text(test), "one **two** three")
    frame(test, {mouse_position = {-100, -100}, actions = {.UNDO}})
    testing.expect_value(t, text(test), "one two three")
    frame(test, {mouse_position = {-100, -100}, actions = {.REDO}})
    testing.expect_value(t, text(test), "one **two** three")
    frame(test, {mouse_position = {-100, -100}, actions = {.UNDO}})

    // no selection: the marks around the cursor, the cursor between them; typing goes there
    select(test, 13, 13)
    testing.expect(t, UiTextWrap(&test.ctx, test.area, test.text[:], &test.length, " `", "`"))
    testing.expect_value(t, text(test), "one two three ``")
    low, high, _ = UiTextSelectionOf(&test.ctx, test.area)
    testing.expect(t, low == 15 && high == 15)
    typed: Input = {mouse_position = {-100, -100}}
    typed.text_count = u8(copy(typed.text[:], "x"))
    frame(test, typed)
    testing.expect_value(t, text(test), "one two three `x`")
    // other marks around the same word are not these marks
    select(test, 4, 7)
    testing.expect(t, UiTextWrap(&test.ctx, test.area, test.text[:], &test.length, "*", "*"))
    testing.expect_value(t, text(test), "one *two* three `x`")
    // no room: nothing changes
    select(test, 0, 3)
    before: int = test.length
    testing.expect(t, !UiTextWrap(&test.ctx, test.area, test.text[:], &test.length, "[[[[[[[", "]]]]]]]"))
    testing.expect_value(t, test.length, before)
    testing.expect_value(t, text(test), "one *two* three `x`")
}

@(test)
test_a_mark_at_the_start_of_the_line_of_the_cursor :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(64, 128, 32, 1024),
        ctx: Context,
        style: Style,
        text: [32]u8,
        length: int,
        area: Id,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    frame :: proc(test: ^Test) {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(500), {}}) {
            test.area = UiId(&test.ctx, "Notes")
            UiTextArea(&test.ctx, "Notes", test.text[:], &test.length, {Fixed(400), Fixed(100)})
        }
        UiEnd(&test.ctx)
    }
    test.length = copy(test.text[:], "first\nsecond\nthird")
    frame(test)
    state: ^WidgetState = stateFind(&test.ctx, test.area)
    // the cursor in "second", after "sec"
    state.anchor, state.cursor = 9, 9
    testing.expect(t, UiTextLinePrefix(&test.ctx, test.area, test.text[:], &test.length, "- "))
    testing.expect_value(t, string(test.text[:test.length]), "first\n- second\nthird")
    testing.expect_value(t, state.cursor, 11)                   // still after "sec"
    // another mark on the same line is put before it; the first one again takes itself away only when the line starts with it
    testing.expect(t, UiTextLinePrefix(&test.ctx, test.area, test.text[:], &test.length, "> "))
    testing.expect_value(t, string(test.text[:test.length]), "first\n> - second\nthird")
    testing.expect(t, UiTextLinePrefix(&test.ctx, test.area, test.text[:], &test.length, "> "))
    testing.expect_value(t, string(test.text[:test.length]), "first\n- second\nthird")
    testing.expect(t, UiTextLinePrefix(&test.ctx, test.area, test.text[:], &test.length, "- "))
    testing.expect_value(t, string(test.text[:test.length]), "first\nsecond\nthird")
    testing.expect_value(t, state.cursor, 9)
    // the first line, the cursor at its start; the last line, the cursor at the end of the text
    state.anchor, state.cursor = 0, 0
    testing.expect(t, UiTextLinePrefix(&test.ctx, test.area, test.text[:], &test.length, "# "))
    testing.expect_value(t, string(test.text[:test.length]), "# first\nsecond\nthird")
    testing.expect_value(t, state.cursor, 2)
    state.anchor, state.cursor = test.length, test.length
    testing.expect(t, UiTextLinePrefix(&test.ctx, test.area, test.text[:], &test.length, "1. "))
    testing.expect_value(t, string(test.text[:test.length]), "# first\nsecond\n1. third")
    testing.expect_value(t, state.cursor, test.length)
    // a cursor inside of the mark that is taken away goes to the start of the line
    state.anchor, state.cursor = 16, 16
    testing.expect(t, UiTextLinePrefix(&test.ctx, test.area, test.text[:], &test.length, "1. "))
    testing.expect_value(t, string(test.text[:test.length]), "# first\nsecond\nthird")
    testing.expect_value(t, state.cursor, 15)
    testing.expect(t, !UiTextLinePrefix(&test.ctx, test.area, test.text[:], &test.length, ""))
    testing.expect(t, !UiTextLinePrefix(&test.ctx, test.area, test.text[:], &test.length, "0123456789012345678901234567890"))
}

@(test)
test_text_is_inserted_at_the_cursor_over_the_selection_and_the_cursor_goes_after_it :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(64, 128, 32, 1024),
        ctx: Context,
        style: Style,
        text: [16]u8,
        length: int,
        field: Id,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    frame :: proc(test: ^Test) {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(500), {}}) {
            test.field = UiId(&test.ctx, "Message")
            UiTextField(&test.ctx, "Message", test.text[:], &test.length, {Fixed(300), {}})
        }
        UiEnd(&test.ctx)
    }
    text :: proc(test: ^Test) -> string { return string(test.text[:test.length]) }
    testing.expect(t, !UiTextInsert(&test.ctx, 999, test.text[:], &test.length, "x"), "a widget that was never declared")
    test.length = copy(test.text[:], "hello world")
    frame(test)
    state: ^WidgetState = stateFind(&test.ctx, test.field)
    state.cursor, state.anchor = 5, 5
    testing.expect(t, UiTextInsert(&test.ctx, test.field, test.text[:], &test.length, ":x:"))
    testing.expect_value(t, text(test), "hello:x: world")
    testing.expect_value(t, [2]int{state.cursor, state.anchor}, [2]int{8, 8})
    testing.expect_value(t, test.ctx.focus, test.field)
    // twice: the second goes after the first
    testing.expect(t, UiTextInsert(&test.ctx, test.field, test.text[:], &test.length, "!"))
    testing.expect_value(t, text(test), "hello:x:! world")
    // over a selection
    state.anchor, state.cursor = 9, 15
    testing.expect(t, UiTextInsert(&test.ctx, test.field, test.text[:], &test.length, "?"))
    testing.expect_value(t, text(test), "hello:x:!?")
    // no room: nothing changes
    testing.expect(t, !UiTextInsert(&test.ctx, test.field, test.text[:], &test.length, "123456789"))
    testing.expect_value(t, text(test), "hello:x:!?")
}
