package ui_default

// The look of the widgets of ui/widgets_extra.odin: a switch, badges, chips and tags, avatars, a segmented choice, breadcrumbs, a spinner.

import "core:math"
import ui ".."

ExtraStyleInstall :: proc(style: ^ui.Style) {
    style.procs[.SWITCH] = DrawSwitch
    style.procs[.BADGE] = DrawBadge
    style.procs[.CHIP] = DrawChip
    style.procs[.AVATAR] = DrawAvatar
    style.procs[.SEGMENTED] = DrawSegmented
    style.procs[.SEGMENT] = DrawSegment
    style.procs[.BREADCRUMB] = DrawBreadcrumb
    style.procs[.SPINNER] = DrawSpinner
}

// The color of a tone as a fill, and the color of what is written on it: a wash of the tone with the tone as ink (the accent has its soft pair in the theme)
ToneColors :: proc(theme: ^Theme, tone: ui.Tone) -> (fill: ui.Color, ink: ui.Color) {
    base: ui.Color
    switch tone {
    case .NEUTRAL:
        return theme.surface_high, theme.text
    case .ACCENT:
        return theme.accent_soft, theme.accent_soft_text
    case .SUCCESS:
        base = theme.success
    case .WARNING:
        base = theme.warning
    case .DANGER:
        base = theme.danger
    }
    // on a dark theme the tone is a dim fill with a light ink, on a light one a pale fill with a deep ink
    if theme.dark { return ui.ColorLerp(theme.panel, base, 0.38), ui.ColorLerp(base, {255, 255, 255, 255}, 0.55) }
    return ui.ColorLerp(theme.panel, base, 0.22), ui.ColorLerp(base, {0, 0, 0, 255}, 0.35)
}

// A track that is the accent when it is on, with a round knob that slides from the left to the right
DrawSwitch :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    height: f32 = min(info.rect.w, 22)
    width: f32 = info.ratio if info.ratio > 0 else height * 1.8
    track: ui.Rect = {info.rect.x, info.rect.y + (info.rect.w - height) * 0.5, width, height}
    FocusRing(painter, &{rect = track, flags = info.flags}, 1)
    fill: ui.Color = ui.ColorLerp(theme.track_strong, theme.accent, info.value)
    fill = StateColor(theme, fill, theme.text, info)
    knob: ui.Color = ui.ColorLerp(theme.text_dim if theme.dark else theme.panel, theme.accent_text, info.value)
    if .DISABLED in info.flags { fill, knob = Faded(theme, fill), Faded(theme, knob) }
    FillRounded(painter, track, 1, fill)
    side: f32 = height - 6
    x: f32 = track.x + 3 + (width - side - 6) * info.value
    FillRounded(painter, {x, track.y + 3, side, side}, 1, knob)
    if info.name != "" {
        TextLeft(painter, info.name, {track.x + width, info.rect.y, info.rect.z - width, info.rect.w}, info.font_size, ctx.style.metrics.padding.x, textColor(theme, info))
    }
}

DrawBadge :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    fill, ink := ToneColors(&painter.theme, ui.Tone(clamp(int(info.actual), 0, len(ui.Tone) - 1)))
    FillRounded(painter, info.rect, 1, fill)
    TextCentered(painter, info.name, info.rect, info.font_size, ink, .STRONG)
}

