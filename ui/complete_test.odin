#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(test)
test_the_word_to_complete_starts_at_a_trigger :: proc(t: ^testing.T) {
    query, start, found := CompleteQuery("see @ma", 7, '@')
    testing.expect(t, found && query == "ma" && start == 5)
    query, start, found = CompleteQuery("@", 1, '@')
    testing.expect(t, found && query == "" && start == 1)
    query, _, found = CompleteQuery("see @main.odin now", 9, '@')
    testing.expect(t, found && query == "main", "up to the caret, not to the end of the word")
    _, _, found = CompleteQuery("see @main now", 13, '@')
    testing.expect(t, !found, "a space ends the word")
    _, _, found = CompleteQuery("mail name@host", 14, '@')
    testing.expect(t, !found, "a trigger inside of a word is a letter")
    _, _, found = CompleteQuery("line\n@x", 7, '@')
    testing.expect(t, found)
    _, _, found = CompleteQuery("", 0, '@')
    testing.expect(t, !found)
    _, _, found = CompleteQuery("plain", 5, '@')
    testing.expect(t, !found)
    query, _, found = CompleteQuery("a #tag", 6, '#')
    testing.expect(t, found && query == "tag")
    testing.expect(t, completeContains("Main.odin", "main") && completeContains("ui/README.md", "read") && completeContains("x", "") && !completeContains("ab", "abc") && !completeContains("layout", "x"))
}

