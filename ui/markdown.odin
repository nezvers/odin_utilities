package ui

// Markdown as widgets: `ui.UiMarkdown(&ctx, source)` shows a text written in Markdown (a help page, a note, a changelog) as titles, wrapped paragraphs, lists, quotes,
// code blocks and rules. It is a reader, not an editor: the text is parsed every frame, block by block, straight into elements, with no tree and no memory of its own.
//
// What it reads: headings (`#` to `######`), paragraphs (lines up to an empty one), lists (`-`, `*`, `+` or `1.`, nested by two spaces of indent), quotes (`>`), fenced
// code (three backticks, kept as it is, in the code face), rules (`---`), tables (`| a | b |` with a line of dashes under the header). Inside of a paragraph, an entry of a list and a quote the marks are styles (richtext.odin):
// `**strong**`, `*italic*`, `` `code` `` and `[links](address)`. A heading is one text in the strong face: its marks are taken away.
//
// The Markdown view of Baldr (baldr/widget_markdown_view.odin) was the reason to have one; the code is written for this library.

MarkdownKind :: enum u8 {
    PARAGRAPH,
    HEADING,            // level 1 to 6
    BULLET,             // level: how deep it is nested, 0 for the outermost
    ORDERED,            // the same, `marker` is its number as it was written ("3.")
    QUOTE,
    CODE,               // text: the lines between the fences, as they are
    RULE,
    TABLE,              // text: its lines (the header, the line of dashes, the rows), level: the number of columns; MarkdownTableCell reads a cell
}

MarkdownBlock :: struct {
    kind: MarkdownKind,
    level: int,
    marker: string,
    text: string,       // a part of the source: a paragraph may go over several lines (its line ends are in it)
}

@(private)
markdownLine :: proc(source: string, cursor: int) -> (line: string, next: int) {
    end: int = cursor
    for end < len(source) && source[end] != '\n' { end += 1 }
    line = source[cursor:end]
    if len(line) > 0 && line[len(line) - 1] == '\r' { line = line[:len(line) - 1] }
    return line, min(end + 1, len(source))
}

@(private)
markdownTrimLeft :: proc(line: string) -> (rest: string, indent: int) {
    for indent < len(line) && (line[indent] == ' ' || line[indent] == '\t') { indent += 1 }
    return line[indent:], indent
}

@(private)
markdownTrim :: proc(text: string) -> string {
    rest, _ := markdownTrimLeft(text)
    for len(rest) > 0 && (rest[len(rest) - 1] == ' ' || rest[len(rest) - 1] == '\t' || rest[len(rest) - 1] == '\r') { rest = rest[:len(rest) - 1] }
    return rest
}

// What a line starts, by its first characters: a heading, an entry of a list, a quote, a rule, a fence; else it is text of a paragraph
@(private)
markdownLineKind :: proc(line: string) -> (kind: MarkdownKind, level: int, marker: string, text: string, fence: bool) {
    rest, indent := markdownTrimLeft(line)
    if len(rest) >= 3 && rest[:3] == "```" { return .CODE, 0, "", "", true }
    if len(rest) > 0 && rest[0] == '#' {
        hashes: int
        for hashes < len(rest) && rest[hashes] == '#' { hashes += 1 }
        if hashes <= 6 && hashes < len(rest) && rest[hashes] == ' ' { return .HEADING, hashes, "", markdownTrim(rest[hashes:]), false }
    }
    if len(rest) >= 3 {
        // a rule: three or more of the same mark and nothing else
        mark: u8 = rest[0]
        if mark == '-' || mark == '*' || mark == '_' {
            only: bool = true
            for i in 0 ..< len(rest) {
                if rest[i] != mark { only = false }
            }
            if only { return .RULE, 0, "", "", false }
        }
    }
    if len(rest) >= 2 && (rest[0] == '-' || rest[0] == '*' || rest[0] == '+') && rest[1] == ' ' { return .BULLET, indent / 2, rest[:1], markdownTrim(rest[2:]), false }
    digits: int
    for digits < len(rest) && rest[digits] >= '0' && rest[digits] <= '9' { digits += 1 }
    if digits > 0 && digits + 1 < len(rest) && rest[digits] == '.' && rest[digits + 1] == ' ' { return .ORDERED, indent / 2, rest[:digits + 1], markdownTrim(rest[digits + 2:]), false }
    if len(rest) > 0 && rest[0] == '>' { return .QUOTE, 0, "", markdownTrim(rest[1:]), false }
    return .PARAGRAPH, 0, "", markdownTrim(line), false
}

