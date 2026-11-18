package ui

// Lists and tables of many rows: only the rows that are in view are declared, the rest of the height is a spacer, so a list of a hundred thousand rows costs the rows on screen.
// The program owns the data and the selection; the widget tells which rows to declare.
//
//     list: ui.VirtualList = {selected = ui.VIRTUAL_NONE}
//     if ui.UiVirtual(&ctx, "Files", &list, len(files), 24, {ui.Fixed(300), ui.Fixed(400)}) {
//         for row in list.first ..< list.last {
//             if ui.UiVirtualRow(&ctx, &list, row) { ui.UiLabel(&ctx, files[row].name) }
//         }
//     }
//     if list.activated { open(files[list.selected]) }
//
// A click selects the row under the pointer (a double click or Enter activates it), up, down, page up, page down, Home and End move the selection while the list has the focus, the view follows it
// and the wheel and the scrollbar scroll. A widget inside of a row (a button) takes its own clicks. The table below adds a header with sorting and columns that are resized by their edges.

import "core:math"

VIRTUAL_NONE :: -1
VIRTUAL_DEFAULT_VIEW_ROWS :: 10             // rows declared in the first frame when the size is not a fixed one: the view is not known yet

VirtualList :: struct {
    selected: int,              // the selected row, VIRTUAL_NONE for none (the zero value is the first row: start with `{selected = VIRTUAL_NONE}`)
    first: int,                 // the rows to declare: first ..< last (set by UiVirtual)
    last: int,
    reveal: bool,               // set by the program to scroll the selected row into view in the next frame (the selection that the person changes is always revealed)
    changed: bool,              // the selection changed in this frame by the person
    activated: bool,            // a double click or Enter on the selected row in this frame
    hover: int,                 // the row under the pointer, VIRTUAL_NONE for none
    hover_fraction: f32,        // how far down in that row the pointer is: 0 at its top edge, 1 at its bottom edge
    row_height: f32,
    count: int,
    chosen: []bool,             // the program says which rows are part of a selection of several (drawn like the selected one): by row, only the rows in view are asked
    marked: int,                // the program marks a row (the target of a drop) by its number plus one: 0 is none
    row_width: f32,             // 0: a row is as wide as the list; else it is this wide and the list scrolls sideways when it is wider than the view (tables)
}

