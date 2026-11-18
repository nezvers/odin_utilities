package ui_default

import "core:math"
import "core:unicode/utf8"
import ui ".."

TimelineStyleInstall :: proc(style: ^ui.Style) {
    style.procs[.TIMELINE] = DrawTimeline
    style.timeline.draw_lane = DrawLane
    style.timeline.draw_clip = DrawClip
    style.timeline.draw_ruler = DrawRuler
    style.timeline.draw_playhead = DrawPlayhead
    style.timeline.draw_box = DrawTimelineBox
    style.timeline.draw_marker = DrawMarker
    style.timeline.draw_curve = DrawCurve
}

DrawTimeline :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    painter.fill_rect(painter, info.rect, painter.theme.track)
    ui.TimelineDraw(ctx, info)
}

DrawLane :: proc(ctx: ^ui.Context, lane: ^ui.LaneDraw) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    shade: ui.Color = ui.ColorLerp(theme.track, theme.control, 0.35 if lane.index % 2 == 0 else 0.12)
    if .HOVERED in lane.flags { shade = ui.ColorLerp(shade, theme.control_hover, 0.4) }
    if .DISABLED in lane.flags { shade = ui.ColorLerp(shade, theme.track, 0.6) }
    painter.fill_rect(painter, lane.rect, shade)
    painter.fill_rect(painter, {lane.rect.x, lane.rect.y + lane.rect.w - 1, lane.rect.z, 1}, theme.border)
    if lane.automation {
        // the middle of the range
        painter.fill_rect(painter, {lane.rect.x, lane.rect.y + lane.rect.w * 0.5, lane.rect.z, 1}, {theme.border.r, theme.border.g, theme.border.b, 90})
    }
    painter.draw_text(painter, lane.name, {lane.rect.x + 6, lane.rect.y + lane.rect.w - ctx.style.metrics.font_size - 4}, ctx.style.metrics.font_size * 0.85, ui.Color{theme.text_dim.r, theme.text_dim.g, theme.text_dim.b, 150})
}

DrawClip :: proc(ctx: ^ui.Context, clip: ^ui.ClipDraw) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    base: ui.Color = clip.color if clip.color.a > 0 else GraphTypeColor(u32(clip.track_index))
    body: ui.Color = ui.ColorLerp(theme.track, base, 0.55)
    if .HOVERED in clip.flags || .PRESSED in clip.flags { body = ui.ColorLerp(body, ui.Color{255, 255, 255, 255}, 0.12) }
    if .DISABLED in clip.flags { body = ui.ColorLerp(body, theme.track, 0.6) }
    border: ui.Color = theme.accent if .SELECTED in clip.flags else ui.ColorLerp(body, ui.Color{0, 0, 0, 255}, 0.4)
    FillRoundedBorder(painter, clip.rect, 0.12, body, border, 2 if .SELECTED in clip.flags else 1, 5)
    size: f32 = ctx.style.metrics.font_size * 0.9
    text_x: f32 = max(clip.rect.x, clip.visible.x) + 6
    room: f32 = min(clip.rect.x + clip.rect.z, clip.visible.x + clip.visible.z) - text_x - 4
    shown: string = clip.name
    for len(shown) > 0 && painter.measure_text(painter, shown, size).x > room {
        _, width := utf8.decode_last_rune_in_string(shown)
        shown = shown[:len(shown) - width]
    }
    if len(shown) > 0 {
        painter.draw_text(painter, shown, {text_x, clip.rect.y + 3}, size, theme.text)
    }
    if .HOVERED in clip.flags || .PRESSED in clip.flags {
        grip: ui.Color = {255, 255, 255, 90}
        if clip.rect.z > 24 {
            painter.fill_rect(painter, {clip.rect.x + 2, clip.rect.y + clip.rect.w * 0.3, 2, clip.rect.w * 0.4}, grip)
            painter.fill_rect(painter, {clip.rect.x + clip.rect.z - 4, clip.rect.y + clip.rect.w * 0.3, 2, clip.rect.w * 0.4}, grip)
        }
    }
}

