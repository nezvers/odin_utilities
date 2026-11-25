package ui_default

// The overview strip of ui/overview.odin: clips as blocks in the rows of their tracks, the sections as a band with names, the window of the view as a frame, the playhead.

import hm "core:container/handle_map"
import ui ".."

DrawOverview :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    overview: ^ui.Overview = cast(^ui.Overview)info.user
    rect: ui.Rect = info.rect
    FocusRing(painter, info)
    FillRoundedBorder(painter, rect, theme.rounding, theme.track, theme.border, theme.border_width, theme.max_radius)
    if overview == nil { return }
    total: f64 = ui.OverviewTotal(overview)
    inner: ui.Rect = ui.RectShrink(rect, 2)
    sections: []ui.OverviewSection = ui.OverviewSections(overview)
    band: f32 = min(inner.w * 0.3, info.font_size + 2) if len(sections) > 0 else 0
    lanes: ui.Rect = {inner.x, inner.y + band, inner.z, inner.w - band}
    for section in sections {
        x0: f32 = inner.x + f32(section.start / total) * inner.z
        x1: f32 = inner.x + f32(min((section.start + section.length) / total, 1)) * inner.z
        color: ui.Color = section.color if section.color.a > 0 else ui.ColorLerp(theme.track, theme.accent, 0.35)
        painter.fill_rect(painter, {x0, inner.y, max(x1 - x0 - 1, 1), band}, color)
        TextLeft(painter, section.name, {x0, inner.y, max(x1 - x0 - 1, 1), band}, info.font_size * 0.75, 3, theme.text)
    }
    it := hm.iterator_make(&overview.timeline.clips)
    for clip, _ in hm.iterate(&it) {
        block, ok := ui.OverviewClipRect(overview, lanes, clip)
        if !ok { continue }
        color: ui.Color = clip.color if clip.color.a > 0 else theme.accent
        painter.fill_rect(painter, block, ui.ColorLerp(theme.track, color, 0.8))
    }
    left, right: f32 = rect.x + rect.z * info.value, rect.x + rect.z * info.ratio
    shade: ui.Color = ui.ColorLerp(theme.track, theme.background, 0.5)
    shade.a = 140
    painter.fill_rect(painter, {rect.x, rect.y, left - rect.x, rect.w}, shade)
    painter.fill_rect(painter, {right, rect.y, rect.x + rect.z - right, rect.w}, shade)
    edge: ui.Color = theme.accent if info.press > 0.01 || info.hover > 0.01 else theme.text_dim
    painter.fill_rect(painter, {left, rect.y, 2, rect.w}, edge)
    painter.fill_rect(painter, {right - 2, rect.y, 2, rect.w}, edge)
    painter.fill_rect(painter, {left, rect.y, right - left, 1}, edge)
    painter.fill_rect(painter, {left, rect.y + rect.w - 1, right - left, 1}, edge)
    painter.fill_rect(painter, {rect.x + rect.z * info.actual, rect.y, 1, rect.w}, theme.text)
}
