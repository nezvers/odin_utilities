#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(test)
test_rich_text_is_read_piece_by_piece :: proc(t: ^testing.T) {
    Expected :: struct { text: string, marks: RichMarks, space_before: bool }
    check :: proc(t: ^testing.T, source: string, expected: []Expected) {
        cursor: RichCursor
        for want, i in expected {
            token, ok := RichNext(source, &cursor)
            testing.expectf(t, ok, "%q: piece %d is there", source, i)
            testing.expectf(t, token.text == want.text && token.marks == want.marks && token.space_before == want.space_before, "%q: piece %d is %v", source, i, token)
        }
        _, more := RichNext(source, &cursor)
        testing.expectf(t, !more, "%q: the end", source)
    }
    check(t, "", {})
    check(t, "  \n ", {})
    check(t, "two words", {{"two", {}, false}, {"words", {}, true}})
    check(t, "a **strong** b", {{"a", {}, false}, {"strong", {.STRONG}, true}, {"b", {}, true}})
    check(t, "__strong__ and _italic_", {{"strong", {.STRONG}, false}, {"and", {}, true}, {"italic", {.ITALIC}, true}})
    check(t, "***both***", {{"both", {.STRONG, .ITALIC}, false}})
    // a mark in the middle of a word cuts it into pieces with no space between
    check(t, "**bold**, then", {{"bold", {.STRONG}, false}, {",", {}, false}, {"then", {}, true}})
    check(t, "snake_case_name", {{"snake_case_name", {}, false}})
    // nothing is a mark inside of code
    check(t, "`a*b _c_` d", {{"a*b", {.CODE}, false}, {"_c_", {.CODE}, true}, {"d", {}, true}})
    check(t, "see [the docs](http://a_b/c) now", {{"see", {}, false}, {"the", {.LINK}, true}, {"docs", {.LINK}, true}, {"now", {}, true}})
    {
        cursor: RichCursor
        _, _ = RichNext("see [the docs](http://a_b/c) now", &cursor)
        token, _ := RichNext("see [the docs](http://a_b/c) now", &cursor)
        testing.expect_value(t, token.address, "http://a_b/c")
        _, _ = RichNext("see [the docs](http://a_b/c) now", &cursor)
        token, _ = RichNext("see [the docs](http://a_b/c) now", &cursor)
        testing.expect_value(t, token.address, "")
    }
    check(t, "[**strong** link](x).", {{"strong", {.LINK, .STRONG}, false}, {"link", {.LINK}, true}, {".", {}, false}})
    check(t, "a [bracket] alone", {{"a", {}, false}, {"[bracket]", {}, true}, {"alone", {}, true}})
    check(t, "open [link(", {{"open", {}, false}, {"[link(", {}, true}})
    check(t, "2 \\* 3", {{"2", {}, false}, {"*", {}, true}, {"3", {}, true}})
    check(t, "~~gone~~ here", {{"gone", {}, false}, {"here", {}, true}})
    check(t, "line\r\nend", {{"line", {}, false}, {"end", {}, true}})
}

