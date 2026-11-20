package ui_default

// The default style of the ui library, and the Painter it draws with. The style procs are ordinary StyleProcs: copy this file as the start
// of a style of your own, or replace single entries of the table (`style.procs[.BUTTON] = MyButton`).
//
// A Painter is what a style needs from a framework: filled rectangles and polygons, text in a few faces, its measure, icons, and the scissor.
// The glue packages (ui/kit, ui/glue_raylib, ui/glue_karl2d) fill one in. The painter is found through `ctx.user`.
//
//     painter: ui_default.Painter
//     ui_raylib.PainterInit(&painter)
//     ui.UiInit(&ctx, &storage, ui_default.Measure, &painter)
//     style := ui_default.StyleMake()
//
// The look follows Baldr (https://github.com/BuLEEto/Baldr, by Lee Fry and the Baldr contributors, zlib License): the colors of THEME_DARK and
// THEME_LIGHT are the roles of its themes for its blue accent (surfaces in steps of lightness, an accent as a fill and as a soft fill, state
// washes of 8 and 14 percent), the corners are its radii (8 for a control, 12 for a card), the text is Inter with the labels of controls in
// semibold, the icons are Lucide. Nothing of its code is here: the numbers were taken from its theme generator and its pictures.
//
// Rounded corners are a part of the shortest side (ui.RoundedRadius): `rounding = 1` is the full round, limited to `max_radius` pixels. A
// painter that can draw a rounded rectangle itself sets `fill_rounded`, the others get a triangle fan from the points of ui.RoundedPoints.
//
// Tags a button understands (ui.UiTagged): "primary" (the accent), "secondary" (the soft accent), "outline" (a border, no fill), "ghost" (only
// the label, in the accent), "danger". A slider or a progress bar with the tag "thin" is a line with a round handle and no text.

import "core:math"
import ui ".."
import icons "../../icons"

Theme :: struct {
    dark: bool,
    background: ui.Color,           // the window, behind the panels
    panel: ui.Color,                // cards, windows
    surface_high: ui.Color,         // what lies above a panel: popups, menus, tooltips, the chosen segment
    border: ui.Color,               // the outline of controls
    border_soft: ui.Color,          // the outline of panels, dividers
    text: ui.Color,
    text_dim: ui.Color,             // placeholders, secondary text
    control: ui.Color,              // a button without a tag
    control_hover: ui.Color,
    control_pressed: ui.Color,
    track: ui.Color,                // wells: text fields, the empty part of progress bars, table headers
    track_strong: ui.Color,         // the line of a thin slider, a switch that is off
    accent: ui.Color,               // what is on, filled, selected
    accent_text: ui.Color,          // text and icons on the accent
    accent_soft: ui.Color,          // the accent as a quiet fill: secondary buttons, chosen chips, the fill of a slider
    accent_soft_text: ui.Color,
    focus: ui.Color,                // the ring of the control that has the keyboard
    danger: ui.Color,               // controls with the tag "danger"
    danger_text: ui.Color,
    warning: ui.Color,
    success: ui.Color,
    shadow: ui.Color,               // under panels and popups (its alpha is the strength: a light theme needs it, a dark one separates by lightness)
    scrim: ui.Color,                // what dims the screen behind a dialog
    hover: f32,                     // how much of the text color is mixed into a control under the pointer
    press: f32,                     // and while it is pressed
    rounding: f32,                  // controls: 0 sharp .. 1 full round
    panel_rounding: f32,
    max_radius: f32,                // pixels, 0: no limit
    panel_max_radius: f32,
    border_width: f32,
}

THEME_DARK :: Theme{
    dark = true,
    background = {17, 19, 21, 255},
    panel = {26, 28, 31, 255},
    surface_high = {48, 50, 53, 255},
    border = {61, 64, 69, 255},
    border_soft = {43, 46, 50, 255},
    text = {220, 222, 226, 255},
    text_dim = {156, 158, 162, 255},
    control = {42, 49, 59, 255},
    control_hover = {56, 63, 72, 255},
    control_pressed = {67, 74, 83, 255},
    track = {35, 37, 40, 255},
    track_strong = {61, 64, 69, 255},
    accent = {121, 171, 252, 255},
    accent_text = {7, 17, 35, 255},
    accent_soft = {31, 60, 108, 255},
    accent_soft_text = {220, 233, 253, 255},
    focus = {157, 191, 246, 255},
    danger = {239, 102, 97, 255},
    danger_text = {28, 2, 2, 255},
    warning = {239, 168, 49, 255},
    success = {98, 195, 122, 255},
    shadow = {0, 0, 0, 110},
    scrim = {0, 0, 0, 128},
    hover = 0.08,
    press = 0.14,
    rounding = 1,
    panel_rounding = 1,
    max_radius = 8,
    panel_max_radius = 12,
    border_width = 1,
}

