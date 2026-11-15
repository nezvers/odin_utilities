package ui_default

// The default style of the ui library, and the Painter it draws with. The style procs are ordinary StyleProcs: copy this file as the start
// of a style of your own, or replace single entries of the table (`style.procs[.BUTTON] = MyButton`).
//
// A Painter is the five things a style needs from a framework: filled rectangles and polygons, text, its measure, and the scissor. The
// glue packages (ui/kit, ui/glue_raylib, ui/glue_karl2d) fill one in. The painter is found through `ctx.user`.
//
//     painter: ui_default.Painter
//     ui_raylib.PainterInit(&painter)
//     ui.UiInit(&ctx, &storage, ui_default.Measure, &painter)
//     style := ui_default.StyleMake()
//
// Rounded corners are a part of the shortest side (ui.RoundedRadius): `rounding = 1` is the full round. A painter that can draw a
// rounded rectangle itself sets `fill_rounded`, the others get a triangle fan from the points of ui.RoundedPoints.

import "core:math"
import ui ".."

Theme :: struct {
    panel: ui.Color,
    border: ui.Color,
    text: ui.Color,
    text_dim: ui.Color,             // placeholders, disabled
    control: ui.Color,
    control_hover: ui.Color,
    control_pressed: ui.Color,
    track: ui.Color,                // the empty part of sliders and progress bars
    accent: ui.Color,               // what is on, filled, selected, focused
    accent_text: ui.Color,
    rounding: f32,                  // controls: 0 sharp .. 1 full round
    panel_rounding: f32,
    max_radius: f32,                // pixels, 0: no limit
    border_width: f32,
}

THEME_DARK :: Theme{
    panel = {32, 34, 42, 235},
    border = {70, 74, 90, 255},
    text = {230, 232, 240, 255},
    text_dim = {140, 144, 160, 255},
    control = {58, 62, 78, 255},
    control_hover = {74, 80, 102, 255},
    control_pressed = {44, 48, 62, 255},
    track = {24, 26, 32, 255},
    accent = {86, 156, 240, 255},
    accent_text = {255, 255, 255, 255},
    rounding = 0.3,
    panel_rounding = 0.08,
    max_radius = 12,
    border_width = 1,
}

Painter :: struct {
    user: rawptr,                   // the glue's own data (the kit.Context of the frame, a font...)
    theme: Theme,
    fill_rect: proc(painter: ^Painter, rect: ui.Rect, color: ui.Color),
    fill_polygon: proc(painter: ^Painter, points: []ui.Vec2, color: ui.Color),                  // convex, nil: no polygons (arrows and rounded corners fall back)
    fill_rounded: proc(painter: ^Painter, rect: ui.Rect, radius: f32, color: ui.Color),         // nil: made from fill_polygon
    draw_text: proc(painter: ^Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color),
    measure_text: proc(painter: ^Painter, text: string, size: f32) -> ui.Vec2,
    clip: proc(painter: ^Painter, rect: ui.Rect, begin: bool),
}

@(private)
painterOf :: proc(ctx: ^ui.Context) -> ^Painter {
    return cast(^Painter)ctx.user
}

// The measure proc for ui.UiInit when the painter is the user pointer
Measure :: proc(ctx: ^ui.Context, text: string, font_size: f32) -> ui.Vec2 {
    painter: ^Painter = painterOf(ctx)
    return painter.measure_text(painter, text, font_size)
}

// The style: the table of procs below with the metrics of the theme
StyleMake :: proc() -> ui.Style {
    style: ui.Style = {
        metrics = ui.DEFAULT_METRICS,
        clip = proc(ctx: ^ui.Context, rect: ui.Rect, begin: bool) {
            painter: ^Painter = painterOf(ctx)
            if painter.clip != nil { painter.clip(painter, rect, begin) }
        },
    }
    style.procs[.PANEL] = DrawPanel
    style.procs[.LABEL] = DrawLabel
    style.procs[.BUTTON] = DrawButton
    style.procs[.TOGGLE] = DrawToggle
    style.procs[.SLIDER] = DrawSlider
    style.procs[.PROGRESS] = DrawProgress
    style.procs[.TEXT_FIELD] = DrawTextField
    style.procs[.SEPARATOR] = DrawSeparator
    style.procs[.DROPDOWN] = DrawDropdown
    style.procs[.DROPDOWN_ITEM] = DrawDropdownItem
    style.procs[.SCROLLBAR] = DrawScrollbar
    return style
}

// ------------------------------------------------------------------------------------------------------------------------
// Helpers for styles

