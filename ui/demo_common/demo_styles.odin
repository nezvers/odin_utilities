#+private file
package demo_common

// The same widgets in three looks. The library draws nothing by itself: a style is a table of procs, one per kind of widget, each gets a
// rectangle and what is known about the widget (DrawInfo: value 0..1, name, the real number, flags, hover fade). The third look is made
// here, in the demo, with procs of its own, and a gauge that is not a widget of the library at all (UiCustom).

import "core:math"
import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"

@(private="package")
demo_styles: kit.Demo = {
    name = "styles",
    init = init,
    draw = draw,
    script = script,
}

LOOK_DEFAULT :: 0
LOOK_LIGHT :: 1
LOOK_NEON :: 2

state: UiDemo
styles: [3]ui.Style
look: int
volume: f32
loading: f32
on: bool
gauge: f32

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    // 0: the default style as it is
    styles[LOOK_DEFAULT] = ui_default.StyleMake()
    // 1: the same procs, other colors and square corners: only the theme of the painter changes (see draw)
    styles[LOOK_LIGHT] = ui_default.StyleMake()
    // 2: procs of our own for some kinds, the default ones for the rest
    styles[LOOK_NEON] = ui_default.StyleMake()
    styles[LOOK_NEON].procs[.BUTTON] = neon_button
    styles[LOOK_NEON].procs[.SLIDER] = segment_slider
    styles[LOOK_NEON].procs[.TOGGLE] = switch_toggle
    styles[LOOK_NEON].procs[.PROGRESS] = stripe_progress
    look = LOOK_DEFAULT
    volume = 30
    loading = 0.45
    on = false
    gauge = 0.5
    ctx.background = {24, 26, 32, 255}
}

draw :: proc(ctx: ^kit.Context) {
    // a style is picked per frame: what the widgets look like is not part of how they are declared
    state.style = styles[look]
    state.painter.theme = ui_default.THEME_DARK
    switch look {
    case LOOK_LIGHT:
        state.painter.theme = light_theme()
        ctx.background = {226, 228, 234, 255}
    case LOOK_NEON:
        ctx.background = {8, 6, 18, 255}
    case:
        ctx.background = {24, 26, 32, 255}
    }
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx
    if ui.UiWindow(c, "Look", {40, 40}, {ui.Fixed(302), {}}) {
        if ui.UiRow(c) {
            if ui.UiButton(c, "Default", {ui.Fixed(90), {}}) { look = LOOK_DEFAULT }
            if ui.UiButton(c, "Light", {ui.Fixed(90), {}}) { look = LOOK_LIGHT }
            if ui.UiButton(c, "Neon", {ui.Fixed(90), {}}) { look = LOOK_NEON }
        }
        wide: ui.Size = {ui.Fixed(282), {}}
        ui.UiSlider(c, "Volume", &volume, 0, 100, wide, "%.0f")
        ui.UiProgress(c, "Loading", loading, 0, 1, wide, "%.2f")
        ui.UiToggle(c, "Enabled", &on, wide)
        dial: ui.Interaction = ui.UiCustom(c, "gauge", draw_gauge, {ui.Fixed(282), ui.Fixed(120)}, nil, gauge, true)
        if dial.pressed && dial.rect.z > 0 {
            gauge = clamp((ctx.input.mouse_position.x - dial.rect.x) / dial.rect.z, 0, 1)
        }
    }
    ui_demo_end(&state)
}

light_theme :: proc() -> ui_default.Theme {
    theme: ui_default.Theme = ui_default.THEME_DARK
    theme.panel = {250, 250, 252, 255}
    theme.border = {190, 194, 206, 255}
    theme.text = {30, 32, 44, 255}
    theme.text_dim = {120, 124, 140, 255}
    theme.control = {222, 226, 238, 255}
    theme.control_hover = {206, 212, 230, 255}
    theme.control_pressed = {186, 194, 220, 255}
    theme.track = {232, 234, 242, 255}
    theme.accent = {60, 120, 220, 255}
    theme.rounding = 0
    theme.panel_rounding = 0
    return theme
}

// ------------------------------------------------------------------------------------------------------------------------
// The procs of the neon look: all of them are ordinary StyleProcs

NEON_PINK :: ui.Color{255, 60, 170, 255}
NEON_CYAN :: ui.Color{40, 230, 255, 255}

painter_of :: proc(ctx: ^ui.Context) -> ^ui_default.Painter {
    return cast(^ui_default.Painter)ctx.user
}

kit_of :: proc(ctx: ^ui.Context) -> ^kit.Context {
    return cast(^kit.Context)painter_of(ctx).user
}

// A pill with a colored outline that lights up when the pointer is on it
neon_button :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^ui_default.Painter = painter_of(ctx)
    glow: ui.Color = ui.ColorLerp(NEON_CYAN, NEON_PINK, info.hover)
    ui_default.FillRoundedBorder(painter, info.rect, 1, ui.ColorLerp({16, 12, 34, 255}, glow, info.press * 0.6), glow, 2)
    ui_default.TextCentered(painter, info.name, info.rect, info.font_size, glow)
}