THEME_LIGHT :: Theme{
    dark = false,
    background = {233, 235, 238, 255},
    panel = {251, 252, 253, 255},
    surface_high = {255, 255, 255, 255},
    border = {195, 200, 207, 255},
    border_soft = {217, 222, 230, 255},
    text = {32, 34, 37, 255},
    text_dim = {97, 99, 103, 255},
    control = {224, 229, 237, 255},
    control_hover = {208, 213, 221, 255},
    control_pressed = {197, 201, 209, 255},
    track = {241, 244, 248, 255},
    track_strong = {195, 200, 207, 255},
    accent = {38, 110, 225, 255},
    accent_text = {250, 252, 255, 255},
    accent_soft = {215, 230, 253, 255},
    accent_soft_text = {11, 52, 116, 255},
    focus = {38, 110, 225, 255},
    danger = {212, 47, 52, 255},
    danger_text = {255, 251, 250, 255},
    warning = {197, 130, 21, 255},
    success = {19, 153, 72, 255},
    shadow = {0, 0, 0, 70},
    scrim = {0, 0, 0, 89},
    hover = 0.08,
    press = 0.14,
    rounding = 1,
    panel_rounding = 1,
    max_radius = 8,
    panel_max_radius = 12,
    border_width = 1,
}

// The faces a style draws text in. A glue that has one font draws them all in it.
Face :: enum u8 {
    REGULAR,            // values, body text, fields
    STRONG,             // the labels of controls, titles (Inter SemiBold)
    ITALIC,
    MONO,               // code, numbers that line up
}

// The first number of the Lucide icons among the icons of the ui (ui.Icon): LucideIcon(.SAVE) is an icon for ui.UiIcon, a button, a tree node
LUCIDE_FIRST :: 0x1000

LucideIcon :: proc "contextless" (icon: icons.Icon) -> ui.Icon {
    return cast(ui.Icon)(LUCIDE_FIRST + u16(icon))
}

// The Lucide icon of an icon of the ui: the few the library itself names (a folder, a file...) and the ones made with LucideIcon. NONE for an icon of the program.
IconToLucide :: proc "contextless" (icon: ui.Icon) -> icons.Icon {
    number: u16 = u16(icon)
    if number > LUCIDE_FIRST && int(number - LUCIDE_FIRST) < len(icons.Icon) { return cast(icons.Icon)(number - LUCIDE_FIRST) }
    #partial switch icon {
    case .FOLDER:
        return .FOLDER
    case .FOLDER_OPEN:
        return .FOLDER_OPEN
    case .FILE:
        return .FILE
    case .TEXT:
        return .FILE_TEXT
    case .IMAGE:
        return .FILE_IMAGE
    case .AUDIO:
        return .FILE_MUSIC
    case .CLOSE:
        return .X
    case .CHECK:
        return .CHECK
    case .SEARCH:
        return .SEARCH
    case .CHEVRON_UP:
        return .CHEVRON_UP
    case .CHEVRON_DOWN:
        return .CHEVRON_DOWN
    case .CHEVRON_LEFT:
        return .CHEVRON_LEFT
    case .CHEVRON_RIGHT:
        return .CHEVRON_RIGHT
    }
    return .NONE
}

