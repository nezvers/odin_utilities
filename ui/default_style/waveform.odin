package ui_default

// The waveform view (ui.UiWaveform): a ruler of time, the samples as a min / max column per pixel around a centre line, the selected region tinted, markers with their names and the
// playhead. The arithmetic is ui/waveform.odin, so the pointer and the picture agree.

import "core:fmt"
import "core:math"
import ui ".."

DrawWaveform :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    view: ^ui.WaveformView = cast(^ui.WaveformView)info.user
    if view == nil || view.wave == nil { return }
    wave: ^ui.Waveform = view.wave
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    areas: ui.WaveAreas = ui.WaveformAreas(info.rect)
    body: ui.Rect = areas.body
    if body.z <= 0 || body.w <= 0 { return }
    size: f32 = info.font_size * 0.85
    spp: f64 = ui.WaveformSamplesPerPixel(wave, view, areas)
    total: f64 = f64(len(wave.samples))
    painter.fill_rect(painter, info.rect, theme.panel)
    painter.fill_rect(painter, body, theme.track)
    mid: f32 = body.y + body.w * 0.5
    half: f32 = max(body.w * 0.5 - 3, 1)
    painter.fill_rect(painter, {body.x, mid, body.z, 1}, theme.border)

    // the ruler: ticks at a round step of seconds (or samples) about 80 pixels apart
    unit: f64 = f64(wave.sample_rate) if wave.sample_rate > 0 else 1
    wanted: f64 = spp * 80 / unit
    step: f64 = 1
    for exponent: f64 = -3; exponent <= 6; exponent += 1 {
        decade: f64 = math.pow(10, exponent)
        done: bool = false
        for m in ([3]f64{1, 2, 5}) {
            if decade * m >= wanted { step, done = decade * m, true; break }
        }
        if done { break }
    }
    if wave.sample_rate <= 0 { step = max(math.round(step), 1) }
    tick: f64 = math.ceil(ui.WaveformSampleAt(wave, view, areas, body.x) / unit / step) * step
    for ; ; tick += step {
        x: f32 = ui.WaveformX(wave, view, areas, tick * unit)
        if x >= body.x + body.z { break }
        if tick * unit > total { break }
        painter.fill_rect(painter, {x, areas.ruler.y + areas.ruler.w - 6, 1, 6}, theme.text_dim)
        label: string = fmt.tprintf("%g s", tick) if wave.sample_rate > 0 else fmt.tprintf("%.0f", tick)
        painter.draw_text(painter, label, {x + 3, areas.ruler.y + 2}, size, theme.text_dim)
    }
    painter.fill_rect(painter, {areas.ruler.x, areas.ruler.y + areas.ruler.w - 1, areas.ruler.z, 1}, theme.border)

    // the selected region under the columns
    if view.has_selection {
        left: f32 = clamp(ui.WaveformX(wave, view, areas, view.selection_start), body.x, body.x + body.z)
        right: f32 = clamp(ui.WaveformX(wave, view, areas, view.selection_end), body.x, body.x + body.z)
        if right > left { painter.fill_rect(painter, {left, body.y, right - left, body.w}, {theme.accent.r, theme.accent.g, theme.accent.b, 45}) }
    }

    // the columns
    for column: f32 = 0; column < body.z; column += 1 {
        first: f64 = view.origin + f64(column) * spp
        if first >= total { break }
        last: f64 = first + spp
        first_index: int = int(first)
        low, high: f32 = ui.WaveformRange(wave, first_index, max(int(math.ceil(last)), first_index + 1) + (1 if spp < 1 else 0))
        top: f32 = mid - clamp(high, -1, 1) * half
        bottom: f32 = mid - clamp(low, -1, 1) * half
        painter.fill_rect(painter, {body.x + column, top, 1, max(bottom - top, 1)}, theme.accent)
    }

    // the markers
    for i in 0 ..< wave.marker_count {
        marker: ui.WaveMarker = wave.markers[i]
        x: f32 = ui.WaveformX(wave, view, areas, marker.position)
        if x < body.x || x >= body.x + body.z { continue }
        color: ui.Color = theme.warning
        if i == view.hover_marker { color = theme.text }
        painter.fill_rect(painter, {x, areas.ruler.y, 1, info.rect.w}, color)
        if marker.name != "" {
            width: f32 = painter.measure_text(painter, marker.name, size).x + 8
            flag: ui.Rect = ui.RectIntersect({x + 1, areas.ruler.y + 1, width, areas.ruler.w - 3}, areas.ruler)
            painter.fill_rect(painter, flag, color)
            painter.draw_text(painter, marker.name, {x + 5, areas.ruler.y + 2}, size, theme.panel)
        } else {
            painter.fill_rect(painter, {x - 3, areas.ruler.y, 7, 4}, color)
        }
    }

    // the playhead
    if view.show_playhead {
        x: f32 = ui.WaveformX(wave, view, areas, view.playhead)
        if x >= body.x && x < body.x + body.z { painter.fill_rect(painter, {x, areas.ruler.y, 1.5, info.rect.w}, {250, 180, 60, 255}) }
    }
}
