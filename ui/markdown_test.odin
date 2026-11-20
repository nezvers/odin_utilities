#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(private = "file")
SAMPLE :: "# Title\n\nA paragraph that goes\nover two lines.\n\n## Lists\n- one\n- two\n  - nested\n1. first\n2. second\n\n> a quote\n> that goes on\n\n```\ncode line\n  indented\n```\n\n---\nlast"

@(test)
test_markdown_is_read_block_by_block :: proc(t: ^testing.T) {
    Expected :: struct { kind: MarkdownKind, level: int, marker: string, text: string }
    expected: [12]Expected = {
        {.HEADING, 1, "", "Title"},
        {.PARAGRAPH, 0, "", "A paragraph that goes\nover two lines."},
        {.HEADING, 2, "", "Lists"},
        {.BULLET, 0, "-", "one"},
        {.BULLET, 0, "-", "two"},
        {.BULLET, 1, "-", "nested"},
        {.ORDERED, 0, "1.", "first"},
        {.ORDERED, 0, "2.", "second"},
        {.QUOTE, 0, "", "> a quote\n> that goes on"},
        {.CODE, 0, "", "code line\n  indented"},
        {.RULE, 0, "", ""},
        {.PARAGRAPH, 0, "", "last"},
    }
    cursor: int
    for want, i in expected {
        block, next, ok := MarkdownNext(SAMPLE, cursor)
        testing.expectf(t, ok, "block %d is there", i)
        testing.expectf(t, block.kind == want.kind && block.level == want.level && block.marker == want.marker && block.text == want.text, "block %d: %v", i, block)
        cursor = next
    }
    _, _, more := MarkdownNext(SAMPLE, cursor)
    testing.expect(t, !more, "the end of the text")

    // nothing, only empty lines, a fence that is never closed, Windows line ends, a hash without a space
    _, _, any := MarkdownNext("", 0)
    testing.expect(t, !any)
    _, _, any = MarkdownNext("\n\n  \n", 0)
    testing.expect(t, !any)
    block, next, ok := MarkdownNext("```\nopen\nstill open", 0)
    testing.expect(t, ok && block.kind == .CODE && block.text == "open\nstill open")
    _, _, any = MarkdownNext("```\nopen\nstill open", next)
    testing.expect(t, !any)
    block, _, ok = MarkdownNext("## Windows\r\n\r\ntext\r\n", 0)
    testing.expect(t, ok && block.kind == .HEADING && block.text == "Windows")
    block, _, ok = MarkdownNext("#hashtag is text", 0)
    testing.expect(t, ok && block.kind == .PARAGRAPH && block.text == "#hashtag is text")
    block, _, ok = MarkdownNext("####### seven is text", 0)
    testing.expect(t, ok && block.kind == .PARAGRAPH)
    block, _, ok = MarkdownNext("***", 0)
    testing.expect(t, ok && block.kind == .RULE)
    block, _, ok = MarkdownNext("12. twelve", 0)
    testing.expect(t, ok && block.kind == .ORDERED && block.marker == "12." && block.text == "twelve")
    block, _, ok = MarkdownNext("-not a list", 0)
    testing.expect(t, ok && block.kind == .PARAGRAPH)
    // a paragraph ends where a list starts
    block, next, ok = MarkdownNext("text\n- item", 0)
    testing.expect(t, ok && block.kind == .PARAGRAPH && block.text == "text")
    block, _, ok = MarkdownNext("text\n- item", next)
    testing.expect(t, ok && block.kind == .BULLET && block.text == "item")
}

