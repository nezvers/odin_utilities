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
    row_height: f32,
    count: int,
}

@(private)
virtualOpen :: proc(ctx: ^Context, id: Id, list: ^VirtualList, count: int, row_height: f32, size: Size, fixed_height: f32 = 0) -> bool {
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    metrics: ^Metrics = &ctx.style.metrics
    height: f32 = max(row_height, 1)
    list.row_height, list.count = height, count
    list.changed, list.activated = false, false
    list.hover = VIRTUAL_NONE
    list.selected = clamp(list.selected, VIRTUAL_NONE, count - 1) if count > 0 else VIRTUAL_NONE
    view: Rect = state.rect
    mouse: Vec2 = ctx.input.mouse_position

    scrollbarDrag(ctx, id, state)
    if ctx.hover_scroll == id && ctx.input.wheel.y != 0 {
        state.scroll.y += ctx.input.wheel.y * metrics.font_size * 2.5
    }
    row_at :: proc(state: ^WidgetState, view: Rect, mouse: Vec2, height: f32, count: int) -> int {
        row: int = int(math.floor((mouse.y - view.y - state.scroll.y) / height))
        return row if row >= 0 && row < count else VIRTUAL_NONE
    }
    if ctx.hover == id && ctx.disabled_depth == 0 { list.hover = row_at(state, view, mouse, height, count) }
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

    visible: f32 = view.w
    if visible <= 0 { visible = fixed_height if fixed_height > 0 else height * VIRTUAL_DEFAULT_VIEW_ROWS }
    list.first = clamp(int(math.floor(-state.scroll.y / height)), 0, count)
    list.last = clamp(list.first + int(math.ceil(visible / height)) + 1, list.first, count)

    ElementOpen(ctx, {
        id = id,
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}, direction = .TOP_TO_BOTTOM},
        clip = {vertical = true, offset = state.scroll},
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
        layout = {size = {Grow(), Fixed(list.row_height)}, direction = .LEFT_TO_RIGHT, align = {y = .CENTER}},
        draw = {kind = .SELECTABLE, hover = 1 if list.hover == row else 0, flags = {.SELECTED} if list.selected == row else {}, font_size = metrics.font_size},
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
}

TableInit :: proc(table: ^Table, columns: []TableColumn) {
    table^ = {sort_column = VIRTUAL_NONE, resizing = VIRTUAL_NONE, list = {selected = VIRTUAL_NONE}}
    table.column_count = min(len(columns), TABLE_MAX_COLUMNS)
    for i in 0 ..< table.column_count { table.columns[i] = columns[i] }
}

// The table: a header (sorting, resizing) and the rows below it. Declare the rows first ..< last of `table.list` with UiTableRow, the cells of a row with UiTableCell.
@(deferred_in = UiTableEnd)
UiTable :: proc(ctx: ^Context, name: string, table: ^Table, count: int, row_height: f32, size: Size = {}) -> bool {
    id: Id = UiId(ctx, name)
    metrics: ^Metrics = &ctx.style.metrics
    table.sort_changed = false
    ElementOpen(ctx, {
        id = IdFromString("table", id),
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}, direction = .TOP_TO_BOTTOM},
    })
    ElementOpen(ctx, {layout = {size = {Grow(), Fixed(metrics.control_height)}, direction = .LEFT_TO_RIGHT}})
    for i in 0 ..< table.column_count {
        column: ^TableColumn = &table.columns[i]
        column.width = max(column.width, column.min_width if column.min_width > 0 else TABLE_MIN_COLUMN)
        header_id: Id = IdFromIndex(u32(i), IdFromString("header", id))
        _ = stateGet(ctx, header_id)
        interaction: Interaction = widgetBehavior(ctx, header_id)
        if interaction.clicked && !column.unsortable {
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
            layout = {size = {Fixed(column.width - TABLE_HANDLE), Grow()}},
            hit = {.INTERACTIVE},
            draw = {kind = .SELECTABLE, name = label, hover = 1 if interaction.hovered else 0, flags = {.SELECTED} if table.sort_column == i else {}, font_size = metrics.font_size},
        })
        ElementClose(ctx)
        handle_id: Id = IdFromIndex(u32(i), IdFromString("edge", id))
        handle_state: ^WidgetState = stateGet(ctx, handle_id)
        handle: Interaction = widgetBehavior(ctx, handle_id)
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
    body: f32 = size.height.min - metrics.control_height if size.height.kind == .FIXED else 0
    return virtualOpen(ctx, id, &table.list, count, row_height, {Grow(), Grow()}, body)
}

UiTableEnd :: proc(ctx: ^Context, name: string, table: ^Table, count: int, row_height: f32, size: Size = {}) {
    virtualClose(ctx, &table.list)
    ElementClose(ctx)
}

// A row of a table (its own deferred end: a wrapper of UiVirtualRow would close the row when the wrapper returns).
@(deferred_in = UiTableRowEnd)
UiTableRow :: proc(ctx: ^Context, table: ^Table, row: int) -> bool {
    metrics: ^Metrics = &ctx.style.metrics
    return ElementOpen(ctx, {
        layout = {size = {Grow(), Fixed(table.list.row_height)}, direction = .LEFT_TO_RIGHT, align = {y = .CENTER}},
        draw = {kind = .SELECTABLE, hover = 1 if table.list.hover == row else 0, flags = {.SELECTED} if table.list.selected == row else {}, font_size = metrics.font_size},
    })
}

UiTableRowEnd :: proc(ctx: ^Context, table: ^Table, row: int) {
    ElementClose(ctx)
}

// A cell: a box as wide as its column (cut at its edges) for what the program puts in it. True while it is declared.
@(deferred_in = UiTableCellEnd)
UiTableCell :: proc(ctx: ^Context, table: ^Table, column: int) -> bool {
    width: f32 = table.columns[clamp(column, 0, TABLE_MAX_COLUMNS - 1)].width
    return ElementOpen(ctx, {
        layout = {size = {Fixed(width), Grow()}, padding = PaddingXY(8, 0), align = {y = .CENTER}},
        clip = {horizontal = true, cut = true},
    })
}

UiTableCellEnd :: proc(ctx: ^Context, table: ^Table, column: int) {
    ElementClose(ctx)
}

// A cell with a text.
UiTableText :: proc(ctx: ^Context, table: ^Table, column: int, text: string) {
    if UiTableCell(ctx, table, column) { UiLabel(ctx, text) }
}
