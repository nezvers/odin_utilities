package ui

import "core:unicode/utf8"

// Text that is read can be selected and copied: everything declared inside of the tag `ui.TEXT_SELECTABLE` (labels, wrapped texts, the paragraphs of rich text and
// Markdown) is one text to the pointer. A press on it and a drag select from the letter under the press to the letter under the pointer, over lines and from one
// text to the next (the messages of a chat, the blocks of a page); the copy action puts the selection on the clipboard, a press somewhere else or the cancel
// action lets it go.
//
//     if ui.UiTagged(&ctx, ui.TEXT_SELECTABLE) { ui.UiMarkdown(&ctx, reply) }
//
// One selection for the whole ui, kept as two places: a text (by its place among the elements of the frame) and a byte in it. That is right as long as the texts
// before it stay the same from frame to frame; a list that only declares its rows in view (UiVirtual) gives its texts other places when it scrolls. The texts are
// found after the layout, so the selection follows the pointer one frame behind. Nothing is allocated: the copied text is in a buffer of the context
// (UI_SELECT_BYTES, a longer selection is cut).
//
// Baldr's selection scope (examples/27_conversation) was the reason to have it; the code is written for this library.

TEXT_SELECTABLE :: "selectable"
UI_SELECT_BYTES :: #config(UI_SELECT_BYTES, 4096)

// A place in the selectable text of a frame
@(private)
SelectPoint :: struct {
    element: i32,               // which text: its index in the elements of the frame
    offset: i32,                // a byte of that text
}

@(private)
TextSelect :: struct {
    tag: Id,
    active: bool,               // there is a selection (it may be empty: a press without a drag)
    dragging: bool,
    anchor: SelectPoint,        // where the press was
    cursor: SelectPoint,        // where the pointer is, or was when the button went up
    over: bool,                 // the pointer was over a selectable line in the last frame
    copied: [UI_SELECT_BYTES]u8,
    copied_length: int,
    whole: bool,                // the selection fit into `copied`
}

@(private)
selectOrdered :: proc "contextless" (select: ^TextSelect) -> (low: SelectPoint, high: SelectPoint) {
    low, high = select.anchor, select.cursor
    if high.element < low.element || (high.element == low.element && high.offset < low.offset) { low, high = high, low }
    return
}

@(private)
selectHasTag :: proc "contextless" (select: ^TextSelect, element: ^Element) -> bool {
    for tag in element.decl.draw.tags {
        if tag == select.tag { return true }
    }
    return false
}

// The part of a text element that is selected: bytes of its text
@(private)
selectRange :: proc "contextless" (select: ^TextSelect, index: i32, length: int) -> (from: int, to: int) {
    if !select.active { return 0, 0 }
    low, high := selectOrdered(select)
    if index < low.element || index > high.element { return 0, 0 }
    from = int(low.offset) if index == low.element else 0
    to = int(high.offset) if index == high.element else length
    return clamp(from, 0, length), clamp(to, 0, length)
}

// From the pass that makes the draw commands, for a line of a text before its own command: the rectangle of the part of the line that is selected
@(private)
selectLineCommand :: proc(ctx: ^Context, element: ^Element, line: TextLine, line_rect: Rect) {
    select: ^TextSelect = &ctx.select
    if !select.active || select.tag == 0 || !selectHasTag(select, element) { return }
    text: string = element.text.text
    index: i32 = i32((uintptr(element) - uintptr(raw_data(ctx.elements))) / size_of(Element))
    from, to := selectRange(select, index, len(text))
    from, to = max(from, int(line.start)), min(to, int(line.start + line.length))
    if to <= from { return }
    font_size: f32 = element.text.config.font_size
    outer_tags: [DRAW_TAGS]Id = ctx.measure_tags
    ctx.measure_tags = element.decl.draw.tags
    x0: f32 = measureText(ctx, text[line.start:from], font_size).x
    x1: f32 = measureText(ctx, text[line.start:to], font_size).x
    ctx.measure_tags = outer_tags
    layoutCommand(ctx, {kind = .DRAW, info = {kind = .TEXT_SELECTION, rect = {line_rect.x + x0, line_rect.y, x1 - x0, line_rect.w}}})
}

