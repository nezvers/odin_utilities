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
    danger: ui.Color,               // controls with the tag "danger"
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
    danger = {190, 60, 60, 255},
    rounding = 0.3,
    panel_rounding = 0.08,
    max_radius = 12,
    border_width = 1,
}

Painter :: struct {
    user: rawptr,                   // the glue's own data (the kit.Context of the frame, a font...)
    theme: Theme,
    scale: f32,                     // UI scale (0 is 1): the layout and the styles work in logical units, the glue multiplies what it draws by this and divides the pointer by it
    offset: ui.Vec2,              // where the logical origin is on the screen: a zoomed container moves it (Style.zoom); the glue draws a point p at p * scale + offset
    saved_scale: f32,               // what a zoomed container found, put back when it ends
    saved_offset: ui.Vec2,
    fill_rect: proc(painter: ^Painter, rect: ui.Rect, color: ui.Color),
    fill_polygon: proc(painter: ^Painter, points: []ui.Vec2, color: ui.Color),                  // convex, nil: no polygons (arrows and rounded corners fall back)
    fill_rounded: proc(painter: ^Painter, rect: ui.Rect, radius: f32, color: ui.Color),         // nil: made from fill_polygon
    draw_text: proc(painter: ^Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color),
    measure_text: proc(painter: ^Painter, text: string, size: f32) -> ui.Vec2,
    clip: proc(painter: ^Painter, rect: ui.Rect, begin: bool),
}

// The scale of a painter, 1 when it was left at 0. For the glue: every coordinate and size that goes to the framework is multiplied by it, the size of a measured
// text is divided (text is measured at the size it is drawn at, so the layout gets the logical size of the pixels that are drawn).
PainterScale :: proc(painter: ^Painter) -> f32 {
    return painter.scale if painter.scale > 0 else 1
}

// What the glue draws: a rectangle or a point of the logical space on the screen (scale, then offset). Sizes (a radius, a text size) are only multiplied by PainterScale.
PaintRect :: proc(painter: ^Painter, rect: ui.Rect) -> ui.Rect {
    scale: f32 = PainterScale(painter)
    return {rect.x * scale + painter.offset.x, rect.y * scale + painter.offset.y, rect.z * scale, rect.w * scale}
}

PaintPoint :: proc(painter: ^Painter, point: ui.Vec2) -> ui.Vec2 {
    return point * PainterScale(painter) + painter.offset
}