// The line at `at` is the header of a table: it starts with a bar and the line under it is bars, dashes and colons
@(private)
markdownTableStarts :: proc(source: string, at: int) -> bool {
    line, next := markdownLine(source, at)
    header: string = markdownTrim(line)
    if len(header) == 0 || header[0] != '|' || next >= len(source) { return false }
    under, _ := markdownLine(source, next)
    dashes: string = markdownTrim(under)
    if len(dashes) == 0 || dashes[0] != '|' { return false }
    any_dash: bool
    for i in 0 ..< len(dashes) {
        switch dashes[i] {
        case '-':
            any_dash = true
        case '|', ':', ' ', '\t':
        case:
            return false
        }
    }
    return any_dash
}

// The cell `index` of a line of a table (`| a | b |`), without the spaces around it. A bar after a backslash is a part of the cell. `ok` is false past the last cell.
MarkdownTableCell :: proc(line: string, index: int) -> (cell: string, ok: bool) {
    row: string = markdownTrim(line)
    if len(row) > 0 && row[0] == '|' { row = row[1:] }
    if len(row) > 0 && row[len(row) - 1] == '|' && (len(row) < 2 || row[len(row) - 2] != '\\') { row = row[:len(row) - 1] }
    start: int
    column: int
    for i in 0 ..= len(row) {
        if i < len(row) && (row[i] != '|' || (i > 0 && row[i - 1] == '\\')) { continue }
        if column == index { return markdownTrim(row[start:i]), true }
        column += 1
        start = i + 1
    }
    return "", false
}

// How many cells a line of a table has
MarkdownTableColumns :: proc(line: string) -> (count: int) {
    for {
        _, ok := MarkdownTableCell(line, count)
        if !ok { return }
        count += 1
    }
}

// The next block of a Markdown text from `cursor` on, and where the one after it starts. `ok` is false at the end of the text.
MarkdownNext :: proc(source: string, cursor: int) -> (block: MarkdownBlock, next: int, ok: bool) {
    at: int = cursor
    line: string
    // empty lines between blocks
    for at < len(source) {
        after: int
        line, after = markdownLine(source, at)
        if markdownTrim(line) != "" { break }
        at = after
    }
    if at >= len(source) { return {}, at, false }
    line_end: int
    line, line_end = markdownLine(source, at)
    kind, level, marker, text, fence := markdownLineKind(line)
    if fence {
        // everything up to the closing fence (or the end of the text), as it is
        start: int = line_end
        end: int = start
        scan: int = start
        for scan < len(source) {
            inner, after := markdownLine(source, scan)
            trimmed, _ := markdownTrimLeft(inner)
            if len(trimmed) >= 3 && trimmed[:3] == "```" {
                scan = after
                break
            }
            end = after
            scan = after
        }
        code: string = source[start:end]
        if len(code) > 0 && code[len(code) - 1] == '\n' { code = code[:len(code) - 1] }
        return {kind = .CODE, text = code}, scan, true
    }
    if kind != .PARAGRAPH && kind != .QUOTE { return {kind = kind, level = level, marker = marker, text = text}, line_end, true }
    if kind == .PARAGRAPH && markdownTableStarts(source, at) {
        // a table: the lines that start with a bar
        end: int = at
        scan: int = at
        for scan < len(source) {
            row, after := markdownLine(source, scan)
            trimmed: string = markdownTrim(row)
            if len(trimmed) == 0 || trimmed[0] != '|' { break }
            end = scan + len(row)
            scan = after
        }
        return {kind = .TABLE, level = MarkdownTableColumns(line), text = source[at:end]}, scan, true
    }
    // a paragraph (or a quote) goes on over the next lines until an empty one or a line that starts something else
    start_of_text: int = at
    end_of_text: int = at + len(line)
    scan: int = line_end
    for scan < len(source) {
        more, after := markdownLine(source, scan)
        if markdownTrim(more) == "" { break }
        more_kind, _, _, _, more_fence := markdownLineKind(more)
        if more_fence || more_kind != kind { break }
        if kind == .PARAGRAPH && markdownTableStarts(source, scan) { break }
        end_of_text = scan + len(more)
        scan = after
    }
    if kind == .QUOTE { return {kind = .QUOTE, text = source[start_of_text:end_of_text]}, scan, true }
    return {kind = .PARAGRAPH, text = markdownTrim(source[start_of_text:end_of_text])}, scan, true
}

