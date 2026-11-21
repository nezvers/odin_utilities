package ui_default

// The default look of the color picker (colorpicker.odin): a square and two bars made of small cells (the painter has no gradients), and the markers.

import ui ".."

COLOR_STRIPS_MAX :: 400
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

// How many strips a side is cut into: one for each pixel of the screen (a strip a pixel wide is as smooth as a gradient: the neighbours differ by one step of a byte), at most COLOR_STRIPS_MAX.
@(private)
strips :: proc(painter: ^Painter, length: f32) -> int {
    return clamp(int(length * PainterScale(painter) + 0.5), 4, COLOR_STRIPS_MAX)
}

// Saturation to the right, brightness upwards, at the hue that is `actual`; the marker is where the color is. Two layers, each of strips a pixel wide: the saturation (from white to the pure hue)
// across the whole square, then black over it that is clearer the brighter the row is. brightness * (white + s * (hue - white)) is exactly what the second layer blends to, so no cell is needed.
DrawColorField :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    rect: ui.Rect = info.rect
    FocusRing(painter, info, 0)
    columns: int = strips(painter, rect.z)
    rows: int = strips(painter, rect.w)
    for column in 0 ..< columns {
        s: f32 = (f32(column) + 0.5) / f32(columns)
        painter.fill_rect(painter, {rect.x + rect.z * f32(column) / f32(columns), rect.y, rect.z / f32(columns) + 0.5, rect.w}, colorBytes(ui.ColorHsvToRgb(info.actual, s, 1)))
    }
    for row in 0 ..< rows {
        v: f32 = 1 - (f32(row) + 0.5) / f32(rows)
        painter.fill_rect(painter, {rect.x, rect.y + rect.w * f32(row) / f32(rows), rect.z, rect.w / f32(rows) + 0.5}, {0, 0, 0, u8((1 - v) * 255 + 0.5)})
    }
    marker(painter, {rect.x + info.value * rect.z, rect.y + (1 - info.ratio) * rect.w}, 6)
}

@(private)
checkerboard :: proc(painter: ^Painter, rect: ui.Rect) {
    rows: int = int(rect.w / COLOR_CHECKER) + 1
    columns: int = int(rect.z / COLOR_CHECKER) + 1
    for row in 0 ..< rows {
        top: f32 = rect.y + f32(row) * COLOR_CHECKER
        height: f32 = min(COLOR_CHECKER, rect.y + rect.w - top)
        for column in 0 ..< columns {
            left: f32 = rect.x + f32(column) * COLOR_CHECKER
            width: f32 = min(COLOR_CHECKER, rect.x + rect.z - left)
            painter.fill_rect(painter, {left, top, width, height}, {200, 200, 200, 255} if (row + column) % 2 == 0 else {120, 120, 120, 255})
        }
    }
}

// The hues from the top down, the alpha from opaque to clear over a checker board of the color it is of, or (actual 2 and 3) a bar of a channel of a color space from left to right, an
// alpha bar for the horizontal layout. `value`: where the marker is. Channel bar: `cursor` the ColorMode, `anchor` the channel, `minimum`, `maximum` and `ratio` the three channels.
DrawColorStrip :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    rect: ui.Rect = info.rect
    FocusRing(painter, info, 0)
    switch {
    case info.actual < 0.5:
        count: int = strips(painter, rect.w)
        for row in 0 ..< count {
            hue: f32 = (f32(row) + 0.5) / f32(count)
            painter.fill_rect(painter, {rect.x, rect.y + rect.w * f32(row) / f32(count), rect.z, rect.w / f32(count) + 0.5}, colorBytes(ui.ColorHsvToRgb(hue, 1, 1)))
        }
    case info.actual < 1.5:
        checkerboard(painter, rect)
        count: int = strips(painter, rect.w)
        for row in 0 ..< count {
            alpha: f32 = 1 - (f32(row) + 0.5) / f32(count)
            painter.fill_rect(painter, {rect.x, rect.y + rect.w * f32(row) / f32(count), rect.z, rect.w / f32(count) + 0.5}, {info.color.r, info.color.g, info.color.b, u8(alpha * 255 + 0.5)})
        }
    case info.actual < 2.5:
        mode: ui.ColorMode = ui.ColorMode(clamp(info.cursor, 0, int(max(ui.ColorMode))))
        values: [3]f32 = {info.minimum, info.maximum, info.ratio}
        count: int = strips(painter, rect.z)
        for column in 0 ..< count {
            t: f32 = (f32(column) + 0.5) / f32(count)
            painter.fill_rect(painter, {rect.x + rect.z * f32(column) / f32(count), rect.y, rect.z / f32(count) + 0.5, rect.w}, colorBytes(ui.ColorChannelColor(mode, info.anchor, t, values)))
        }
        barMarker(painter, rect, info.value)
        return
    case:
        checkerboard(painter, rect)
        count: int = strips(painter, rect.z)
        for column in 0 ..< count {
            alpha: f32 = (f32(column) + 0.5) / f32(count)
            painter.fill_rect(painter, {rect.x + rect.z * f32(column) / f32(count), rect.y, rect.z / f32(count) + 0.5, rect.w}, {info.color.r, info.color.g, info.color.b, u8(alpha * 255 + 0.5)})
        }
        barMarker(painter, rect, info.value)
        return
    }
    y: f32 = rect.y + clamp(info.value, 0, 1) * rect.w
    painter.fill_rect(painter, {rect.x - 1, y - 2.5, rect.z + 2, 5}, {0, 0, 0, 255})
    painter.fill_rect(painter, {rect.x, y - 1.5, rect.z, 3}, {255, 255, 255, 255})
}

// The marker of a horizontal bar: a white line with a dark edge across the bar, at `value` (0 .. 1) of its width
@(private)
barMarker :: proc(painter: ^Painter, rect: ui.Rect, value: f32) {
    x: f32 = clamp(rect.x + clamp(value, 0, 1) * rect.z, rect.x + 2, rect.x + rect.z - 2)
    painter.fill_rect(painter, {x - 2.5, rect.y - 1, 5, rect.w + 2}, {0, 0, 0, 255})
    painter.fill_rect(painter, {x - 1.5, rect.y, 3, rect.w}, {255, 255, 255, 255})
}