// Style.zoom: a zoomed container starts, everything in it is scaled by `factor` around `origin` (so a point p of its logical space is shown at origin + (p - origin) * factor,
// then through the transform that was in force); at its end the painter is as it was. Does not nest (the layout does not zoom a zoomed container again).
Zoom :: proc(ctx: ^ui.Context, origin: ui.Vec2, factor: f32, begin: bool) {
    painter: ^Painter = painterOf(ctx)
    if begin {
        painter.saved_scale, painter.saved_offset = painter.scale, painter.offset
        scale: f32 = PainterScale(painter)
        painter.offset = painter.offset + origin * scale * (1 - factor)
        painter.scale = scale * factor
    } else {
        painter.scale, painter.offset = painter.saved_scale, painter.saved_offset
    }
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
        zoom = Zoom,
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
    style.procs[.COLLAPSING] = DrawCollapsing
    style.procs[.RADIO] = DrawRadio
    style.procs[.SELECTABLE] = DrawSelectable
    style.procs[.TAB] = DrawTab
    style.procs[.DRAG] = DrawDrag
    style.procs[.ARROW] = DrawArrow
    style.procs[.PLOT] = DrawPlot
    style.procs[.SWATCH] = DrawSwatch
    style.procs[.MENU_BAR] = DrawMenuBar
    style.procs[.MENU] = DrawMenu
    style.procs[.MENU_ITEM] = DrawMenuItem
    style.procs[.WINDOW_TITLE] = DrawWindowTitle
    style.procs[.SPLITTER] = DrawSplitter
    style.procs[.RESIZE_GRIP] = DrawResizeGrip
    style.procs[.BULLET] = DrawBullet
    style.procs[.SEPARATOR_TEXT] = DrawSeparatorText
    style.procs[.BACKDROP] = DrawBackdrop
    style.procs[.TEXT_AREA] = DrawTextArea
    style.procs[.HIGHLIGHT] = DrawHighlight
    style.procs[.TEXT_SELECTION] = DrawTextSelection
    style.procs[.TEXT_CARET] = DrawTextCaret
    GraphStyleInstall(&style)
    AudioStyleInstall(&style)
    TimelineStyleInstall(&style)
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

// The ring of the widget that has the focus (keyboard, gamepad, navigation): drawn behind the control, two pixels wider than it
FocusRing :: proc(painter: ^Painter, info: ^ui.DrawInfo, rounding: f32 = -1) {
    if .FOCUSED not_in info.flags { return }
    theme: ^Theme = &painter.theme
    FillRounded(painter, {info.rect.x - 2, info.rect.y - 2, info.rect.z + 4, info.rect.w + 4}, theme.rounding if rounding < 0 else rounding, theme.accent, theme.max_radius + 2)
}

// A straight line of a thickness, as a quad
Line :: proc(painter: ^Painter, from: ui.Vec2, to: ui.Vec2, thickness: f32, color: ui.Color) {
    delta: ui.Vec2 = to - from
    length: f32 = math.sqrt(delta.x * delta.x + delta.y * delta.y)
    if length < 0.001 { return }
    side: ui.Vec2 = {-delta.y, delta.x} * (thickness * 0.5 / length)
    if painter.fill_polygon == nil {
        painter.fill_rect(painter, {min(from.x, to.x), min(from.y, to.y), max(abs(delta.x), thickness), max(abs(delta.y), thickness)}, color)
        return
    }
    points: [4]ui.Vec2 = {from + side, to + side, to - side, from - side}
    painter.fill_polygon(painter, points[:], color)
}

// A triangle that points `direction` (0 up, 1 down, 2 left, 3 right) in a square of `size` around `center`
ArrowShape :: proc(painter: ^Painter, center: ui.Vec2, size: f32, direction: int, color: ui.Color) {
    if painter.fill_polygon == nil { return }
    h: f32 = size * 0.5
    points: [3]ui.Vec2
    switch direction {
    case 0: points = {{center.x - h, center.y + h * 0.6}, {center.x, center.y - h * 0.8}, {center.x + h, center.y + h * 0.6}}
    case 1: points = {{center.x - h, center.y - h * 0.6}, {center.x + h, center.y - h * 0.6}, {center.x, center.y + h * 0.8}}
    case 2: points = {{center.x + h * 0.6, center.y - h}, {center.x - h * 0.8, center.y}, {center.x + h * 0.6, center.y + h}}
    case: points = {{center.x - h * 0.6, center.y - h}, {center.x + h * 0.8, center.y}, {center.x - h * 0.6, center.y + h}}
    }
    painter.fill_polygon(painter, points[:], color)
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
    base: ui.Color = theme.control
    hover: ui.Color = theme.control_hover
    // tags: "danger" and "primary" controls are tinted, the states are the same
    if ui.DrawInfoHasTag(info, "danger") {
        base, hover = ui.ColorLerp(theme.control, theme.danger, 0.55), ui.ColorLerp(theme.control_hover, theme.danger, 0.8)
    } else if ui.DrawInfoHasTag(info, "primary") {
        base, hover = ui.ColorLerp(theme.control, theme.accent, 0.55), ui.ColorLerp(theme.control_hover, theme.accent, 0.8)
    }
    color: ui.Color = ui.ColorLerp(base, hover, info.hover)
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
    color: ui.Color = info.color if info.color.a > 0 else painter.theme.text
    painter.draw_text(painter, info.text, {info.rect.x, info.rect.y}, info.font_size, color)
}

DrawButton :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = theme.control if .DISABLED in info.flags else ControlColor(theme, info)
    FocusRing(painter, info)
    FillRounded(painter, info.rect, theme.rounding, color, theme.max_radius)
    TextCentered(painter, info.name, info.rect, info.font_size, textColor(theme, info))
}