Painter :: struct {
    user: rawptr,                   // the glue's own data (the kit.Context of the frame, a font...)
    flush: proc(painter: ^Painter),  // draws what the painter has collected (the text of the font library is batched: every draw of a shape calls PainterFlush first, so the order stays right); nil: nothing is collected
    vector_text: rawptr,            // the glue's text system when the text is drawn from outlines by the font library (the glue's PainterUseVectorText sets it and the text procs)
    theme: Theme,
    scale: f32,                     // UI scale (0 is 1): the layout and the styles work in logical units, the glue multiplies what it draws by this and divides the pointer by it
    offset: ui.Vec2,              // where the logical origin is on the screen: a zoomed container moves it (Style.zoom); the glue draws a point p at p * scale + offset
    saved_scale: f32,               // what a zoomed container found, put back when it ends
    saved_offset: ui.Vec2,
    face: Face,                     // the face draw_text and measure_text use: a style sets it before a text and puts REGULAR back (the Text... helpers do)
    glue_fonts: [Face]u32,          // for the glue: its fonts by face (0: the face is drawn in the regular one)
    glue_icon_font: u32,            // for the glue: its icon font
    glue_ready: bool,               // for the glue: the fonts were loaded
    fonts: rawptr,                  // for the glue: its set of fonts (the glue's Fonts and PainterUseFonts)
    vector_faces: [Face]u8,         // for the glue: the face of the text system each face of the style is drawn in, when the text is drawn from outlines
    vector_icon_face: u8,           // and the face the icon font is (0: no icons)
    fill_rect: proc(painter: ^Painter, rect: ui.Rect, color: ui.Color),
    fill_polygon: proc(painter: ^Painter, points: []ui.Vec2, color: ui.Color),                  // convex, nil: no polygons (arrows and rounded corners fall back)
    fill_rounded: proc(painter: ^Painter, rect: ui.Rect, radius: f32, color: ui.Color),         // nil: made from fill_polygon
    draw_text: proc(painter: ^Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color),
    measure_text: proc(painter: ^Painter, text: string, size: f32) -> ui.Vec2,
    draw_icon: proc(painter: ^Painter, icon: icons.Icon, rect: ui.Rect, color: ui.Color),      // a Lucide icon in a square; nil: the style draws what it can with rectangles and triangles
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

// Draws what the painter collected so far (a glue's text batch). A glue calls it first in every proc that draws something else.
PainterFlush :: proc(painter: ^Painter) {
    if painter.flush != nil { painter.flush(painter) }
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
        render_end = proc(ctx: ^ui.Context) { PainterFlush(painterOf(ctx)) },
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
    style.procs[.ICON] = DrawIcon
    style.procs[.TEXT_SELECTION] = DrawTextSelection
    style.procs[.TEXT_CARET] = DrawTextCaret
    GraphStyleInstall(&style)
    AudioStyleInstall(&style)
    ColorStyleInstall(&style)
    TimelineStyleInstall(&style)
    ExtraStyleInstall(&style)
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

// A soft shadow under a rectangle with round corners: a few wider and fainter copies of it, a little lower. `strength` scales the alpha of theme.shadow.
Shadow :: proc(painter: ^Painter, rect: ui.Rect, radius: f32, strength: f32 = 1) {
    shadow: ui.Color = painter.theme.shadow
    if shadow.a == 0 || strength <= 0 { return }
    LAYERS :: 4
    for layer := LAYERS; layer >= 1; layer -= 1 {
        grow: f32 = f32(layer) * 1.5
        alpha: f32 = f32(shadow.a) * strength * 0.11 * f32(LAYERS + 1 - layer) / LAYERS
        box: ui.Rect = {rect.x - grow, rect.y - grow + f32(layer) * 0.75 + 0.5, rect.z + grow * 2, rect.w + grow * 2}
        half: f32 = min(box.z, box.w) * 0.5
        FillRounded(painter, box, (radius + grow) / max(half, 0.001), {shadow.r, shadow.g, shadow.b, u8(clamp(alpha, 0, 255))})
    }
}

// The outline of a rounded rectangle, `width` wide, inside of `rect`: a band of quads between the points of the outer and of the inner corners, so what is under it shows
// through its middle (a painter without polygons gets four bars)
RingRounded :: proc(painter: ^Painter, rect: ui.Rect, radius: f32, width: f32, color: ui.Color) {
    if color.a == 0 || width <= 0 || rect.z <= 0 || rect.w <= 0 { return }
    if painter.fill_polygon == nil || radius <= 0.5 {
        painter.fill_rect(painter, {rect.x, rect.y, rect.z, width}, color)
        painter.fill_rect(painter, {rect.x, rect.y + rect.w - width, rect.z, width}, color)
        painter.fill_rect(painter, {rect.x, rect.y + width, width, rect.w - 2 * width}, color)
        painter.fill_rect(painter, {rect.x + rect.z - width, rect.y + width, width, rect.w - 2 * width}, color)
        return
    }
    outer_radius: f32 = min(radius, min(rect.z, rect.w) * 0.5)
    inner_radius: f32 = max(outer_radius - width, 0.01)
    segments: int = ui.RoundedSegments(outer_radius)
    outer_buffer, inner_buffer: ui.RoundedBuffer
    outer: []ui.Vec2 = ui.RoundedPoints(rect, {outer_radius, outer_radius, outer_radius, outer_radius}, segments, outer_buffer[:])
    inner: []ui.Vec2 = ui.RoundedPoints(ui.RectShrink(rect, width), {inner_radius, inner_radius, inner_radius, inner_radius}, segments, inner_buffer[:])
    count: int = min(len(outer), len(inner))
    for i in 0 ..< count {
        next: int = (i + 1) % count
        quad: [4]ui.Vec2 = {outer[i], outer[next], inner[next], inner[i]}
        painter.fill_polygon(painter, quad[:], color)
    }
}

// The ring of the widget that has the focus (keyboard, gamepad, navigation): an outline around the control, two pixels wide and outside of it
FocusRing :: proc(painter: ^Painter, info: ^ui.DrawInfo, rounding: f32 = -1) {
    if .FOCUSED not_in info.flags { return }
    theme: ^Theme = &painter.theme
    ring: ui.Rect = {info.rect.x - 2, info.rect.y - 2, info.rect.z + 4, info.rect.w + 4}
    RingRounded(painter, ring, ui.RoundedRadius(ring, theme.rounding if rounding < 0 else rounding, theme.max_radius + 2), 2, theme.focus)
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

// A Lucide icon in a square of `size` around `center`. A painter without icons gets nothing (IconOrArrow has a fallback for the arrows).
IconAt :: proc(painter: ^Painter, icon: icons.Icon, center: ui.Vec2, size: f32, color: ui.Color) {
    if painter.draw_icon == nil || icon == .NONE || color.a == 0 { return }
    painter.draw_icon(painter, icon, {center.x - size * 0.5, center.y - size * 0.5, size, size}, color)
}

// A chevron that points `direction` (0 up, 1 down, 2 left, 3 right): the icon, or a triangle when the painter has no icons
Chevron :: proc(painter: ^Painter, center: ui.Vec2, size: f32, direction: int, color: ui.Color) {
    if painter.draw_icon == nil {
        ArrowShape(painter, center, size * 0.55, direction, color)
        return
    }
    chevrons: [4]icons.Icon = {.CHEVRON_UP, .CHEVRON_DOWN, .CHEVRON_LEFT, .CHEVRON_RIGHT}
    IconAt(painter, chevrons[clamp(direction, 0, 3)], center, size, color)
}

// A text with its center at the center of the rect
TextCentered :: proc(painter: ^Painter, text: string, rect: ui.Rect, size: f32, color: ui.Color, face: Face = .REGULAR) {
    painter.face = face
    measured: ui.Vec2 = painter.measure_text(painter, text, size)
    painter.draw_text(painter, text, {rect.x + (rect.z - measured.x) * 0.5, rect.y + (rect.w - measured.y) * 0.5}, size, color)
    painter.face = .REGULAR
}

// A text on the left of the rect (`padding` from the edge), centered up and down
TextLeft :: proc(painter: ^Painter, text: string, rect: ui.Rect, size: f32, padding: f32, color: ui.Color, face: Face = .REGULAR) {
    painter.face = face
    measured: ui.Vec2 = painter.measure_text(painter, text, size)
    painter.draw_text(painter, text, {rect.x + padding, rect.y + (rect.w - measured.y) * 0.5}, size, color)
    painter.face = .REGULAR
}

TextRight :: proc(painter: ^Painter, text: string, rect: ui.Rect, size: f32, padding: f32, color: ui.Color, face: Face = .REGULAR) {
    painter.face = face
    measured: ui.Vec2 = painter.measure_text(painter, text, size)
    painter.draw_text(painter, text, {rect.x + rect.z - measured.x - padding, rect.y + (rect.w - measured.y) * 0.5}, size, color)
    painter.face = .REGULAR
}

// The width of a text in a face
TextWidth :: proc(painter: ^Painter, text: string, size: f32, face: Face = .REGULAR) -> f32 {
    painter.face = face
    width: f32 = painter.measure_text(painter, text, size).x
    painter.face = .REGULAR
    return width
}

// A color under the pointer and under a press: a little of `ink` (what is drawn on it) is mixed in, as the theme says
StateColor :: proc(theme: ^Theme, base: ui.Color, ink: ui.Color, info: ^ui.DrawInfo) -> ui.Color {
    amount: f32 = clamp(info.hover * theme.hover + info.press * (theme.press - theme.hover), 0, 1)
    mixed: ui.Color = ui.ColorLerp(base, ink, amount)
    mixed.a = base.a
    return mixed
}

// A wash of the text color for something that has no fill of its own (a row, a ghost button): nothing at rest, a faint fill under the pointer
StateWash :: proc(theme: ^Theme, ink: ui.Color, info: ^ui.DrawInfo, rest: f32 = 0) -> ui.Color {
    amount: f32 = clamp(rest + info.hover * theme.hover + info.press * (theme.press - theme.hover), 0, 1)
    return {ink.r, ink.g, ink.b, u8(amount * 255)}
}

// A color of something that is disabled: most of the way to the panel behind it
Faded :: proc(theme: ^Theme, color: ui.Color) -> ui.Color {
    faded: ui.Color = ui.ColorLerp(color, theme.panel, 0.55)
    faded.a = color.a
    return faded
}

// The color of a control through its states: base, then hover, then pressed (the style animates with info.hover and info.press)
ControlColor :: proc(theme: ^Theme, info: ^ui.DrawInfo) -> ui.Color {
    fill, _, _ := ButtonColors(theme, info)
    return fill
}

// The fill, the color of the label and the border of a button by its tags, with the states mixed in. A fill with alpha 0 is not drawn.
ButtonColors :: proc(theme: ^Theme, info: ^ui.DrawInfo) -> (fill: ui.Color, ink: ui.Color, border: ui.Color) {
    switch {
    case ui.DrawInfoHasTag(info, "danger"):
        fill, ink = theme.danger, theme.danger_text
    case ui.DrawInfoHasTag(info, "primary"):
        fill, ink = theme.accent, theme.accent_text
    case ui.DrawInfoHasTag(info, "secondary"):
        fill, ink = theme.accent_soft, theme.accent_soft_text
    case ui.DrawInfoHasTag(info, "outline"):
        fill, ink, border = theme.panel, theme.text, theme.border
    case ui.DrawInfoHasTag(info, "ghost"):
        ink = theme.accent
        fill = StateWash(theme, ink, info)
        if .DISABLED in info.flags { ink = Faded(theme, ink) }
        return
    case:
        fill, ink = theme.control, theme.text
    }
    if .DISABLED in info.flags {
        return Faded(theme, fill), Faded(theme, ink), Faded(theme, border)
    }
    return StateColor(theme, fill, ink, info), ink, border
}

@(private)
textColor :: proc(theme: ^Theme, info: ^ui.DrawInfo) -> ui.Color {
    return theme.text_dim if .DISABLED in info.flags else theme.text
}

// ------------------------------------------------------------------------------------------------------------------------
// The procs of the style

// A panel is a card: its surface, a faint outline and a soft shadow. What the library puts above the cards (a tooltip, the list of a dropdown, a menu, what is dragged), and a
// panel with the tag "popup", is a lighter surface with a stronger shadow. The tag "flat" takes the shadow away.
DrawPanel :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    raised: bool = ui.DrawInfoHasTag(info, "popup")
    switch info.name {
    case "tooltip", "dropdown", "combo", "menu", "drag":
        raised = true
    }
    radius: f32 = ui.RoundedRadius(info.rect, theme.panel_rounding, theme.max_radius if raised else theme.panel_max_radius)
    if !ui.DrawInfoHasTag(info, "flat") { Shadow(painter, info.rect, radius, 1.4 if raised else 1) }
    FillRoundedBorder(painter, info.rect, theme.panel_rounding, theme.surface_high if raised else theme.panel, theme.border if raised else theme.border_soft, theme.border_width, theme.max_radius if raised else theme.panel_max_radius)
}

// A text. With the tag "title" it is in the strong face, with "dim" in the dim color, with "mono" in the code face.
DrawLabel :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    color: ui.Color = info.color if info.color.a > 0 else (theme.text_dim if ui.DrawInfoHasTag(info, "dim") else theme.text)
    painter.face = .STRONG if ui.DrawInfoHasTag(info, "title") else (.MONO if ui.DrawInfoHasTag(info, "mono") else .REGULAR)
    painter.draw_text(painter, info.text, {info.rect.x, info.rect.y}, info.font_size, color)
    painter.face = .REGULAR
}

// The icon of a control and its label, centered together in the rect. An icon without a label is in the middle.
IconAndLabel :: proc(painter: ^Painter, info: ^ui.DrawInfo, ink: ui.Color, face: Face = .STRONG) {
    icon: icons.Icon = IconToLucide(info.icon) if painter.draw_icon != nil else .NONE
    icon_size: f32 = info.font_size
    gap: f32 = 6 if icon != .NONE && info.name != "" else 0
    text_width: f32 = TextWidth(painter, info.name, info.font_size, face) if info.name != "" else 0
    total: f32 = text_width + gap + (icon_size if icon != .NONE else 0)
    x: f32 = info.rect.x + (info.rect.z - total) * 0.5
    if icon != .NONE {
        IconAt(painter, icon, {x + icon_size * 0.5, info.rect.y + info.rect.w * 0.5}, icon_size, ink)
        x += icon_size + gap
    }
    if info.name != "" { TextLeft(painter, info.name, {x, info.rect.y, text_width, info.rect.w}, info.font_size, 0, ink, face) }
}

DrawButton :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    fill, ink, border := ButtonColors(theme, info)
    FocusRing(painter, info)
    FillRoundedBorder(painter, info.rect, theme.rounding, fill, border, theme.border_width if border.a > 0 else 0, theme.max_radius)
    IconAndLabel(painter, info, ink)
}

