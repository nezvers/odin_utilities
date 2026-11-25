package ui

import "core:math"

// A modulation matrix: sources (LFOs, envelopes, macros) down the left, targets (parameters) across the top, and in each crossing how much the source moves the target, -1 .. 1.
// A connected cell shows its amount as a bar from the middle (up is positive), an empty one is a dim dot.
//
//     routing: ui.ModMatrix = {sources = {"LFO 1", "Env 1"}, targets = {"Cutoff", "Pitch", "Pan"}, amounts = amounts[:]}      // amounts: sources * targets values, row by row
//     ui.UiModMatrix(&ctx, "Matrix", &routing)
//
//   A click on an empty cell connects it at 50 %. A drag up or down on a cell sets its amount (the cell height is a fifth of the range; Shift for a tenth of that), the wheel over a cell
//   moves it by 5 %, a double click clears it. The selected cell is the last one pressed (`ModMatrixSelected`): the program shows its amount in text or a value bar.
//
// The data is the program's (`amounts` lives as long as the matrix is drawn). No allocations.
//
// Limits: one amount per crossing (no curve or polarity switch), the names are cut to their column (no rotated header, no tooltip), amounts and names of 64 sources and 64 targets at most are
//     drawn (the rest are not shown), no drag from a source to a target, no keyboard control of cells.

MOD_MATRIX_HEADER :: f32(24)               // the height of the row of target names
MOD_MATRIX_MAX :: 64
MOD_MATRIX_CELL_RANGE :: f32(5)            // cell heights of drag for the whole range 0 .. 1 (so a drag across 1 cell height is 0.2)

ModMatrix :: struct {
    sources: []string,              // rows, alive until UiRender
    targets: []string,              // columns
    amounts: []f32,                 // sources * targets values, -1 .. 1, row by row
}

// The room of the name column and of the cells in a rect of the widget
ModMatrixAreas :: proc(rect: Rect, rows: int, columns: int) -> (names: Rect, header: Rect, cells: Rect) {
    label: f32 = clamp(rect.z * 0.22, 60, 140)
    header_height: f32 = min(MOD_MATRIX_HEADER, rect.w * 0.3)
    names = {rect.x, rect.y + header_height, label, rect.w - header_height}
    header = {rect.x + label, rect.y, rect.z - label, header_height}
    cells = {rect.x + label, rect.y + header_height, rect.z - label, rect.w - header_height}
    return
}

// The cell under a point: its source row and target column; ok is false outside of the cells
ModMatrixCellAt :: proc(rect: Rect, rows: int, columns: int, point: Vec2) -> (row: int, column: int, ok: bool) {
    if rows <= 0 || columns <= 0 { return }
    _, _, cells := ModMatrixAreas(rect, rows, columns)
    if point.x < cells.x || point.y < cells.y || point.x >= cells.x + cells.z || point.y >= cells.y + cells.w { return }
    column = int((point.x - cells.x) / cells.z * f32(columns))
    row = int((point.y - cells.y) / cells.w * f32(rows))
    return min(row, rows - 1), min(column, columns - 1), true
}

// The rectangle of a cell
ModMatrixCellRect :: proc(rect: Rect, rows: int, columns: int, row: int, column: int) -> Rect {
    _, _, cells := ModMatrixAreas(rect, rows, columns)
    width, height: f32 = cells.z / f32(columns), cells.w / f32(rows)
    return {cells.x + f32(column) * width, cells.y + f32(row) * height, width, height}
}

// The cell that was pressed last: its row and column, ok false when none
ModMatrixSelected :: proc(ctx: ^Context, name: string, mm: ^ModMatrix) -> (row: int, column: int, ok: bool) {
    state: ^WidgetState = stateFind(ctx, UiId(ctx, name))
    columns: int = len(mm.targets)
    if state == nil || state.cursor <= 0 || columns == 0 { return }
    index: int = state.cursor - 1
    return index / columns, index % columns, index < len(mm.sources) * columns
}

// `changed` in a frame an amount changed. Style kind MOD_MATRIX: user the ^ModMatrix, cursor the selected cell (index + 1, 0 none), anchor the hovered cell (index + 1, 0 none).
UiModMatrix :: proc(ctx: ^Context, name: string, mm: ^ModMatrix, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    rows: int = min(len(mm.sources), MOD_MATRIX_MAX)
    columns: int = min(len(mm.targets), MOD_MATRIX_MAX)
    assert(len(mm.amounts) >= len(mm.sources) * len(mm.targets), "UiModMatrix: amounts has to hold sources * targets values")
    stride: int = len(mm.targets)
    set :: proc(value: ^f32, wanted: f32) -> bool {
        amount: f32 = clamp(wanted, -1, 1)
        if abs(amount) < 0.005 { amount = 0 }
        if amount == value^ { return false }
        value^ = amount
        return true
    }
    hover: int
    if !disabled && state.rect.z > 0 && interaction.hovered {
        if row, column, ok := ModMatrixCellAt(state.rect, rows, columns, ctx.input.mouse_position); ok { hover = row * columns + column + 1 }
    }
    if !disabled && state.rect.z > 0 {
        mouse: Vec2 = ctx.input.mouse_position
        if interaction.pressed && ctx.input.mouse_pressed {
            if row, column, ok := ModMatrixCellAt(state.rect, rows, columns, mouse); ok {
                state.cursor = row * columns + column + 1
                state.drag = mouse
                state.scroll.x = mm.amounts[row * stride + column]
                state.scroll.y = 0
                if interaction.double_clicked { changed = set(&mm.amounts[row * stride + column], 0) || changed }
            } else {
                state.cursor = 0
            }
        } else if interaction.pressed && ctx.input.mouse_down && state.cursor > 0 {
            index: int = state.cursor - 1
            row, column: int = index / columns, index % columns
            cell: Rect = ModMatrixCellRect(state.rect, rows, columns, row, column)
            delta: f32 = (state.drag.y - mouse.y) / (cell.w * MOD_MATRIX_CELL_RANGE)
            if .SHIFT in ctx.input.modifiers { delta *= 0.1 }
            state.scroll.y = max(state.scroll.y, abs(state.drag.y - mouse.y))
            if state.scroll.y > 2 {
                changed = set(&mm.amounts[row * stride + column], state.scroll.x + delta) || changed
            }
        } else if interaction.pressed && ctx.input.mouse_released && state.cursor > 0 && state.scroll.y <= 2 && !interaction.double_clicked {
            // a click that did not move: an empty cell is connected at half
            index: int = state.cursor - 1
            row, column: int = index / columns, index % columns
            if mm.amounts[row * stride + column] == 0 { changed = set(&mm.amounts[row * stride + column], 0.5) || changed }
        }
        if hover > 0 && ctx.input.wheel.y != 0 {
            index: int = hover - 1
            row, column: int = index / columns, index % columns
            step: f32 = 0.05 * (1 if ctx.input.wheel.y > 0 else -1)
            changed = set(&mm.amounts[row * stride + column], math.round((mm.amounts[row * stride + column] + step) * 100) / 100) || changed
        }
    }
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_height * 14, metrics.control_height * (f32(rows) + 1.2))},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .HAND,
        draw = {kind = .MOD_MATRIX, name = IdSplitName(name), user = mm, cursor = state.cursor, anchor = hover, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    return
}
