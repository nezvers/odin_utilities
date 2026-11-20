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
// before it stay the same from frame to frame. The texts are found after the layout, so the selection follows the pointer one frame behind. Nothing is allocated:
// the copied text is in a buffer of the context (UI_SELECT_BYTES, a longer selection is cut).
//
// A list that declares only the rows in view (UiVirtual, UiTable) gives its texts other places when it scrolls, and the rows out of view are no texts at all. Such a
// list is told to the selection: `group := ui.UiSelectRows(&ctx, "log", count, row_text, user)` before it, and `if ui.UiSelectRow(&ctx, group, row) { ... }` around
// the texts of every row it declares. A place in a row is then the row, the text of the row (its cell: the selectable texts of a row are numbered in the order they
// are declared) and a byte of it, so it stays right when the list scrolls, and the rows between the ends of the selection are copied from `cell_text(user, row, cell)`,
// the text of any cell as the program has it. A row with several cells (a table) is copied with a tab between its cells and a new line between its rows.
//
// Baldr's selection scope (examples/27_conversation) was the reason to have it; the code is written for this library.

TEXT_SELECTABLE :: "selectable"
UI_SELECT_BYTES :: #config(UI_SELECT_BYTES, 4096)

// The text of the cell `cell` of the row `row` of a list that was told to the selection: the bytes of the text that the row declares there. It is called after the
// layout, for the cells between the ends of the selection, in order, and has to give a string that is valid when it returns (it is copied at once).
SelectRowText :: proc(user: rawptr, row: int, cell: int) -> string

UI_SELECT_GROUPS :: #config(UI_SELECT_GROUPS, 8)

@(private)
SelectGroup :: struct {
    id: Id,
    base: i32,                  // the elements declared before the list: where the list is among the other texts
    count: int,
    cells: int,                 // the selectable texts of a row
    row_text: SelectRowText,
    user: rawptr,
}

// A place in the selectable text of a frame
@(private)
SelectPoint :: struct {
    group: Id,                  // 0: a text of its own; else the list it is a row of
    element: i32,               // which text: its index in the elements of the frame, or its row in the list
    offset: i32,                // a byte of that text
    cell: i32,                  // in a list: which text of the row
}

// Where a place is among all the places: the position (a text counts twice its place plus one, a list twice its base, so that a list comes before a text that is
// declared after it), the list, the row. Compared one after the other.
@(private)
SelectKey :: [4]i32

@(private)
selectKeyLess :: proc "contextless" (a: SelectKey, b: SelectKey) -> bool {
    for i in 0 ..< 4 {
        if a[i] != b[i] { return a[i] < b[i] }
    }
    return false
}

@(private)
TextSelect :: struct {
    tag: Id,
    active: bool,               // there is a selection (it may be empty: a press without a drag)
    dragging: bool,
    anchor: SelectPoint,        // where the press was
    cursor: SelectPoint,        // where the pointer is, or was when the button went up
    over: bool,                 // the pointer was over a selectable line in the last frame
    press_time: f64,            // the last press on a text and where it was: a press at the same place soon after is a double click
    press_place: SelectPoint,
    presses: int,
    groups: [UI_SELECT_GROUPS]SelectGroup,
    group_count: int,
    row_group: Id,              // while a row is declared (UiSelectRow): the list and the row of the texts that are declared
    row_index: i32,
    row_cells: i32,             // the selectable texts that the row has declared so far
    copied: [UI_SELECT_BYTES]u8,
    copied_length: int,
    whole: bool,                // the selection fit into `copied`
}

@(private)
selectGroupSlot :: proc "contextless" (select: ^TextSelect, group: Id) -> int {
    for i in 0 ..< select.group_count {
        if select.groups[i].id == group { return i }
    }
    return -1
}

// Where a place is (false: it is a row of a list that is not declared in this frame)
@(private)
selectKeyOf :: proc "contextless" (select: ^TextSelect, point: SelectPoint) -> (key: SelectKey, ok: bool) {
    if point.group == 0 { return {2 * point.element + 1, 0, 0, 0}, true }
    slot: int = selectGroupSlot(select, point.group)
    if slot < 0 { return {}, false }
    return {2 * select.groups[slot].base, i32(slot) + 1, point.element, point.cell}, true
}