// A check box: a small box on the left that fills with the accent and gets a check mark, the name next to it
DrawToggle :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    side: f32 = min(info.rect.w, 18)
    box: ui.Rect = {info.rect.x + 1, info.rect.y + (info.rect.w - side) * 0.5, side, side}
    on: bool = .ON in info.flags
    disabled: bool = .DISABLED in info.flags
    if .FOCUSED in info.flags { RingRounded(painter, ui.RectShrink(box, -2), 6, 2, theme.focus) }
    fill: ui.Color = theme.accent if on else StateColor(theme, theme.track, theme.text, info)
    border: ui.Color = theme.accent if on else theme.border
    if disabled { fill, border = Faded(theme, fill), Faded(theme, border) }
    FillRoundedBorder(painter, box, 1, fill, border, 1.5, 4)
    if on {
        if painter.draw_icon != nil {
            IconAt(painter, .CHECK, ui.RectCenter(box), side - 4, theme.accent_text)
        } else {
            center: ui.Vec2 = ui.RectCenter(box)
            Line(painter, center + {-4, 0}, center + {-1, 3.5}, 2, theme.accent_text)
            Line(painter, center + {-1, 3.5}, center + {4.5, -3.5}, 2, theme.accent_text)
        }
    }
    TextLeft(painter, info.name, {info.rect.x + info.rect.w, info.rect.y, info.rect.z - info.rect.w, info.rect.w}, info.font_size, 4, textColor(theme, info))
}

