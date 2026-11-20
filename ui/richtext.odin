package ui

// A paragraph with several styles in it: `ui.UiRichText(&ctx, name, "plain, **strong**, *italic*, `code` and a [link](address)")`. The marks are the ones of Markdown.
// The paragraph wraps at words like a label, and a line may hold runs of different styles: the widget breaks the lines itself (the layout only knows texts of one
// style) for the width it had in the last frame, and declares a row of texts per line. In its first frame, before it knows its width, it is a plain wrapped text.
//
// The style draws a run by its tags: "strong", "italic", "mono" (code) and "link"; they are measured in the same faces (a text is measured with its tags). Nothing is
// allocated: the runs are built in the text memory of the frame.
//
// Limits: marks: strong, italic, code, links; `~~strike~~` is taken away, not drawn; no underline, no colors, no images
//     a link that is broken over two lines is two links with the same address; a run keeps the innermost `ui.DRAW_TAGS` (4) tags, so a paragraph inside of three tags loses the outer ones
//     lines are broken by the width the paragraph had in the last frame (the first frame is plain); a word wider than the line is not cut

RichMark :: enum u8 {
    STRONG,
    ITALIC,
    CODE,
    LINK,
}
RichMarks :: bit_set[RichMark; u8]

// A piece of a paragraph that is drawn in one go: a word or a part of one, with the marks that are on at that place
RichToken :: struct {
    text: string,               // a part of the source
    marks: RichMarks,
    space_before: bool,         // a space (or a line end) was between this piece and the one before
    address: string,            // a piece of a link: what stands in the round brackets (a part of the source)
}

// Where RichNext is in a text
RichCursor :: struct {
    at: int,
    marks: RichMarks,
    link_end: int,              // inside of the text of a link: where its closing bracket is (0: not in a link)
    link_address: string,
    pending_space: bool,
}

@(private)
richIsSpace :: proc "contextless" (character: u8) -> bool {
    return character == ' ' || character == '\t' || character == '\n' || character == '\r'
}

// The address part of a link whose text ends at `close` (the `]`): where its `)` is, -1 when it is not a link
@(private)
richLinkEnd :: proc "contextless" (source: string, close: int) -> int {
    if close + 1 >= len(source) || source[close + 1] != '(' { return -1 }
    for k in close + 2 ..< len(source) {
        if source[k] == ')' { return k }
        if source[k] == '\n' { return -1 }
    }
    return -1
}

// The next piece of `source`. The marks of Markdown switch the styles and are not part of a piece: `**` and `__` strong, `*` and `_` italic (an underscore inside of
// a word is a letter), a backtick code (nothing is a mark inside of code), `[text](address)` a link that shows its text, a backslash takes the meaning of the mark
// after it away. `ok` is false at the end of the text.
RichNext :: proc "contextless" (source: string, cursor: ^RichCursor) -> (token: RichToken, ok: bool) {
    for cursor.at < len(source) {
        character: u8 = source[cursor.at]
        // the end of the text of a link: its address is skipped
        if cursor.link_end != 0 && cursor.at == cursor.link_end {
            cursor.at = richLinkEnd(source, cursor.link_end) + 1
            cursor.link_end = 0
            cursor.link_address = ""
            cursor.marks -= {.LINK}
            continue
        }
        if richIsSpace(character) {
            cursor.pending_space = true
            cursor.at += 1
            continue
        }
        if .CODE in cursor.marks {
            if character == '`' {
                cursor.marks -= {.CODE}
                cursor.at += 1
                continue
            }
        } else {
            switch character {
            case '`':
                cursor.marks += {.CODE}
                cursor.at += 1
                continue
            case '*', '_':
                // an underscore between two letters is a part of a name
                if character == '_' && cursor.at > 0 && cursor.at + 1 < len(source) && !richIsSpace(source[cursor.at - 1]) && !richIsSpace(source[cursor.at + 1]) && source[cursor.at - 1] != '_' && source[cursor.at + 1] != '_' && source[cursor.at - 1] != '*' && source[cursor.at + 1] != '*' { break }
                double: bool = cursor.at + 1 < len(source) && source[cursor.at + 1] == character
                cursor.marks ~= {.STRONG} if double else {.ITALIC}
                cursor.at += 2 if double else 1
                continue
            case '~':
                if cursor.at + 1 < len(source) && source[cursor.at + 1] == '~' {
                    cursor.at += 2                          // struck text is shown as it is: the marks are gone
                    continue
                }
            case '[':
                if cursor.link_end == 0 {
                    close: int = -1
                    for k in cursor.at + 1 ..< len(source) {
                        if source[k] == ']' {
                            close = k
                            break
                        }
                        if source[k] == '\n' { break }
                    }
                    if close > 0 && richLinkEnd(source, close) > 0 {
                        cursor.link_end = close
                        cursor.link_address = source[close + 2:richLinkEnd(source, close)]
                        cursor.marks += {.LINK}
                        cursor.at += 1
                        continue
                    }
                }
            }
        }
        // a piece: up to a space or to the next mark
        start: int = cursor.at
        if character == '\\' && .CODE not_in cursor.marks && cursor.at + 1 < len(source) {
            // the mark after a backslash is a letter: the piece starts at it
            start = cursor.at + 1
            cursor.at += 2
        } else {
            cursor.at += 1
        }
        for cursor.at < len(source) {
            next: u8 = source[cursor.at]
            if richIsSpace(next) || next == '`' { break }
            if cursor.link_end != 0 && cursor.at == cursor.link_end { break }
            if .CODE not_in cursor.marks {
                if next == '*' || next == '\\' || next == '[' { break }
                if next == '~' && cursor.at + 1 < len(source) && source[cursor.at + 1] == '~' { break }
                if next == '_' {
                    inside: bool = cursor.at + 1 < len(source) && !richIsSpace(source[cursor.at + 1]) && source[cursor.at + 1] != '_' && source[cursor.at + 1] != '*'
                    if !inside { break }
                }
            }
            cursor.at += 1
        }
        token = {text = source[start:cursor.at], marks = cursor.marks, space_before = cursor.pending_space, address = cursor.link_address}
        cursor.pending_space = false
        return token, true
    }
    return {}, false
}