@(private)
virtualOpen :: proc(ctx: ^Context, id: Id, list: ^VirtualList, count: int, row_height: f32, size: Size, fixed_height: f32 = 0, content_width: f32 = 0) -> bool {
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    metrics: ^Metrics = &ctx.style.metrics
    height: f32 = max(row_height, 1)
    list.row_height, list.count, list.row_width = height, count, content_width
    list.changed, list.activated = false, false
    list.hover = VIRTUAL_NONE
    list.selected = clamp(list.selected, VIRTUAL_NONE, count - 1) if count > 0 else VIRTUAL_NONE
    view: Rect = state.rect
    mouse: Vec2 = ctx.input.mouse_position

    scrollbarDrag(ctx, id, state)
    if ctx.hover_scroll == id {
        sideways: bool = content_width > 0 && (ctx.input.wheel.x != 0 || (.SHIFT in ctx.input.modifiers && ctx.input.wheel.y != 0))
        if sideways {
            state.scroll.x += (ctx.input.wheel.x if ctx.input.wheel.x != 0 else ctx.input.wheel.y) * metrics.font_size * 2.5
        } else if ctx.input.wheel.y != 0 {
            state.scroll.y += ctx.input.wheel.y * metrics.font_size * 2.5
        }
    }
    row_at :: proc(state: ^WidgetState, view: Rect, mouse: Vec2, height: f32, count: int) -> int {
        row: int = int(math.floor((mouse.y - view.y - state.scroll.y) / height))
        return row if row >= 0 && row < count else VIRTUAL_NONE
    }
    if ctx.hover == id && ctx.disabled_depth == 0 {
        list.hover = row_at(state, view, mouse, height, count)
        if list.hover != VIRTUAL_NONE { list.hover_fraction = clamp((mouse.y - view.y - state.scroll.y) / height - f32(list.hover), 0, 1) }
    }
    if interaction.hovered && ctx.input.mouse_pressed {
        row: int = row_at(state, view, mouse, height, count)
        if row != VIRTUAL_NONE {
            if row != list.selected {
                list.selected = row
                list.changed = true
            }
            if interaction.double_clicked { list.activated = true }
        }
    }
    state.own_vertical = true
    state.editing = ctx.focus == id
    page: int = max(int(view.w / height) - 1, 1)
    if state.editing && count > 0 {
        actions: Actions = ctx.input.actions
        target: int = list.selected
        if .DOWN in actions { target = list.selected + 1 if list.selected != VIRTUAL_NONE else 0 }
        if .UP in actions { target = list.selected - 1 if list.selected != VIRTUAL_NONE else count - 1 }
        if .PAGE_DOWN in actions { target = max(list.selected, 0) + page }
        if .PAGE_UP in actions { target = max(list.selected, 0) - page }
        if .HOME in actions { target = 0 }
        if .END in actions { target = count - 1 }
        target = clamp(target, 0, count - 1)
        if target != list.selected {
            list.selected = target
            list.changed = true
        }
        if .ACCEPT in actions && list.selected != VIRTUAL_NONE { list.activated = true }
    }
    // the selected row stays in view when the selection moved (the wheel and the bar can take it out again)
    if (list.changed || list.reveal) && list.selected != VIRTUAL_NONE && view.w > 0 {
        list.reveal = false
        top: f32 = f32(list.selected) * height + state.scroll.y
        if top < 0 {
            state.scroll.y -= top
        } else if top + height > view.w {
            state.scroll.y -= top + height - view.w
        }
    }
    total: f32 = f32(count) * height
    limit: f32 = max(total - view.w, 0)
    state.scroll.y = clamp(state.scroll.y, -limit, 0)
    state.scroll.x = clamp(state.scroll.x, -max(content_width - view.z, 0), 0) if content_width > 0 else 0

    visible: f32 = view.w
    if visible <= 0 { visible = fixed_height if fixed_height > 0 else height * VIRTUAL_DEFAULT_VIEW_ROWS }
    list.first = clamp(int(math.floor(-state.scroll.y / height)), 0, count)
    list.last = clamp(list.first + int(math.ceil(visible / height)) + 1, list.first, count)

    ElementOpen(ctx, {
        id = id,
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}, direction = .TOP_TO_BOTTOM},
        clip = {horizontal = content_width > 0, vertical = true, offset = state.scroll},
        hit = {.INTERACTIVE, .SCROLL},
        draw = {kind = .SCROLL_AREA, font_size = metrics.font_size},
    })
    ElementOpen(ctx, {layout = {size = {Grow(), Fixed(f32(list.first) * height)}}})
    ElementClose(ctx)
    return true
}

@(private)
virtualClose :: proc(ctx: ^Context, list: ^VirtualList) {
    ElementOpen(ctx, {layout = {size = {Grow(), Fixed(f32(list.count - list.last) * list.row_height)}}})
    ElementClose(ctx)
    ElementClose(ctx)
}

// A list with a row count and a row height. Declare the rows first ..< last of `list` inside of it with UiVirtualRow.
@(deferred_in = UiVirtualEnd)
UiVirtual :: proc(ctx: ^Context, name: string, list: ^VirtualList, count: int, row_height: f32, size: Size = {}) -> bool {
    return virtualOpen(ctx, UiId(ctx, name), list, count, row_height, size, size.height.min if size.height.kind == .FIXED else 0)
}

UiVirtualEnd :: proc(ctx: ^Context, name: string, list: ^VirtualList, count: int, row_height: f32, size: Size = {}) {
    virtualClose(ctx, list)
}

// One row: a box of the row height, in a line (left to right) for what the program puts in it; selected and hovered rows are marked. True while it is declared.
@(deferred_in = UiVirtualRowEnd)
UiVirtualRow :: proc(ctx: ^Context, list: ^VirtualList, row: int) -> bool {
    metrics: ^Metrics = &ctx.style.metrics
    return ElementOpen(ctx, {
        layout = {size = {Fixed(list.row_width) if list.row_width > 0 else Grow(), Fixed(list.row_height)}, direction = .LEFT_TO_RIGHT, align = {y = .CENTER}},
        draw = {kind = .SELECTABLE, hover = 1 if list.hover == row else 0, flags = (({.SELECTED} if list.selected == row || (row < len(list.chosen) && list.chosen[row]) else {}) + ({.PRESSED} if list.marked == row + 1 else {})), font_size = metrics.font_size},
    })
}

