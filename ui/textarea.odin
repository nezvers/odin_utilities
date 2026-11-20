package ui

// A text of several lines: new lines, word wrap, a selection that runs over lines, up and down, Home and End of a line, a scrollbar. It edits the buffer of the program
// like the text field (same keys, same clipboard, see textedit.odin) and keeps nothing else.
//
//     changed := ui.UiTextArea(&ctx, "Notes", buffer[:], &length, {ui.Fixed(300), ui.Fixed(120)})
//
// The lines are found each frame from the text and the width (a fixed table of UI_TEXT_AREA_LINES lines: a longer text shows its first lines), and only the lines that are in view
// become elements: a line of text, the rectangles of the selection and the caret are absolute children of the area. The style draws the kinds TEXT_AREA, TEXT_SELECTION,
// TEXT_CARET and SCROLLBAR.

import "core:unicode/utf8"

UI_TEXT_AREA_LINES :: #config(UI_TEXT_AREA_LINES, 2048)
UI_TEXT_AREA_CACHES :: #config(UI_TEXT_AREA_CACHES, 4)      // text areas whose rows are kept from one frame to the next (the least recently used one is replaced)

// The rows of one text area as they were found, with what they depend on: they are used again while the text, the width, the wrap and the font are the same.
@(private)
AreaCache :: struct {
    id: Id,                 // 0: free
    key: u64,
    count: int,
    used: u32,              // the frame it was used in last
    states_key: u64,        // the key the highlight states of the rows were found for (0: they are not), by which highlighter
    states_for: TextHighlight,
    states_user: rawptr,
    rows: [UI_TEXT_AREA_LINES]AreaLine,
}

@(private)
AreaCaches :: struct {
    entries: [UI_TEXT_AREA_CACHES]AreaCache,
    hits: u64,              // rows that were found again without measuring / that were measured
    misses: u64,
}

// What the rows of a text depend on, in one number: the bytes of the text, the width, the wrap, the font size and the generation of the measure cache (a new font or scale).
@(private)
areaKey :: proc(ctx: ^Context, text: string, max_width: f32, wrap: bool) -> u64 {
    hash: u64 = 14695981039346656037
    for byte in transmute([]u8)text {
        hash ~= u64(byte)
        hash *= 1099511628211
    }
    for part in ([4]u64{u64(transmute(u32)max_width), u64(transmute(u32)ctx.style.metrics.font_size), u64(ctx.measure_cache.epoch), u64(wrap)}) {
        hash ~= part
        hash *= 1099511628211
    }
    return hash | 1
}

// The rows of the text of the area `owner` in `ctx.area_lines`: the ones kept from the last time when nothing they depend on changed, else they are found (areaLines) and kept.
@(private)
areaLinesCached :: proc(ctx: ^Context, owner: Id, text: string, max_width: f32, wrap: bool) -> int {
    key: u64 = areaKey(ctx, text, max_width, wrap)
    caches: ^AreaCaches = &ctx.area_caches
    slot: ^AreaCache
    for &entry in caches.entries {
        if entry.id == owner { slot = &entry }
    }
    if slot != nil && slot.key == key {
        count: int = slot.count
        copy(ctx.area_lines[:count], slot.rows[:count])
        slot.used = ctx.frame
        caches.hits += 1
        return count
    }
    count: int = areaLines(ctx, text, max_width, wrap)
    caches.misses += 1
    if slot == nil {
        // a free slot, else the one that was used the longest ago
        slot = &caches.entries[0]
        for &entry in caches.entries {
            if entry.id == 0 {
                slot = &entry
                break
            }
            if entry.used < slot.used { slot = &entry }
        }
    }
    slot.id, slot.key, slot.count, slot.used = owner, key, count, ctx.frame
    copy(slot.rows[:count], ctx.area_lines[:count])
    return count
}

// The highlight state of every row of the area `owner` (in `ctx.area_lines`): one run of the highlighter over all rows when the text, the rows or the highlighter
// changed, kept with the rows after that.
@(private)
areaStates :: proc(ctx: ^Context, owner: Id, text: string, count: int, highlight: TextHighlight, user: rawptr) {
    slot: ^AreaCache
    for &entry in ctx.area_caches.entries {
        if entry.id == owner { slot = &entry }
    }
    if slot != nil && slot.count == count && slot.states_key == slot.key && slot.states_for == highlight && slot.states_user == user { return }
    spans: [AREA_SPANS]TextSpan
    state: u32
    for i in 0 ..< count {
        line: ^AreaLine = &ctx.area_lines[i]
        line.state = state
        highlight(text, int(line.start), int(line.end), spans[:], user, &state)
    }
    if slot != nil && slot.count == count {
        copy(slot.rows[:count], ctx.area_lines[:count])
        slot.states_key, slot.states_for, slot.states_user = slot.key, highlight, user
    }
}

