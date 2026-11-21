#+private file
package demo_common

// Three more of Baldr's examples (https://github.com/BuLEEto/Baldr, by Lee Fry and the Baldr contributors, zlib License): 23_chrome (a window that draws its own frame: title bar
// with icon, minimise / maximise / close, a double click on the title maximises, the edges resize), 38_windows (a main window and a Preferences window of one program, both
// reading and writing ONE state: the theme switch of Preferences changes the main window) and 14_bar_applets (a bar with applet slots; an applet that stops leaves its slot
// with a Restart button, the others go on). Baldr's windows are operating system windows and its applets are separate processes: the kit has one window, so the windows are
// floating elements with their own frame and the applets are plain data. The frame is made here, with `UiInteract` and the floating elements of the library: a program that
// wants the frame of `UiWindowResizable` uses that instead.

import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"
import icons "../../icons"

@(private="package")
demo_windows: kit.Demo = {
    name = "baldr windows",
    init = init,
    draw = draw,
    script = script,
}

BAR_HEIGHT :: f32(40)
TITLE_HEIGHT :: f32(34)
MIN_SIZE :: ui.Vec2{240, 140}
GRIP :: f32(6)

Win :: struct {
    title: string,
    icon: icons.Icon,
    position: ui.Vec2,
    size: ui.Vec2,
    restore_position: ui.Vec2,      // where it was before it was maximised
    restore_size: ui.Vec2,
    open: bool,
    minimised: bool,
    maximised: bool,
    grab: ui.Vec2,                  // the pointer at the press of a drag
    start: ui.Vec2,                 // the position or the size at the press
}

Applet :: struct {
    name: string,
    icon: icons.Icon,
    running: bool,
    starts: int,
}

State :: struct {
    app: UiDemo,
    windows: [2]Win,
    order: [2]int,                  // back to front
    // the one state that both windows read and write
    dark: bool,
    count: int,
    notes: int,
    applets: [3]Applet,
    minutes: int,
    screen: ui.Vec2,
    ids: [16]ui.Id,
}

MAIN :: 0
PREFERENCES :: 1

ID_TITLE :: 0                       // + the window: the title bar
ID_MAXIMISE :: 2
ID_CLOSE :: 4
ID_MINIMISE :: 6
ID_PREFERENCES :: 8
ID_CRASH :: 9
ID_INCREMENT :: 10
ID_RESTART :: 11
ID_GRIP :: 12                       // the corner of the main window

state: State
target: ui.Vec2

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    state.windows = {
        {title = "Notes", icon = .FILE_TEXT, position = {120, 110}, size = {420, 300}, open = true},
        {title = "Preferences", icon = .SETTINGS, position = {600, 180}, size = {360, 240}},
    }
    state.order = {PREFERENCES, MAIN}
    state.dark = true
    state.applets = {{"Clock", .CLOCK, true, 1}, {"Network", .WIFI, true, 1}, {"Battery", .BATTERY, true, 1}}
    state.minutes = 14 * 60 + 5
}

// ---- the frame of a window ---------------------------------------------------------------------------------------------------------------------------------

raise :: proc(index: int) {
    at: int
    for entry, i in state.order { if entry == index { at = i } }
    for i := at; i < len(state.order) - 1; i += 1 { state.order[i] = state.order[i + 1] }
    state.order[len(state.order) - 1] = index
}

maximise :: proc(w: ^Win) {
    if w.maximised {
        w.position, w.size, w.maximised = w.restore_position, w.restore_size, false
    } else {
        w.restore_position, w.restore_size, w.maximised = w.position, w.size, true
    }
}

frameButton :: proc(c: ^ui.Context, id_slot: int, name: string, icon: icons.Icon) -> bool {
    state.ids[id_slot] = ui.UiId(c, name)
    return ui.UiButton(c, name, {ui.Fixed(28), ui.Fixed(26)}, icon = ui_default.LucideIcon(icon))
}

