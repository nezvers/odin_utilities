#+private file
package demo_common

// Four examples of Baldr (https://github.com/BuLEEto/Baldr, by Lee Fry and the Baldr contributors, zlib License) made again with this library, one per tab:
// 01_hello (a counter), 04_controls (check boxes, a switch and sliders bound to a state), 03_scroll (a list of cards that scrolls) and 17_toasts (cards at the top right
// that a click takes away). The texts and the sample data are the ones of the originals. There a `view` builds a tree and an `update` answers messages; here the page is
// declared every frame and a widget hands back what happened: the counter is `if ui.UiButton(...) { count += 1 }`.

import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"

@(private="package")
demo_examples: kit.Demo = {
    name = "examples",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    example: int,
    // 01_hello
    count: int,
    // 04_controls
    remember: bool,
    notify: bool,
    two_factor: bool,
    dark: bool,
    size: f32,
    volume: f32,
    // 03_scroll
    picked: int,
    messages_id: ui.Id,             // for the script: the list and the Pick button of the second card, as they were declared
    pick_id: ui.Id,
    // 17_toasts
    toasts: [3]bool,
}

state: State

EXAMPLES: [4]string = {"Hello", "Controls", "Scroll", "Toasts"}
TOASTS: [3]string = {"Build finished", "Ada: Lunch at one?", "Backup complete"}
MESSAGES :: 40

controlsReset :: proc() {
    state.remember, state.notify, state.two_factor = false, false, false
    state.dark, state.size, state.volume = true, 15, 0.4
}

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    controlsReset()
    state.toasts = {true, true, true}
    ctx.background = kit.Color(state.app.painter.theme.background)
}

@(deferred_in = rowEnd)
row :: proc(c: ^ui.Context, gap: f32 = 12, align: ui.AlignX = .LEFT) -> bool {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = gap, align = {x = align, y = .CENTER}}})
    return true
}

rowEnd :: proc(c: ^ui.Context, gap: f32 = 12, align: ui.AlignX = .LEFT) {
    ui.ElementClose(c)
}

// The window of an example: a panel of the size the original opens with, in the middle of what is left of the screen
@(deferred_in = stageEnd)
stage :: proc(c: ^ui.Context, name: string, size: ui.Vec2, layout: ui.Layout) -> bool {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Grow()}, direction = .TOP_TO_BOTTOM, align = {x = .CENTER, y = .CENTER}}})
    inner: ui.Layout = layout
    inner.size = {ui.Fixed(size.x), ui.Fixed(size.y)}
    ui.ElementOpen(c, {id = ui.UiId(c, name), layout = inner, hit = {.BLOCKER}, draw = {kind = .PANEL, name = name}})
    return true
}

stageEnd :: proc(c: ^ui.Context, name: string, size: ui.Vec2, layout: ui.Layout) {
    ui.ElementClose(c)
    ui.ElementClose(c)
}

// 01_hello: a heading, a count, and minus, Reset and plus
hello :: proc(c: ^ui.Context) {
    if stage(c, "hello", {480, 320}, {direction = .TOP_TO_BOTTOM, gap = 16, padding = ui.PaddingAll(32), align = {x = .CENTER, y = .CENTER}}) {
        ui.UiTitle(c, "Hello, Baldr", 1.9)
        ui.UiPushTag(c, "dim")
        ui.UiTitle(c, ui.UiFormat(c, "Count: %d", state.count), 1.4)
        ui.UiPopTag(c)
        ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 12}})
        if ui.UiTagged(c, "secondary") {
            if ui.UiButton(c, "##minus", icon = ui_default.LucideIcon(.MINUS)) { state.count -= 1 }
        }
        if ui.UiTagged(c, "outline") {
            if ui.UiButton(c, "Reset", disabled = state.count == 0) { state.count = 0 }
        }
        if ui.UiTagged(c, "primary") {
            if ui.UiButton(c, "##plus", icon = ui_default.LucideIcon(.PLUS)) { state.count += 1 }
        }
        ui.ElementClose(c)
    }
}

