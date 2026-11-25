package ui_default

// The modulation mm of ui/mod_matrix.odin: names of the sources on the left, of the targets above, a cell for every crossing (an empty one a dot, a connected one a bar from the middle:
// up is positive, in the accent, down is negative, in the warning color), the selected cell outlined and its amount written in it.

import "core:fmt"
import ui ".."

DrawModMatrix :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    mm: ^ui.ModMatrix = cast(^ui.ModMatrix)info.user
    rect: ui.Rect = info.rect
    FocusRing(painter, info)
    FillRoundedBorder(painter, rect, theme.rounding, theme.panel, theme.border, theme.border_width, theme.max_radius)
    if mm == nil { return }
    rows: int = min(len(mm.sources), ui.MOD_MATRIX_MAX)
    columns: int = min(len(mm.targets), ui.MOD_MATRIX_MAX)
    if rows == 0 || columns == 0 { return }
    names, header, cells := ui.ModMatrixAreas(rect, rows, columns)
    width, height: f32 = cells.z / f32(columns), cells.w / f32(rows)
    small: f32 = info.font_size * 0.85
    stride: int = len(mm.targets)
    hover_row, hover_column: int = -1, -1
    if info.anchor > 0 { hover_row, hover_column = (info.anchor - 1) / columns, (info.anchor - 1) % columns }
    if painter.clip != nil { painter.clip(painter, rect, true) }
    defer if painter.clip != nil { painter.clip(painter, rect, false) }
    for column in 0 ..< columns {
        label: ui.Rect = {header.x + f32(column) * width, header.y, width, header.w}
        TextCentered(painter, mm.targets[column], label, small, theme.accent if column == hover_column else theme.text_dim)
    }
    for row in 0 ..< rows {
        label: ui.Rect = {names.x, cells.y + f32(row) * height, names.z, height}
        TextLeft(painter, mm.sources[row], label, small, 8, theme.accent if row == hover_row else theme.text)
        painter.fill_rect(painter, {rect.x + 1, cells.y + f32(row) * height, rect.z - 2, 1}, theme.border_soft)
    }
    for column in 0 ..< columns {
        painter.fill_rect(painter, {cells.x + f32(column) * width, rect.y + 1, 1, rect.w - 2}, theme.border_soft)
    }
    for row in 0 ..< rows {
        for column in 0 ..< columns {
            amount: f32 = mm.amounts[row * stride + column]
            cell: ui.Rect = ui.ModMatrixCellRect(rect, rows, columns, row, column)
            inner: ui.Rect = ui.RectShrink(cell, 3)
            if row == hover_row || column == hover_column {
                painter.fill_rect(painter, cell, ui.Color{theme.accent.r, theme.accent.g, theme.accent.b, 14})
            }
            if amount == 0 {
                size: f32 = 3 if row == hover_row && column == hover_column else 2
                FillRounded(painter, {cell.x + (cell.z - size) * 0.5, cell.y + (cell.w - size) * 0.5, size, size}, 1, theme.text_dim, 3)
                continue
            }
            middle: f32 = inner.y + inner.w * 0.5
            extent: f32 = inner.w * 0.5 * abs(amount)
            color: ui.Color = theme.accent if amount > 0 else theme.warning
            FillRounded(painter, {inner.x, inner.y, inner.z, inner.w}, 2, ui.Color{color.r, color.g, color.b, 40}, 3)
            top: f32 = middle - extent if amount > 0 else middle
            FillRounded(painter, {inner.x, top, inner.z, max(extent, 1)}, 2, color, 3)
            painter.fill_rect(painter, {inner.x, middle, inner.z, 1}, ui.Color{255, 255, 255, 70})
        }
    }
    if info.cursor > 0 {
        index: int = info.cursor - 1
        row, column: int = index / columns, index % columns
        if row < rows {
            cell: ui.Rect = ui.ModMatrixCellRect(rect, rows, columns, row, column)
            RingRounded(painter, cell, 2, 2, theme.accent)
            amount: f32 = mm.amounts[row * stride + column]
            if amount != 0 && cell.z > 34 {
                TextCentered(painter, fmt.tprintf("%+.0f", amount * 100), cell, info.font_size * 0.7, theme.text)
            }
        }
    }
}
