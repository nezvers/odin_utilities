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