// The tags a run is declared in, for the style: the names of its marks
@(private)
richPushTags :: proc(ctx: ^Context, marks: RichMarks) -> (pushed: int) {
    if .STRONG in marks {
        UiPushTag(ctx, "strong")
        pushed += 1
    }
    if .ITALIC in marks {
        UiPushTag(ctx, "italic")
        pushed += 1
    }
    if .CODE in marks {
        UiPushTag(ctx, "mono")
        pushed += 1
    }
    if .LINK in marks {
        UiPushTag(ctx, "link")
        pushed += 1
    }
    return
}

// The width of a text with the tags that are pushed now
@(private)
richWidth :: proc(ctx: ^Context, text: string, font_size: f32) -> f32 {
    outer_tags: [DRAW_TAGS]Id = ctx.measure_tags
    ctx.measure_tags = {}
    for i in 0 ..< min(ctx.tag_count, DRAW_TAGS) { ctx.measure_tags[i] = ctx.tag_stack[ctx.tag_count - 1 - i] }
    width: f32 = measureText(ctx, text, font_size).x
    ctx.measure_tags = outer_tags
    return width
}

// A paragraph of `source` with its marks drawn as styles, as wide as its container. `name` makes its id (it remembers its width), `scale` is its size as a part of
// the font size. The tags that are pushed around it reach every run (a "dim" paragraph is dim). A link takes the pointer and the keyboard like a button: when one
// is clicked `clicked` is true and `address` is what stands in its round brackets (a part of `source`); what to do with it is the program's.
// With `max_width` the paragraph is as wide as its text and not wider than that (the text of a bubble): its lines are broken for `max_width`.
UiRichText :: proc(ctx: ^Context, name: string, source: string, scale: f32 = 1, max_width: f32 = 0) -> (address: string, clicked: bool) {
    return richParagraph(ctx, UiId(ctx, name), source, ctx.style.metrics.font_size * scale, max_width)
}

// The run that is built: the pieces of one style (and of one link) that follow each other on a line, at the end of the text memory of the frame
@(private)
RichRun :: struct {
    marks: RichMarks,
    address: string,
    start: int,
    open: bool,
    links: u32,                 // the link runs of the paragraph so far: they make the ids
    lines: int,                 // the lines of the paragraph so far
    continues: bool,            // the run is the first of a line after the first line: it goes on the text of the line before
    clicked: bool,
    clicked_address: string,
}