// One grip of the edge: the size follows the pointer from where the press started
grip :: proc(c: ^ui.Context, w: ^Win, name: string, point: ui.AttachPoint, size: ui.Size, cursor: ui.Cursor, x: bool, y: bool) {
    id: ui.Id = ui.UiId(c, name)
    interaction: ui.Interaction = ui.UiInteract(c, id)
    input: ^ui.Input = &c.input
    if interaction.pressed && (input.mouse_down || input.mouse_released) {
        if input.mouse_pressed {
            w.grab, w.start = input.mouse_position, w.size
        } else if !w.maximised {
            moved: ui.Vec2 = input.mouse_position - w.grab
            if x { w.size.x = max(w.start.x + moved.x, MIN_SIZE.x) }
            if y { w.size.y = max(w.start.y + moved.y, MIN_SIZE.y) }
        }
    }
    ui.ElementOpen(c, {id = id, layout = {size = size}, floating = {attach_to = .PARENT, parent_point = point, element_point = point}, hit = {.INTERACTIVE, .NO_FOCUS}, cursor = cursor})
    ui.ElementClose(c)
}

// Opens the frame and the body of a window; the caller declares the body and closes both with `frameEnd`
frameBegin :: proc(c: ^ui.Context, index: int, z: i16) -> bool {
    w: ^Win = &state.windows[index]
    if !w.open || w.minimised { return false }
    if w.maximised {
        w.position, w.size = {0, BAR_HEIGHT}, {state.screen.x, state.screen.y - BAR_HEIGHT}
    }
    id: ui.Id = ui.UiId(c, w.title)
    // a press anywhere on it raises it (the rectangle of the last frame)
    rect, found := ui.UiElementRect(c, id)
    if found && c.input.mouse_pressed {
        p: ui.Vec2 = c.input.mouse_position
        if p.x >= rect.x && p.x < rect.x + rect.z && p.y >= rect.y && p.y < rect.y + rect.w { raise(index) }
    }
    ui.ElementOpen(c, {
        id = id,
        layout = {size = {ui.Fixed(w.size.x), ui.Fixed(w.size.y)}, direction = .TOP_TO_BOTTOM},
        floating = {attach_to = .ROOT, parent_point = .LEFT_TOP, element_point = .LEFT_TOP, offset = w.position, z_index = z, capture = true},
        hit = {.BLOCKER},
        draw = {kind = .PANEL},
    })
    title_id: ui.Id = ui.UiId(c, "##title")
    state.ids[ID_TITLE + index] = title_id
    interaction: ui.Interaction = ui.UiInteract(c, title_id)
    input: ^ui.Input = &c.input
    if interaction.double_clicked { maximise(w) }
    if interaction.pressed && (input.mouse_down || input.mouse_released) && !w.maximised {
        if input.mouse_pressed {
            w.grab, w.start = input.mouse_position, w.position
        } else {
            w.position = w.start + (input.mouse_position - w.grab)
            w.position.y = max(w.position.y, BAR_HEIGHT)
        }
    }
    ui.ElementOpen(c, {
        id = title_id,
        layout = {size = {ui.Grow(), ui.Fixed(TITLE_HEIGHT)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(10, 4), gap = 6, align = {y = .CENTER}},
        hit = {.INTERACTIVE, .NO_FOCUS},
        draw = {kind = .MENU_BAR},
    })
    ui.UiIcon(c, ui_default.LucideIcon(w.icon))
    ui.UiLabel(c, w.title)
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fixed(1)}}})
    ui.ElementClose(c)
    if frameButton(c, ID_MINIMISE + index, ui.UiFormat(c, "##minimise%d", index), .MINUS) { w.minimised = true }
    if frameButton(c, ID_MAXIMISE + index, ui.UiFormat(c, "##maximise%d", index), .MINIMIZE_2 if w.maximised else .MAXIMIZE_2) { maximise(w) }
    if frameButton(c, ID_CLOSE + index, ui.UiFormat(c, "##close%d", index), .X) { w.open = false }
    ui.ElementClose(c)
    grip(c, w, "grip.right", .RIGHT_TOP, {ui.Fixed(GRIP), ui.Grow()}, .RESIZE_HORIZONTAL, true, false)
    grip(c, w, "grip.bottom", .LEFT_BOTTOM, {ui.Grow(), ui.Fixed(GRIP)}, .RESIZE_VERTICAL, false, true)
    grip(c, w, "grip.corner", .RIGHT_BOTTOM, {ui.Fixed(14), ui.Fixed(14)}, .RESIZE_DIAGONAL_NWSE, true, true)
    state.ids[ID_GRIP] = ui.UiId(c, "grip.corner")
    return ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Grow()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(14), gap = 10}, clip = {horizontal = true, vertical = true, cut = true}})
}