@(test)
test_rich_text_is_lines_of_runs_in_their_styles :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 4096),
        ctx: Context,
        style: Style,
        narrow: Id,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    find :: proc(ctx: ^Context, text: string) -> (info: DrawInfo, found: bool) {
        for command in UiCommands(ctx) {
            if command.kind == .DRAW && command.info.kind == .LABEL && command.info.text == text { return command.info, true }
        }
        return
    }
    for frame in 0 ..< 3 {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {1200, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(1000), {}}) {
            UiRichText(&test.ctx, "wide", "plain **strong words** and `code` with a [link here](address), end")
            test.narrow = UiId(&test.ctx, "narrow")
            ElementOpen(&test.ctx, {id = test.narrow, layout = {size = {Fixed(DEFAULT_METRICS.font_size * 3.5), Fit()}, direction = .TOP_TO_BOTTOM}})
            UiRichText(&test.ctx, "wrapped", "aaaa **bbbb** cccc dddd *eeee* ffff")
            ElementClose(&test.ctx)
        }
        UiEnd(&test.ctx)
        if frame == 0 {
            // before the paragraph knows its width it is a text without its marks
            _, plain := find(&test.ctx, "plain strong words and code with a link here, end")
            testing.expect(t, plain, "the first frame is plain")
        }
    }
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
    // the runs: a space between two styles is in the plain one, never in a link or in code
    first, first_found := find(&test.ctx, "plain ")
    strong, strong_found := find(&test.ctx, "strong words")
    code, code_found := find(&test.ctx, "code")
    link, link_found := find(&test.ctx, "link here")
    end, end_found := find(&test.ctx, ", end")
    testing.expect(t, first_found && strong_found && code_found && link_found && end_found, "the runs are there")
    testing.expect(t, !DrawInfoHasTag(&first, "strong") && DrawInfoHasTag(&strong, "strong") && DrawInfoHasTag(&code, "mono") && DrawInfoHasTag(&link, "link") && !DrawInfoHasTag(&end, "link"))
    testing.expect(t, first.rect.y == strong.rect.y && strong.rect.y == end.rect.y, "one line")
    testing.expect(t, strong.rect.x >= first.rect.x + first.rect.z - 0.5 && link.rect.x > code.rect.x && end.rect.x >= link.rect.x + link.rect.z - 0.5, "one after the other")
    // the narrow one: 7 letters wide, a word and a half fit: every word has a line, in its style, inside of the box
    box, box_found := UiElementRect(&test.ctx, test.narrow)
    testing.expect(t, box_found)
    words: [6]string = {"aaaa", "bbbb", "cccc", "dddd", "eeee", "ffff"}
    last_y: f32 = -1
    for word, i in words {
        info, found := find(&test.ctx, word)
        testing.expectf(t, found, "%s is drawn", word)
        testing.expectf(t, info.rect.y > last_y, "%s is on a line of its own", word)
        testing.expect(t, info.rect.x >= box.x - 0.5 && info.rect.x + info.rect.z <= box.x + box.z + 0.5, "inside of the box")
        testing.expect(t, DrawInfoHasTag(&info, "strong") == (i == 1) && DrawInfoHasTag(&info, "italic") == (i == 4))
        last_y = info.rect.y
    }
    testing.expect(t, box.w >= DEFAULT_METRICS.font_size * 6, "the box grew to its six lines")
}

@(test)
test_a_link_of_a_rich_text_is_clicked :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 4096),
        ctx: Context,
        style: Style,
        address: string,
        clicks: int,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    SOURCE :: "go to [the first](one.md) or [the second](two.md) or\n\n- an entry with [a third](three.md)"
    frame :: proc(test: ^Test, input: Input) {
        UiBegin(&test.ctx, input, 1.0 / 60, {1200, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(1000), {}}) {
            address, clicked := UiMarkdown(&test.ctx, SOURCE)
            if clicked {
                test.address = address
                test.clicks += 1
            }
        }
        UiEnd(&test.ctx)
    }
    center :: proc(ctx: ^Context, text: string) -> (point: Vec2, hot: bool) {
        for command in UiCommands(ctx) {
            info: DrawInfo = command.info
            if command.kind == .DRAW && info.kind == .LABEL && info.text == text && DrawInfoHasTag(&info, "link") {
                return {info.rect.x + info.rect.z * 0.5, info.rect.y + info.rect.w * 0.5}, DrawInfoHasTag(&info, "hover")
            }
        }
        return {-1, -1}, false
    }
    click :: proc(test: ^Test, text: string) {
        point, _ := center(&test.ctx, text)
        frame(test, {mouse_position = point})
        frame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
        frame(test, {mouse_position = point, mouse_released = true})
        frame(test, {mouse_position = {-100, -100}})
    }
    for _ in 0 ..< 3 { frame(test, {mouse_position = {-100, -100}}) }
    testing.expect_value(t, test.clicks, 0)
    // the pointer over a link: it is shown as hot and the cursor is the hand
    point, hot := center(&test.ctx, "the second")
    testing.expect(t, point.x > 0 && !hot)
    frame(test, {mouse_position = point})
    frame(test, {mouse_position = point})
    _, hot = center(&test.ctx, "the second")
    testing.expect(t, hot, "the link under the pointer is hot")
    testing.expect_value(t, UiCursor(&test.ctx), Cursor.HAND)
    _, hot = center(&test.ctx, "the first")
    testing.expect(t, !hot, "the other one is not")
    click(test, "the second")
    testing.expect_value(t, test.clicks, 1)
    testing.expect_value(t, test.address, "two.md")
    click(test, "the first")
    testing.expect_value(t, test.address, "one.md")
    click(test, "a third")
    testing.expect_value(t, test.address, "three.md")
    testing.expect_value(t, test.clicks, 3)
    // a click on plain text is no click
    frame(test, {mouse_position = {40, 40}, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = {40, 40}, mouse_released = true})
    testing.expect_value(t, test.clicks, 3)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_a_rich_text_breaks_again_when_its_room_changes :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 4096),
        ctx: Context,
        style: Style,
        box: Id,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    frame :: proc(test: ^Test, width: f32) {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {1200, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(1000), {}}) {
            test.box = UiId(&test.ctx, "box")
            ElementOpen(&test.ctx, {id = test.box, layout = {size = {Fixed(width), Fit()}, direction = .TOP_TO_BOTTOM}})
            UiRichText(&test.ctx, "text", "aaaa **bbbb** cccc dddd")
            ElementClose(&test.ctx)
        }
        UiEnd(&test.ctx)
    }
    lines :: proc(test: ^Test) -> (count: int, widest: f32) {
        last_y: f32 = -1
        box, _ := UiElementRect(&test.ctx, test.box)
        for command in UiCommands(&test.ctx) {
            if command.kind != .DRAW || command.info.kind != .LABEL { continue }
            if command.info.rect.y > last_y {
                count += 1
                last_y = command.info.rect.y
            }
            widest = max(widest, command.info.rect.x + command.info.rect.z - box.x)
        }
        return
    }
    size: f32 = DEFAULT_METRICS.font_size
    for _ in 0 ..< 4 { frame(test, size * 20) }
    count, widest := lines(test)
    testing.expect_value(t, count, 1)
    // narrower: after a frame or two the lines are broken for the new width
    for _ in 0 ..< 4 { frame(test, size * 3.5) }
    count, widest = lines(test)
    testing.expect_value(t, count, 4)
    testing.expect(t, widest <= size * 3.5 + 0.5, "inside of the narrow box")
    // and wider again
    for _ in 0 ..< 4 { frame(test, size * 20) }
    count, _ = lines(test)
    testing.expect_value(t, count, 1)
}