// A filled rounded rectangle: `rounding` is the part of half the shortest side (1 is the full round), limited to `max_radius` pixels (0: no limit)
FillRounded :: proc(painter: ^Painter, rect: ui.Rect, rounding: f32, color: ui.Color, max_radius: f32 = 0) {
    if color.a == 0 || rect.z <= 0 || rect.w <= 0 { return }
    radius: f32 = ui.RoundedRadius(rect, rounding, max_radius)
    if radius <= 0.5 {
        painter.fill_rect(painter, rect, color)
        return
    }
    if painter.fill_rounded != nil {
        painter.fill_rounded(painter, rect, radius, color)
        return
    }
    if painter.fill_polygon == nil {
        painter.fill_rect(painter, rect, color)
        return
    }
    buffer: ui.RoundedBuffer
    points: []ui.Vec2 = ui.RoundedPoints(rect, {radius, radius, radius, radius}, ui.RoundedSegments(radius), buffer[:])
    painter.fill_polygon(painter, points, color)
}

// A rounded rectangle with a border: the border color first, the fill inside of it
FillRoundedBorder :: proc(painter: ^Painter, rect: ui.Rect, rounding: f32, color: ui.Color, border: ui.Color, border_width: f32, max_radius: f32 = 0) {
    if border_width > 0 && border.a > 0 {
        FillRounded(painter, rect, rounding, border, max_radius)
        inner: ui.Rect = ui.RectShrink(rect, border_width)
        // the inner corners are smaller by the width of the border, so the border has the same width all around
        outer_radius: f32 = ui.RoundedRadius(rect, rounding, max_radius)
        inner_radius: f32 = max(outer_radius - border_width, 0)
        half: f32 = min(inner.z, inner.w) * 0.5
        FillRounded(painter, inner, inner_radius / max(half, 0.001), color)
    } else {
        FillRounded(painter, rect, rounding, color, max_radius)
    }
}

// A text with its center at the center of the rect
TextCentered :: proc(painter: ^Painter, text: string, rect: ui.Rect, size: f32, color: ui.Color) {
    measured: ui.Vec2 = painter.measure_text(painter, text, size)
    painter.draw_text(painter, text, {rect.x + (rect.z - measured.x) * 0.5, rect.y + (rect.w - measured.y) * 0.5}, size, color)
}

// A text on the left of the rect (`padding` from the edge), centered up and down
TextLeft :: proc(painter: ^Painter, text: string, rect: ui.Rect, size: f32, padding: f32, color: ui.Color) {
    measured: ui.Vec2 = painter.measure_text(painter, text, size)
    painter.draw_text(painter, text, {rect.x + padding, rect.y + (rect.w - measured.y) * 0.5}, size, color)
}

TextRight :: proc(painter: ^Painter, text: string, rect: ui.Rect, size: f32, padding: f32, color: ui.Color) {
    measured: ui.Vec2 = painter.measure_text(painter, text, size)
    painter.draw_text(painter, text, {rect.x + rect.z - measured.x - padding, rect.y + (rect.w - measured.y) * 0.5}, size, color)
}

// The color of a control through its states: base, then hover, then pressed (the style animates with info.hover and info.press)
ControlColor :: proc(theme: ^Theme, info: ^ui.DrawInfo) -> ui.Color {
    color: ui.Color = ui.ColorLerp(theme.control, theme.control_hover, info.hover)
    return ui.ColorLerp(color, theme.control_pressed, info.press)
}

@(private)
textColor :: proc(theme: ^Theme, info: ^ui.DrawInfo) -> ui.Color {
    return theme.text_dim if .DISABLED in info.flags else theme.text
}

// ------------------------------------------------------------------------------------------------------------------------
// The procs of the style

DrawPanel :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FillRoundedBorder(painter, info.rect, theme.panel_rounding, theme.panel, theme.border, theme.border_width, theme.max_radius)
}

DrawLabel :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    painter.draw_text(painter, info.text, {info.rect.x, info.rect.y}, info.font_size, painter.theme.text)
}

DrawButton :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = theme.control if .DISABLED in info.flags else ControlColor(theme, info)
    FillRounded(painter, info.rect, theme.rounding, color, theme.max_radius)
    TextCentered(painter, info.name, info.rect, info.font_size, textColor(theme, info))
}

DrawToggle :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    box: ui.Rect = {info.rect.x, info.rect.y, info.rect.w, info.rect.w}
    on: bool = .ON in info.flags
    FillRoundedBorder(painter, box, theme.rounding, theme.accent if on else ControlColor(theme, info), theme.border, theme.border_width, theme.max_radius)
    if on {
        // a check mark inside of the box
        inner: ui.Rect = ui.RectShrink(box, box.z * 0.28)
        FillRounded(painter, inner, theme.rounding, theme.accent_text, theme.max_radius)
    }
    TextLeft(painter, info.name, {info.rect.x + box.z, info.rect.y, info.rect.z - box.z, info.rect.w}, info.font_size, 8, textColor(theme, info))
}