DrawToggle :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    box: ui.Rect = {info.rect.x, info.rect.y, info.rect.w, info.rect.w}
    on: bool = .ON in info.flags
    FocusRing(painter, &{rect = box, flags = info.flags})
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
    FocusRing(painter, info)
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
    // the selection under the text
    if focused && info.anchor != info.cursor {
        low: int = clamp(min(info.anchor, info.cursor), 0, len(info.text))
        high: int = clamp(max(info.anchor, info.cursor), 0, len(info.text))
        start: f32 = painter.measure_text(painter, info.text[:low], info.font_size).x
        finish: f32 = painter.measure_text(painter, info.text[:high], info.font_size).x
        highlight: ui.Color = {theme.accent.r, theme.accent.g, theme.accent.b, 130}
        painter.fill_rect(painter, {info.rect.x + padding + start, info.rect.y + 4, finish - start, info.rect.w - 8}, highlight)
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
    FocusRing(painter, info)
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
    if .FOCUSED in info.flags {
        // the focused option: a frame in the accent color, drawn inside of the row so the list does not overlap itself
        FillRounded(painter, info.rect, theme.rounding * 0.6, theme.accent, theme.max_radius)
        FillRounded(painter, ui.RectShrink(info.rect, 2), theme.rounding * 0.5, ui.ColorLerp(theme.control, theme.accent, 0.35) if .SELECTED in info.flags else theme.control_hover, theme.max_radius)
    } else if .SELECTED in info.flags {
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

// ------------------------------------------------------------------------------------------------------------------------
// The kinds of widgets_more.odin

DrawCollapsing :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    open: bool = .OPEN in info.flags
    tree: bool = info.actual == 1
    FocusRing(painter, info)
    if tree {
        if info.hover > 0.01 { FillRounded(painter, info.rect, theme.rounding * 0.6, ui.ColorLerp(theme.panel, theme.control_hover, info.hover * 0.6), theme.max_radius) }
    } else {
        FillRounded(painter, info.rect, theme.rounding * 0.6, ui.ColorLerp(ui.ColorLerp(theme.control, theme.accent, 0.25), theme.control_hover, info.hover), theme.max_radius)
    }
    ArrowShape(painter, {info.rect.x + 14, info.rect.y + info.rect.w * 0.5}, info.rect.w * 0.3, 1 if open else 3, theme.text)
    TextLeft(painter, info.name, info.rect, info.font_size, 28, theme.text)
}

DrawRadio :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    box: ui.Rect = {info.rect.x, info.rect.y, info.rect.w, info.rect.w}
    FocusRing(painter, &{rect = box, flags = info.flags}, 1)
    FillRoundedBorder(painter, box, 1, ControlColor(theme, info), theme.border, theme.border_width)
    if .ON in info.flags { FillRounded(painter, ui.RectShrink(box, box.z * 0.3), 1, theme.accent) }
    TextLeft(painter, info.name, {info.rect.x + box.z, info.rect.y, info.rect.z - box.z, info.rect.w}, info.font_size, 8, textColor(theme, info))
}

DrawSelectable :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    if .FOCUSED in info.flags { FillRounded(painter, info.rect, theme.rounding * 0.4, theme.accent, theme.max_radius) }
    inner: ui.Rect = ui.RectShrink(info.rect, 2 if .FOCUSED in info.flags else 0)
    if .SELECTED in info.flags {
        FillRounded(painter, inner, theme.rounding * 0.4, ui.ColorLerp(theme.control, theme.accent, 0.55), theme.max_radius)
    } else if info.hover > 0.01 {
        FillRounded(painter, inner, theme.rounding * 0.4, ui.ColorLerp(theme.panel, theme.control_hover, info.hover), theme.max_radius)
    }
    TextLeft(painter, info.name, info.rect, info.font_size, 8, textColor(theme, info))
}

DrawTab :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    selected: bool = .SELECTED in info.flags
    FocusRing(painter, info, 0.2)
    FillRounded(painter, info.rect, theme.rounding * 0.5, ui.ColorLerp(theme.control, theme.control_hover, info.hover) if !selected else ui.ColorLerp(theme.control_hover, theme.accent, 0.5), theme.max_radius)
    TextCentered(painter, info.name, info.rect, info.font_size, theme.text if selected else theme.text_dim)
}

DrawDrag :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FocusRing(painter, info, theme.rounding * 0.6)
    FillRoundedBorder(painter, info.rect, theme.rounding * 0.6, ui.ColorLerp(theme.control, theme.control_hover, max(info.hover, info.press)), theme.border, theme.border_width, theme.max_radius)
    TextCentered(painter, info.text, info.rect, info.font_size, textColor(theme, info))
}