// A slider is a well that fills up to the value, with its name and its number in it. With the tag "thin" it is a line with a round handle.
DrawSlider :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    if ui.DrawInfoHasTag(info, "thin") {
        line: f32 = 4
        handle: f32 = min(rect.w, 16)
        middle: f32 = rect.y + rect.w * 0.5
        x: f32 = rect.x + handle * 0.5 + (rect.z - handle) * info.value
        FillRounded(painter, {rect.x, middle - line * 0.5, rect.z, line}, 1, theme.track_strong)
        FillRounded(painter, {rect.x, middle - line * 0.5, x - rect.x, line}, 1, theme.accent)
        knob: ui.Rect = {x - handle * 0.5, middle - handle * 0.5, handle, handle}
        if .FOCUSED in info.flags { FillRounded(painter, ui.RectShrink(knob, -3), 1, {theme.focus.r, theme.focus.g, theme.focus.b, 110}) }
        FillRounded(painter, knob, 1, theme.panel)
        FillRounded(painter, ui.RectShrink(knob, 2 - info.press), 1, theme.accent)
        return
    }
    FocusRing(painter, info)
    FillRoundedBorder(painter, rect, theme.rounding, theme.track, theme.border, theme.border_width, theme.max_radius)
    inner: ui.Rect = ui.RectShrink(rect, theme.border_width)
    width: f32 = inner.z * info.value
    if width > 0 {
        FillRounded(painter, {inner.x, inner.y, max(width, inner.w * 0.5), inner.w}, theme.rounding, theme.accent_soft, theme.max_radius - theme.border_width)
    }
    handle_width: f32 = 3
    handle_x: f32 = clamp(inner.x + width - handle_width * 0.5, inner.x + 3, inner.x + inner.z - handle_width - 3)
    FillRounded(painter, {handle_x, rect.y + 5, handle_width, rect.w - 10}, 1, ui.ColorLerp(theme.accent, theme.text, info.press))
    TextLeft(painter, info.name, rect, info.font_size, 10, textColor(theme, info), .STRONG)
    TextRight(painter, info.text, rect, info.font_size, 10, textColor(theme, info), .MONO if painter.glue_fonts[.MONO] != 0 else .REGULAR)
}

