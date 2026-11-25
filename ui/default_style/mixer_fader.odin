package ui_default

// The mixer fader (ui.UiMixerFader): the numbers of the dB scale, a groove with the handle (a coloured mark across it), a stereo meter that shares the scale (green, yellow from -12 dB,
// red from -3 dB, a held peak line, a clip mark above 0 dB) and the value written under it. Positions are the arithmetic of ui/mixer_fader.odin.

import ui ".."

DrawMixerFader :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    has_meter: bool = len(info.values) >= 4
    areas: ui.MixerFaderAreas = ui.MixerFaderLayout(rect, has_meter)
    disabled: bool = .DISABLED in info.flags
    size: f32 = info.font_size * 0.8
    if .FOCUSED in info.flags {
        painter.fill_rect(painter, {rect.x, rect.y, rect.z, 1}, theme.accent)
        painter.fill_rect(painter, {rect.x, rect.y + rect.w - 1, rect.z, 1}, theme.accent)
        painter.fill_rect(painter, {rect.x, rect.y, 1, rect.w}, theme.accent)
        painter.fill_rect(painter, {rect.x + rect.z - 1, rect.y, 1, rect.w}, theme.accent)
    }

    // the scale: a tick on the groove and the number, when there is room for it
    last_label: f32 = -1e9
    for db in ui.MIXER_FADER_TICKS {
        y: f32 = ui.MixerFaderY(areas, ui.MixerFaderPosition(db))
        painter.fill_rect(painter, {areas.track.x - 5, y, 4, 1}, theme.text_dim)
        if y - last_label < size + 2 { continue }
        last_label = y
        label: string = ui.UiFormat(ctx, "%d", int(db)) if db <= 0 else ui.UiFormat(ctx, "+%d", int(db))
        painter.draw_text(painter, label, {areas.scale.x + areas.scale.z - 8 - painter.measure_text(painter, label, size).x, y - size * 0.55}, size, theme.text_dim)
    }

    // the groove, the fill up to the handle and the 0 dB (default) line
    center: f32 = areas.track.x + areas.track.z * 0.5
    handle_height: f32 = ui.MixerFaderHandleHeight(areas.track)
    top: f32 = areas.track.y + handle_height * 0.5
    bottom: f32 = areas.track.y + areas.track.w - handle_height * 0.5
    FillRounded(painter, {center - 2, top, 4, max(bottom - top, 1)}, 1.5, theme.track)
    handle_y: f32 = ui.MixerFaderY(areas, info.value)
    fill: ui.Color = theme.text_dim if disabled else theme.accent_soft
    painter.fill_rect(painter, {center - 2, handle_y, 4, max(bottom - handle_y, 0)}, fill)
    default_y: f32 = ui.MixerFaderY(areas, info.ratio)
    painter.fill_rect(painter, {areas.track.x + 2, default_y, areas.track.z - 4, 1}, theme.border)

    // the stereo meter
    if has_meter {
        levels: []f32 = info.values
        for channel in 0 ..< 2 {
            bar: ui.Rect = {areas.meter.x + f32(channel) * (ui.MIXER_METER_BAR + 3), areas.meter.y, ui.MIXER_METER_BAR, areas.meter.w}
            painter.fill_rect(painter, bar, theme.track)
            // the travel of the meter is the one of the fader from its lowest to its highest point
            level_top: f32 = bar.y + bar.w * (1 - ui.MixerFaderPosition(levels[channel]))
            zones: [3][3]f32 = {{ui.MIXER_FADER_MIN, -12, 0}, {-12, -3, 1}, {-3, ui.MIXER_FADER_MAX, 2}}
            colors: [3]ui.Color = {theme.success, theme.warning, theme.danger}
            for zone in zones {
                zone_top: f32 = bar.y + bar.w * (1 - ui.MixerFaderPosition(zone[1]))
                zone_bottom: f32 = bar.y + bar.w * (1 - ui.MixerFaderPosition(zone[0]))
                from: f32 = max(level_top, zone_top)
                if from < zone_bottom { painter.fill_rect(painter, {bar.x, from, bar.z, zone_bottom - from}, colors[int(zone[2])]) }
            }
            peak: f32 = levels[2 + channel]
            if peak > ui.MIXER_FADER_MIN {
                peak_y: f32 = bar.y + bar.w * (1 - ui.MixerFaderPosition(peak))
                painter.fill_rect(painter, {bar.x, clamp(peak_y, bar.y, bar.y + bar.w - 2), bar.z, 2}, theme.danger if peak > 0 else theme.text)
            }
            if peak > 0 { painter.fill_rect(painter, {bar.x, bar.y - 3, bar.z, 2}, theme.danger) }
        }
    }

    // the handle
    handle: ui.Rect = {areas.track.x + 1, handle_y - handle_height * 0.5, areas.track.z - 2, handle_height}
    FillRoundedBorder(painter, handle, theme.rounding, ControlColor(theme, info), theme.border, theme.border_width, theme.max_radius)
    painter.fill_rect(painter, {handle.x + 3, handle.y + handle.w * 0.5 - 1, handle.z - 6, 2}, theme.text_dim if disabled else theme.accent)

    // the value
    FillRoundedBorder(painter, ui.RectShrink(areas.readout, 1), theme.rounding, theme.track, theme.border, 1, theme.max_radius)
    text_size: f32 = info.font_size * 0.9
    width: f32 = painter.measure_text(painter, info.text, text_size).x
    painter.draw_text(painter, info.text, {areas.readout.x + (areas.readout.z - width) * 0.5, areas.readout.y + (areas.readout.w - text_size) * 0.5}, text_size, theme.text_dim if disabled else theme.text)
}