UiVirtualRowEnd :: proc(ctx: ^Context, list: ^VirtualList, row: int) {
    ElementClose(ctx)
}

// ------------------------------------------------------------------------------------------------------------------------
// The table

TABLE_MAX_COLUMNS :: 16
TABLE_MIN_COLUMN :: f32(32)
TABLE_HANDLE :: f32(6)
TABLE_CELL_PADDING :: f32(8)       // what UiTableCell leaves at each side of its text

TableColumn :: struct {
    name: string,               // the text of the header (it has to live as long as the table)
    width: f32,                 // the person changes it by dragging the edge
    min_width: f32,             // 0: TABLE_MIN_COLUMN
    unsortable: bool,           // a click on the header does nothing
}

// A table: columns with names and widths and a sorting the person chooses. The program keeps the order of its rows: when `sort_changed` is true it sorts by `sort_column` (VIRTUAL_NONE: the
// original order), descending when `sort_descending`. A click on a header makes its column ascending, the next click descending, the third click none.
Table :: struct {
    list: VirtualList,
    columns: [TABLE_MAX_COLUMNS]TableColumn,
    column_count: int,
    sort_column: int,           // VIRTUAL_NONE for none: start with `{sort_column = VIRTUAL_NONE, list = {selected = VIRTUAL_NONE}}`
    sort_descending: bool,
    sort_changed: bool,
    resizing: int,              // the column whose edge is dragged, VIRTUAL_NONE for none
    fill_last: bool,            // the last column takes the room that the others leave (never narrower than its width)
    shown: [TABLE_MAX_COLUMNS]f32,  // the widths of this frame: the widths of the columns, the last one wider when it fills
    body_id: Id,                // the id of the rows (what UiTable made it: the end of the table needs the same one)
    content_width: f32,         // all the columns together: the table scrolls sideways when this is more than its width
    cells: bool,                // the cells can be moved to with the keys: a cell of the selected row is the current one (drawn marked while the table has the focus), left and right move it, a click sets it
    cell: int,                  // the column of the current cell (the places follow the order of the columns when they were moved)
    cell_changed: bool,         // it changed in this frame
    cell_activated: bool,       // Enter (or a double click) on the current cell: the program toggles, opens its editor, ... in `list.selected`, `cell`
    current_row: int,           // the row that UiTableRow declared last (what UiTableCell marks)
    reorderable: bool,          // a header can be dragged to another place: the program declares the cells by place (TableColumnAt) and not by column
    order: [TABLE_MAX_COLUMNS]int,  // the column that is at each place from the left: the identity until a header is moved
    fit: int,                   // the column whose edge was double clicked in this frame, VIRTUAL_NONE for none: the program measures its cells and calls TableFit (the table only declares the rows in view)
    moved: int,                 // the column that was dropped at a new place in this frame, VIRTUAL_NONE for none
    reorder: int,               // the column whose header is held, VIRTUAL_NONE for none
    reorder_active: bool,       // the pointer moved far enough: it is a drag and not a click
    reorder_start: Vec2,
    reorder_target: int,        // the place it would go to
}

// The column that is at a place from the left (the places are 0 ..< column_count): declare the cells of a row in this order, `UiTableText(ctx, table, TableColumnAt(table, place), ...)`.
TableColumnAt :: proc(table: ^Table, place: int) -> int {
    return table.order[clamp(place, 0, TABLE_MAX_COLUMNS - 1)]
}

// Makes a column as wide as its widest content (a width in pixels, from UiTextWidth) plus the padding of a cell. Call it when `table.fit` names the column.
TableFit :: proc(table: ^Table, column: int, content_width: f32) {
    if column < 0 || column >= table.column_count { return }
    least: f32 = table.columns[column].min_width if table.columns[column].min_width > 0 else TABLE_MIN_COLUMN
    table.columns[column].width = max(content_width + TABLE_CELL_PADDING * 2, least)
}

