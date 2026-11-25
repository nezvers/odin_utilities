package ui_default

// The content of a clip (ui/clip_body.odin): notes as dashes, a mirrored wave, the cells of a pattern. Only what is inside of the clip and of the part of the screen in view is drawn.

import ui ".."

@(private)
clipBody :: proc(ctx: ^ui.Context, painter: ^Painter, clip: ^ui.ClipDraw, base: ui.Color) {
    body: ^ui.ClipBody = clip.body
    if body == nil || body.kind == .NONE || clip.length <= 0 { return }
    theme: ^Theme = &painter.theme
    area: ui.Rect = ui.ClipBodyArea(clip.rect, ctx.style.metrics.font_size * 0.9 + 5)
    if area.z < 4 || area.w < 4 { return }
    ink: ui.Color = ui.ColorLerp(base, ui.Color{255, 255, 255, 255}, 0.7)
    if .DISABLED in clip.flags { ink = ui.ColorLerp(ink, theme.track, 0.6) }
    view_left, view_right: f32 = clip.visible.x, clip.visible.x + clip.visible.z
    // a rectangle cut to the part in view
    put :: proc(painter: ^Painter, rect: ui.Rect, left: f32, right: f32, color: ui.Color) {
        x0, x1: f32 = max(rect.x, left), min(rect.x + rect.z, right)
        if x1 > x0 { painter.fill_rect(painter, {x0, rect.y, x1 - x0, rect.w}, color) }
    }
    repeats: int = ui.ClipBodyRepeats(body, clip.length)
    switch body.kind {
    case .NONE:
    case .NOTES:
        low, high: int = ui.ClipBodyPitchRange(body)
        for repeat in 0 ..< repeats {
            for note in body.notes {
                rect, ok := ui.ClipBodyNoteRect(body, area, clip.length, note, repeat, low, high)
                if ok { put(painter, rect, view_left, view_right, ink) }
            }
        }
    case .STEPS:
        per_row: int = len(body.steps) / max(body.rows, 1)
        for repeat in 0 ..< repeats {
            for row in 0 ..< body.rows {
                for step in 0 ..< per_row {
                    value: f32 = body.steps[row * per_row + step]
                    if value <= 0 { continue }
                    rect, ok := ui.ClipBodyStepRect(body, area, clip.length, row, step, repeat)
                    if ok { put(painter, rect, view_left, view_right, ui.ColorLerp(ink, base, 1 - min(value, 1))) }
                }
            }
        }
    case .WAVEFORM:
        columns: int = int(area.z)
        middle: f32 = area.y + area.w * 0.5
        first: int = max(int(view_left - area.x), 0)
        last: int = min(int(view_right - area.x) + 1, columns)
        for column in first ..< last {
            peak: f32 = ui.ClipBodyPeak(body, clip.length, column, columns)
            half: f32 = max(peak * area.w * 0.5, 0.5)
            painter.fill_rect(painter, {area.x + f32(column), middle - half, 1, half * 2}, ink)
        }
    }
}
