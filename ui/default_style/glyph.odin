package ui_default

import ui ".."

// The picture of an input (ui/glyph.odin). A texture of the program is drawn through `painter.draw_texture` when both exist; else the shape is drawn from rectangles,
// circles and text, in the colors of the theme (a face button keeps its own color: it is the one thing a person knows it by).
DrawGlyph :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    if info.texture != 0 && painter.draw_texture != nil {
        painter.draw_texture(painter, info.texture, info.source, rect, ui.Color{255, 255, 255, 255})
        return
    }
    shape: ui.GlyphShape = ui.GlyphShape(clamp(int(info.actual), 0, len(ui.GlyphShape) - 1))
    side: f32 = min(rect.z, rect.w)
    ink: ui.Color = theme.text
    switch shape {
    case .KEY, .MOUSE:
        // a keycap has a thicker bottom edge: it reads as a key and not as a button
        FillRounded(painter, {rect.x, rect.y + 1, rect.z, rect.w - 1}, 0.35, theme.border)
        FillRoundedBorder(painter, {rect.x, rect.y, rect.z, rect.w - 2}, 0.35, theme.control, theme.border, theme.border_width)
        TextCentered(painter, info.text, {rect.x, rect.y, rect.z, rect.w - 2}, info.font_size, ink, .STRONG)
    case .FACE:
        color: ui.Color = info.color if info.color.a > 0 else theme.control
        text_color: ui.Color = theme.accent_text if info.color.a > 0 else ink
        FillRounded(painter, {rect.x + (rect.z - side) * 0.5, rect.y + (rect.w - side) * 0.5, side, side}, 1, color)
        TextCentered(painter, info.text, rect, info.font_size, text_color, .STRONG)
    case .SHOULDER, .TRIGGER:
        FillRoundedBorder(painter, rect, 0.6 if shape == .SHOULDER else 0.4, theme.control, theme.border, theme.border_width)
        TextCentered(painter, info.text, rect, info.font_size, ink, .STRONG)
    case .DPAD:
        arm: f32 = side / 3
        center: ui.Vec2 = ui.RectCenter(rect)
        painter.fill_rect(painter, {center.x - arm * 0.5, center.y - side * 0.5, arm, side}, theme.control)
        painter.fill_rect(painter, {center.x - side * 0.5, center.y - arm * 0.5, side, arm}, theme.control)
        // the arm that the label names is lit
        lit: ui.Color = theme.accent
        switch info.text {
        case "U": painter.fill_rect(painter, {center.x - arm * 0.5, center.y - side * 0.5, arm, arm}, lit)
        case "D": painter.fill_rect(painter, {center.x - arm * 0.5, center.y + side * 0.5 - arm, arm, arm}, lit)
        case "L": painter.fill_rect(painter, {center.x - side * 0.5, center.y - arm * 0.5, arm, arm}, lit)
        case "R": painter.fill_rect(painter, {center.x + side * 0.5 - arm, center.y - arm * 0.5, arm, arm}, lit)
        }
    case .STICK:
        box: ui.Rect = {rect.x + (rect.z - side) * 0.5, rect.y + (rect.w - side) * 0.5, side, side}
        FillRoundedBorder(painter, box, 1, theme.control, theme.border, theme.border_width)
        inner: f32 = side * 0.5
        FillRounded(painter, {box.x + (side - inner) * 0.5, box.y + (side - inner) * 0.5, inner, inner}, 1, theme.border)
        if info.text != "" { TextCentered(painter, info.text, rect, info.font_size, ink, .STRONG) }
    }
}
