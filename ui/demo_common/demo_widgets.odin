#+private file
package demo_common

// Every widget of the library in one window. The script is the test: it clicks, drags and types on real widgets of the layout.
// The positions of the script are the ones of the layout: the window is at (40, 40) with 10 px of padding, controls are 28 high, 6 apart.

import "core:math"
import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_widgets: kit.Demo = {
    name = "widgets",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

WIDTH :: 220

state: UiDemo
clicks: int
music: bool
volume: f32
progress: f32
name_buffer: [32]u8
name_length: int
quality: int
options: [3]string = {"Low", "Medium", "High"}

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    clicks = 0
    music = true
    volume = 20
    progress = 0
    name_length = 0
    quality = 0
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

update :: proc(ctx: ^kit.Context) {
    progress = f32(math.mod(ctx.time * 0.25, 1.0))
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx
    wide: ui.Size = {ui.Fixed(WIDTH), {}}
    if ui.UiWindow(c, "Settings", {40, 40}, {ui.Fixed(WIDTH + 20), {}}) {
        if ui.UiButton(c, "Click me", wide) { clicks += 1 }
        ui.UiToggle(c, "Music", &music, wide)
        ui.UiSlider(c, "Volume", &volume, 0, 100, wide, "%.0f")
        ui.UiProgress(c, "Loading", progress, 0, 1, wide, "%.2f")
        ui.UiTextField(c, "Your name", name_buffer[:], &name_length, wide)
        ui.UiDropdown(c, "Quality", options[:], &quality, wide)
    }
    // what the widgets gave back, in a window of its own
    if ui.UiWindow(c, "State", {340, 40}, {ui.Fixed(260), {}}) {
        ui.UiLabelf(c, "clicks: %d", clicks)
        ui.UiLabelf(c, "music: %v", music)
        ui.UiLabelf(c, "volume: %.1f", volume)
        ui.UiLabelf(c, "name: %s", string(name_buffer[:name_length]))
        ui.UiLabelf(c, "quality: %s", options[quality])
        ui.UiSeparator(c)
        ui.UiLabelf(c, "pointer over ui: %v", ui.UiPointerOverUi(c))
    }
    ui_demo_end(&state)
}

script: []kit.Step = {
    kit.Wait(3),
    // button: 28 high at y 50
    kit.Click({80, 64}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return clicks == 1 }, "the button was clicked once"),
    // a click outside of every window is not for the ui
    kit.MoveTo({900, 600}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !ui.UiPointerOverUi(&state.ctx) }, "the pointer is not over the ui on empty ground"),
    kit.Click({80, 98}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !music }, "the toggle was flipped"),
    // slider: x from 50 to 270, y 118 .. 146. From the left to the middle: 50
    kit.Drag({60, 132}, {160, 132}, 10),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(volume - 50) < 6 }, "the slider follows the drag"),
    // text field at y 179 .. 207
    kit.Click({100, 193}),
    kit.Wait(2),
    kit.Type("hi"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(name_buffer[:name_length]) == "hi" }, "the text field takes what is typed"),
    kit.Tap(.BACKSPACE),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(name_buffer[:name_length]) == "h" }, "backspace removes a character"),
    // dropdown at y 213 .. 241, the list under it with 28 high rows: the third is at y 299 .. 327
    kit.Click({100, 227}),
    kit.Wait(3),
    kit.Capture("widgets_dropdown_open"),
    kit.Click({100, 313}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return quality == 2 }, "the third option of the dropdown was picked"),
    kit.Capture("widgets_done"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