frameEnd :: proc(c: ^ui.Context) {
    ui.ElementClose(c)      // the body
    ui.ElementClose(c)      // the window
}

// ---- the two windows -----------------------------------------------------------------------------------------------------------------------------------------------

mainWindow :: proc(c: ^ui.Context, z: i16) {
    if !frameBegin(c, MAIN, z) { return }
    defer frameEnd(c)
    ui.UiTitle(c, "One state, two windows", 1.2)
    ui.UiLabelDim(c, "Preferences changes what this window shows: both read the same data.", .WORDS)
    ui.UiLabel(c, ui.UiFormat(c, "Theme: %s", "dark" if state.dark else "light"))
    ui.UiLabel(c, ui.UiFormat(c, "Count: %d", state.count))
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 8}})
    state.ids[ID_INCREMENT] = ui.UiId(c, "Increment")
    if ui.UiButton(c, "Increment") { state.count += 1 }
    state.ids[ID_PREFERENCES] = ui.UiId(c, "Preferences...")
    if ui.UiButton(c, "Preferences...") {
        state.windows[PREFERENCES].open, state.windows[PREFERENCES].minimised = true, false
        raise(PREFERENCES)
    }
    ui.ElementClose(c)
}

preferencesWindow :: proc(c: ^ui.Context, z: i16) {
    if !frameBegin(c, PREFERENCES, z) { return }
    defer frameEnd(c)
    ui.UiTitle(c, "Preferences", 1.2)
    ui.UiSwitch(c, "Dark theme", &state.dark)
    ui.UiLabelDim(c, ui.UiFormat(c, "The count of the main window is %d.", state.count), .WORDS)
    state.ids[ID_CRASH] = ui.UiId(c, "Stop the Clock applet")
    if ui.UiButton(c, "Stop the Clock applet") { state.applets[0].running = false }
}

// ---- the bar ------------------------------------------------------------------------------------------------------------------------------------------------------------

// A slot per applet. An applet that stopped is a slot with a Restart button: the bar and the other slots do not change.
bar :: proc(c: ^ui.Context) {
    ui.ElementOpen(c, {
        layout = {size = {ui.Grow(), ui.Fixed(BAR_HEIGHT)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(12, 0), gap = 12, align = {y = .CENTER}},
        draw = {kind = .MENU_BAR},
    })
    ui.UiTitle(c, "Shell", 1.1)
    for window, i in state.windows {
        if window.open && window.minimised {
            // a minimised window waits in the bar
            if ui.UiButton(c, ui.UiFormat(c, "%s##restore%d", window.title, i), icon = ui_default.LucideIcon(window.icon)) {
                state.windows[i].minimised = false
                raise(i)
            }
        }
    }
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fixed(1)}}})
    ui.ElementClose(c)
    for &applet, i in state.applets {
        ui.ElementOpen(c, {id = ui.UiId(c, ui.UiFormat(c, "##slot%d", i)), layout = {size = {ui.Fit(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 6, align = {y = .CENTER}}})
        ui.UiIcon(c, ui_default.LucideIcon(applet.icon))
        switch {
        case !applet.running:
            ui.UiLabelDim(c, ui.UiFormat(c, "%s stopped", applet.name))
            state.ids[ID_RESTART + i] = ui.UiId(c, ui.UiFormat(c, "Restart##%d", i))
            if ui.UiButton(c, ui.UiFormat(c, "Restart##%d", i), icon = ui_default.LucideIcon(.REFRESH_CW)) { applet.running, applet.starts = true, applet.starts + 1 }
        case i == 0:
            ui.UiLabel(c, ui.UiFormat(c, "%02d:%02d", state.minutes / 60, state.minutes % 60))
        case:
            ui.UiLabelDim(c, applet.name)
        }
        ui.ElementClose(c)
    }
    ui.ElementClose(c)
}

draw :: proc(ctx: ^kit.Context) {
    state.app.painter.theme = ui_default.THEME_DARK if state.dark else ui_default.THEME_LIGHT
    ctx.background = kit.Color(state.app.painter.theme.background)
    state.screen = ctx.screen
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    ui.ElementOpen(c, {layout = {size = {ui.Fixed(ctx.screen.x), ui.Fixed(ctx.screen.y)}, direction = .TOP_TO_BOTTOM}})
    bar(c)
    ui.ElementClose(c)
    // the windows are floating: declared back to front, so the last one is on top
    for entry, z in state.order {
        switch entry {
        case MAIN: mainWindow(c, i16(10 + z))
        case PREFERENCES: preferencesWindow(c, i16(10 + z))
        }
    }
    ui_demo_end(&state.app)
}

// ---- the script ------------------------------------------------------------------------------------------------------------------------------------------------------------

at :: proc(id: ui.Id) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, id)
    target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return found && rect.z > 0
}