DrawArrow :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FocusRing(painter, info)
    FillRounded(painter, info.rect, theme.rounding, ControlColor(theme, info), theme.max_radius)
    ArrowShape(painter, ui.RectCenter(info.rect), info.rect.w * 0.35, int(info.actual), theme.text)
}

DrawPlot :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FillRoundedBorder(painter, info.rect, theme.rounding * 0.4, theme.track, theme.border, theme.border_width, theme.max_radius)
    inner: ui.Rect = ui.RectShrink(info.rect, 3)
    count: int = len(info.values)
    range: f32 = max(info.maximum - info.minimum, 0.000001)
    if count > 0 {
        if info.actual == 1 {
            // a histogram: a bar per number
            width: f32 = inner.z / f32(count)
            for value, i in info.values {
                height: f32 = clamp((value - info.minimum) / range, 0, 1) * inner.w
                painter.fill_rect(painter, {inner.x + f32(i) * width + 0.5, inner.y + inner.w - height, max(width - 1, 1), height}, theme.accent)
            }
        } else if count > 1 {
            previous: ui.Vec2
            for value, i in info.values {
                point: ui.Vec2 = {inner.x + f32(i) / f32(count - 1) * inner.z, inner.y + inner.w - clamp((value - info.minimum) / range, 0, 1) * inner.w}
                if i > 0 { Line(painter, previous, point, 1.5, theme.accent) }
                previous = point
            }
        }
    }
    if info.text != "" {
        TextCentered(painter, info.text, {info.rect.x, info.rect.y + 2, info.rect.z, info.font_size + 4}, info.font_size, theme.text_dim)
    }
}

DrawSwatch :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FocusRing(painter, info)
    FillRoundedBorder(painter, info.rect, theme.rounding * 0.5, info.color, ui.ColorLerp(theme.border, theme.text, info.hover), max(theme.border_width, 1), theme.max_radius)
}

DrawMenuBar :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    painter.fill_rect(painter, info.rect, ui.ColorLerp(painter.theme.panel, painter.theme.control, 0.5))
}

DrawMenu :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    lit: f32 = 1 if .OPEN in info.flags else info.hover
    FocusRing(painter, info, 0.2)
    if lit > 0.01 { FillRounded(painter, info.rect, theme.rounding * 0.5, ui.ColorLerp(theme.panel, theme.control_hover, lit), theme.max_radius) }
    if info.actual == 1 {
        TextLeft(painter, info.name, info.rect, info.font_size, 8, textColor(theme, info))
        ArrowShape(painter, {info.rect.x + info.rect.z - 12, info.rect.y + info.rect.w * 0.5}, info.rect.w * 0.3, 3, theme.text_dim)
    } else {
        TextCentered(painter, info.name, info.rect, info.font_size, textColor(theme, info))
    }
}

DrawMenuItem :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    if .FOCUSED in info.flags { FillRounded(painter, info.rect, theme.rounding * 0.4, theme.accent, theme.max_radius) }
    inner: ui.Rect = ui.RectShrink(info.rect, 2 if .FOCUSED in info.flags else 0)
    if info.hover > 0.01 || .FOCUSED in info.flags { FillRounded(painter, inner, theme.rounding * 0.4, ui.ColorLerp(theme.panel, theme.control_hover, max(info.hover, 0.6 if .FOCUSED in info.flags else 0)), theme.max_radius) }
    if .ON in info.flags {
        // a check mark: two strokes
        c: ui.Vec2 = {info.rect.x + 12, info.rect.y + info.rect.w * 0.5}
        Line(painter, c + {-4, 0}, c + {-1, 3.5}, 2, theme.accent)
        Line(painter, c + {-1, 3.5}, c + {5, -4}, 2, theme.accent)
    }
    TextLeft(painter, info.name, info.rect, info.font_size, 26, textColor(theme, info))
    if info.text != "" { TextRight(painter, info.text, info.rect, info.font_size, 10, theme.text_dim) }
}

DrawWindowTitle :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = ui.ColorLerp(theme.control, theme.accent, 0.55 if .FOCUSED in info.flags else 0.3)
    FillRounded(painter, info.rect, theme.panel_rounding, color, theme.max_radius)
    TextLeft(painter, info.name, info.rect, info.font_size, 10, theme.text)
}