DrawRuler :: proc(ctx: ^ui.Context, ruler: ^ui.RulerDraw) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    painter.fill_rect(painter, ruler.rect, ui.ColorLerp(theme.panel, theme.control, 0.5))
    painter.fill_rect(painter, {ruler.rect.x, ruler.rect.y + ruler.rect.w - 1, ruler.rect.z, 1}, theme.border)
    if ruler.loop_enabled {
        left: f32 = max(ruler.loop_x, ruler.rect.x)
        right: f32 = min(ruler.loop_end_x, ruler.rect.x + ruler.rect.z)
        if right > left {
            accent: ui.Color = theme.accent
            painter.fill_rect(painter, {left, ruler.rect.y, right - left, ruler.rect.w - 1}, {accent.r, accent.g, accent.b, 90})
            if ruler.loop_x >= ruler.rect.x { painter.fill_rect(painter, {ruler.loop_x, ruler.rect.y, 2, ruler.rect.w - 1}, accent) }
            if ruler.loop_end_x <= ruler.rect.x + ruler.rect.z { painter.fill_rect(painter, {ruler.loop_end_x - 2, ruler.rect.y, 2, ruler.rect.w - 1}, accent) }
        }
    }
    size: f32 = ctx.style.metrics.font_size * 0.8
    first: f64 = math.ceil(ruler.origin / ruler.step) * ruler.step
    last: f64 = ruler.origin + f64(ruler.rect.z / ruler.zoom)
    for time := first; time <= last; time += ruler.step {
        x: f32 = ruler.rect.x + f32((time - ruler.origin) * f64(ruler.zoom))
        painter.fill_rect(painter, {x, ruler.rect.y + ruler.rect.w * 0.45, 1, ruler.rect.w * 0.55}, theme.text_dim)
        painter.draw_text(painter, ui.UiFormat(ctx, "%g", time), {x + 3, ruler.rect.y + 2}, size, theme.text_dim)
        for part in 1 ..< 5 {
            minor: f32 = x + f32(f64(part) * ruler.step / 5 * f64(ruler.zoom))
            if minor < ruler.rect.x + ruler.rect.z { painter.fill_rect(painter, {minor, ruler.rect.y + ruler.rect.w * 0.75, 1, ruler.rect.w * 0.25}, theme.border) }
        }
    }
}

DrawPlayhead :: proc(ctx: ^ui.Context, head: ^ui.PlayheadDraw) {
    painter: ^Painter = painterOf(ctx)
    color: ui.Color = {240, 90, 80, 255}
    painter.fill_rect(painter, {head.x - 0.5, head.rect.y + head.ruler_height * 0.5, 2, head.rect.w - head.ruler_height * 0.5}, color)
    if painter.fill_polygon != nil {
        points: [3]ui.Vec2 = {{head.x - 6, head.rect.y + head.ruler_height * 0.35}, {head.x + 6, head.rect.y + head.ruler_height * 0.35}, {head.x, head.rect.y + head.ruler_height - 1}}
        painter.fill_polygon(painter, points[:], color)
    }
}

DrawTimelineBox :: proc(ctx: ^ui.Context, box: ^ui.BoxDraw) {
    painter: ^Painter = painterOf(ctx)
    accent: ui.Color = painter.theme.accent
    rect: ui.Rect = box.rect
    painter.fill_rect(painter, rect, {accent.r, accent.g, accent.b, 45})
    painter.fill_rect(painter, {rect.x, rect.y, rect.z, 1}, accent)
    painter.fill_rect(painter, {rect.x, rect.y + rect.w - 1, rect.z, 1}, accent)
    painter.fill_rect(painter, {rect.x, rect.y, 1, rect.w}, accent)
    painter.fill_rect(painter, {rect.x + rect.z - 1, rect.y, 1, rect.w}, accent)
}

DrawMarker :: proc(ctx: ^ui.Context, marker: ^ui.MarkerDraw) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = marker.color if marker.color.a > 0 else ui.Color{250, 200, 80, 255}
    if .SELECTED in marker.flags { color = theme.accent }
    painter.fill_rect(painter, {marker.x, marker.ruler.y + marker.ruler.w, 1, marker.area.w - marker.ruler.w}, {color.r, color.g, color.b, 110})
    size: f32 = ctx.style.metrics.font_size * 0.8
    flag: ui.Rect = {marker.x, marker.ruler.y, min(painter.measure_text(painter, marker.name, size).x + 12, marker.width), marker.ruler.w * 0.5}
    body: ui.Color = ui.ColorLerp(theme.panel, color, 0.6 if .HOVERED in marker.flags || .PRESSED in marker.flags else 0.45)
    painter.fill_rect(painter, flag, body)
    painter.fill_rect(painter, {marker.x, marker.ruler.y, 2, marker.ruler.w}, color)
    painter.draw_text(painter, marker.name, {marker.x + 6, marker.ruler.y + 1}, size, theme.text)
}

DrawCurve :: proc(ctx: ^ui.Context, curve: ^ui.CurveDraw) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = curve.color if curve.color.a > 0 else GraphTypeColor(5)
    for i in 1 ..< len(curve.points) {
        a, b: ui.CurvePoint = curve.points[i - 1], curve.points[i]
        if curve.steps {
            Line(painter, {a.x, a.y}, {b.x, a.y}, 2, color)
            Line(painter, {b.x, a.y}, {b.x, b.y}, 2, color)
        } else {
            Line(painter, {a.x, a.y}, {b.x, b.y}, 2, color)
        }
    }
    for point in curve.points {
        if point.x < curve.rect.x - 4 || point.x > curve.rect.x + curve.rect.z + 4 { continue }
        size: f32 = 4
        fill: ui.Color = theme.accent if .SELECTED in point.flags else ui.ColorLerp(color, ui.Color{255, 255, 255, 255}, 0.5 if .HOVERED in point.flags else 0)
        painter.fill_rect(painter, {point.x - size, point.y - size, size * 2, size * 2}, ui.ColorLerp(fill, ui.Color{0, 0, 0, 255}, 0.55))
        painter.fill_rect(painter, {point.x - size + 1.5, point.y - size + 1.5, size * 2 - 3, size * 2 - 3}, fill)
    }
}