// Where a text of the frame is
@(private)
selectElementKey :: proc "contextless" (select: ^TextSelect, element: ^Element, index: i32) -> SelectKey {
    if element.text.select_group != 0 {
        if key, ok := selectKeyOf(select, {group = element.text.select_group, element = element.text.select_row, cell = element.text.select_cell}); ok { return key }
    }
    return {2 * index + 1, 0, 0, 0}
}

// The place of a letter of a text of the frame
@(private)
selectPointOf :: proc "contextless" (ctx: ^Context, index: i32, offset: i32) -> SelectPoint {
    element: ^Element = &ctx.elements[index]
    if element.text.select_group != 0 && selectGroupSlot(&ctx.select, element.text.select_group) >= 0 {
        return {group = element.text.select_group, element = element.text.select_row, offset = offset, cell = element.text.select_cell}
    }
    return {element = index, offset = offset}
}

// The text of the frame a place is in (-1: it is not declared, a row of a list that is out of view)
@(private)
selectElementOf :: proc "contextless" (ctx: ^Context, point: SelectPoint) -> i32 {
    if point.group == 0 {
        if point.element < 0 || point.element >= i32(ctx.element_count) { return -1 }
        return point.element
    }
    for index in 0 ..< i32(ctx.element_count) {
        element: ^Element = &ctx.elements[index]
        if element.is_text && element.text.select_group == point.group && element.text.select_row == point.element && element.text.select_cell == point.cell { return index }
    }
    return -1
}

