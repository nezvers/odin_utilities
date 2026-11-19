package ui_default

// The default look of the color picker (colorpicker.odin): a square and two bars made of small cells (the painter has no gradients), and the markers.

import ui ".."

COLOR_FIELD_CELLS :: 24
COLOR_STRIP_CELLS :: 36
COLOR_CHECKER :: f32(6)

ColorStyleInstall :: proc(style: ^ui.Style) {
    style.procs[.COLOR_FIELD] = DrawColorField
    style.procs[.COLOR_STRIP] = DrawColorStrip
}

@(private)
colorBytes :: proc(rgb: [3]f32, alpha: f32 = 1) -> ui.Color {
    return {u8(clamp(rgb.r, 0, 1) * 255 + 0.5), u8(clamp(rgb.g, 0, 1) * 255 + 0.5), u8(clamp(rgb.b, 0, 1) * 255 + 0.5), u8(clamp(alpha, 0, 1) * 255 + 0.5)}
}

// A ring that marks a place on the picker, white over black so it shows on any color
@(private)
marker :: proc(painter: ^Painter, center: ui.Vec2, radius: f32) {
    FillRoundedBorder(painter, {center.x - radius, center.y - radius, radius * 2, radius * 2}, 1, {0, 0, 0, 0}, {0, 0, 0, 255}, 3, radius)
    FillRoundedBorder(painter, {center.x - radius + 1, center.y - radius + 1, radius * 2 - 2, radius * 2 - 2}, 1, {0, 0, 0, 0}, {255, 255, 255, 255}, 1.5, radius)
}

// Saturation to the right, brightness upwards, at the hue that is `actual`; the marker is where the color is
DrawColorField :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    rect: ui.Rect = info.rect
    cell_w: f32 = rect.z / COLOR_FIELD_CELLS
    cell_h: f32 = rect.w / COLOR_FIELD_CELLS
    for row in 0 ..< COLOR_FIELD_CELLS {
        v: f32 = 1 - (f32(row) + 0.5) / COLOR_FIELD_CELLS
        for column in 0 ..< COLOR_FIELD_CELLS {
            s: f32 = (f32(column) + 0.5) / COLOR_FIELD_CELLS
            // a little over the edges: no seams between the cells
            painter.fill_rect(painter, {rect.x + f32(column) * cell_w, rect.y + f32(row) * cell_h, cell_w + 0.5, cell_h + 0.5}, colorBytes(ui.ColorHsvToRgb(info.actual, s, v)))
        }
    }
    marker(painter, {rect.x + info.value * rect.z, rect.y + (1 - info.ratio) * rect.w}, 6)
}

// The hues from the top down, or the alpha from opaque to clear over a checker board of the color it is of
DrawColorStrip :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    rect: ui.Rect = info.rect
    if info.actual < 0.5 {
        cell: f32 = rect.w / COLOR_STRIP_CELLS
        for row in 0 ..< COLOR_STRIP_CELLS {
            hue: f32 = (f32(row) + 0.5) / COLOR_STRIP_CELLS
            painter.fill_rect(painter, {rect.x, rect.y + f32(row) * cell, rect.z, cell + 0.5}, colorBytes(ui.ColorHsvToRgb(hue, 1, 1)))
        }
    } else {
        rows: int = int(rect.w / COLOR_CHECKER) + 1
        for row in 0 ..< rows {
            top: f32 = rect.y + f32(row) * COLOR_CHECKER
            height: f32 = min(COLOR_CHECKER, rect.y + rect.w - top)
            for column in 0 ..< 2 {
                light: bool = (row + column) % 2 == 0
                painter.fill_rect(painter, {rect.x + f32(column) * rect.z * 0.5, top, rect.z * 0.5, height}, {200, 200, 200, 255} if light else {120, 120, 120, 255})
            }
        }
        cell: f32 = rect.w / COLOR_STRIP_CELLS
        for row in 0 ..< COLOR_STRIP_CELLS {
            alpha: f32 = 1 - (f32(row) + 0.5) / COLOR_STRIP_CELLS
            painter.fill_rect(painter, {rect.x, rect.y + f32(row) * cell, rect.z, cell + 0.5}, {info.color.r, info.color.g, info.color.b, u8(alpha * 255 + 0.5)})
        }
    }
    y: f32 = rect.y + clamp(info.value, 0, 1) * rect.w
    painter.fill_rect(painter, {rect.x - 1, y - 2.5, rect.z + 2, 5}, {0, 0, 0, 255})
    painter.fill_rect(painter, {rect.x, y - 1.5, rect.z, 3}, {255, 255, 255, 255})
}