// After the layout: where the pointer is in the selectable text, what a press, a drag and the keys do to the selection, and the selected text for a copy
@(private)
selectAfterLayout :: proc(ctx: ^Context) {
    select: ^TextSelect = &ctx.select
    if select.tag == 0 { select.tag = IdFromString(TEXT_SELECTABLE) }
    input: ^Input = &ctx.input
    mouse: Vec2 = input.mouse_position
    // the line that is the nearest to the pointer: by its height first (a drag below the last line of a text is at the end of that line), then sideways
    Best :: struct {
        found: bool,
        direct: bool,           // the pointer is on the line
        vertical: f32,
        sideways: f32,
        element: i32,
        line: TextLine,
        x: f32,                 // the pointer from the start of the line
    }
    best: Best
    select.copied_length = 0
    select.whole = true
    last: i32 = -1
    for index in 0 ..< i32(ctx.element_count) {
        element: ^Element = &ctx.elements[index]
        if !element.is_text || !selectHasTag(select, element) { continue }
        data: ^TextData = &element.text
        rect: Rect = element.rect
        line_height: f32 = data.config.line_height if data.config.line_height > 0 else data.preferred.y
        for l in 0 ..< int(data.line_count) {
            line: TextLine = ctx.lines[int(data.line_start) + l]
            top: f32 = rect.y + f32(l) * line_height
            // a line that is cut away by its container (scrolled out) is not under the pointer
            if top + line_height < element.clip_rect.y || top > element.clip_rect.y + element.clip_rect.w { continue }
            shift: f32 = rect.z - line.width
            switch data.config.align {
            case .LEFT: shift = 0
            case .CENTER: shift *= 0.5
            case .RIGHT:
            }
            vertical: f32 = max(top - mouse.y, mouse.y - (top + line_height), 0)
            sideways: f32 = max(rect.x - mouse.x, mouse.x - (rect.x + rect.z), 0)
            if !best.found || vertical < best.vertical || (vertical == best.vertical && sideways < best.sideways) {
                best = {true, vertical == 0 && sideways == 0 && RectContains(element.clip_rect, mouse), vertical, sideways, index, line, mouse.x - (rect.x + shift)}
            }
        }
        // the selected part of this text, for the copy: a new line between two texts unless they stand in one row (the runs of a paragraph)
        from, to := selectRange(select, index, len(data.text))
        if to > from {
            if last >= 0 {
                before: Rect = ctx.elements[last].rect
                same_row: bool = abs((before.y + before.w) - (rect.y + rect.w)) < max(rect.w, 1) * 0.5 && rect.x >= before.x
                if !same_row { selectCopy(select, " " if data.config.continues else "\n") }
            }
            selectCopy(select, data.text[from:to])
            last = index
        }
    }
    select.over = best.found && best.direct
    if select.over && ctx.cursor == .ARROW && (ctx.hover == 0 || select.dragging) { ctx.cursor = .TEXT }
    // the place of the pointer: the nearest end of a letter of the line
    place: SelectPoint
    if best.found {
        element: ^Element = &ctx.elements[best.element]
        text: string = element.text.text[best.line.start:best.line.start + best.line.length]
        outer_tags: [DRAW_TAGS]Id = ctx.measure_tags
        ctx.measure_tags = element.decl.draw.tags
        offset: int
        nearest: f32 = abs(best.x)
        at: int
        for at < len(text) {
            _, width := utf8.decode_rune_in_string(text[at:])
            at += width
            distance: f32 = abs(best.x - measureText(ctx, text[:at], element.text.config.font_size).x)
            if distance < nearest {
                nearest = distance
                offset = at
            }
        }
        ctx.measure_tags = outer_tags
        place = {best.element, best.line.start + i32(offset)}
    }
    if input.mouse_pressed {
        // a press on a text that no widget took starts a selection, any other press lets the selection go
        if best.found && best.direct && ctx.active == 0 {
            select.active, select.dragging = true, true
            select.anchor, select.cursor = place, place
        } else {
            select.active, select.dragging = false, false
        }
    } else if select.dragging {
        if best.found { select.cursor = place }
        if !input.mouse_down { select.dragging = false }
    }
    if !select.active { return }
    if ctx.cancel_pending {
        select.active, select.dragging = false, false
        return
    }
    // copy, unless a text field that is edited has the keys
    focused: ^WidgetState = stateFind(ctx, ctx.focus)
    if .COPY in input.actions && select.copied_length > 0 && !(focused != nil && focused.editing) {
        UiClipboardSet(ctx, string(select.copied[:select.copied_length]))
    }
}

@(private)
selectCopy :: proc "contextless" (select: ^TextSelect, text: string) {
    count: int = min(len(text), len(select.copied) - select.copied_length)
    if count < len(text) {
        select.whole = false
        for count > 0 && !utf8.rune_start(text[count]) { count -= 1 }
    }
    copy(select.copied[select.copied_length:], text[:count])
    select.copied_length += count
}

// The selected text as of the last frame (valid until the next UiEnd); `whole` is false when it was longer than UI_SELECT_BYTES and is cut. Empty when nothing
// is selected.
UiTextSelected :: proc(ctx: ^Context) -> (text: string, whole: bool) {
    if !ctx.select.active { return "", true }
    return string(ctx.select.copied[:ctx.select.copied_length]), ctx.select.whole
}

// Lets the selection go
UiTextSelectionClear :: proc(ctx: ^Context) {
    ctx.select.active, ctx.select.dragging = false, false
}