// A progress bar: a well with the fill in the accent and the name on it. With the tag "thin" it is a line.
DrawProgress :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    rect: ui.Rect = info.rect
    if ui.DrawInfoHasTag(info, "thin") {
        line: f32 = min(rect.w, 6)
        rect = {rect.x, rect.y + (rect.w - line) * 0.5, rect.z, line}
    }
    FillRounded(painter, rect, 1, theme.track, theme.max_radius)
    // the fill keeps the round ends of the bar even when it is short
    width: f32 = rect.z * info.value
    if width > 0 {
        FillRounded(painter, {rect.x, rect.y, max(width, rect.w), rect.w}, 1, theme.accent, theme.max_radius)
    }
    if rect.w >= info.font_size {
        // the name is read on the fill and on the well: its color follows what is under its middle
        TextCentered(painter, info.name, rect, info.font_size, theme.accent_text if info.value > 0.5 else theme.text, .STRONG)
    }
}

// The box of a text field or a text area: a well with an outline that turns into the accent when it has the keyboard
FieldBox :: proc(painter: ^Painter, rect: ui.Rect, focused: bool, disabled: bool = false) {
    theme: ^Theme = &painter.theme
    if focused {
        FillRoundedBorder(painter, rect, theme.rounding, theme.track, theme.accent, 2, theme.max_radius)
    } else {
        FillRoundedBorder(painter, rect, theme.rounding, Faded(theme, theme.track) if disabled else theme.track, theme.border, theme.border_width, theme.max_radius)
    }
}

DrawTextField :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    focused: bool = .FOCUSED in info.flags
    FieldBox(painter, info.rect, focused, .DISABLED in info.flags)
    padding: f32 = ctx.style.metrics.padding.x
    if info.text == "" && !focused {
        TextLeft(painter, info.name, info.rect, info.font_size, padding, theme.text_dim)
        return
    }
    // the selection under the text: the accent, with the text of the selection drawn over it in the color that reads on the accent
    low: int = clamp(min(info.anchor, info.cursor), 0, len(info.text))
    high: int = clamp(max(info.anchor, info.cursor), 0, len(info.text))
    start: f32 = painter.measure_text(painter, info.text[:low], info.font_size).x
    finish: f32 = painter.measure_text(painter, info.text[:high], info.font_size).x
    if focused && low != high {
        FillRounded(painter, {info.rect.x + padding + start, info.rect.y + 5, finish - start, info.rect.w - 10}, 1, theme.accent, 3)
    }
    TextLeft(painter, info.text, info.rect, info.font_size, padding, textColor(theme, info))
    if focused && low != high {
        TextLeft(painter, info.text[low:high], info.rect, info.font_size, padding + start, theme.accent_text)
    }
    // the caret blinks twice a second
    if focused && math.mod(ctx.time, 1.0) < 0.5 {
        x: f32 = info.rect.x + padding + painter.measure_text(painter, info.text[:info.cursor], info.font_size).x
        painter.fill_rect(painter, {x, info.rect.y + 6, 1.5, info.rect.w - 12}, theme.text)
    }
}

DrawSeparator :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    painter.fill_rect(painter, info.rect, painter.theme.border_soft)
}

// The closed box of a dropdown: the surface of a card with an outline, the chosen option and a chevron that turns when the list is open
DrawDropdown :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FocusRing(painter, info)
    fill: ui.Color = StateColor(theme, theme.panel, theme.text, info)
    if .DISABLED in info.flags { fill = Faded(theme, fill) }
    FillRoundedBorder(painter, info.rect, theme.rounding, fill, theme.accent if .OPEN in info.flags else theme.border, theme.border_width, theme.max_radius)
    TextLeft(painter, info.text, info.rect, info.font_size, ctx.style.metrics.padding.x, textColor(theme, info))
    Chevron(painter, {info.rect.x + info.rect.z - info.rect.w * 0.5, info.rect.y + info.rect.w * 0.5}, info.font_size, 0 if .OPEN in info.flags else 1, theme.text_dim)
}

// A row that can be chosen (an option of a list, a row of a table, a menu entry): the soft accent when it is chosen (what a row is made of, texts and icons of their own, stays
// readable on it), a wash under the pointer, a ring inside of the row with the keyboard (rows touch: a ring outside would lie on the rows next to it)
RowBox :: proc(painter: ^Painter, info: ^ui.DrawInfo, selected: bool) -> (ink: ui.Color) {
    theme: ^Theme = &painter.theme
    ink = textColor(theme, info)
    if selected {
        FillRounded(painter, info.rect, theme.rounding, StateColor(theme, theme.accent_soft, theme.accent_soft_text, info), 6)
        if .DISABLED not_in info.flags { ink = theme.accent_soft_text }
    } else if info.hover > 0.01 || info.press > 0.01 {
        FillRounded(painter, info.rect, theme.rounding, StateWash(theme, theme.text, info), 6)
    }
    if .FOCUSED in info.flags { RingRounded(painter, info.rect, ui.RoundedRadius(info.rect, theme.rounding, 6), 2, theme.focus) }
    return
}