// 04_controls: every value is the state of the program, the widgets change it in place
controls :: proc(c: ^ui.Context) {
    if stage(c, "controls", {520, 480}, {direction = .TOP_TO_BOTTOM, gap = 16, padding = ui.PaddingAll(24)}) {
        ui.UiTitle(c, "Settings", 1.6)
        if ui.UiTagged(c, "flat") {
            if ui.UiCard(c, "Account") {
                ui.UiToggle(c, "Remember me on this device", &state.remember)
                ui.UiToggle(c, "Email me about new releases", &state.notify)
                ui.UiToggle(c, "Two-factor (managed by your organisation)", &state.two_factor, disabled = true)
            }
            if ui.UiCard(c, "Appearance") {
                ui.UiSwitch(c, "Dark theme", &state.dark)
                if row(c) {
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(72), ui.Fit()}}})
                    ui.UiLabelDim(c, "Text size")
                    ui.ElementClose(c)
                    if ui.UiTagged(c, "thin") {
                        if ui.UiSlider(c, "##size", &state.size, 12, 24, {ui.Grow(), {}}) { state.size = f32(int(state.size + 0.5)) }
                    }
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(52), ui.Fit()}, direction = .LEFT_TO_RIGHT, align = {x = .RIGHT}}})
                    ui.UiLabelf(c, "%.0f px", state.size)
                    ui.ElementClose(c)
                }
                if row(c) {
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(72), ui.Fit()}}})
                    ui.UiLabelDim(c, "Volume")
                    ui.ElementClose(c)
                    if ui.UiTagged(c, "thin") { ui.UiSlider(c, "##volume", &state.volume, 0, 1, {ui.Grow(), {}}) }
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(52), ui.Fit()}, direction = .LEFT_TO_RIGHT, align = {x = .RIGHT}}})
                    ui.UiLabelf(c, "%d%%", int(state.volume * 100 + 0.5))
                    ui.ElementClose(c)
                }
            }
        }
        if ui.UiTagged(c, "outline") {
            if ui.UiButton(c, "Reset") { controlsReset() }
        }
    }
}

// 03_scroll: forty cards in a region of a fixed height
scroll :: proc(c: ^ui.Context) {
    if stage(c, "scroll", {560, 480}, {direction = .TOP_TO_BOTTOM, gap = 16, padding = ui.PaddingAll(24)}) {
        if row(c) {
            ui.UiTitle(c, "Inbox", 1.6)
            ui.UiSpacer(c, {ui.Grow(), ui.Fixed(1)})
            ui.UiLabelDim(c, ui.UiFormat(c, "%d picked", state.picked))
            if ui.UiTagged(c, "outline") {
                if ui.UiButton(c, "Clear", disabled = state.picked == 0) { state.picked = 0 }
            }
        }
        state.messages_id = ui.UiId(c, "##messages")
        if ui.UiScroll(c, "##messages", {ui.Grow(), ui.Grow()}, {direction = .TOP_TO_BOTTOM, gap = 8, padding = {0, 12, 0, 0}}) {
            theme: ^ui_default.Theme = &state.app.painter.theme
            for i in 0 ..< MESSAGES {
                ui.ElementOpen(c, {
                    id = ui.IdFromIndex(u32(i), ui.UiId(c, "message")),
                    layout = {size = {ui.Grow(), ui.Fit()}, direction = .TOP_TO_BOTTOM, gap = 4, padding = ui.PaddingAll(12)},
                    draw = {kind = .PANEL},
                })
                if row(c) {
                    // a dot: every third message is unread
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(10), ui.Fixed(10)}}, draw = {kind = .AVATAR, color = theme.accent if i % 3 == 0 else theme.border}})
                    ui.ElementClose(c)
                    ui.UiTitle(c, ui.UiFormat(c, "Message %d - build finished", i + 1), 1.1)
                    ui.UiSpacer(c, {ui.Grow(), ui.Fixed(1)})
                    if ui.UiTagged(c, "ghost") {
                        if i == 1 { state.pick_id = ui.UiId(c, "Pick##1") }
                        if ui.UiButton(c, ui.UiFormat(c, "Pick##%d", i)) { state.picked += 1 }
                    }
                }
                ui.UiLabelDim(c, "All 55 headless tests passed. The Wayland and Win32 backends both presented the counter.", .WORDS)
                ui.ElementClose(c)
            }
        }
    }
}

// 17_toasts: cards at the top right, each one gone with a click. The original closes its program with the last one; here a button brings them back.
toasts :: proc(c: ^ui.Context, screen: ui.Vec2) {
    if stage(c, "toasts", {420, 160}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(24), align = {x = .CENTER, y = .CENTER}}) {
        left: int
        for shown in state.toasts {
            if shown { left += 1 }
        }
        ui.UiLabelDim(c, ui.UiFormat(c, "%d toasts at the top right: a click takes one away", left))
        if ui.UiTagged(c, "outline") {
            if ui.UiButton(c, "Show them again", disabled = left == len(state.toasts)) { state.toasts = {true, true, true} }
        }
    }
    y: f32 = 64
    for title, i in TOASTS {
        if !state.toasts[i] { continue }
        id: ui.Id = ui.IdFromIndex(u32(i), ui.UiId(c, "toast"))
        if ui.UiInteract(c, id).clicked { state.toasts[i] = false }
        ui.UiPushTag(c, "popup")
        ui.ElementOpen(c, {
            id = id,
            layout = {size = {ui.Fixed(370), ui.Fixed(72)}, direction = .TOP_TO_BOTTOM, gap = 2, padding = ui.PaddingAll(12), align = {y = .CENTER}},
            floating = {attach_to = .ROOT, offset = {screen.x - 370 - 16, y}, z_index = 10},
            hit = {.INTERACTIVE, .BLOCKER},
            draw = {kind = .PANEL, name = title},
        })
        ui.UiPopTag(c)
        ui.UiTitle(c, title, 1)
        ui.UiLabelDim(c, "Click to dismiss")
        ui.ElementClose(c)
        y += 80
    }
}