// The text of a line as it is shown: line ends are spaces, the marks of emphasis (`*`, `_`, `~~`, backticks) and of quotes at the start of a line are gone, a link
// `[text](address)` is its text. Written into `out`; what does not fit is cut.
MarkdownInline :: proc(text: string, out: []u8) -> string {
    count: int
    put :: proc(out: []u8, count: ^int, character: u8) {
        if count^ < len(out) {
            out[count^] = character
            count^ += 1
        }
    }
    i: int
    line_start: bool = true
    for i < len(text) {
        character: u8 = text[i]
        switch {
        case character == '\r':
            i += 1
        case character == '\n':
            if count > 0 && out[count - 1] != ' ' { put(out, &count, ' ') }
            line_start = true
            i += 1
        case line_start && (character == ' ' || character == '\t' || character == '>'):
            i += 1                                          // the indent and the mark of a quote on a line that goes on
        case character == '\\' && i + 1 < len(text):
            put(out, &count, text[i + 1])                   // an escaped mark is the mark itself
            line_start = false
            i += 2
        case character == '*' || character == '`' || character == '~':
            i += 1
            line_start = false
        case character == '_':
            // an underscore inside of a word is a part of the word (snake_case), at its edge it is emphasis
            inside: bool = i > 0 && i + 1 < len(text) && text[i - 1] != ' ' && text[i + 1] != ' ' && text[i - 1] != '_' && text[i + 1] != '_'
            if inside { put(out, &count, character) }
            i += 1
            line_start = false
        case character == '[':
            // a link: its text is kept, its address in the round brackets after it is not
            close: int = -1
            for k in i + 1 ..< len(text) {
                if text[k] == ']' {
                    close = k
                    break
                }
                if text[k] == '\n' { break }
            }
            if close > 0 && close + 1 < len(text) && text[close + 1] == '(' {
                address_end: int = -1
                for k in close + 2 ..< len(text) {
                    if text[k] == ')' {
                        address_end = k
                        break
                    }
                    if text[k] == '\n' { break }
                }
                if address_end > 0 {
                    for k in i + 1 ..< close { put(out, &count, text[k]) }
                    i = address_end + 1
                    line_start = false
                    continue
                }
            }
            put(out, &count, character)
            i += 1
            line_start = false
        case:
            put(out, &count, character)
            line_start = false
            i += 1
        }
    }
    for count > 0 && out[count - 1] == ' ' { count -= 1 }
    return string(out[:count])
}

// The shown text of a block in the memory of the frame
@(private)
markdownShown :: proc(ctx: ^Context, text: string) -> string {
    free_space: []u8 = ctx.text_buffer[ctx.text_used:]
    shown: string = MarkdownInline(text, free_space[:min(len(free_space), len(text))])
    if len(text) > len(free_space) { ctx.problems += {.TEXT_FULL} }
    ctx.text_used += len(shown)
    return shown
}

// The sizes of the headings, as parts of the font size
MARKDOWN_HEADING_SCALES: [6]f32 = {1.9, 1.5, 1.25, 1.1, 1, 1}

// The lines of a quote without the mark at their start, in the memory of the frame (the marks of styles stay: the paragraph reads them)
@(private)
markdownQuoteText :: proc(ctx: ^Context, text: string) -> string {
    start: int = ctx.text_used
    line_start: bool = true
    for i in 0 ..< len(text) {
        character: u8 = text[i]
        if line_start && (character == '>' || character == ' ' || character == '\t') { continue }
        line_start = character == '\n'
        if ctx.text_used >= len(ctx.text_buffer) {
            ctx.problems += {.TEXT_FULL}
            break
        }
        ctx.text_buffer[ctx.text_used] = character
        ctx.text_used += 1
    }
    return string(ctx.text_buffer[start:ctx.text_used])
}