@(test)
test_markdown_marks_inside_of_a_line_are_taken_away :: proc(t: ^testing.T) {
    buffer: [128]u8
    testing.expect_value(t, MarkdownInline("plain", buffer[:]), "plain")
    testing.expect_value(t, MarkdownInline("**bold** and *italic* and `code`", buffer[:]), "bold and italic and code")
    testing.expect_value(t, MarkdownInline("__bold__ and _italic_ and ~~gone~~", buffer[:]), "bold and italic and gone")
    testing.expect_value(t, MarkdownInline("snake_case_name stays", buffer[:]), "snake_case_name stays")
    testing.expect_value(t, MarkdownInline("see [the docs](https://example.com/a_b) now", buffer[:]), "see the docs now")
    testing.expect_value(t, MarkdownInline("a [bracket] alone", buffer[:]), "a [bracket] alone")
    testing.expect_value(t, MarkdownInline("an open [link(", buffer[:]), "an open [link(")
    testing.expect_value(t, MarkdownInline("two\nlines", buffer[:]), "two lines")
    testing.expect_value(t, MarkdownInline("two\r\nlines  ", buffer[:]), "two lines")
    testing.expect_value(t, MarkdownInline("> a quote\n> that goes on", buffer[:]), "a quote that goes on")
    testing.expect_value(t, MarkdownInline("a \\* star and 2 \\* 3", buffer[:]), "a * star and 2 * 3")
    testing.expect_value(t, MarkdownInline("", buffer[:]), "")
    // what does not fit is cut, nothing is written outside
    small: [4]u8
    testing.expect_value(t, MarkdownInline("longer than four", small[:]), "long")
    testing.expect_value(t, MarkdownInline("x", nil), "")
}

@(test)
test_markdown_becomes_titles_texts_bullets_and_a_code_block :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 4096),
        ctx: Context,
        style: Style,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    for _ in 0 ..< 2 {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 900}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(300), {}}) { UiMarkdown(&test.ctx, SAMPLE) }
        UiEnd(&test.ctx)
    }
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
    find :: proc(ctx: ^Context, text: string) -> (info: DrawInfo, found: bool) {
        for command in UiCommands(ctx) {
            if command.kind == .DRAW && command.info.kind == .LABEL && command.info.text == text { return command.info, true }
        }
        return
    }
    title, title_found := find(&test.ctx, "Title")
    testing.expect(t, title_found && DrawInfoHasTag(&title, "title") && title.font_size > DEFAULT_METRICS.font_size * 1.8)
    second, second_found := find(&test.ctx, "Lists")
    testing.expect(t, second_found && DrawInfoHasTag(&second, "title") && second.font_size < title.font_size)
    // the paragraph is one text that wraps: its two source lines are joined, and at 300 pixels it takes two lines again, broken at words
    _, joined := find(&test.ctx, "A paragraph that goes over two lines.")
    testing.expect(t, !joined, "too wide for the window: it is wrapped")
    first_line, first_found := find(&test.ctx, "A paragraph that goes over two")
    testing.expect(t, first_found && !DrawInfoHasTag(&first_line, "title"))
    nested, nested_found := find(&test.ctx, "nested")
    one, one_found := find(&test.ctx, "one")
    testing.expect(t, nested_found && one_found && nested.rect.x > one.rect.x, "a nested entry is further in")
    number, number_found := find(&test.ctx, "2.")
    testing.expect(t, number_found && DrawInfoHasTag(&number, "dim"))
    quote, quote_found := find(&test.ctx, "a quote that goes on")
    testing.expect(t, quote_found && DrawInfoHasTag(&quote, "dim"))
    // the code keeps its lines and its indent, in the code face, in a panel of its own
    code, code_found := find(&test.ctx, "  indented")
    testing.expect(t, code_found && DrawInfoHasTag(&code, "mono"))
    bullets, panels, rules: int
    for command in UiCommands(&test.ctx) {
        if command.kind != .DRAW { continue }
        #partial switch command.info.kind {
        case .BULLET:
            bullets += 1
        case .PANEL:
            if command.info.name == "code" { panels += 1 }
        case .SEPARATOR:
            rules += 1
        }
    }
    testing.expect_value(t, bullets, 3)
    testing.expect_value(t, panels, 1)
    testing.expect_value(t, rules, 2)                       // the bar of the quote and the rule
}