script: []kit.Step = {
    kit.Wait(4),
    // the frame: a drag of the title moves the window
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, state.ids[ID_TITLE + MAIN])
        target = {rect.x + 60, rect.y + rect.w * 0.5}
        return found
    }, "the title bar of the first window"),
    kit.MoveAt(&target),
    kit.Wait(2),
    kit.MouseDownStep(),
    kit.Wait(2),
    kit.MoveTo({260, 200}),
    kit.Wait(3),
    kit.MouseUpStep(),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.windows[MAIN].position.x != 120 || state.windows[MAIN].position.y != 110 }, "dragging the title moves the window"),
    // the corner resizes it
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        w: ^Win = &state.windows[MAIN]
        target = {w.position.x + w.size.x - 5, w.position.y + w.size.y - 5}
        return true
    }, "the corner of the window"),
    kit.MoveAt(&target),
    kit.Wait(2),
    kit.MouseDownStep(),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { target = target + {80, 40}; return true }, "the new corner"),
    kit.MoveAt(&target),
    kit.Wait(3),
    kit.MouseUpStep(),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.windows[MAIN].size.x == 500 && state.windows[MAIN].size.y == 340 }, "the corner resizes the window"),
    // a double click on the title maximises, another restores
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, state.ids[ID_TITLE + MAIN])
        target = {rect.x + 120, rect.y + rect.w * 0.5}
        return found
    }, "the title bar again"),
    kit.ClickAt(&target),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.windows[MAIN].maximised && state.windows[MAIN].size.x == state.screen.x }, "a double click on the title maximises"),
    kit.Capture("windows_maximised"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return at(state.ids[ID_MAXIMISE + MAIN]) }, "the maximise button"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.windows[MAIN].maximised && state.windows[MAIN].size.x == 500 }, "the button restores the size it had"),
    // two windows, one state
    kit.Check(proc(ctx: ^kit.Context) -> bool { return at(state.ids[ID_PREFERENCES]) }, "Preferences..."),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.windows[PREFERENCES].open && state.order[1] == PREFERENCES }, "the second window opens in front"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, ui.UiId(&state.app.ctx, "Preferences"))
        target = {rect.x + 100, rect.y + 70}
        return found
    }, "the dark theme switch"),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.dark }, "the theme starts dark"),
    // the Clock applet stops from Preferences and restarts from its slot
    kit.Check(proc(ctx: ^kit.Context) -> bool { return at(state.ids[ID_CRASH]) }, "the button that stops the Clock applet"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.applets[0].running && state.applets[1].running && state.applets[2].running }, "only the Clock applet stopped"),
    kit.Capture("windows_applet_stopped"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return at(state.ids[ID_RESTART]) }, "Restart in the slot of the Clock"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.applets[0].running && state.applets[0].starts == 2 }, "Restart starts the applet again"),
    // close
    kit.Check(proc(ctx: ^kit.Context) -> bool { return at(state.ids[ID_CLOSE + PREFERENCES]) }, "the close button of Preferences"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.windows[PREFERENCES].open && state.windows[MAIN].open }, "close closes one window only"),
    kit.MoveTo({1000, 650}),
    kit.Wait(3),
    kit.Capture("windows_main"),
    kit.Wait(2),
}
