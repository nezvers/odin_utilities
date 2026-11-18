package ui_default

// The default look of the knob, the fader and the level meter (widgets_audio.odin).

import "core:math"
import ui ".."

KNOB_START :: f32(math.PI * 0.75)           // the arc starts bottom left and goes round the top to the bottom right (270 degrees)
KNOB_SWEEP :: f32(math.PI * 1.5)
KNOB_STEPS :: 28

AudioStyleInstall :: proc(style: ^ui.Style) {
    style.procs[.KNOB] = DrawKnob
    style.procs[.FADER] = DrawFader
    style.procs[.METER] = DrawMeter
}

// A piece of the arc of a circle as short straight quads
@(private)
arc :: proc(painter: ^Painter, center: ui.Vec2, radius: f32, from: f32, to: f32, thickness: f32, color: ui.Color) {
    previous: ui.Vec2 = center + ui.Vec2{math.cos(from), math.sin(from)} * radius
    for i in 1 ..= KNOB_STEPS {
        angle: f32 = from + (to - from) * f32(i) / KNOB_STEPS
        current: ui.Vec2 = center + ui.Vec2{math.cos(angle), math.sin(angle)} * radius
        Line(painter, previous, current, thickness, color)
        previous = current
    }
}

DrawKnob :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    side: f32 = min(info.rect.z, info.rect.w)
    center: ui.Vec2 = ui.RectCenter(info.rect)
    radius: f32 = side * 0.5 - 3
    disabled: bool = .DISABLED in info.flags
    if .FOCUSED in info.flags { FocusRing(painter, info, 1) }
    FillRounded(painter, {center.x - radius, center.y - radius, radius * 2, radius * 2}, 1, ControlColor(theme, info))
    thickness: f32 = max(side * 0.07, 2)
    arc_radius: f32 = radius - thickness
    arc(painter, center, arc_radius, KNOB_START, KNOB_START + KNOB_SWEEP, thickness, theme.track)
    fill: ui.Color = theme.text_dim if disabled else theme.accent
    // a knob that has a default shows the arc from the default (a pan knob fills from the middle)
    from: f32 = info.ratio
    arc(painter, center, arc_radius, KNOB_START + KNOB_SWEEP * min(from, info.value), KNOB_START + KNOB_SWEEP * max(from, info.value), thickness, fill)
    angle: f32 = KNOB_START + KNOB_SWEEP * info.value
    direction: ui.Vec2 = {math.cos(angle), math.sin(angle)}
    Line(painter, center + direction * (radius * 0.25), center + direction * (arc_radius - thickness * 0.5), max(thickness * 0.8, 2), theme.text)
}

DrawFader :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    if .FOCUSED in info.flags {
        // an outline: a fader has no body to hide a filled ring behind
        accent: ui.Color = theme.accent
        painter.fill_rect(painter, {rect.x, rect.y, rect.z, 2}, accent)
        painter.fill_rect(painter, {rect.x, rect.y + rect.w - 2, rect.z, 2}, accent)
        painter.fill_rect(painter, {rect.x, rect.y, 2, rect.w}, accent)
        painter.fill_rect(painter, {rect.x + rect.z - 2, rect.y, 2, rect.w}, accent)
    }
    groove_width: f32 = max(rect.z * 0.18, 3)
    handle_height: f32 = ui.FaderHandleHeight(rect.z)
    run: f32 = rect.w - handle_height
    center_x: f32 = rect.x + rect.z * 0.5
    groove: ui.Rect = {center_x - groove_width * 0.5, rect.y + handle_height * 0.5, groove_width, run}
    handle_y: f32 = rect.y + run * (1 - info.value)
    FillRounded(painter, groove, 1, theme.track)
    fill: ui.Color = theme.text_dim if .DISABLED in info.flags else theme.accent
    painter.fill_rect(painter, {groove.x, handle_y + handle_height * 0.5, groove.z, groove.y + groove.w - handle_y - handle_height * 0.5}, fill)
    // a tick at the default
    default_y: f32 = rect.y + handle_height * 0.5 + run * (1 - info.ratio)
    painter.fill_rect(painter, {rect.x + rect.z * 0.1, default_y, rect.z * 0.8, 1}, theme.border)
    handle: ui.Rect = {rect.x + rect.z * 0.05, handle_y, rect.z * 0.9, handle_height}
    FillRoundedBorder(painter, handle, theme.rounding, ControlColor(theme, info), theme.border, theme.border_width, theme.max_radius)
    painter.fill_rect(painter, {handle.x + 2, handle.y + handle.w * 0.5 - 0.5, handle.z - 4, 2}, theme.text)
}

// Green up to 70 %, yellow to 90 %, red above: three rectangles at most, no matter how often it is drawn
DrawMeter :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    horizontal: bool = info.cursor == 1
    painter.fill_rect(painter, rect, theme.track)
    inner: ui.Rect = ui.RectShrink(rect, 1)
    length: f32 = inner.z if horizontal else inner.w
    // the part of the zone from `low` to `high` (0..1) that the level reaches
    zone :: proc(painter: ^Painter, inner: ui.Rect, horizontal: bool, length: f32, low: f32, high: f32, level: f32, color: ui.Color) {
        top: f32 = min(level, high)
        if top <= low { return }
        if horizontal {
            painter.fill_rect(painter, {inner.x + low * length, inner.y, (top - low) * length, inner.w}, color)
        } else {
            painter.fill_rect(painter, {inner.x, inner.y + inner.w - top * length, inner.z, (top - low) * length}, color)
        }
    }
    zone(painter, inner, horizontal, length, 0, 0.7, info.value, {80, 200, 110, 255})
    zone(painter, inner, horizontal, length, 0.7, 0.9, info.value, {235, 200, 70, 255})
    zone(painter, inner, horizontal, length, 0.9, 1, info.value, {230, 80, 70, 255})
    if info.ratio >= 0 {
        if horizontal {
            painter.fill_rect(painter, {inner.x + info.ratio * length - 1, inner.y, 2, inner.w}, theme.text)
        } else {
            painter.fill_rect(painter, {inner.x, inner.y + inner.w - info.ratio * length - 1, inner.z, 2}, theme.text)
        }
    }
}