// The handle between two sections: a thin line in the middle of its rectangle that lights up under the pointer and while it is dragged
DrawSplitter :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    strength: f32 = max(info.hover, info.press)
    if .PRESSED in info.flags { strength = 1 }
    color: ui.Color = ui.ColorLerp(theme.border, theme.accent, strength)
    line: f32 = 2 if strength > 0.05 else 1
    rect: ui.Rect = info.rect
    if info.actual == 0 {
        painter.fill_rect(painter, {rect.x + (rect.z - line) * 0.5, rect.y, line, rect.w}, color)
    } else {
        painter.fill_rect(painter, {rect.x, rect.y + (rect.w - line) * 0.5, rect.z, line}, color)
    }
    if .FOCUSED in info.flags {
        painter.fill_rect(painter, {rect.x, rect.y, rect.z, 1}, theme.accent)
    }
}

// Three rows of small squares in the corner, the usual sign that a window can be resized
DrawResizeGrip :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = ui.ColorLerp(theme.text_dim, theme.accent, max(info.hover, info.press))
    if .PRESSED in info.flags { color = theme.accent }
    corner: ui.Vec2 = {info.rect.x + info.rect.z - 3, info.rect.y + info.rect.w - 3}
    for row in 0 ..< 3 {
        for column in 0 ..< 3 - row {
            painter.fill_rect(painter, {corner.x - f32(column) * 4 - 2, corner.y - f32(row) * 4 - 2, 2, 2}, color)
        }
    }
}

DrawBullet :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    size: f32 = min(info.rect.z, info.rect.w) * 0.45
    center: ui.Vec2 = ui.RectCenter(info.rect)
    FillRounded(painter, {center.x - size * 0.5, center.y - size * 0.5, size, size}, 1, painter.theme.text_dim)
}

DrawSeparatorText :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    measured: ui.Vec2 = painter.measure_text(painter, info.name, info.font_size)
    y: f32 = info.rect.y + info.rect.w * 0.5
    painter.fill_rect(painter, {info.rect.x, y, 14, 1}, theme.border)
    painter.draw_text(painter, info.name, {info.rect.x + 22, info.rect.y + (info.rect.w - measured.y) * 0.5}, info.font_size, theme.text_dim)
    after: f32 = info.rect.x + 30 + measured.x
    painter.fill_rect(painter, {after, y, max(info.rect.x + info.rect.z - after, 0), 1}, theme.border)
}

DrawBackdrop :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    painter.fill_rect(painter, info.rect, {0, 0, 0, 130})
}

// The box of a text area: like a text field, with the name shown while it is empty. Its lines, selection and caret are elements of their own.
DrawTextArea :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    focused: bool = .FOCUSED in info.flags
    FillRoundedBorder(painter, info.rect, theme.rounding * 0.6, theme.track, theme.accent if focused else theme.border, theme.border_width, theme.max_radius)
    if info.text == "" && !focused {
        metrics: ^ui.Metrics = &ctx.style.metrics
        painter.draw_text(painter, info.name, {info.rect.x + metrics.padding.x, info.rect.y + metrics.padding.y}, info.font_size, theme.text_dim)
    }
}

DrawTextSelection :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    accent: ui.Color = painter.theme.accent
    painter.fill_rect(painter, info.rect, {accent.r, accent.g, accent.b, 130})
}

// The caret blinks twice a second
DrawTextCaret :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    if math.mod(ctx.time, 1.0) < 0.5 {
        painter.fill_rect(painter, info.rect, painter.theme.text)
    }
}

DrawHighlight :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    color: ui.Color = info.color
    rect: ui.Rect = info.rect
    painter.fill_rect(painter, rect, {color.r, color.g, color.b, 50})
    painter.fill_rect(painter, {rect.x, rect.y, rect.z, 2}, color)
    painter.fill_rect(painter, {rect.x, rect.y + rect.w - 2, rect.z, 2}, color)
    painter.fill_rect(painter, {rect.x, rect.y, 2, rect.w}, color)
    painter.fill_rect(painter, {rect.x + rect.z - 2, rect.y, 2, rect.w}, color)
}
