package ui_default

// The value bar (ui.UiValueBar): a well with a fill from the origin (the left edge, or the middle of a bipolar bar) to the value, a mark at the value, the name at the left
// and the number at the right. With the tag "modulation" the fill is hatched.

import ui ".."

DrawValueBar :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    FocusRing(painter, info)
    FillRoundedBorder(painter, rect, theme.rounding, theme.track, theme.border, theme.border_width, theme.max_radius)
    inner: ui.Rect = ui.RectShrink(rect, theme.border_width)
    origin_x: f32 = inner.x + inner.z * info.ratio
    value_x: f32 = inner.x + inner.z * info.value
    left, right: f32 = min(origin_x, value_x), max(origin_x, value_x)
    if right - left >= 0.5 {
        fill: ui.Rect = {left, inner.y, right - left, inner.w}
        if ui.DrawInfoHasTag(info, "modulation") {
            painter.fill_rect(painter, fill, {theme.accent.r, theme.accent.g, theme.accent.b, 60})
            hatch(painter, fill, theme.accent)
        } else {
            painter.fill_rect(painter, fill, theme.accent_soft)
        }
    }
    // the mark at the value, and a faint one at the origin of a bipolar bar
    if info.ratio > 0 { painter.fill_rect(painter, {origin_x - 0.5, inner.y + 3, 1, inner.w - 6}, theme.text_dim) }
    mark: f32 = clamp(value_x - 1, inner.x, inner.x + inner.z - 2)
    painter.fill_rect(painter, {mark, inner.y, 2, inner.w}, ui.ColorLerp(theme.accent, theme.text, info.press))
    if info.name != "" { TextLeft(painter, info.name, rect, info.font_size, 8, textColor(theme, info), .REGULAR) }
    TextRight(painter, info.text, rect, info.font_size, 8, textColor(theme, info), .MONO if painter.glue_fonts[.MONO] != 0 else .REGULAR)
}

// Diagonal lines over a rectangle, cut at its sides by arithmetic (the painter has no clip for a shape)
@(private)
hatch :: proc(painter: ^Painter, area: ui.Rect, color: ui.Color) {
    STEP :: 6
    height: f32 = area.w
    line: ui.Color = {color.r, color.g, color.b, 150}
    // a line leaves the bottom at x and reaches the top at x + height (45 degrees)
    for x: f32 = area.x - height; x < area.x + area.z; x += STEP {
        start, end: ui.Vec2 = {x, area.y + area.w}, {x + height, area.y}
        if start.x < area.x {
            cut: f32 = area.x - start.x
            start = {area.x, start.y - cut}
        }
        if end.x > area.x + area.z {
            cut: f32 = end.x - (area.x + area.z)
            end = {area.x + area.z, end.y + cut}
        }
        if start.x >= end.x { continue }
        Line(painter, start, end, 1, line)
    }
}