// A chip is a pill with an outline that fills with the soft accent when it is chosen (a check mark comes before its name). A tag (actual 1) keeps its outline and has a cross.
DrawChip :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    selected: bool = .SELECTED in info.flags
    tag: bool = info.actual == 1
    fill: ui.Color = theme.accent_soft if selected else theme.panel
    ink: ui.Color = theme.accent_soft_text if selected else theme.text
    border: ui.Color = theme.accent_soft if selected else theme.border
    fill = StateColor(theme, fill, ink, info)
    if .DISABLED in info.flags { fill, ink, border = Faded(theme, fill), Faded(theme, ink), Faded(theme, border) }
    FocusRing(painter, info, 1)
    FillRoundedBorder(painter, info.rect, 1, fill, border, theme.border_width)
    padding: f32 = ctx.style.metrics.padding.x * 0.8
    x: f32 = info.rect.x + padding
    middle: f32 = info.rect.y + info.rect.w * 0.5
    if painter.draw_icon != nil {
        if info.icon != .NONE {
            IconAt(painter, IconToLucide(info.icon), {x + info.font_size * 0.5, middle}, info.font_size, ink)
            x += info.font_size + 4
        } else if selected && !tag {
            IconAt(painter, .CHECK, {x + info.font_size * 0.5, middle}, info.font_size, ink)
            x += info.font_size + 4
        }
    } else if info.icon != .NONE || (selected && !tag) {
        x += info.font_size + 4
    }
    TextLeft(painter, info.name, {x, info.rect.y, info.rect.z, info.rect.w}, info.font_size, 0, ink, .STRONG)
    if tag {
        center: ui.Vec2 = {info.rect.x + info.rect.z - padding - info.ratio * 0.5 + 3, middle}
        if painter.draw_icon != nil {
            IconAt(painter, .X, center, info.font_size * 0.9, theme.text_dim)
        } else {
            Line(painter, center + {-3.5, -3.5}, center + {3.5, 3.5}, 1.5, theme.text_dim)
            Line(painter, center + {-3.5, 3.5}, center + {3.5, -3.5}, 1.5, theme.text_dim)
        }
    }
}

DrawAvatar :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    color: ui.Color = info.color if info.color.a > 0 else painter.theme.accent
    FillRounded(painter, info.rect, 1, color)
    // white letters on a dark disc, dark ones on a light disc
    light: bool = int(color.r) * 299 + int(color.g) * 587 + int(color.b) * 114 > 150 * 1000
    TextCentered(painter, info.name, info.rect, info.font_size, {20, 22, 26, 255} if light else {255, 255, 255, 255}, .STRONG)
}

DrawSegmented :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FillRounded(painter, info.rect, theme.rounding, theme.track if theme.dark else theme.control, theme.max_radius + 2)
}

DrawSegment :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    selected: bool = .SELECTED in info.flags
    FocusRing(painter, info)
    if selected {
        Shadow(painter, info.rect, theme.max_radius - 2, 0.6)
        FillRounded(painter, info.rect, theme.rounding, theme.surface_high, theme.max_radius - 2)
    } else if info.hover > 0.01 || info.press > 0.01 {
        FillRounded(painter, info.rect, theme.rounding, StateWash(theme, theme.text, info), theme.max_radius - 2)
    }
    TextCentered(painter, info.name, info.rect, info.font_size, theme.text if selected else theme.text_dim, .STRONG)
}

// A part of a path: the accent for the ones that can be clicked, the plain text for the last one
DrawBreadcrumb :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    last: bool = .SELECTED in info.flags
    FocusRing(painter, info)
    if !last && (info.hover > 0.01 || info.press > 0.01) { FillRounded(painter, info.rect, theme.rounding, StateWash(theme, theme.accent, info), 6) }
    TextCentered(painter, info.name, info.rect, info.font_size, theme.text if last else theme.accent, .STRONG)
}

// Eight dots on a circle, the strongest one going around once a second
DrawSpinner :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    accent: ui.Color = painter.theme.accent
    DOTS :: 8
    center: ui.Vec2 = ui.RectCenter(info.rect)
    radius: f32 = min(info.rect.z, info.rect.w) * 0.38
    dot: f32 = max(min(info.rect.z, info.rect.w) * 0.16, 2)
    lead: int = int(math.mod(info.value, 1) * DOTS)
    for i in 0 ..< DOTS {
        angle: f32 = f32(i) / DOTS * 2 * math.PI
        // the dots behind the leading one fade
        behind: int = (lead - i + DOTS) % DOTS
        alpha: f32 = 1 - f32(behind) / DOTS * 0.85
        position: ui.Vec2 = center + {math.cos(angle), math.sin(angle)} * radius
        FillRounded(painter, {position.x - dot * 0.5, position.y - dot * 0.5, dot, dot}, 1, {accent.r, accent.g, accent.b, u8(alpha * 255)})
    }
}