DrawSlider :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    // a bar that fills up to the value, a thin handle at the end of the fill, the name and the number on it
    FillRounded(painter, rect, theme.rounding, theme.track, theme.max_radius)
    width: f32 = rect.z * info.value
    if width > 0 {
        FillRounded(painter, {rect.x, rect.y, max(width, rect.w * 0.5), rect.w}, theme.rounding, theme.accent, theme.max_radius)
    }
    handle_width: f32 = 4
    handle_x: f32 = clamp(rect.x + width - handle_width * 0.5, rect.x + 2, rect.x + rect.z - handle_width - 2)
    handle_color: ui.Color = ui.ColorLerp(theme.text, theme.accent_text, info.press)
    FillRounded(painter, {handle_x, rect.y + 4, handle_width, rect.w - 8}, 1, handle_color)
    TextLeft(painter, info.name, rect, info.font_size, 10, theme.accent_text if width > 60 else textColor(theme, info))
    TextRight(painter, info.text, rect, info.font_size, 10, textColor(theme, info))
}

DrawProgress :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FillRounded(painter, info.rect, 1, theme.track, theme.max_radius)
    // the fill keeps the round ends of the bar even when it is short
    width: f32 = info.rect.z * info.value
    if width > 0 {
        FillRounded(painter, {info.rect.x, info.rect.y, max(width, info.rect.w), info.rect.w}, 1, theme.accent, theme.max_radius)
    }
    TextCentered(painter, info.name, info.rect, info.font_size, theme.accent_text)
}

DrawTextField :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    focused: bool = .FOCUSED in info.flags
    FillRoundedBorder(painter, info.rect, theme.rounding * 0.6, theme.track, theme.accent if focused else theme.border, theme.border_width, theme.max_radius)
    padding: f32 = ctx.style.metrics.padding.x
    if info.text == "" && !focused {
        TextLeft(painter, info.name, info.rect, info.font_size, padding, theme.text_dim)
        return
    }
    TextLeft(painter, info.text, info.rect, info.font_size, padding, textColor(theme, info))
    // the caret blinks twice a second
    if focused && math.mod(ctx.time, 1.0) < 0.5 {
        x: f32 = info.rect.x + padding + painter.measure_text(painter, info.text[:info.cursor], info.font_size).x
        painter.fill_rect(painter, {x, info.rect.y + 5, 2, info.rect.w - 10}, theme.text)
    }
}

DrawSeparator :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    painter.fill_rect(painter, info.rect, painter.theme.border)
}

DrawDropdown :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FillRounded(painter, info.rect, theme.rounding, ControlColor(theme, info), theme.max_radius)
    TextLeft(painter, info.text, info.rect, info.font_size, ctx.style.metrics.padding.x, textColor(theme, info))
    // an arrow that turns up when the list is open
    center: ui.Vec2 = {info.rect.x + info.rect.z - info.rect.w * 0.5, info.rect.y + info.rect.w * 0.5}
    size: f32 = info.rect.w * 0.16
    points: [3]ui.Vec2 = {{center.x - size, center.y - size * 0.5}, {center.x + size, center.y - size * 0.5}, {center.x, center.y + size}}
    if .OPEN in info.flags {
        points = {{center.x - size, center.y + size * 0.5}, {center.x, center.y - size}, {center.x + size, center.y + size * 0.5}}
    }
    if painter.fill_polygon != nil {
        painter.fill_polygon(painter, points[:], theme.text)
    }
}

DrawDropdownItem :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    if .SELECTED in info.flags {
        FillRounded(painter, info.rect, theme.rounding * 0.6, ui.ColorLerp(theme.control, theme.accent, 0.6), theme.max_radius)
    } else if info.hover > 0.01 {
        FillRounded(painter, info.rect, theme.rounding * 0.6, ui.ColorLerp(theme.panel, theme.control_hover, info.hover), theme.max_radius)
    }
    TextLeft(painter, info.name, info.rect, info.font_size, ctx.style.metrics.padding.x, theme.text)
}

DrawScrollbar :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    track: ui.Rect = ui.RectShrink(info.rect, 1)
    thumb_height: f32 = max(track.w * info.ratio, track.z * 2)
    thumb: ui.Rect = {track.x, track.y + (track.w - thumb_height) * info.value, track.z, thumb_height}
    FillRounded(painter, track, 1, ui.Color{theme.track.r, theme.track.g, theme.track.b, 140})
    FillRounded(painter, thumb, 1, theme.text_dim)
}