// The ends of the selection in order: the places and where they are. False when one of them is a row of a list that is not there.
@(private)
selectOrdered :: proc "contextless" (select: ^TextSelect) -> (low: SelectPoint, high: SelectPoint, low_key: SelectKey, high_key: SelectKey, ok: bool) {
    first, first_ok := selectKeyOf(select, select.anchor)
    second, second_ok := selectKeyOf(select, select.cursor)
    if !first_ok || !second_ok { return }
    low, high, low_key, high_key = select.anchor, select.cursor, first, second
    if selectKeyLess(second, first) || (second == first && select.cursor.offset < select.anchor.offset) {
        low, high, low_key, high_key = select.cursor, select.anchor, second, first
    }
    return low, high, low_key, high_key, true
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
selectRange :: proc "contextless" (select: ^TextSelect, element: ^Element, index: i32, length: int) -> (from: int, to: int) {
    if !select.active { return 0, 0 }
    low, high, low_key, high_key, ok := selectOrdered(select)
    if !ok { return 0, 0 }
    key: SelectKey = selectElementKey(select, element, index)
    if selectKeyLess(key, low_key) || selectKeyLess(high_key, key) { return 0, 0 }
    from = int(low.offset) if key == low_key else 0
    to = int(high.offset) if key == high_key else length
    return clamp(from, 0, length), clamp(to, 0, length)
}

// Tells the selection that the rows of a list are its texts: call it right before the list is declared. `count` rows, `row_text` gives the text of any of them (see
// SelectRowText) and `cells` selectable texts in each row (a table: one for every column that has text). Returns the list for UiSelectRow. When the lists of a
// frame are more than UI_SELECT_GROUPS the others are not selectable.
UiSelectRows :: proc(ctx: ^Context, name: string, count: int, row_text: SelectRowText, user: rawptr = nil, cells: int = 1) -> Id {
    id: Id = UiId(ctx, name)
    select: ^TextSelect = &ctx.select
    if select.group_count < len(select.groups) && selectGroupSlot(select, id) < 0 {
        select.groups[select.group_count] = {id = id, base = i32(ctx.element_count), count = count, cells = max(cells, 1), row_text = row_text, user = user}
        select.group_count += 1
    }
    return id
}

// The text that is declared inside of this block is the row `row` of the list `group`: `if ui.UiSelectRow(&ctx, group, i) { ui.UiLabel(&ctx, line) }`
@(deferred_in = UiSelectRowEnd)
UiSelectRow :: proc(ctx: ^Context, group: Id, row: int) -> bool {
    ctx.select.row_group, ctx.select.row_index, ctx.select.row_cells = group, i32(row), 0
    return true
}

UiSelectRowEnd :: proc(ctx: ^Context, group: Id, row: int) {
    ctx.select.row_group, ctx.select.row_index, ctx.select.row_cells = 0, 0, 0
}

// The selected rows of a list for the copy: from the place `low` of the selection to the place `high`, as far as they are in this list. The cells of a row are
// separated by a tab, the rows by a new line.
@(private)
selectCopyGroup :: proc(ctx: ^Context, slot: int, low: SelectPoint, high: SelectPoint, low_key: SelectKey, high_key: SelectKey) {
    select: ^TextSelect = &ctx.select
    group: ^SelectGroup = &select.groups[slot]
    if group.count <= 0 || group.row_text == nil { return }
    last_cell: int = group.cells - 1
    first: SelectKey = {2 * group.base, i32(slot) + 1, 0, 0}
    final: SelectKey = {2 * group.base, i32(slot) + 1, i32(group.count) - 1, i32(last_cell)}
    if selectKeyLess(final, low_key) || selectKeyLess(high_key, first) { return }
    start_row, start_cell, start_offset: int = 0, 0, 0
    if !selectKeyLess(low_key, first) { start_row, start_cell, start_offset = int(low_key[2]), int(low_key[3]), int(low.offset) }
    end_row, end_cell, end_offset: int = group.count - 1, last_cell, -1       // -1: to the end of the text of the cell
    if !selectKeyLess(final, high_key) { end_row, end_cell, end_offset = int(high_key[2]), int(high_key[3]), int(high.offset) }
    for row in start_row ..= end_row {
        if !select.whole { return }
        first_cell: int = start_cell if row == start_row else 0
        final_cell: int = end_cell if row == end_row else last_cell
        if select.copied_length > 0 { selectCopy(select, "\n") }
        for cell in first_cell ..= final_cell {
            text: string = group.row_text(group.user, row, cell)
            from: int = clamp(start_offset if row == start_row && cell == start_cell else 0, 0, len(text))
            to: int = clamp(end_offset if row == end_row && cell == end_cell && end_offset >= 0 else len(text), 0, len(text))
            if cell > first_cell { selectCopy(select, "\t") }
            if to > from { selectCopy(select, text[from:to]) }
        }
    }
}

// From the pass that makes the draw commands, for a line of a text before its own command: the rectangle of the part of the line that is selected
@(private)
selectLineCommand :: proc(ctx: ^Context, element: ^Element, line: TextLine, line_rect: Rect) {
    select: ^TextSelect = &ctx.select
    if !select.active || select.tag == 0 || !selectHasTag(select, element) { return }
    text: string = element.text.text
    index: i32 = i32((uintptr(element) - uintptr(raw_data(ctx.elements))) / size_of(Element))
    from, to := selectRange(select, element, index, len(text))
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
    first_text, last_text: i32 = -1, -1                   // the first and the last selectable text of the frame
    // a selection that has an end in a list that is not declared in this frame (another page) is gone
    low, high, low_key, high_key, ordered := selectOrdered(select)
    if select.active && !ordered { select.active, select.dragging = false, false }
    for index in 0 ..= i32(ctx.element_count) {
        // the lists that stand here: the rows between the ends of the selection, from the program's own texts
        if select.active {
            for slot in 0 ..< select.group_count {
                if select.groups[slot].base == index { selectCopyGroup(ctx, slot, low, high, low_key, high_key) }
            }
        }
        if index == i32(ctx.element_count) { break }
        element: ^Element = &ctx.elements[index]
        if !element.is_text || !selectHasTag(select, element) { continue }
        data: ^TextData = &element.text
        rect: Rect = element.rect
        if element.text.select_group == 0 || selectGroupSlot(select, element.text.select_group) < 0 {
            if first_text < 0 { first_text = index }
            last_text = index
        }
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
        // the selected part of this text, for the copy: a new line between two texts unless they stand in one row (the runs of a paragraph); the rows of a list
        // are copied from the program's texts, where the list stands
        if element.text.select_group != 0 && selectGroupSlot(select, element.text.select_group) >= 0 { continue }
        from, to := selectRange(select, element, index, len(data.text))
        if to > from {
            if last >= 0 {
                if !selectSameRow(ctx, last, index) { selectCopy(select, " " if data.config.continues else "\n") }
            } else if select.copied_length > 0 {
                selectCopy(select, "\n")
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
        place = selectPointOf(ctx, best.element, best.line.start + i32(offset))
    }
    if input.mouse_pressed {
        // a press on a text that no widget took starts a selection, any other press lets the selection go
        if best.found && best.direct && ctx.active == 0 && select.active && .SHIFT in input.modifiers {
            // with Shift: from where the selection started to here
            select.cursor, select.dragging = place, true
        } else if best.found && best.direct && ctx.active == 0 {
            again: bool = ctx.time - select.press_time <= DOUBLE_CLICK_SECONDS && select.press_place.group == place.group && select.press_place.element == place.element && abs(select.press_place.offset - place.offset) <= 1
            select.presses = select.presses + 1 if again else 1
            select.press_time, select.press_place = ctx.time, place
            select.active, select.dragging = true, true
            select.anchor, select.cursor = place, place
            whole: string = ctx.elements[best.element].text.text
            switch select.presses {
            case 1:
            case 2:
                // the word under the pointer
                from, to := textWordAt(whole, int(place.offset))
                select.anchor, select.cursor = selectPointOf(ctx, best.element, i32(from)), selectPointOf(ctx, best.element, i32(to))
                select.dragging = false
            case:
                // the whole paragraph: the texts before and after this one that stand in its row or go on from its line (the runs and lines of a rich text)
                first, final: i32 = best.element, best.element
                for {
                    previous: i32 = selectNeighbor(ctx, first, -1)
                    if previous < 0 || !(selectSameRow(ctx, previous, first) || ctx.elements[first].text.config.continues) { break }
                    first = previous
                }
                for {
                    next: i32 = selectNeighbor(ctx, final, 1)
                    if next < 0 || !(selectSameRow(ctx, final, next) || ctx.elements[next].text.config.continues) { break }
                    final = next
                }
                select.anchor, select.cursor = selectPointOf(ctx, first, 0), selectPointOf(ctx, final, i32(len(ctx.elements[final].text.text)))
                select.dragging = false
            }
        } else {
            select.active, select.dragging = false, false
        }
    } else if select.dragging {
        if best.found { select.cursor = place }
        if !input.mouse_down { select.dragging = false }
    }
    // select all, when the keys are not a text field's and the pointer is over the text or a part of it is selected: every selectable text of the frame
    focused: ^WidgetState = stateFind(ctx, ctx.focus)
    editing: bool = focused != nil && focused.editing
    if .SELECT_ALL in input.actions && !editing && (first_text >= 0 || select.group_count > 0) && (select.active || select.over) {
        // from the first place to the last of all: the texts of their own and the rows of the lists
        start, finish: SelectPoint
        start_key, finish_key: SelectKey
        have: bool
        consider :: proc(select: ^TextSelect, point: SelectPoint, end: bool, start, finish: ^SelectPoint, start_key, finish_key: ^SelectKey, have: ^bool) {
            key, _ := selectKeyOf(select, point)
            if !have^ || selectKeyLess(key, start_key^) { start^, start_key^ = point, key }
            if !have^ || selectKeyLess(finish_key^, key) { finish^, finish_key^ = point, key }
            have^ = true
        }
        if first_text >= 0 {
            consider(select, {element = first_text}, false, &start, &finish, &start_key, &finish_key, &have)
            consider(select, {element = last_text, offset = i32(len(ctx.elements[last_text].text.text))}, true, &start, &finish, &start_key, &finish_key, &have)
        }
        for slot in 0 ..< select.group_count {
            group: ^SelectGroup = &select.groups[slot]
            if group.count <= 0 || group.row_text == nil { continue }
            consider(select, {group = group.id}, false, &start, &finish, &start_key, &finish_key, &have)
            consider(select, {group = group.id, element = i32(group.count) - 1, cell = i32(group.cells) - 1, offset = i32(len(group.row_text(group.user, group.count - 1, group.cells - 1)))}, true, &start, &finish, &start_key, &finish_key, &have)
        }
        select.active, select.dragging = true, false
        select.anchor, select.cursor = start, finish
        // the copy was made for the selection of before: make it again for this one
        select.copied_length, select.whole = 0, true
        low, high, low_key, high_key, ordered = selectOrdered(select)
        for index in 0 ..= i32(ctx.element_count) {
            for slot in 0 ..< select.group_count {
                if select.groups[slot].base == index { selectCopyGroup(ctx, slot, low, high, low_key, high_key) }
            }
            if index == i32(ctx.element_count) { break }
            element: ^Element = &ctx.elements[index]
            if !element.is_text || !selectHasTag(select, element) { continue }
            if element.text.select_group != 0 && selectGroupSlot(select, element.text.select_group) >= 0 { continue }
            from, to := selectRange(select, element, index, len(element.text.text))
            if to > from {
                if last >= 0 {
                    if !selectSameRow(ctx, last, index) { selectCopy(select, " " if element.text.config.continues else "\n") }
                } else if select.copied_length > 0 {
                    selectCopy(select, "\n")
                }
                selectCopy(select, element.text.text[from:to])
                last = index
            }
        }
    }
    if !select.active { return }
    if ctx.cancel_pending {
        select.active, select.dragging = false, false
        return
    }
    if !select.dragging && selectKeysTaken(ctx, input^) != {} { selectKeys(ctx) }
    // copy, unless a text field that is edited has the keys
    if .COPY in input.actions && select.copied_length > 0 && !editing {
        UiClipboardSet(ctx, string(select.copied[:select.copied_length]))
    }
}

// Two selectable texts, the second after the first, stand in one row (the runs of a line of a paragraph)
@(private)
selectSameRow :: proc(ctx: ^Context, first: i32, second: i32) -> bool {
    before: Rect = ctx.elements[first].rect
    rect: Rect = ctx.elements[second].rect
    return abs((before.y + before.w) - (rect.y + rect.w)) < max(rect.w, 1) * 0.5 && rect.x >= before.x
}

// The selectable text before (-1) or after (1) the text `index` among the elements of the frame, -1 when there is none
@(private)
selectNeighbor :: proc(ctx: ^Context, index: i32, step: i32) -> i32 {
    at: i32 = index + step
    for at >= 0 && at < i32(ctx.element_count) {
        element: ^Element = &ctx.elements[at]
        if element.is_text && selectHasTag(&ctx.select, element) { return at }
        at += step
    }
    return -1
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

// The keys that move the end of the selection in this frame: the arrows, Home and End while Shift is held, there is a selection and no text field is edited.
// UiBegin leaves these to the selection (they do not move the focus).
@(private)
selectKeysTaken :: proc(ctx: ^Context, input: Input) -> Actions {
    if !ctx.select.active || .SHIFT not_in input.modifiers { return {} }
    focused: ^WidgetState = stateFind(ctx, ctx.focus)
    if focused != nil && focused.editing { return {} }
    return input.actions & {.LEFT, .RIGHT, .UP, .DOWN, .HOME, .END}
}

// The line of a selectable text a place is in, and where the place is on the screen
@(private)
selectLineOf :: proc(ctx: ^Context, place: SelectPoint) -> (line: TextLine, top: f32, x: f32, height: f32, found: bool) {
    index: i32 = selectElementOf(ctx, place)
    if index < 0 { return }
    element: ^Element = &ctx.elements[index]
    if !element.is_text || !selectHasTag(&ctx.select, element) { return }
    data: ^TextData = &element.text
    height = data.config.line_height if data.config.line_height > 0 else data.preferred.y
    for l in 0 ..< int(data.line_count) {
        candidate: TextLine = ctx.lines[int(data.line_start) + l]
        last: bool = l == int(data.line_count) - 1
        // a place at the end of a line is of that line; at the start of the next one only when a new line stands between them
        if place.offset < candidate.start || place.offset > candidate.start + candidate.length { continue }
        if place.offset == candidate.start + candidate.length && !last {
            next: TextLine = ctx.lines[int(data.line_start) + l + 1]
            if next.start == place.offset { continue }
        }
        shift: f32 = element.rect.z - candidate.width
        switch data.config.align {
        case .LEFT: shift = 0
        case .CENTER: shift *= 0.5
        case .RIGHT:
        }
        outer_tags: [DRAW_TAGS]Id = ctx.measure_tags
        ctx.measure_tags = element.decl.draw.tags
        x = element.rect.x + shift + measureText(ctx, data.text[candidate.start:place.offset], data.config.font_size).x
        ctx.measure_tags = outer_tags
        return candidate, element.rect.y + f32(l) * height, x, height, true
    }
    return
}

// The place in the line above (-1) or below (1) the height `edge` that is the nearest to `x`
@(private)
selectLineStep :: proc(ctx: ^Context, x: f32, edge: f32, direction: int) -> (place: SelectPoint, found: bool) {
    best_vertical, best_sideways: f32
    best_element: i32
    best_line: TextLine
    best_x: f32
    for index in 0 ..< i32(ctx.element_count) {
        element: ^Element = &ctx.elements[index]
        if !element.is_text || !selectHasTag(&ctx.select, element) { continue }
        data: ^TextData = &element.text
        rect: Rect = element.rect
        height: f32 = data.config.line_height if data.config.line_height > 0 else data.preferred.y
        for l in 0 ..< int(data.line_count) {
            line: TextLine = ctx.lines[int(data.line_start) + l]
            center: f32 = rect.y + (f32(l) + 0.5) * height
            if (direction < 0 && center >= edge) || (direction > 0 && center <= edge) { continue }
            shift: f32 = rect.z - line.width
            switch data.config.align {
            case .LEFT: shift = 0
            case .CENTER: shift *= 0.5
            case .RIGHT:
            }
            vertical: f32 = abs(center - edge)
            sideways: f32 = max(rect.x + shift - x, x - (rect.x + shift + line.width), 0)
            // rows of one height are one line (the runs of a paragraph): the nearest row first, then the run the place is over
            closer: bool = !found || vertical < best_vertical - height * 0.25 || (abs(vertical - best_vertical) <= height * 0.25 && sideways < best_sideways)
            if closer {
                found = true
                best_vertical, best_sideways, best_element, best_line, best_x = vertical, sideways, index, line, x - (rect.x + shift)
            }
        }
    }
    if !found { return }
    return selectPointOf(ctx, best_element, best_line.start + selectOffsetAt(ctx, best_element, best_line, best_x)), true
}

// The byte of a line whose end of a letter is the nearest to `x` (from the start of the line)
@(private)
selectOffsetAt :: proc(ctx: ^Context, index: i32, line: TextLine, x: f32) -> i32 {
    element: ^Element = &ctx.elements[index]
    text: string = element.text.text[line.start:line.start + line.length]
    outer_tags: [DRAW_TAGS]Id = ctx.measure_tags
    ctx.measure_tags = element.decl.draw.tags
    offset: int
    nearest: f32 = abs(x)
    at: int
    for at < len(text) {
        _, width := utf8.decode_rune_in_string(text[at:])
        at += width
        distance: f32 = abs(x - measureText(ctx, text[:at], element.text.config.font_size).x)
        if distance < nearest {
            nearest = distance
            offset = at
        }
    }
    ctx.measure_tags = outer_tags
    return i32(offset)
}

// Shift and an arrow, Home or End: the end of the selection moves by a letter, a line, to the start or the end of its line. The start stays.
@(private)
selectKeys :: proc(ctx: ^Context) {
    select: ^TextSelect = &ctx.select
    actions: Actions = ctx.input.actions
    cursor: SelectPoint = select.cursor
    line, top, x, height, found := selectLineOf(ctx, cursor)
    if !found { return }
    element: i32 = selectElementOf(ctx, cursor)               // a row that is in view: the text it is (the end of the selection may not move out of view)
    text: string = ctx.elements[element].text.text
    if .LEFT in actions {
        if cursor.offset > 0 {
            _, width := utf8.decode_last_rune_in_string(text[:cursor.offset])
            cursor.offset -= i32(width)
        } else if previous := selectNeighbor(ctx, element, -1); previous >= 0 {
            // into the text before, one letter in: its end is the same place on the screen when it stands in the same row, and the same selection
            // when a line break is between them, and a press of a key should change what is selected
            before: string = ctx.elements[previous].text.text
            cursor = selectPointOf(ctx, previous, i32(len(before)))
            if len(before) > 0 {
                _, width := utf8.decode_last_rune_in_string(before)
                cursor.offset -= i32(width)
            }
        }
    }
    if .RIGHT in actions {
        if int(cursor.offset) < len(text) {
            _, width := utf8.decode_rune_in_string(text[cursor.offset:])
            cursor.offset += i32(width)
        } else if next := selectNeighbor(ctx, element, 1); next >= 0 {
            after: string = ctx.elements[next].text.text
            cursor = selectPointOf(ctx, next, 0)
            if len(after) > 0 {
                _, width := utf8.decode_rune_in_string(after)
                cursor.offset += i32(width)
            }
        }
    }
    if .HOME in actions { cursor.offset = line.start }
    if .END in actions { cursor.offset = line.start + line.length }
    if .UP in actions {
        if place, above := selectLineStep(ctx, x, top + height * 0.25, -1); above { cursor = place }
    }
    if .DOWN in actions {
        if place, below := selectLineStep(ctx, x, top + height * 0.75, 1); below { cursor = place }
    }
    select.cursor = cursor
}