@(test)
test_a_completion_list_writes_the_item_in :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 2048),
        ctx: Context,
        style: Style,
        text: [64]u8,
        length: int,
        area: Id,
        inserted: int,
        item: int,
    }
    FILES: [5]string = {"main.odin", "layout.odin", "README.md", "markdown.odin", "render.odin"}
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    frame :: proc(test: ^Test, input: Input) {
        files: [5]string = {"main.odin", "layout.odin", "README.md", "markdown.odin", "render.odin"}
        UiBegin(&test.ctx, input, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(500), {}}) {
            // something above the area: the list is placed by where the area is
            ElementOpen(&test.ctx, {layout = {size = {Fixed(10), Fixed(200)}}})
            ElementClose(&test.ctx)
            test.area = UiId(&test.ctx, "Message")
            inserted, item := UiComplete(&test.ctx, "Message", test.text[:], &test.length, files[:])
            if inserted {
                test.inserted += 1
                test.item = item
            }
            UiTextArea(&test.ctx, "Message", test.text[:], &test.length, {Fixed(400), Fixed(100)})
        }
        UiEnd(&test.ctx)
    }
    away: Input = {mouse_position = {-100, -100}}
    type :: proc(test: ^Test, text: string) {
        input: Input = {mouse_position = {-100, -100}}
        input.text_count = u8(copy(input.text[:], text))
        frame(test, input)
        frame(test, {mouse_position = {-100, -100}})
    }
    rows :: proc(test: ^Test) -> (count: int, selected: string, first: Rect) {
        for command in UiCommands(&test.ctx) {
            if command.kind != .DRAW || command.info.kind != .DROPDOWN_ITEM { continue }
            if count == 0 { first = command.info.rect }
            count += 1
            if .SELECTED in command.info.flags { selected = command.info.name }
        }
        return
    }
    frame(test, away)
    UiFocus(&test.ctx, test.area)
    frame(test, away)
    type(test, "see ")
    count, _, _ := rows(test)
    testing.expect_value(t, count, 0)
    // the trigger: every item is offered, the first is chosen, the list is under the caret
    type(test, "@")
    selected: string
    first: Rect
    count, selected, first = rows(test)
    testing.expect_value(t, count, 5)
    testing.expect_value(t, selected, "main.odin")
    area, _ := UiElementRect(&test.ctx, test.area)
    testing.expect(t, area.y >= 200)
    testing.expect(t, first.y > area.y + DEFAULT_METRICS.font_size && first.y < area.y + 60 && first.x > area.x + DEFAULT_METRICS.font_size * 2 && first.x < area.x + 100, "under the caret, after the typed text")
    // typing narrows the list: the items that have the letters in them
    type(test, "ma")
    count, selected, _ = rows(test)
    testing.expect_value(t, count, 2)
    testing.expect_value(t, selected, "main.odin")
    // the arrows choose and go round, the caret of the area stays in its row
    frame(test, {mouse_position = {-100, -100}, actions = {.DOWN}})
    frame(test, away)
    _, selected, _ = rows(test)
    testing.expect_value(t, selected, "markdown.odin")
    frame(test, {mouse_position = {-100, -100}, actions = {.DOWN}})
    frame(test, away)
    _, selected, _ = rows(test)
    testing.expect_value(t, selected, "main.odin")
    frame(test, {mouse_position = {-100, -100}, actions = {.UP}})
    // Enter writes the item in, with a space, and breaks no line
    frame(test, {mouse_position = {-100, -100}, keys = {.ENTER}})
    testing.expect_value(t, string(test.text[:test.length]), "see @markdown.odin ")
    testing.expect_value(t, test.inserted, 1)
    testing.expect_value(t, FILES[test.item], "markdown.odin")
    frame(test, away)
    count, _, _ = rows(test)
    testing.expect_value(t, count, 0)
    testing.expect_value(t, UiFocused(&test.ctx), test.area)

    // Escape closes the list for this word and keeps the focus in the area; a new word opens it again
    type(test, "@re")
    count, _, _ = rows(test)
    testing.expect_value(t, count, 2)                           // README.md, render.odin
    frame(test, {mouse_position = {-100, -100}, keys = {.ESCAPE}, actions = {.CANCEL}})
    frame(test, away)
    count, _, _ = rows(test)
    testing.expect_value(t, count, 0)
    testing.expect_value(t, UiFocused(&test.ctx), test.area)
    type(test, "n")
    count, _, _ = rows(test)
    testing.expect_value(t, count, 0)
    type(test, " @lay")
    count, selected, first = rows(test)
    testing.expect_value(t, count, 1)
    // a click on a row writes it in and the focus stays in the area
    point: Vec2 = {first.x + first.z * 0.5, first.y + first.w * 0.5}
    frame(test, {mouse_position = point})
    frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = point, mouse_released = true})
    frame(test, away)
    testing.expect_value(t, string(test.text[:test.length]), "see @markdown.odin @ren @layout.odin ")
    testing.expect_value(t, test.inserted, 2)
    testing.expect_value(t, UiFocused(&test.ctx), test.area)
    // nothing matches: no list, Enter is a new line of the area
    type(test, "@zzz")
    count, _, _ = rows(test)
    testing.expect_value(t, count, 0)
    before: int = test.length
    frame(test, {mouse_position = {-100, -100}, keys = {.ENTER}})
    testing.expect_value(t, test.length, before + 1)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_a_completion_list_of_a_text_field_and_its_undo :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 2048),
        ctx: Context,
        style: Style,
        text: [64]u8,
        length: int,
        field: Id,
        other: Id,
        submits: int,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    frame :: proc(test: ^Test, input: Input) {
        names: [3]string = {"Ada", "Alan", "Grace"}
        UiBegin(&test.ctx, input, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(500), {}}) {
            test.other = UiId(&test.ctx, "Above")
            UiButton(&test.ctx, "Above")
            test.field = UiId(&test.ctx, "To")
            UiComplete(&test.ctx, "To", test.text[:], &test.length, names[:])
            _, submitted := UiTextField(&test.ctx, "To", test.text[:], &test.length, {Fixed(300), {}})
            if submitted { test.submits += 1 }
            UiButton(&test.ctx, "Below")
        }
        UiEnd(&test.ctx)
    }
    away: Input = {mouse_position = {-100, -100}}
    type :: proc(test: ^Test, text: string) {
        input: Input = {mouse_position = {-100, -100}}
        input.text_count = u8(copy(input.text[:], text))
        frame(test, input)
        frame(test, {mouse_position = {-100, -100}})
    }
    selected :: proc(test: ^Test) -> (name: string, count: int, first: Rect) {
        for command in UiCommands(&test.ctx) {
            if command.kind != .DRAW || command.info.kind != .DROPDOWN_ITEM { continue }
            if count == 0 { first = command.info.rect }
            count += 1
            if .SELECTED in command.info.flags { name = command.info.name }
        }
        return
    }
    frame(test, away)
    UiFocus(&test.ctx, test.field)
    frame(test, away)
    type(test, "hi ")
    type(test, "@a")
    name, count, first := selected(test)
    testing.expect_value(t, count, 3)                           // Ada, Alan, Grace: all have the letter
    testing.expect_value(t, name, "Ada")
    field, _ := UiElementRect(&test.ctx, test.field)
    testing.expect(t, first.y >= field.y + field.w - 1 && first.x > field.x + DEFAULT_METRICS.font_size, "under the field, at the caret")
    // down chooses in the list: the focus does not go to the button below
    frame(test, {mouse_position = {-100, -100}, actions = {.DOWN}})
    frame(test, away)
    name, _, _ = selected(test)
    testing.expect_value(t, name, "Alan")
    testing.expect_value(t, UiFocused(&test.ctx), test.field)
    // Enter writes the name in and does not submit the field
    frame(test, {mouse_position = {-100, -100}, keys = {.ENTER}, actions = {.ACCEPT}})
    testing.expect_value(t, string(test.text[:test.length]), "hi @Alan ")
    testing.expect_value(t, test.submits, 0)
    frame(test, away)
    // undo gives the typed word back, redo the name
    frame(test, {mouse_position = {-100, -100}, actions = {.UNDO}})
    testing.expect_value(t, string(test.text[:test.length]), "hi @a")
    frame(test, {mouse_position = {-100, -100}, actions = {.REDO}})
    testing.expect_value(t, string(test.text[:test.length]), "hi @Alan ")
    frame(test, away)
    // the list is closed: Enter submits, and up moves the focus again
    _, count, _ = selected(test)
    testing.expect_value(t, count, 0)
    frame(test, {mouse_position = {-100, -100}, keys = {.ENTER}})
    testing.expect_value(t, test.submits, 1)
    frame(test, away)
    frame(test, {mouse_position = {-100, -100}, actions = {.UP}})
    frame(test, away)
    testing.expect_value(t, UiFocused(&test.ctx), test.other)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_the_completion_list_stands_above_the_caret_where_it_does_not_fit_below :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 2048),
        ctx: Context,
        style: Style,
        text: [64]u8,
        length: int,
        area: Id,
        top: f32,                   // where the window is
        screen: Vec2,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    frame :: proc(test: ^Test, input: Input) {
        files: [5]string = {"main.odin", "layout.odin", "README.md", "markdown.odin", "render.odin"}
        UiBegin(&test.ctx, input, 1.0 / 60, test.screen, &test.style)
        if UiWindow(&test.ctx, "window", {0, test.top}, {Fixed(500), {}}) {
            test.area = UiId(&test.ctx, "Message")
            UiComplete(&test.ctx, "Message", test.text[:], &test.length, files[:])
            UiTextArea(&test.ctx, "Message", test.text[:], &test.length, {Fixed(400), Fixed(60)})
        }
        UiEnd(&test.ctx)
    }
    rows :: proc(test: ^Test) -> (count: int, top: f32, bottom: f32) {
        top = 1e9
        for command in UiCommands(&test.ctx) {
            if command.kind != .DRAW || command.info.kind != .DROPDOWN_ITEM { continue }
            count += 1
            top = min(top, command.info.rect.y)
            bottom = max(bottom, command.info.rect.y + command.info.rect.w)
        }
        return
    }
    open :: proc(test: ^Test) {
        away: Input = {mouse_position = {-100, -100}}
        for _ in 0 ..< 3 { frame(test, away) }
        UiFocus(&test.ctx, test.area)
        frame(test, away)
        input: Input = away
        input.text_count = u8(copy(input.text[:], "@"))
        frame(test, input)
        frame(test, away)
        frame(test, away)
    }
    // plenty of room below: the list is below the row of the caret, as before
    test.screen, test.top = {800, 600}, 100
    open(test)
    area, _ := UiElementRect(&test.ctx, test.area)
    count, top, bottom := rows(test)
    testing.expect_value(t, count, 5)
    testing.expect(t, top >= area.y + DEFAULT_METRICS.font_size, "below the caret")
    // the window is low on the screen: the list would end below it, so it stands above the row of the caret and inside of the screen
    test.length = 0
    UiTextSelectionClear(&test.ctx)
    test.screen, test.top = {800, 600}, 540
    open(test)
    area, _ = UiElementRect(&test.ctx, test.area)
    count, top, bottom = rows(test)
    testing.expect_value(t, count, 5)
    testing.expect(t, bottom <= area.y + DEFAULT_METRICS.padding.y + 1 && top >= 0, "above the row of the caret, inside of the screen")
    testing.expect(t, bottom - top >= f32(count) * DEFAULT_METRICS.control_height - 1, "the rows are all there")
    // no room above either (a tall list in a short screen): it stays below, where there is more of it to see
    test.length = 0
    test.screen, test.top = {800, 120}, 40
    open(test)
    area, _ = UiElementRect(&test.ctx, test.area)
    count, top, bottom = rows(test)
    testing.expect(t, count >= 1, "the rows that are on the screen are drawn")
    testing.expect(t, top >= area.y + DEFAULT_METRICS.font_size, "below the caret when there is no room above")
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_the_items_of_a_completion_list_are_ranked_and_tell_the_style_what_matched :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 2048),
        ctx: Context,
        style: Style,
        text: [64]u8,
        length: int,
        area: Id,
        items: []string,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    frame :: proc(test: ^Test, input: Input) {
        UiBegin(&test.ctx, input, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(500), {}}) {
            test.area = UiId(&test.ctx, "Message")
            UiComplete(&test.ctx, "Message", test.text[:], &test.length, test.items)
            UiTextArea(&test.ctx, "Message", test.text[:], &test.length, {Fixed(400), Fixed(100)})
        }
        UiEnd(&test.ctx)
    }
    away: Input = {mouse_position = {-100, -100}}
    type :: proc(test: ^Test, text: string) {
        input: Input = {mouse_position = {-100, -100}}
        input.text_count = u8(copy(input.text[:], text))
        frame(test, input)
        frame(test, {mouse_position = {-100, -100}})
    }
    Row :: struct { name: string, from: int, to: int }
    rows :: proc(test: ^Test) -> (result: [COMPLETE_ROWS]Row, count: int) {
        for command in UiCommands(&test.ctx) {
            if command.kind != .DRAW || command.info.kind != .DROPDOWN_ITEM || count == COMPLETE_ROWS { continue }
            result[count] = {command.info.name, command.info.cursor, command.info.anchor}
            count += 1
        }
        return
    }
    // a prefix first, the start of a part next (after an underscore, a dot), then the rest: each in the order of the items
    test.items = {"format.odin", "main.odin", "go_main", "mark.md", "Domain", "a.Main"}
    for _ in 0 ..< 3 { frame(test, away) }
    UiFocus(&test.ctx, test.area)
    frame(test, away)
    type(test, "@")
    list, count := rows(test)
    testing.expect_value(t, count, 6)
    testing.expect(t, list[0].name == "format.odin" && list[0].from == 0 && list[0].to == 0, "no word: all of them in order, nothing marked")
    type(test, "ma")
    list, count = rows(test)
    testing.expect_value(t, count, 6)
    expected: [6]Row = {{"main.odin", 0, 2}, {"mark.md", 0, 2}, {"go_main", 3, 5}, {"a.Main", 2, 4}, {"format.odin", 3, 5}, {"Domain", 2, 4}}
    for want, i in expected {
        testing.expectf(t, list[i] == want, "row %d is %v, not %v", i, list[i], want)
    }
    // the first of the items is not the first of the list when an item that starts with the word comes later: more than the rows there are
    many: [12]string = {"xma0", "xma1", "xma2", "xma3", "xma4", "xma5", "xma6", "xma7", "xma8", "xma9", "ma_late", "Ma_last"}
    test.items = many[:]
    test.length = 0
    UiTextSelectionClear(&test.ctx)
    type(test, "@ma")
    list, count = rows(test)
    testing.expect_value(t, count, COMPLETE_ROWS)
    testing.expect(t, list[0].name == "ma_late" && list[1].name == "Ma_last" && list[2].name == "xma0", "the prefix matches come first, also from the end of the items")
    testing.expect(t, list[0].from == 0 && list[0].to == 2 && list[2].from == 1 && list[2].to == 3)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}