// Shows `source` as a column of blocks, as wide as its container. The texts are in the memory of the frame (the storage of the context needs room for the text).
// `name` makes the id of the view: two views in one container need two names (a paragraph remembers its width by it).
// When a link is clicked `clicked` is true and `address` is the address of the link (a part of `source`).
UiMarkdown :: proc(ctx: ^Context, source: string, name: string = "markdown") -> (address: string, clicked: bool) {
    metrics: ^Metrics = &ctx.style.metrics
    root: Id = UiId(ctx, name)
    ElementOpen(ctx, {id = root, layout = {size = {Grow(), Fit()}, direction = .TOP_TO_BOTTOM, gap = metrics.gap * 1.5}})
    cursor: int
    index: u32
    for {
        block, next, ok := MarkdownNext(source, cursor)
        if !ok { break }
        cursor = next
        index += 1
        paragraph: Id = IdFromIndex(index, root)
        link: string
        link_clicked: bool
        defer if link_clicked { address, clicked = link, true }
        switch block.kind {
        case .HEADING:
            UiPushTag(ctx, "title")
            TextOpen(ctx, markdownShown(ctx, block.text), {font_size = metrics.font_size * MARKDOWN_HEADING_SCALES[clamp(block.level, 1, 6) - 1], wrap = .WORDS})
            UiPopTag(ctx)
        case .PARAGRAPH:
            link, link_clicked = richParagraph(ctx, paragraph, block.text, metrics.font_size)
        case .BULLET, .ORDERED:
            ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = metrics.gap, padding = {left = f32(block.level) * metrics.font_size * 1.2}}})
            if block.kind == .BULLET {
                ElementOpen(ctx, {layout = {size = {Fixed(metrics.font_size * 0.6), Fixed(metrics.font_size)}}, draw = {kind = .BULLET}})
                ElementClose(ctx)
            } else {
                UiPushTag(ctx, "dim")
                TextOpen(ctx, block.marker)
                UiPopTag(ctx)
            }
            link, link_clicked = richParagraph(ctx, paragraph, block.text, metrics.font_size)
            ElementClose(ctx)
        case .QUOTE:
            // a bar on the left, the text dim
            ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = metrics.gap * 1.5}})
            ElementOpen(ctx, {layout = {size = {Fixed(3), Grow()}}, draw = {kind = .SEPARATOR}})
            ElementClose(ctx)
            UiPushTag(ctx, "dim")
            link, link_clicked = richParagraph(ctx, paragraph, markdownQuoteText(ctx, block.text), metrics.font_size)
            UiPopTag(ctx)
            ElementClose(ctx)
        case .CODE:
            // a well with the lines as they are, in the code face
            UiPushTag(ctx, "flat")
            ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .TOP_TO_BOTTOM, padding = PaddingAll(metrics.padding.x)}, draw = {kind = .PANEL, name = "code"}})
            UiPopTag(ctx)
            UiPushTag(ctx, "mono")
            TextOpen(ctx, block.text, {wrap = .NEWLINES, font_size = metrics.font_size * 0.9})
            UiPopTag(ctx)
            ElementClose(ctx)
        case .RULE:
            ElementOpen(ctx, {layout = {size = {Grow(), Fixed(1)}}, draw = {kind = .SEPARATOR}})
            ElementClose(ctx)
        case .TABLE:
            // columns of the same width, a cell is a paragraph (it wraps, its marks are styles); the header is strong, a line under every row
            columns: int = max(block.level, 1)
            ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .TOP_TO_BOTTOM, gap = metrics.gap * 0.5}})
            line_at: int
            row_index: int
            for line_at < len(block.text) {
                row, after := markdownLine(block.text, line_at)
                line_at = after
                row_index += 1
                if row_index == 2 { continue }                      // the line of dashes
                ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = metrics.gap * 2}})
                if row_index == 1 { UiPushTag(ctx, "strong") }
                for column in 0 ..< columns {
                    cell, _ := MarkdownTableCell(row, column)       // a row with fewer cells has empty ones
                    ElementOpen(ctx, {layout = {size = {Percent(1 / f32(columns)), Fit()}}})
                    cell_link, cell_clicked := richParagraph(ctx, IdFromIndex(u32(row_index * 64 + column), paragraph), cell, metrics.font_size)
                    if cell_clicked { link, link_clicked = cell_link, true }
                    ElementClose(ctx)
                }
                if row_index == 1 { UiPopTag(ctx) }
                ElementClose(ctx)
                ElementOpen(ctx, {layout = {size = {Grow(), Fixed(1)}}, draw = {kind = .SEPARATOR}})
                ElementClose(ctx)
            }
            ElementClose(ctx)
        }
    }
    ElementClose(ctx)
    return
}