@(private)
richRunFlush :: proc(ctx: ^Context, paragraph: Id, run: ^RichRun, font_size: f32) {
    if !run.open { return }
    run.open = false
    text: string = string(ctx.text_buffer[run.start:ctx.text_used])
    run.start = ctx.text_used
    link: bool = .LINK in run.marks
    hot: bool
    if link {
        // a link is a widget: an element around its text that takes the pointer. A link that goes over two lines is two of them.
        run.links += 1
        id: Id = IdFromIndex(run.links, paragraph)
        interaction: Interaction = UiInteract(ctx, id)
        if interaction.clicked {
            run.clicked = true
            run.clicked_address = run.address
        }
        hot = interaction.hovered || ctx.focus == id
        ElementOpen(ctx, {id = id, hit = {.INTERACTIVE}, cursor = .HAND})
    }
    pushed: int = richPushTags(ctx, run.marks)
    if hot {
        UiPushTag(ctx, "hover")
        pushed += 1
    }
    TextOpen(ctx, text, {font_size = font_size, wrap = .NONE, continues = run.continues})
    run.continues = false
    for _ in 0 ..< pushed { UiPopTag(ctx) }
    if link { ElementClose(ctx) }
}

@(private)
richPut :: proc(ctx: ^Context, text: string) -> bool {
    if ctx.text_used + len(text) > len(ctx.text_buffer) {
        ctx.problems += {.TEXT_FULL}
        return false
    }
    copy(ctx.text_buffer[ctx.text_used:], text)
    ctx.text_used += len(text)
    return true
}

@(private)
richParagraph :: proc(ctx: ^Context, id: Id, source: string, font_size: f32, max_width: f32 = 0) -> (address: string, clicked: bool) {
    state: ^WidgetState = stateGet(ctx, id)
    // the width to break for: the one it had in the last frame, or the given one (then it is as wide as its lines)
    fit: bool = max_width > 0
    width: f32 = max_width if fit else state.rect.z
    line_width_sizing: SizingAxis = Fit() if fit else Grow()
    ElementOpen(ctx, {id = id, layout = {size = {line_width_sizing, Fit()}, direction = .TOP_TO_BOTTOM}})
    defer ElementClose(ctx)
    if width <= 0 {
        // the first frame: the width is not known yet, the paragraph is a wrapped text without its marks
        free_space: []u8 = ctx.text_buffer[ctx.text_used:]
        shown: string = MarkdownInline(source, free_space[:min(len(free_space), len(source))])
        ctx.text_used += len(shown)
        TextOpen(ctx, shown, {wrap = .WORDS, font_size = font_size})
        return
    }
    cursor: RichCursor
    line_width: f32
    line_open: bool
    run: RichRun = {start = ctx.text_used}
    for {
        token, ok := RichNext(source, &cursor)
        if !ok { break }
        pushed: int = richPushTags(ctx, token.marks)
        token_width: f32 = richWidth(ctx, token.text, font_size)
        space_width: f32 = richWidth(ctx, " ", font_size) if token.space_before && line_open else 0
        for _ in 0 ..< pushed { UiPopTag(ctx) }
        // a line is only broken at a space: the pieces that follow this one without a space (the comma after a strong word, the end of a word that is half
        // italic) are one word with it, and the word has to fit
        word_width: f32 = token_width
        if token.space_before {
            ahead: RichCursor = cursor
            for {
                next, more := RichNext(source, &ahead)
                if !more || next.space_before { break }
                next_pushed: int = richPushTags(ctx, next.marks)
                word_width += richWidth(ctx, next.text, font_size)
                for _ in 0 ..< next_pushed { UiPopTag(ctx) }
            }
        }
        if line_open && token.space_before && line_width + space_width + word_width > width + LAYOUT_EPSILON {
            // the word does not fit: the line ends, the word starts the next one (without the space before it)
            richRunFlush(ctx, id, &run, font_size)
            ElementClose(ctx)
            line_open = false
            line_width, space_width = 0, 0
        }
        if !line_open {
            ElementOpen(ctx, {layout = {size = {line_width_sizing, Fit()}, direction = .LEFT_TO_RIGHT, align = {y = .BOTTOM}}})
            line_open = true
            run.continues = run.lines > 0
            run.lines += 1
        }
        space: bool = space_width > 0
        same: bool = token.marks == run.marks && token.address == run.address
        if run.open && !same {
            // the space between two styles is in the plainer one: a link is not underlined past its last word, a strong run does not end in a space
            if space && run.marks & {.LINK, .CODE} == {} && token.marks != {} {
                if !richPut(ctx, " ") { break }
                space = false
            }
            richRunFlush(ctx, id, &run, font_size)
        }
        if !run.open {
            run.marks = token.marks
            run.address = token.address
            run.start = ctx.text_used
            run.open = true
        }
        if space && !richPut(ctx, " ") { break }
        if !richPut(ctx, token.text) { break }
        line_width += space_width + token_width
    }
    richRunFlush(ctx, id, &run, font_size)
    if line_open { ElementClose(ctx) }
    return run.clicked_address, run.clicked
}