// A row of little blocks: as many are lit as the value says
segment_slider :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^ui_default.Painter = painter_of(ctx)
    SEGMENTS :: 20
    gap: f32 = 3
    width: f32 = (info.rect.z - gap * (SEGMENTS - 1)) / SEGMENTS
    lit: int = int(info.value * SEGMENTS + 0.5)
    for i in 0 ..< SEGMENTS {
        x: f32 = info.rect.x + f32(i) * (width + gap)
        color: ui.Color = ui.ColorLerp(NEON_CYAN, NEON_PINK, f32(i) / SEGMENTS) if i < lit else ui.Color{30, 24, 56, 255}
        painter.fill_rect(painter, {x, info.rect.y + 4, width, info.rect.w - 8}, color)
    }
}

// A switch: a pill with a knob that sits on the left or on the right
switch_toggle :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^ui_default.Painter = painter_of(ctx)
    lit_on: bool = .ON in info.flags
    track: ui.Rect = {info.rect.x, info.rect.y + 2, info.rect.w * 1.8, info.rect.w - 4}
    ui_default.FillRounded(painter, track, 1, NEON_PINK if lit_on else ui.Color{30, 24, 56, 255})
    knob_size: f32 = track.w - 6
    knob_x: f32 = track.x + track.z - knob_size - 3 if lit_on else track.x + 3
    ui_default.FillRounded(painter, {knob_x, track.y + 3, knob_size, knob_size}, 1, {255, 255, 255, 255})
    ui_default.TextLeft(painter, info.name, {track.x + track.z, info.rect.y, info.rect.z, info.rect.w}, info.font_size, 10, NEON_CYAN)
}

// Diagonal stripes in the part that is filled
stripe_progress :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^ui_default.Painter = painter_of(ctx)
    ui_default.FillRoundedBorder(painter, info.rect, 0.3, {16, 12, 34, 255}, NEON_CYAN, 1)
    filled: f32 = (info.rect.z - 4) * info.value
    x: f32 = info.rect.x + 2
    for x < info.rect.x + 2 + filled {
        stripe: f32 = min(8, info.rect.x + 2 + filled - x)
        painter.fill_rect(painter, {x, info.rect.y + 3, stripe, info.rect.w - 6}, NEON_PINK)
        x += 14
    }
    ui_default.TextCentered(painter, info.text, info.rect, info.font_size, {255, 255, 255, 255})
}

// An element that is not a widget of the library: a dial drawn with lines, from the value of the element
draw_gauge :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    kit_context: ^kit.Context = kit_of(ctx)
    center: ui.Vec2 = {info.rect.x + info.rect.z * 0.5, info.rect.y + info.rect.w * 0.9}
    radius: f32 = min(info.rect.z * 0.45, info.rect.w * 0.8)
    STEPS :: 36
    // a half circle from the left to the right, the part up to the value is bright
    for i in 0 ..< STEPS {
        a0: f32 = math.PI + f32(i) / STEPS * math.PI
        a1: f32 = math.PI + f32(i + 1) / STEPS * math.PI
        color: kit.Color = {255, 60, 170, 255} if f32(i) / STEPS < info.value else {90, 90, 110, 255}
        kit.DrawLine(kit_context, center + radius * ui.Vec2{math.cos(a0), math.sin(a0)}, center + radius * ui.Vec2{math.cos(a1), math.sin(a1)}, 4, color)
    }
    needle: f32 = math.PI + info.value * math.PI
    kit.DrawLine(kit_context, center, center + radius * 0.9 * ui.Vec2{math.cos(needle), math.sin(needle)}, 3, {255, 255, 255, 255})
    kit.DrawCircle(kit_context, center, 6, {255, 255, 255, 255})
}

script: []kit.Step = {
    kit.Wait(3),
    // the buttons are 90 wide with 6 between, at y 50 .. 78
    kit.Click({280, 64}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return look == LOOK_NEON }, "the third button picks the neon look"),
    kit.Capture("styles_neon"),
    kit.Click({150, 64}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return look == LOOK_LIGHT }, "the second button picks the light look"),
    // the slider is drawn by whatever style: it works the same. x 50 .. 332
    kit.Drag({60, 98}, {191, 98}, 8),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(volume - 50) < 3 }, "the slider works in every look"),
    // progress at y 118 .. 139 (nothing to click), the toggle at y 145 .. 173
    kit.Click({60, 159}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return on }, "the toggle was flipped"),
    // the gauge is a custom element: 120 high at y 179 .. 299 with x 50 .. 332. A drag to the left end sets it to 0
    kit.Drag({190, 240}, {50, 240}, 6),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return gauge < 0.05 }, "a custom element is dragged like a widget"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