// One row of the text on the screen: a part of a line of the text that fits the width (or the whole line), `hard` when it ends at a new line.
@(private)
AreaLine :: struct {
    start: u32,
    end: u32,               // without the new line
    hard: bool,
    state: u32,             // what the highlighter has open at the start of the row (areaStates)
}

// Finds the rows of `text` for a width: the table of the context. Returns how many. Words are not broken unless one alone is wider than the width.
@(private)
areaLines :: proc(ctx: ^Context, text: string, max_width: f32, wrap: bool) -> int {
    lines: []AreaLine = ctx.area_lines[:]
    count: int
    emit :: proc(lines: []AreaLine, count: ^int, start: int, end: int, hard: bool) {
        if count^ < len(lines) {
            lines[count^] = {u32(start), u32(end), hard, 0}
            count^ += 1
        }
    }
    font: f32 = ctx.style.metrics.font_size
    start: int
    for count < len(lines) {
        newline: int = start
        for newline < len(text) && text[newline] != '\n' { newline += 1 }
        hard: bool = newline < len(text)
        row: int = start
        if !wrap || max_width <= 0 {
            emit(lines, &count, start, newline, hard)
        } else {
            for count < len(lines) {
                // the longest run of words that fits (spaces before a word go with it, spaces after the last one hang over the edge)
                fit: int = row
                position: int = row
                for position < newline {
                    word_end: int = position
                    for word_end < newline && text[word_end] == ' ' { word_end += 1 }
                    for word_end < newline && text[word_end] != ' ' { word_end += 1 }
                    if measureText(ctx, text[row:word_end], font).x > max_width { break }
                    fit = word_end
                    position = word_end
                }
                if position >= newline {
                    emit(lines, &count, row, newline, hard)
                    break
                }
                if fit == row {
                    // a word wider than the room: as many runes as fit (at least one)
                    next: int = row
                    for next < newline {
                        _, width := utf8.decode_rune_in_string(text[next:])
                        if next > row && measureText(ctx, text[row:next + width], font).x > max_width { break }
                        next += width
                    }
                    fit = next
                }
                end: int = fit
                for end < newline && text[end] == ' ' { end += 1 }
                emit(lines, &count, row, end, false)
                row = end
            }
        }
        if !hard { break }
        start = newline + 1
    }
    return max(count, 1)
}

// The row a byte offset is on: the cursor at the end of a row that wrapped is at the start of the next one.
@(private)
areaLineOf :: proc(lines: []AreaLine, count: int, offset: int) -> int {
    for i in 0 ..< count {
        line: AreaLine = lines[i]
        if offset < int(line.end) { return i }
        if offset == int(line.end) && (line.hard || i == count - 1) { return i }
    }
    return max(count - 1, 0)
}

// The farthest the cursor may go on a row: the end of a hard row or of the last one, one rune before the end of a row that wrapped (after that it would be on the next row).
@(private)
areaLineLimit :: proc(text: string, line: AreaLine, last: bool) -> int {
    if line.hard || last || line.end <= line.start { return int(line.end) }
    _, width := utf8.decode_last_rune_in_string(text[:line.end])
    return int(line.end) - width
}

