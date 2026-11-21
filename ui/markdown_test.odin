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

@(test)
test_markdown_reads_and_shows_a_table :: proc(t: ^testing.T) {
    TABLE :: "before\n| Name | Size |\n|---|:--:|\n| **a** | 1 |\n| b \\| c |\n| [d](d.md) | 3 | extra |\nafter"
    block, next, ok := MarkdownNext(TABLE, 0)
    testing.expect(t, ok && block.kind == .PARAGRAPH && block.text == "before", "a table ends the paragraph over it")
    block, next, ok = MarkdownNext(TABLE, next)
    testing.expect(t, ok && block.kind == .TABLE && block.level == 2)
    testing.expect_value(t, block.text, "| Name | Size |\n|---|:--:|\n| **a** | 1 |\n| b \\| c |\n| [d](d.md) | 3 | extra |")
    block, _, ok = MarkdownNext(TABLE, next)
    testing.expect(t, ok && block.kind == .PARAGRAPH && block.text == "after")
    // a line with bars and no line of dashes under it is text
    block, _, ok = MarkdownNext("| not | a table |\nmore", 0)
    testing.expect(t, ok && block.kind == .PARAGRAPH)
    cell, found := MarkdownTableCell("| Name | Size |", 0)
    testing.expect(t, found && cell == "Name")
    cell, found = MarkdownTableCell("| Name | Size |", 1)
    testing.expect(t, found && cell == "Size")
    _, found = MarkdownTableCell("| Name | Size |", 2)
    testing.expect(t, !found)
    cell, found = MarkdownTableCell("| b \\| c |", 0)
    testing.expect(t, found && cell == "b \\| c", "an escaped bar is a part of the cell")
    testing.expect_value(t, MarkdownTableColumns("| b \\| c |"), 1)
    testing.expect_value(t, MarkdownTableColumns("a | b | c"), 3)
    testing.expect_value(t, MarkdownTableColumns("||"), 1)

    Test :: struct {
        storage: Storage(128, 256, 64, 4096),
        ctx: Context,
        style: Style,
        address: string,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    for _ in 0 ..< 3 {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 900}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(600), {}}) { UiMarkdown(&test.ctx, TABLE) }
        UiEnd(&test.ctx)
    }
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
    find :: proc(ctx: ^Context, text: string) -> (info: DrawInfo, found: bool) {
        for command in UiCommands(ctx) {
            if command.kind == .DRAW && command.info.kind == .LABEL && command.info.text == text { return command.info, true }
        }
        return
    }
    name, name_found := find(&test.ctx, "Name")
    size, size_found := find(&test.ctx, "Size")
    a, a_found := find(&test.ctx, "a")
    one, one_found := find(&test.ctx, "1")
    escaped, escaped_found := find(&test.ctx, "b | c")
    link, link_found := find(&test.ctx, "d")
    three, three_found := find(&test.ctx, "3")
    _, extra_found := find(&test.ctx, "extra")
    testing.expect(t, name_found && size_found && a_found && one_found && escaped_found && link_found && three_found, "the cells are drawn")
    testing.expect(t, !extra_found, "a cell past the columns of the header is not shown")
    testing.expect(t, DrawInfoHasTag(&name, "strong") && DrawInfoHasTag(&size, "strong") && DrawInfoHasTag(&a, "strong") && !DrawInfoHasTag(&one, "strong"), "the header is strong, a cell has its own marks")
    testing.expect(t, DrawInfoHasTag(&link, "link"))
    middle :: proc(info: DrawInfo) -> f32 { return info.rect.x + info.rect.z * 0.5 }
    testing.expect(t, name.rect.x == a.rect.x && a.rect.x == escaped.rect.x && size.rect.x > name.rect.x, "the first column lines up on its left edge")
    testing.expect(t, abs(middle(size) - middle(one)) < 1 && abs(middle(one) - middle(three)) < 1 && size.rect.x != one.rect.x, "the centred column lines up on its middle")
    testing.expect_value(t, MarkdownTableAlign("|---|:--:|--:|:--|", 0), AlignX.LEFT)
    testing.expect_value(t, MarkdownTableAlign("|---|:--:|--:|:--|", 1), AlignX.CENTER)
    testing.expect_value(t, MarkdownTableAlign("|---|:--:|--:|:--|", 2), AlignX.RIGHT)
    testing.expect_value(t, MarkdownTableAlign("|---|:--:|--:|:--|", 3), AlignX.LEFT)
    testing.expect_value(t, MarkdownTableAlign("|---|", 5), AlignX.LEFT)
    testing.expect(t, a.rect.y > name.rect.y && escaped.rect.y > a.rect.y && link.rect.y > escaped.rect.y, "a row under the other")
}