DrawDropdownItem :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    ink: ui.Color = RowBox(painter, info, .SELECTED in info.flags)
    TextLeft(painter, info.name, info.rect, info.font_size, ctx.style.metrics.padding.x, ink)
}

// A scrollbar is only its thumb: a round bar that gets stronger under the pointer
DrawScrollbar :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    track: ui.Rect = ui.RectShrink(info.rect, 1)
    thumb: ui.Rect
    if info.actual == 1 {
        thumb_width: f32 = max(track.z * info.ratio, track.w * 2)
        thumb = {track.x + (track.z - thumb_width) * info.value, track.y, thumb_width, track.w}
    } else {
        thumb_height: f32 = max(track.w * info.ratio, track.z * 2)
        thumb = {track.x, track.y + (track.w - thumb_height) * info.value, track.z, thumb_height}
    }
    strength: f32 = 0.45 + 0.35 * max(info.hover, info.press)
    FillRounded(painter, thumb, 1, {theme.text_dim.r, theme.text_dim.g, theme.text_dim.b, u8(strength * 255)})
}

// ------------------------------------------------------------------------------------------------------------------------
// The kinds of widgets_more.odin

// The header of a section: a chevron and the name. A section (not a tree node) has a quiet fill.
DrawCollapsing :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    open: bool = .OPEN in info.flags
    tree: bool = info.actual == 1
    FocusRing(painter, info)
    if tree {
        if info.hover > 0.01 || info.press > 0.01 { FillRounded(painter, info.rect, theme.rounding, StateWash(theme, theme.text, info), 6) }
    } else {
        FillRounded(painter, info.rect, theme.rounding, StateColor(theme, theme.track, theme.text, info), theme.max_radius)
    }
    Chevron(painter, {info.rect.x + 14, info.rect.y + info.rect.w * 0.5}, info.font_size, 1 if open else 3, theme.text_dim)
    TextLeft(painter, info.name, info.rect, info.font_size, 28, theme.text, .REGULAR if tree else .STRONG)
}

DrawRadio :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    side: f32 = min(info.rect.w, 18)
    box: ui.Rect = {info.rect.x + 1, info.rect.y + (info.rect.w - side) * 0.5, side, side}
    on: bool = .ON in info.flags
    FocusRing(painter, &{rect = box, flags = info.flags}, 1)
    FillRoundedBorder(painter, box, 1, StateColor(theme, theme.track, theme.text, info), theme.accent if on else theme.border, 1.5)
    if on { FillRounded(painter, ui.RectShrink(box, side * 0.28), 1, theme.accent) }
    TextLeft(painter, info.name, {info.rect.x + info.rect.w, info.rect.y, info.rect.z - info.rect.w, info.rect.w}, info.font_size, 4, textColor(theme, info))
}

DrawSelectable :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    ink: ui.Color = RowBox(painter, info, .SELECTED in info.flags)
    TextLeft(painter, info.name, info.rect, info.font_size, 8, ink)
}

// A tab: its name, strong and with a line of the accent under it when it is the chosen one
DrawTab :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    selected: bool = .SELECTED in info.flags
    FocusRing(painter, info)
    if !selected && (info.hover > 0.01 || info.press > 0.01) { FillRounded(painter, info.rect, theme.rounding, StateWash(theme, theme.text, info), 6) }
    TextCentered(painter, info.name, info.rect, info.font_size, theme.text if selected else ui.ColorLerp(theme.text_dim, theme.text, info.hover), .STRONG)
    if selected { FillRounded(painter, {info.rect.x + 4, info.rect.y + info.rect.w - 2, info.rect.z - 8, 2}, 1, theme.accent) }
}

DrawDrag :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FocusRing(painter, info)
    FillRoundedBorder(painter, info.rect, theme.rounding, StateColor(theme, theme.track, theme.text, info), theme.border, theme.border_width, theme.max_radius)
    TextCentered(painter, info.text, info.rect, info.font_size, textColor(theme, info), .MONO if painter.glue_fonts[.MONO] != 0 else .REGULAR)
}

// An arrow button. A small one (the arrow that opens a row of a tree) is only the chevron, with a wash under the pointer.
DrawArrow :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    if info.rect.z < ctx.style.metrics.control_height * 0.8 {
        side: f32 = min(info.rect.z, info.rect.w)
        center: ui.Vec2 = ui.RectCenter(info.rect)
        if info.hover > 0.01 || info.press > 0.01 { FillRounded(painter, {center.x - side * 0.5, center.y - side * 0.5, side, side}, theme.rounding, StateWash(theme, theme.text, info), 5) }
        Chevron(painter, center, min(side, info.font_size), int(info.actual), theme.text_dim)
        return
    }
    fill, ink, border := ButtonColors(theme, info)
    FocusRing(painter, info)
    FillRoundedBorder(painter, info.rect, theme.rounding, fill, border, theme.border_width if border.a > 0 else 0, theme.max_radius)
    Chevron(painter, ui.RectCenter(info.rect), info.rect.w * 0.6, int(info.actual), ink)
}