// A text of several lines in a scrolling box. True when the text changed. `wrap` breaks long lines at words (else they are cut by the box).
// `highlight` colors the words of the rows (highlight.odin: `ui.HighlightCode` for code), `highlight_user` is passed to it.
UiTextArea :: proc(ctx: ^Context, name: string, buffer: []u8, length: ^int, size: Size = {}, wrap: bool = true, disabled: bool = false, highlight: TextHighlight = nil, highlight_user: rawptr = nil) -> (changed: bool) {
    // the lines are measured with the tags the area is declared in (a "mono" area wraps by the widths of the code face)
    for i in 0 ..< min(ctx.tag_count, DRAW_TAGS) { ctx.measure_tags[i] = ctx.tag_stack[ctx.tag_count - 1 - i] }
    defer ctx.measure_tags = {}
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    length^ = clamp(length^, 0, len(buffer))
    state.cursor = clamp(state.cursor, 0, length^)
    state.anchor = clamp(state.anchor, 0, length^)
    state.own_vertical = true

    padding: Vec2 = {metrics.padding.x, metrics.padding.y}
    line_height: f32 = max(measureText(ctx, "A", metrics.font_size).y, metrics.font_size) * 1.1
    view: Rect = state.rect
    bar_width: f32 = metrics.scrollbar_width
    room: f32 = view.z - 2 * padding.x - bar_width                 // from the last frame: the first one has no wrap
    text: string = string(buffer[:length^])
    count: int = areaLinesCached(ctx, id, text, room if view.z > 0 else 0, wrap)
    lines: []AreaLine = ctx.area_lines[:]

    cursor_on_screen :: proc(ctx: ^Context, text: string, lines: []AreaLine, count: int, offset: int, line_height: f32, padding: Vec2) -> (position: Vec2, row: int) {
        row = areaLineOf(lines, count, offset)
        start: int = int(lines[row].start)
        position = {padding.x + measureText(ctx, text[start:offset], ctx.style.metrics.font_size).x, padding.y + f32(row) * line_height}
        return
    }
    // the cursor at a point of the screen
    cursor_at :: proc(ctx: ^Context, text: string, lines: []AreaLine, count: int, point: Vec2, view: Rect, scroll: f32, line_height: f32, padding: Vec2) -> int {
        row: int = clamp(int((point.y - view.y - padding.y - scroll) / line_height), 0, count - 1)
        line: AreaLine = lines[row]
        limit: int = areaLineLimit(text, line, row == count - 1)
        within: int = textFieldCursorAt(ctx, text[int(line.start):limit], point.x - view.x - padding.x)
        return int(line.start) + within
    }

    // the pointer: a press puts the cursor there, dragging selects, a double click takes a word
    if interaction.hovered && ctx.input.mouse_pressed {
        ctx.focus = id
        state.cursor = cursor_at(ctx, text, lines, count, ctx.input.mouse_position, view, state.scroll.y, line_height, padding)
        if .SHIFT not_in ctx.input.modifiers { state.anchor = state.cursor }
        if interaction.double_clicked { state.anchor, state.cursor = textWordAt(text, state.cursor) }
    } else if interaction.pressed && ctx.input.mouse_down && !ctx.input.mouse_pressed && ctx.focus == id {
        state.cursor = cursor_at(ctx, text, lines, count, ctx.input.mouse_position, view, state.scroll.y, line_height, padding)
    }
    state.editing = ctx.focus == id && !disabled

    if state.editing {
        // where the cursor is now: up and down keep the column it was left at
        if state.last_cursor != state.cursor {
            position, _ := cursor_on_screen(ctx, text, lines, count, state.cursor, line_height, padding)
            state.column = position.x - padding.x
        }
        changed, _ = textFieldEdit(ctx, state, buffer, length, true)
        input: ^Input = &ctx.input
        shift: bool = .SHIFT in input.modifiers
        ctrl: bool = .CTRL in input.modifiers
        if .ENTER in input.keys && !ctrl {
            changed = textInsert(state, buffer, length, "\n") || changed
        }
        text = string(buffer[:length^])
        if changed { count = areaLinesCached(ctx, id, text, room if view.z > 0 else 0, wrap) }
        row: int = areaLineOf(lines, count, state.cursor)
        move :: proc(state: ^WidgetState, to: int, extend: bool) {
            state.cursor = to
            if !extend { state.anchor = to }
        }
        vertical: int
        if .UP in input.actions { vertical = -1 }
        if .DOWN in input.actions { vertical = 1 }
        if .PAGE_UP in input.actions { vertical = -max(int(view.w / line_height) - 1, 1) }
        if .PAGE_DOWN in input.actions { vertical = max(int(view.w / line_height) - 1, 1) }
        if vertical != 0 {
            target: int = row + vertical
            if target < 0 {
                move(state, 0, shift)
            } else if target >= count {
                move(state, length^, shift)
            } else {
                line: AreaLine = lines[target]
                within: int = textFieldCursorAt(ctx, text[int(line.start):areaLineLimit(text, line, target == count - 1)], state.column)
                move(state, int(line.start) + within, shift)
            }
        }
        if .HOME in input.keys {
            move(state, 0 if ctrl else int(lines[row].start), shift)
        }
        if .END in input.keys {
            move(state, length^ if ctrl else areaLineLimit(text, lines[row], row == count - 1), shift)
        }
        if vertical != 0 {
            state.last_cursor = state.cursor            // the column stays: it is not a move to a new place
        }
    }
    text = string(buffer[:length^])
    count = areaLinesCached(ctx, id, text, room if view.z > 0 else 0, wrap)

    // scrolling: the wheel, and the cursor stays in view when it moved
    content: f32 = f32(count) * line_height + 2 * padding.y
    view_height: f32 = view.w
    if ctx.hover_scroll == id && ctx.input.wheel.y != 0 {
        state.scroll.y += ctx.input.wheel.y * scrollStep(ctx, state)
    }
    cursor_position, _ := cursor_on_screen(ctx, text, lines, count, state.cursor, line_height, padding)
    if state.editing && state.shown_cursor != state.cursor && view_height > 0 {
        top: f32 = cursor_position.y + state.scroll.y
        if top < padding.y {
            state.scroll.y += padding.y - top
        } else if top + line_height > view_height - padding.y {
            state.scroll.y -= top + line_height - (view_height - padding.y)
        }
    }
    state.shown_cursor = state.cursor
    limit: f32 = max(content - view_height, 0)
    state.scroll.y = clamp(state.scroll.y, -limit, 0)

    default_size: Size = {Fixed(metrics.control_width * 2), Fixed(metrics.control_height * 4)}
    ElementOpen(ctx, {
        id = id,
        layout = {size = {axisOrDefault(size.width, default_size.width.min), axisOrDefault(size.height, default_size.height.min)}},
        hit = {} if disabled else {.INTERACTIVE, .SCROLL},
        cursor = .TEXT,
        clip = {horizontal = true, vertical = true, cut = true, offset = state.scroll},
        draw = {kind = .TEXT_AREA, name = IdSplitName(name), text = text, font_size = metrics.font_size, flags = ({.DISABLED} if disabled else {}) + ({.FOCUSED} if ctx.focus == id else {})},
    })
    if highlight != nil { areaStates(ctx, id, text, count, highlight, highlight_user) }
    // only the rows in view become elements
    first: int = clamp(int(-state.scroll.y / line_height), 0, count - 1)
    last: int = min(first + int(view_height / line_height) + 2, count - 1)
    focused: bool = ctx.focus == id
    low, high: int = textSelection(state)
    for row in first ..= last {
        line: AreaLine = lines[row]
        y: f32 = padding.y + f32(row) * line_height
        if focused && high > low && low <= int(line.end) && high >= int(line.start) && !(high == int(line.start) && row > 0) {
            from: int = max(low, int(line.start))
            to: int = min(high, int(line.end))
            x0: f32 = measureText(ctx, text[int(line.start):from], metrics.font_size).x
            x1: f32 = measureText(ctx, text[int(line.start):to], metrics.font_size).x
            if high > int(line.end) && line.hard { x1 += metrics.font_size * 0.4 }          // the new line is selected too: a little room after the text
            if x1 > x0 {
                ElementOpen(ctx, {layout = {size = {Fixed(x1 - x0), Fixed(line_height)}}, absolute = {enabled = true, offset = {padding.x + x0, y}}, draw = {kind = .TEXT_SELECTION}})
                ElementClose(ctx)
            }
        }
        if line.end > line.start && highlight == nil {
            shown: string = text[int(line.start):int(line.end)]
            ElementOpen(ctx, {
                layout = {size = {Fixed(measureText(ctx, shown, metrics.font_size).x), Fixed(line_height)}},
                absolute = {enabled = true, offset = {padding.x, y}},
            })
            TextOpen(ctx, shown, {wrap = .NONE})
            ElementClose(ctx)
        } else if line.end > line.start {
            // a text per span, each where the text before it ends (the same measure the caret and the selection are placed by)
            spans: [AREA_SPANS]TextSpan
            row_state: u32 = line.state
            span_count: int = clamp(highlight(text, int(line.start), int(line.end), spans[:], highlight_user, &row_state), 0, AREA_SPANS)
            at: int = int(line.start)
            for index in 0 ..= span_count {
                // after the spans: what they did not cover, plain
                span: TextSpan = spans[index] if index < span_count else {int(line.end) - at, ""}
                piece_end: int = min(at + span.length, int(line.end))
                if piece_end <= at { continue }
                piece: string = text[at:piece_end]
                x: f32 = measureText(ctx, text[int(line.start):at], metrics.font_size).x
                ElementOpen(ctx, {
                    layout = {size = {Fixed(measureText(ctx, piece, metrics.font_size).x), Fixed(line_height)}},
                    absolute = {enabled = true, offset = {padding.x + x, y}},
                })
                if span.tag != "" { UiPushTag(ctx, span.tag) }
                TextOpen(ctx, piece, {wrap = .NONE})
                if span.tag != "" { UiPopTag(ctx) }
                ElementClose(ctx)
                at = piece_end
            }
        }
    }
    if focused {
        ElementOpen(ctx, {layout = {size = {Fixed(2), Fixed(line_height)}}, absolute = {enabled = true, offset = cursor_position}, draw = {kind = .TEXT_CARET}})
        ElementClose(ctx)
    }
    if limit > 0 {
        // the scrollbar stays where it is while the text moves under it
        ElementOpen(ctx, {
            layout = {size = {Fixed(bar_width), Fixed(view_height)}},
            absolute = {enabled = true, offset = {view.z - bar_width, -state.scroll.y}},
            draw = {kind = .SCROLLBAR, value = clamp(-state.scroll.y / limit, 0, 1), ratio = clamp(view_height / content, 0, 1)},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
    return
}