TableInit :: proc(table: ^Table, columns: []TableColumn) {
    table^ = {sort_column = VIRTUAL_NONE, resizing = VIRTUAL_NONE, moved = VIRTUAL_NONE, fit = VIRTUAL_NONE, reorder = VIRTUAL_NONE, list = {selected = VIRTUAL_NONE}}
    table.column_count = min(len(columns), TABLE_MAX_COLUMNS)
    for i in 0 ..< table.column_count {
        table.columns[i] = columns[i]
        table.order[i] = i
    }
}

// The table: a header (sorting, resizing) and the rows below it. Declare the rows first ..< last of `table.list` with UiTableRow, the cells of a row with UiTableCell.
@(deferred_in = UiTableEnd)
UiTable :: proc(ctx: ^Context, name: string, table: ^Table, count: int, row_height: f32, size: Size = {}) -> bool {
    id: Id = UiId(ctx, name)
    metrics: ^Metrics = &ctx.style.metrics
    table.sort_changed = false
    table.moved, table.fit = VIRTUAL_NONE, VIRTUAL_NONE
    table.cell_changed, table.cell_activated = false, false
    table.body_id = id
    // the widths of this frame: the columns, the last one wider when it fills the room (from the last frame); the table scrolls sideways when they are more than the room
    body: ^WidgetState = stateFind(ctx, id)
    scroll_x: f32 = body.scroll.x if body != nil else 0
    room: f32 = body.rect.z - metrics.scrollbar_width if body != nil else 0
    table.content_width = 0
    for i in 0 ..< table.column_count {
        column: ^TableColumn = &table.columns[i]
        column.width = max(column.width, column.min_width if column.min_width > 0 else TABLE_MIN_COLUMN)
        table.shown[i] = column.width
        table.content_width += column.width
    }
    if table.fill_last && table.column_count > 0 && room > table.content_width {
        table.shown[table.column_count - 1] += room - table.content_width
        table.content_width = room
    }
    ElementOpen(ctx, {
        id = IdFromString("table", id),
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}, direction = .TOP_TO_BOTTOM},
    })
    ElementOpen(ctx, {layout = {size = {Grow(), Fixed(metrics.control_height)}}, clip = {horizontal = true, cut = true, offset = {scroll_x, 0}}})
    ElementOpen(ctx, {layout = {size = {Fixed(table.content_width), Grow()}, direction = .LEFT_TO_RIGHT}})
    for place in 0 ..< table.column_count {
        i: int = table.order[place] if table.reorderable else place
        column: ^TableColumn = &table.columns[i]
        header_id: Id = IdFromIndex(u32(i), IdFromString("header", id))
        _ = stateGet(ctx, header_id)
        interaction: Interaction = widgetBehavior(ctx, header_id)
        if table.reorderable && interaction.pressed && ctx.input.mouse_pressed {
            table.reorder, table.reorder_start, table.reorder_active = i, ctx.input.mouse_position, false
        }
        if interaction.clicked && !column.unsortable && !table.reorder_active {
            if table.sort_column != i {
                table.sort_column, table.sort_descending = i, false
            } else if !table.sort_descending {
                table.sort_descending = true
            } else {
                table.sort_column, table.sort_descending = VIRTUAL_NONE, false
            }
            table.sort_changed = true
        }
        label: string = column.name
        if table.sort_column == i { label = UiFormat(ctx, "%s %s", column.name, "v" if table.sort_descending else "^") }
        ElementOpen(ctx, {
            id = header_id,
            layout = {size = {Fixed(table.shown[i] - TABLE_HANDLE), Grow()}},
            hit = {.INTERACTIVE},
            draw = {kind = .SELECTABLE, name = label, hover = 1 if interaction.hovered else 0, flags = ({.SELECTED} if table.sort_column == i else {}) + ({.PRESSED} if table.reorder_active && table.reorder_target == place else {}), font_size = metrics.font_size},
        })
        ElementClose(ctx)
        handle_id: Id = IdFromIndex(u32(i), IdFromString("edge", id))
        handle_state: ^WidgetState = stateGet(ctx, handle_id)
        handle: Interaction = widgetBehavior(ctx, handle_id)
        if handle.double_clicked && handle.pressed && ctx.input.mouse_pressed { table.fit = i }
        if handle.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
            if ctx.input.mouse_pressed {
                handle_state.drag = ctx.input.mouse_position
            } else {
                column.width = max(column.width + ctx.input.mouse_position.x - handle_state.drag.x, column.min_width if column.min_width > 0 else TABLE_MIN_COLUMN)
                handle_state.drag = ctx.input.mouse_position
            }
            table.resizing = i
        } else if table.resizing == i {
            table.resizing = VIRTUAL_NONE
        }
        ElementOpen(ctx, {
            id = handle_id,
            layout = {size = {Fixed(TABLE_HANDLE), Grow()}},
            hit = {.INTERACTIVE, .NO_FOCUS},
            cursor = .RESIZE_HORIZONTAL,
            draw = {kind = .SPLITTER, actual = 0, hover = 1 if handle.hovered else 0, flags = {.PRESSED} if handle.pressed else {}},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
    ElementClose(ctx)
    tableReorder(ctx, table, id)
    fixed_body: f32 = size.height.min - metrics.control_height if size.height.kind == .FIXED else 0
    if table.cells && table.column_count > 0 {
        table.cell = clamp(table.cell, 0, table.column_count - 1)
        place: int
        for p in 0 ..< table.column_count {
            if table.order[p] == table.cell { place = p }
        }
        before: int = table.cell
        if ctx.focus == id {
            if .LEFT in ctx.input.actions { place = max(place - 1, 0) }
            if .RIGHT in ctx.input.actions { place = min(place + 1, table.column_count - 1) }
            table.cell = table.order[place]
        }
        // a click on a row sets the column under the pointer
        if ctx.hover == id && ctx.input.mouse_pressed {
            first: ^WidgetState = stateFind(ctx, IdFromIndex(u32(table.order[0]), IdFromString("header", id)))
            if first != nil {
                left: f32 = first.rect.x
                clicked_place: int
                for clicked_place < table.column_count - 1 && ctx.input.mouse_position.x >= left + table.shown[table.order[clicked_place]] {
                    left += table.shown[table.order[clicked_place]]
                    clicked_place += 1
                }
                table.cell = table.order[clicked_place]
            }
        }
        table.cell_changed = table.cell != before
    }
    return virtualOpen(ctx, id, &table.list, count, row_height, {Grow(), Grow()}, fixed_body, table.content_width)
}

// Dragging a header: the column goes to the place the pointer is at when it is let go (the headers of the last frame say where the places are). Escape drops the drag.
@(private)
tableReorder :: proc(ctx: ^Context, table: ^Table, id: Id) {
    if !table.reorderable || table.reorder == VIRTUAL_NONE { return }
    mouse: Vec2 = ctx.input.mouse_position
    if .CANCEL in ctx.input.actions {
        table.reorder, table.reorder_active = VIRTUAL_NONE, false
        return
    }
    first: ^WidgetState = stateFind(ctx, IdFromIndex(u32(table.order[0]), IdFromString("header", id)))
    if ctx.input.mouse_down {
        delta: Vec2 = mouse - table.reorder_start
        if !table.reorder_active && delta.x * delta.x + delta.y * delta.y > 36 { table.reorder_active = true }
        if table.reorder_active && first != nil {
            left: f32 = first.rect.x
            place: int
            for place < table.column_count - 1 && mouse.x >= left + table.shown[table.order[place]] {
                left += table.shown[table.order[place]]
                place += 1
            }
            table.reorder_target = place
        }
        return
    }
    if table.reorder_active {
        current: int
        for place in 0 ..< table.column_count {
            if table.order[place] == table.reorder { current = place }
        }
        target: int = clamp(table.reorder_target, 0, table.column_count - 1)
        if target != current {
            column: int = table.order[current]
            for current < target {
                table.order[current] = table.order[current + 1]
                current += 1
            }
            for current > target {
                table.order[current] = table.order[current - 1]
                current -= 1
            }
            table.order[target] = column
            table.moved = column
        }
    }
    table.reorder, table.reorder_active = VIRTUAL_NONE, false
}

UiTableEnd :: proc(ctx: ^Context, name: string, table: ^Table, count: int, row_height: f32, size: Size = {}) {
    virtualClose(ctx, &table.list)
    if table.cells && table.list.activated { table.cell_activated = true }
    // the bar for the sideways scrolling, under the rows, while the columns are wider than the table
    id: Id = table.body_id
    body: ^WidgetState = stateFind(ctx, id)
    if body != nil && body.rect.z > 0 && table.content_width > body.rect.z + 0.5 {
        metrics: ^Metrics = &ctx.style.metrics
        bar_id: Id = IdFromString("sideways", id)
        bar_state: ^WidgetState = stateGet(ctx, bar_id)
        bar: Interaction = widgetBehavior(ctx, bar_id)
        limit: f32 = table.content_width - body.rect.z
        ratio: f32 = clamp(body.rect.z / table.content_width, 0, 1)
        track: Rect = bar_state.rect
        thumb: f32 = max(track.z * ratio, metrics.scrollbar_width * 2)
        free: f32 = track.z - thumb
        if bar.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) && free > 0 {
            if ctx.input.mouse_pressed {
                left: f32 = track.x + free * clamp(-body.scroll.x / limit, 0, 1)
                x: f32 = ctx.input.mouse_position.x
                bar_state.drag.x = x - left if x >= left && x <= left + thumb else thumb * 0.5
            }
            body.scroll.x = -clamp((ctx.input.mouse_position.x - bar_state.drag.x - track.x) / free, 0, 1) * limit
        }
        ElementOpen(ctx, {
            id = bar_id,
            layout = {size = {Grow(), Fixed(metrics.scrollbar_width + 2)}},
            hit = {.INTERACTIVE, .NO_FOCUS},
            draw = {kind = .SCROLLBAR, actual = 1, value = clamp(-body.scroll.x / limit, 0, 1), ratio = ratio},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
}

// A row of a table (its own deferred end: a wrapper of UiVirtualRow would close the row when the wrapper returns).
@(deferred_in = UiTableRowEnd)
UiTableRow :: proc(ctx: ^Context, table: ^Table, row: int) -> bool {
    metrics: ^Metrics = &ctx.style.metrics
    table.current_row = row
    return ElementOpen(ctx, {
        layout = {size = {Fixed(table.list.row_width) if table.list.row_width > 0 else Grow(), Fixed(table.list.row_height)}, direction = .LEFT_TO_RIGHT, align = {y = .CENTER}},
        draw = {kind = .SELECTABLE, hover = 1 if table.list.hover == row else 0, flags = {.SELECTED} if table.list.selected == row else {}, font_size = metrics.font_size},
    })
}

UiTableRowEnd :: proc(ctx: ^Context, table: ^Table, row: int) {
    ElementClose(ctx)
}

// A cell: a box as wide as its column (cut at its edges) for what the program puts in it. True while it is declared.
@(deferred_in = UiTableCellEnd)
UiTableCell :: proc(ctx: ^Context, table: ^Table, column: int) -> bool {
    width: f32 = table.shown[clamp(column, 0, TABLE_MAX_COLUMNS - 1)]
    // the current cell of the selected row is marked while the table has the focus
    current: bool = table.cells && column == table.cell && table.current_row == table.list.selected && ctx.focus == table.body_id
    return ElementOpen(ctx, {
        layout = {size = {Fixed(width), Grow()}, padding = PaddingXY(TABLE_CELL_PADDING, 0), align = {y = .CENTER}},
        clip = {horizontal = true, cut = true},
        draw = {kind = .HIGHLIGHT, color = {90, 190, 255, 255}} if current else {},
    })
}

UiTableCellEnd :: proc(ctx: ^Context, table: ^Table, column: int) {
    ElementClose(ctx)
}

// A cell with a text.
UiTableText :: proc(ctx: ^Context, table: ^Table, column: int, text: string) {
    if UiTableCell(ctx, table, column) { UiLabel(ctx, text) }
}

// How far the columns are scrolled to the left, in pixels (0 or more).
UiTableScrollX :: proc(ctx: ^Context, table: ^Table) -> f32 {
    state: ^WidgetState = stateFind(ctx, table.body_id)
    return -state.scroll.x if state != nil else 0
}

// Scrolls the columns sideways to a distance in pixels (it is kept within the table).
UiTableScrollSet :: proc(ctx: ^Context, table: ^Table, x: f32) {
    if state := stateFind(ctx, table.body_id); state != nil { state.scroll.x = -max(x, 0) }
}