draw :: proc(ctx: ^kit.Context) {
    state.app.painter.theme = ui_default.THEME_DARK if state.dark else ui_default.THEME_LIGHT
    ctx.background = kit.Color(state.app.painter.theme.background)
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    metrics: ^ui.Metrics = &c.style.metrics
    ui.ElementOpen(c, {layout = {size = {ui.Fixed(ctx.screen.x), ui.Fixed(ctx.screen.y)}, direction = .TOP_TO_BOTTOM}})
    ui.ElementOpen(c, {
        layout = {size = {ui.Grow(), ui.Fixed(metrics.control_height + 24)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(16, 0), gap = 16, align = {y = .CENTER}},
        draw = {kind = .MENU_BAR},
    })
    ui.UiTitle(c, "Baldr examples", 1.3)
    ui.UiTabBar(c, "##examples", EXAMPLES[:], &state.example)
    ui.ElementClose(c)
    switch state.example {
    case 0:
        hello(c)
    case 1:
        controls(c)
    case 2:
        scroll(c)
    case 3:
        toasts(c, ctx.screen)
    }
    ui.ElementClose(c)
    ui_demo_end(&state.app)
}

// The script finds the widgets by where they were in the last frame: the pages are laid out by the widths of their texts
target: ui.Vec2

aim :: proc(id: ui.Id) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, id)
    target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return found && rect.z > 0
}

tab :: proc(index: u32) -> bool {
    return aim(ui.IdFromIndex(index, ui.UiId(&state.app.ctx, "##examples")))
}

script: []kit.Step = {
    kit.Wait(4),
    // hello: plus twice, minus once, reset
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("hello", "##plus")) }, "the plus button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.count == 2 }, "two clicks on plus count to 2"),
    kit.MoveTo({640, 700}),
    kit.Wait(3),
    kit.Capture("examples_hello"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("hello", "##minus")) }, "the minus button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.count == 1 }, "minus takes one away"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("hello", "Reset")) }, "the Reset button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.count == 0 }, "Reset sets the count to 0"),

    // controls: a check box, the switch (the theme of the page follows it), a slider, Reset
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(1) }, "the Controls tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("controls", "Account", "Remember me on this device")) }, "the first check box is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.remember }, "the check box was ticked"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("controls", "Account", "Two-factor (managed by your organisation)")) }, "the disabled check box is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.two_factor }, "a disabled check box does not take a click"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, ui.UiIdPath("controls", "Appearance", "##volume"))
        target = {rect.x + rect.z * 0.75, rect.y + rect.w * 0.5}
        return found
    }, "the volume slider is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(state.volume - 0.75) < 0.06 }, "a click at three quarters of the slider sets it there"),
    kit.MoveTo({640, 700}),
    kit.Wait(3),
    kit.Capture("examples_controls"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("controls", "Appearance", "Dark theme")) }, "the switch is on the page"),
    kit.ClickAt(&target),
    kit.Wait(12),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.dark && !state.app.painter.theme.dark }, "the switch turned the page to the light theme"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("controls", "Reset")) }, "the Reset button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.dark && !state.remember && state.volume == 0.4 }, "Reset puts every value back"),

    // scroll: a pick, then the wheel
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(2) }, "the Scroll tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(state.pick_id) }, "the Pick button of the second card is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.picked == 1 }, "a pick was counted"),
    kit.Scroll(-3),
    kit.Wait(6),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiScrollGet(&state.app.ctx, state.messages_id) > 10 }, "the wheel scrolls the list"),
    kit.MoveTo({640, 700}),
    kit.Wait(3),
    kit.Capture("examples_scroll"),
    kit.Wait(2),

    // toasts: one goes with a click, the button brings it back
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(3) }, "the Toasts tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Capture("examples_toasts"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.IdFromIndex(1, ui.UiId(&state.app.ctx, "toast"))) }, "the second toast is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.toasts == [3]bool{true, false, true} }, "a click took the second toast away"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("toasts", "Show them again")) }, "the button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.toasts == [3]bool{true, true, true} }, "the toasts are back"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