// A text that arrives a few characters at a time (a reply that is streamed) is shown at every length: half a fence, half a link, half a table
@(test)
test_markdown_is_shown_at_every_length_of_a_text :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(256, 512, 128, 8192),
        ctx: Context,
        style: Style,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    EXTRA :: "| a | b |\n|---|---|\n| **c** | [d](e) |\n\ntext with `code`, a [link](address), **strong *both* strong**, snake_case and a \\* star\n> quote [l](m)\n- item `x`\n  - nested **y**"
    sources: [2]string = {SAMPLE, EXTRA}
    for source in sources {
        for length in 0 ..= len(source) {
            part: string = source[:length]
            // the reader always ends, and every block is inside of the text
            cursor: int
            blocks: int
            for {
                block, next, ok := MarkdownNext(part, cursor)
                if !ok { break }
                testing.expectf(t, next > cursor, "length %d: the reader goes on", length)
                if next <= cursor { break }
                cursor = next
                blocks += 1
                testing.expect(t, len(block.text) <= length)
            }
            testing.expect(t, blocks <= length)
            // two frames: the second one is the rich text with the widths of the first
            for _ in 0 ..< 2 {
                UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 900}, &test.style)
                if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(300), {}}) { UiMarkdown(&test.ctx, part) }
                UiEnd(&test.ctx)
            }
            testing.expectf(t, UiProblems(&test.ctx) == Problems{}, "length %d: %v", length, UiProblems(&test.ctx))
        }
    }
}

@(test)
test_markdown_reads_setext_headings_and_tilde_fences :: proc(t: ^testing.T) {
    source: string = "Title\n=====\n\nA section\nover two lines\n--\n\nplain\n\n~~~\ncode ``` stays\n~~~\n\n```\nand ~~~ stays\n```\n\nafter"
    block, next, ok := MarkdownNext(source, 0)
    testing.expect(t, ok && block.kind == .HEADING && block.level == 1 && block.text == "Title")
    block, next, ok = MarkdownNext(source, next)
    testing.expect(t, ok && block.kind == .HEADING && block.level == 2 && block.text == "A section\nover two lines", "a heading of two lines")
    block, next, ok = MarkdownNext(source, next)
    testing.expect(t, ok && block.kind == .PARAGRAPH && block.text == "plain")
    block, next, ok = MarkdownNext(source, next)
    testing.expect(t, ok && block.kind == .CODE && block.text == "code ``` stays", "a tilde fence is closed by tildes")
    block, next, ok = MarkdownNext(source, next)
    testing.expect(t, ok && block.kind == .CODE && block.text == "and ~~~ stays", "a backtick fence is closed by backticks")
    block, next, ok = MarkdownNext(source, next)
    testing.expect(t, ok && block.kind == .PARAGRAPH && block.text == "after")
    // a rule after an empty line is still a rule, and a lone dash under text is not an underline
    block, _, ok = MarkdownNext("text\n-\n", 0)
    testing.expect(t, ok && block.kind != .HEADING)
    block, _, ok = MarkdownNext("\n---\n", 0)
    testing.expect(t, ok && block.kind == .RULE)
}