@(test)
test_a_rich_text_with_a_width_limit_is_as_wide_as_its_text :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 4096),
        ctx: Context,
        style: Style,
        short, long: Id,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    size: f32 = DEFAULT_METRICS.font_size
    // already in the first frame: the width does not come from the frame before
    UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {1200, 600}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(1000), {}}) {
        test.short, test.long = UiId(&test.ctx, "short"), UiId(&test.ctx, "long")
        UiRichText(&test.ctx, "short", "aaaa **bbbb**", 1, size * 10)
        UiRichText(&test.ctx, "long", "aaaa bbbb cccc dddd eeee ffff", 1, size * 5)
    }
    UiEnd(&test.ctx)
    short, short_found := UiElementRect(&test.ctx, test.short)
    long, long_found := UiElementRect(&test.ctx, test.long)
    testing.expect(t, short_found && long_found)
    testing.expect_value(t, short.z, size * 4.5)                // nine letters: the text, not the limit and not the window
    testing.expect_value(t, short.w, size)
    testing.expect_value(t, long.z, size * 4.5)                 // two words a line
    testing.expect_value(t, long.w, size * 3)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_a_rich_text_breaks_its_lines_only_at_spaces :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 4096),
        ctx: Context,
        style: Style,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    size: f32 = DEFAULT_METRICS.font_size
    for _ in 0 ..< 3 {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {1200, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(1000), {}}) {
            // nine and a half letters fit: "aaaa bbbb" would, the comma after it would not
            ElementOpen(&test.ctx, {layout = {size = {Fixed(size * 4.75), Fit()}, direction = .TOP_TO_BOTTOM}})
            UiRichText(&test.ctx, "text", "aaaa **bbbb**, cccc re*lat*ly")
            ElementClose(&test.ctx)
        }
        UiEnd(&test.ctx)
    }
    find :: proc(ctx: ^Context, text: string) -> (info: DrawInfo, found: bool) {
        for command in UiCommands(ctx) {
            if command.kind == .DRAW && command.info.kind == .LABEL && command.info.text == text { return command.info, true }
        }
        return
    }
    first, first_found := find(&test.ctx, "aaaa")
    strong, strong_found := find(&test.ctx, "bbbb")
    comma, comma_found := find(&test.ctx, ",")
    last, last_found := find(&test.ctx, "cccc")
    testing.expect(t, first_found && strong_found && comma_found && last_found, "the pieces are drawn")
    testing.expect(t, strong.rect.y > first.rect.y, "the strong word went to the next line with its comma")
    testing.expect(t, comma.rect.y == strong.rect.y && comma.rect.x >= strong.rect.x + strong.rect.z - 0.5, "the comma stands after its word")
    testing.expect(t, last.rect.y > comma.rect.y)
    // a word with a style change inside of it is one word
    head, head_found := find(&test.ctx, "re")
    middle, middle_found := find(&test.ctx, "lat")
    tail, tail_found := find(&test.ctx, "ly")
    testing.expect(t, head_found && middle_found && tail_found)
    testing.expect(t, head.rect.y == middle.rect.y && middle.rect.y == tail.rect.y && head.rect.y > last.rect.y, "the three pieces of the word are on one line")
}