DrawPlot :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FillRoundedBorder(painter, info.rect, theme.rounding, theme.track, theme.border_soft, theme.border_width, theme.max_radius)
    inner: ui.Rect = ui.RectShrink(info.rect, 4)
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
    FillRoundedBorder(painter, info.rect, theme.rounding, info.color, ui.ColorLerp(theme.border, theme.text, info.hover), max(theme.border_width, 1), theme.max_radius)
}

DrawMenuBar :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    painter.fill_rect(painter, info.rect, theme.track)
    painter.fill_rect(painter, {info.rect.x, info.rect.y + info.rect.w - 1, info.rect.z, 1}, theme.border_soft)
}

// The title of a menu: its name with a wash while it is open or under the pointer. With a button tag around it ("outline", "primary"...) it is that button: a menu that
// opens from a button, not from a bar.
DrawMenu :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FocusRing(painter, info)
    if info.actual != 1 {
        for tag in ([?]string{"outline", "primary", "secondary", "danger"}) {
            if !ui.DrawInfoHasTag(info, tag) { continue }
            pressed: ui.DrawInfo = info^
            if .OPEN in info.flags { pressed.press = 1 }
            fill, ink, border := ButtonColors(theme, &pressed)
            FillRoundedBorder(painter, info.rect, theme.rounding, fill, border, theme.border_width if border.a > 0 else 0, theme.max_radius)
            IconAndLabel(painter, info, ink)
            return
        }
    }
    wash: ui.Color = StateWash(theme, theme.text, info, theme.press if .OPEN in info.flags else 0)
    if wash.a > 2 { FillRounded(painter, info.rect, theme.rounding, wash, 6) }
    if info.actual == 1 {
        TextLeft(painter, info.name, info.rect, info.font_size, 8, textColor(theme, info))
        Chevron(painter, {info.rect.x + info.rect.z - 12, info.rect.y + info.rect.w * 0.5}, info.font_size, 3, theme.text_dim)
    } else {
        TextCentered(painter, info.name, info.rect, info.font_size, textColor(theme, info), .STRONG)
    }
}

DrawMenuItem :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    ink: ui.Color = RowBox(painter, info, false)
    if .ON in info.flags {
        center: ui.Vec2 = {info.rect.x + 13, info.rect.y + info.rect.w * 0.5}
        if painter.draw_icon != nil {
            IconAt(painter, .CHECK, center, info.font_size, theme.accent)
        } else {
            Line(painter, center + {-5, 0}, center + {-2, 3.5}, 2, theme.accent)
            Line(painter, center + {-2, 3.5}, center + {4, -4}, 2, theme.accent)
        }
    }
    TextLeft(painter, info.name, info.rect, info.font_size, 26, ink)
    if info.text != "" { TextRight(painter, info.text, info.rect, info.font_size, 10, theme.text_dim) }
}

// The title bar of a window: the top of its card, a shade off its surface, with the title in the strong face
DrawWindowTitle :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    FillRounded(painter, info.rect, theme.panel_rounding, theme.track, theme.panel_max_radius - 2)
    TextLeft(painter, info.name, info.rect, info.font_size, 10, theme.text if .FOCUSED in info.flags else theme.text_dim, .STRONG)
}

// The handle between two sections: a thin line in the middle of its rectangle that lights up under the pointer and while it is dragged
DrawSplitter :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    strength: f32 = max(info.hover, info.press)
    if .PRESSED in info.flags { strength = 1 }
    color: ui.Color = ui.ColorLerp(theme.border_soft, theme.accent, strength)
    line: f32 = 2 if strength > 0.05 else 1
    rect: ui.Rect = info.rect
    if info.actual == 0 {
        painter.fill_rect(painter, {rect.x + (rect.z - line) * 0.5, rect.y, line, rect.w}, color)
    } else {
        painter.fill_rect(painter, {rect.x, rect.y + (rect.w - line) * 0.5, rect.z, line}, color)
    }
    if .FOCUSED in info.flags {
        painter.fill_rect(painter, {rect.x, rect.y, rect.z, 1}, theme.focus)
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
    width: f32 = TextWidth(painter, info.name, info.font_size, .STRONG)
    y: f32 = info.rect.y + info.rect.w * 0.5
    painter.fill_rect(painter, {info.rect.x, y, 14, 1}, theme.border_soft)
    TextLeft(painter, info.name, info.rect, info.font_size, 22, theme.text_dim, .STRONG)
    after: f32 = info.rect.x + 30 + width
    painter.fill_rect(painter, {after, y, max(info.rect.x + info.rect.z - after, 0), 1}, theme.border_soft)
}

DrawBackdrop :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    painter.fill_rect(painter, info.rect, painter.theme.scrim)
}

// The box of a text area: like a text field, with the name shown while it is empty. Its lines, selection and caret are elements of their own.
DrawTextArea :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    theme: ^Theme = &painter.theme
    focused: bool = .FOCUSED in info.flags
    FieldBox(painter, info.rect, focused, .DISABLED in info.flags)
    if info.text == "" && !focused {
        metrics: ^ui.Metrics = &ctx.style.metrics
        painter.draw_text(painter, info.name, {info.rect.x + metrics.padding.x, info.rect.y + metrics.padding.y}, info.font_size, theme.text_dim)
    }
}

DrawTextSelection :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    accent: ui.Color = painter.theme.accent
    painter.fill_rect(painter, info.rect, {accent.r, accent.g, accent.b, 110})
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
