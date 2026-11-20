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
