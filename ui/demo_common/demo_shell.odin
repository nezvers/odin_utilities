#+private file
package demo_common

// The desktop shell examples of Baldr (https://github.com/BuLEEto/Baldr, by Lee Fry and the Baldr contributors, zlib License) remade with this library: 15_control_centre
// (tiles: round icon toggles, big sliders whose icon follows the value, a segmented power mode, a page of the Sound tile), 16_launcher (a search field over results that are walked
// with the arrows while the field keeps the focus), 18_dock (icons that grow with the distance of the pointer, a download on one of them, marks under the running ones),
// 13_taskbar (the open windows with raise, minimise, maximise and close, workspaces), 24_desktop (icons that stay where they are put: the app owns the places) and
// 12_applet (a clock with a calendar that opens away from it). Baldr's versions need a Wayland compositor (layer surfaces, foreign toplevels, applet slots): here the
// windows, workspaces and applets are plain data of the demo, the widgets are the same. 31_emoji needs a color emoji font and is not here.

import "core:strings"
import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"
import icons "../../icons"

@(private="package")
demo_shell: kit.Demo = {
    name = "shell",
    init = init,
    draw = draw,
    script = script,
}

TABS: [6]string = {"Control centre", "Launcher", "Dock", "Taskbar", "Desktop", "Clock"}

GRID :: f32(352)
GAP :: f32(10)
UNIT :: (GRID - 3 * GAP) / 4

App :: struct {
    name: string,
    kind: string,
    icon: icons.Icon,
}

APPS: [9]App = {
    {"Terminal", "System", .TERMINAL}, {"Text Editor", "Office", .FILE_TEXT}, {"Files", "System", .FOLDER}, {"Settings", "System", .SETTINGS},
    {"Calendar", "Office", .CALENDAR}, {"Camera", "Media", .CAMERA}, {"Music", "Media", .MUSIC}, {"Mail", "Office", .MAIL}, {"Terminal Settings", "System", .SLIDERS_HORIZONTAL},
}

Window :: struct {
    title: string,
    icon: icons.Icon,
    workspace: int,
    minimised: bool,
    maximised: bool,
    closed: bool,
}

DESKTOP_COLUMNS :: 6
DESKTOP_ROWS :: 3

ID_WIFI :: 0
ID_MORE_SOUND :: 1
ID_BACK :: 2
ID_OUTPUT_1 :: 3
ID_QUERY :: 4
ID_DOCK :: 5                    // 6 of them
ID_WINDOW :: 12                 // 4 windows, 3 buttons each
ID_CELL :: 30                   // the desktop cells
ID_CLOCK :: 50
ID_DAY :: 51
ID_SLOTS :: 64

State :: struct {
    app: UiDemo,
    tab: int,
    ids: [ID_SLOTS]ui.Id,
    // 15_control_centre
    wifi, bluetooth, dnd, night, airplane, record, tunnel, muted: bool,
    volume, brightness: f32,
    power, output, page: int,
    // 16_launcher
    query: [48]u8,
    query_length: int,
    current: int,
    launched: int,
    pinned: [len(APPS)]bool,
    removed: [len(APPS)]bool,
    results: [len(APPS)]int,
    result_count: int,
    result_ids: [len(APPS)]ui.Id,
    result_rects: [len(APPS)]ui.Rect,       // where the rows were in the last frame
    // 18_dock
    dock_always: bool,
    dock_progress: f32,
    dock_box: ui.Rect,              // the area of the dock in the last frame
    dock_near: bool,
    // 13_taskbar
    windows: [4]Window,
    front: int,
    workspace: int,
    // 24_desktop
    cells: [DESKTOP_COLUMNS * DESKTOP_ROWS]int,          // the item in a cell, 1 + its number (0: empty)
    chosen: [8]bool,
    moves: int,
    renamed: int,
    // 12_applet
    minutes: int,
    date: ui.Date,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    state.wifi, state.bluetooth, state.volume, state.brightness, state.power = true, true, 62, 80, 1
    state.launched = -1
    state.windows = {
        {"Terminal - ~/projects/odin/ui/demo_common", .TERMINAL, 0, false, false, false},
        {"Files", .FOLDER, 0, false, false, false},
        {"Notes - a very long title that is cut with an ellipsis past its room", .FILE_TEXT, 1, false, false, false},
        {"Settings", .SETTINGS, 1, true, false, false},
    }
    state.front = 0
    for i in 0 ..< 8 { state.cells[i * 2] = i + 1 }
    state.minutes, state.date = 9 * 60 + 41, {2026, 11, 14}
}

// ---- helpers ------------------------------------------------------------------------------------------------------------------------------------------

lucide :: proc(icon: icons.Icon) -> ui.Icon {
    return ui_default.LucideIcon(icon)
}

stage :: proc(c: ^ui.Context, size: ui.Vec2, layout: ui.Layout) {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Grow()}, direction = .TOP_TO_BOTTOM, align = {x = .CENTER, y = .CENTER}}})
    inner: ui.Layout = layout
    inner.size = {ui.Fixed(size.x), ui.Fixed(size.y)}
    ui.ElementOpen(c, {layout = inner, hit = {.BLOCKER}, draw = {kind = .PANEL}})
}

stageEnd :: proc(c: ^ui.Context) {
    ui.ElementClose(c)
    ui.ElementClose(c)
}

spacer :: proc(c: ^ui.Context) {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fixed(1)}}})
    ui.ElementClose(c)
}

row :: proc(c: ^ui.Context, gap: f32 = 8, size: ui.Size = {}) {
    wanted: ui.Size = size if size != {} else {ui.Grow(), ui.Fit()}
    ui.ElementOpen(c, {layout = {size = wanted, direction = .LEFT_TO_RIGHT, gap = gap, align = {y = .CENTER}}})
}

column :: proc(c: ^ui.Context, gap: f32 = 4, size: ui.Size = {}) {
    wanted: ui.Size = size if size != {} else {ui.Grow(), ui.Fit()}
    ui.ElementOpen(c, {layout = {size = wanted, direction = .TOP_TO_BOTTOM, gap = gap}})
}

// A round button with an icon that is lit while it is on
iconToggle :: proc(c: ^ui.Context, slot: int, name: string, icon: icons.Icon, on: bool, side: f32 = 40) -> (clicked: bool) {
    label: string = ui.UiFormat(c, "##%s", name)
    state.ids[slot] = ui.UiId(c, label)
    ui.UiPushTag(c, "primary" if on else "secondary")
    clicked = ui.UiButton(c, label, {ui.Fixed(side), ui.Fixed(side)}, false, lucide(icon))
    ui.UiPopTag(c)
    return
}

iconButton :: proc(c: ^ui.Context, slot: int, name: string, icon: icons.Icon) -> (clicked: bool) {
    label: string = ui.UiFormat(c, "##%s", name)
    if slot >= 0 { state.ids[slot] = ui.UiId(c, label) }
    ui.UiPushTag(c, "ghost")
    clicked = ui.UiButton(c, label, {}, false, lucide(icon))
    ui.UiPopTag(c)
    return
}

// Something of a kind with a name was drawn in the last frame: `target` is its middle
drawn :: proc(kind: ui.StyleKind, name: string) -> bool {
    for command in ui.UiCommands(&state.app.ctx) {
        info: ui.DrawInfo = command.info
        if command.kind == .DRAW && info.kind == kind && (info.name == name || info.text == name) {
            target = {info.rect.x + info.rect.z * 0.5, info.rect.y + info.rect.w * 0.5}
            return true
        }
    }
    return false
}

center :: proc(slot: int) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, state.ids[slot])
    target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return found && rect.z > 0
}

target: ui.Vec2

// ---- 15_control_centre -------------------------------------------------------------------------------------------------------------------------------

tile :: proc(c: ^ui.Context, width: f32, height: f32, direction: ui.LayoutDirection, gap: f32 = 8, centered: bool = false) {
    ui.ElementOpen(c, {
        layout = {size = {ui.Fixed(width), height > 0 ? ui.Fixed(height) : ui.Fit()}, direction = direction, padding = ui.PaddingAll(10), gap = gap, align = {x = .CENTER if centered else .LEFT, y = .CENTER}},
        draw = {kind = .PANEL},
    })
}

wideTile :: proc(c: ^ui.Context, slot: int, name: string, icon: icons.Icon, on: ^bool, detail: string) {
    tile(c, 2 * UNIT + GAP, 60, .LEFT_TO_RIGHT)
    if iconToggle(c, slot, name, icon, on^) { on^ = !on^ }
    column(c, 0, {ui.Grow(), ui.Fit()})
    ui.UiLabel(c, name)
    ui.UiLabelDim(c, detail)
    ui.ElementClose(c)
    iconButton(c, -1, ui.UiFormat(c, "%s settings", name), .CHEVRON_RIGHT)
    ui.ElementClose(c)
}

squareTile :: proc(c: ^ui.Context, slot: int, name: string, icon: icons.Icon, on: ^bool) {
    tile(c, UNIT, 82, .TOP_TO_BOTTOM, 4, true)
    if iconToggle(c, slot, name, icon, on^) { on^ = !on^ }
    ui.UiLabelDim(c, name, .WORDS)
    ui.ElementClose(c)
}

controlCentre :: proc(c: ^ui.Context) {
    stage(c, {GRID + 48, 520}, {direction = .TOP_TO_BOTTOM, gap = GAP, padding = ui.PaddingAll(24), align = {x = .CENTER}})
    defer stageEnd(c)
    if state.page == 1 {
        row(c, 4)
        if iconButton(c, ID_BACK, "Back", .ARROW_LEFT) { state.page = 0 }
        ui.UiTitle(c, "Sound", 1.3)
        ui.ElementClose(c)
        outputs: [2]struct { name, detail: string, icon: icons.Icon } = {{"Speakers", "Built-in audio", .VOLUME_2}, {"Headphones", "Bluetooth, 80 %", .HEADPHONES}}
        for output, i in outputs {
            name: string = ui.UiFormat(c, "%s - %s##output%d", output.name, output.detail, i)
            if i == 1 { state.ids[ID_OUTPUT_1] = ui.UiId(c, name) }
            if ui.UiSelectable(c, name, state.output == i, {ui.Grow(), {}}) { state.output = i }
        }
        ui.UiSwitch(c, "Office tunnel", &state.tunnel)
        return
    }
    row(c, GAP)
    wideTile(c, ID_WIFI, "Wi-Fi", .WIFI, &state.wifi, "Studio 5G" if state.wifi else "Off")
    wideTile(c, ID_WIFI + 20, "Bluetooth", .BLUETOOTH, &state.bluetooth, "2 connected" if state.bluetooth else "Off")
    ui.ElementClose(c)
    row(c, GAP)
    squareTile(c, ID_WIFI + 21, "Do Not Disturb", .MOON_STAR, &state.dnd)
    squareTile(c, ID_WIFI + 22, "Night light", .SUN_MOON, &state.night)
    squareTile(c, ID_WIFI + 23, "Airplane", .PLANE, &state.airplane)
    squareTile(c, ID_WIFI + 24, "Record", .CIRCLE_DOT, &state.record)
    ui.ElementClose(c)
    // the sound tile: the icon follows the value and mutes, an arrow opens its page
    tile(c, GRID, 0, .TOP_TO_BOTTOM)
    row(c, 8)
    ui.UiLabel(c, "Sound")
    spacer(c)
    if iconButton(c, ID_MORE_SOUND, "Sound output", .CHEVRON_RIGHT) { state.page = 1 }
    ui.ElementClose(c)
    row(c, 8)
    volume_icon: icons.Icon = .VOLUME_X if state.volume == 0 || state.muted else .VOLUME_1 if state.volume < 50 else .VOLUME_2
    if iconButton(c, ID_WIFI + 25, "Mute", volume_icon) { state.muted = !state.muted }
    ui.UiSlider(c, "Sound##level", &state.volume, 0, 100, {ui.Grow(), {}}, "%.0f %%")
    ui.ElementClose(c)
    ui.ElementClose(c)
    tile(c, GRID, 0, .TOP_TO_BOTTOM)
    ui.UiLabel(c, "Brightness")
    row(c, 8)
    ui.UiIcon(c, lucide(.SUN_DIM if state.brightness < 50 else .SUN))
    ui.UiSlider(c, "Brightness##level", &state.brightness, 0, 100, {ui.Grow(), {}}, "%.0f %%")
    ui.ElementClose(c)
    ui.ElementClose(c)
    tile(c, GRID, 0, .TOP_TO_BOTTOM)
    ui.UiLabel(c, "76% - 2 h 40 min left")
    ui.UiSegmented(c, "Power mode", {"Saver", "Balanced", "Performance"}, &state.power)
    ui.ElementClose(c)
}

// ---- 16_launcher ---------------------------------------------------------------------------------------------------------------------------------------

launcherFilter :: proc() {
    query: string = strings.to_lower(string(state.query[:state.query_length]), context.temp_allocator)
    state.result_count = 0
    // the pinned first, then the rest in order
    for pass in 0 ..< 2 {
        for app, i in APPS {
            if state.removed[i] || state.pinned[i] != (pass == 0) { continue }
            if query != "" && !strings.contains(strings.to_lower(app.name, context.temp_allocator), query) { continue }
            state.results[state.result_count] = i
            state.result_count += 1
        }
    }
    state.current = clamp(state.current, 0, max(state.result_count - 1, 0))
}

launcher :: proc(c: ^ui.Context, input: ^kit.Input) {
    stage(c, {480, 460}, {direction = .TOP_TO_BOTTOM, gap = 10, padding = ui.PaddingAll(20)})
    defer stageEnd(c)
    state.ids[ID_QUERY] = ui.UiId(c, "Search##query")
    changed, _ := ui.UiTextField(c, "Search##query", state.query[:], &state.query_length, {ui.Grow(), {}})
    ui.UiNavBlock(c, .UP)
    ui.UiNavBlock(c, .DOWN)
    if changed { state.current = 0 }
    launcherFilter()
    // the pointer resting on a row makes it current (the rectangles are the ones of the last frame)
    if input.mouse_delta != {} {
        for i in 0 ..< state.result_count {
            rect: ui.Rect = state.result_rects[i]
            point: ui.Vec2 = c.input.mouse_position
            if rect.z > 0 && point.x >= rect.x && point.x < rect.x + rect.z && point.y >= rect.y && point.y < rect.y + rect.w { state.current = i }
        }
    }
    // the arrows walk the results while the field keeps the focus; Enter takes the current one; Ctrl+P pins it; Shift+Delete removes it
    if state.result_count > 0 {
        if .DOWN in input.keys_pressed { state.current = (state.current + 1) % state.result_count }
        if .UP in input.keys_pressed { state.current = (state.current + state.result_count - 1) % state.result_count }
        item: int = state.results[state.current]
        if .ENTER in input.keys_pressed { state.launched = item }
        if kit.CtrlDown(input) && .P in input.keys_pressed {
            state.pinned[item] = !state.pinned[item]
            state.current = 0                           // a pinned result goes first and the current one goes with it
        }
        if kit.ShiftDown(input) && .DELETE in input.keys_pressed { state.removed[item] = true }
    }
    ui.UiSeparator(c)
    if state.result_count == 0 { ui.UiLabelDim(c, "Nothing matches") }
    state.result_rects = {}
    for i in 0 ..< state.result_count {
        item: int = state.results[i]
        app: App = APPS[item]
        label: string = ui.UiFormat(c, "%s%s##result%d", "* " if state.pinned[item] else "", app.name, item)
        state.result_ids[i] = ui.UiId(c, label)
        row(c, 8)
        ui.UiIcon(c, lucide(app.icon))
        if ui.UiSelectable(c, label, state.current == i, {ui.Grow(), {}}) { state.launched = item }
        ui.UiBadge(c, app.kind)
        ui.ElementClose(c)
    }
    spacer(c)
    if state.launched >= 0 { ui.UiLabel(c, ui.UiFormat(c, "Launched %s", APPS[state.launched].name)) }
    ui.UiLabelDim(c, "Up and Down walk the list, Enter opens, Ctrl+P pins, Shift+Delete removes.", .WORDS)
}

// ---- 18_dock ---------------------------------------------------------------------------------------------------------------------------------------------

DOCK_ICONS: [6]icons.Icon = {.FOLDER, .TERMINAL, .MAIL, .CAMERA, .DOWNLOAD, .SETTINGS}
DOCK_RUNNING: [6]bool = {true, true, false, false, true, false}
DOCK_BASE :: f32(44)
DOCK_SPACING :: f32(8)

// How big the icon `index` is for a pointer at `x`: its own size at rest, up to 1.8 times as big right under the pointer, falling off over 120 pixels
dockSize :: proc(box: ui.Rect, index: int, x: f32, near: bool) -> f32 {
    if !near { return DOCK_BASE }
    total: f32 = f32(len(DOCK_ICONS)) * (DOCK_BASE + DOCK_SPACING) - DOCK_SPACING
    middle: f32 = box.x + (box.z - total) * 0.5 + f32(index) * (DOCK_BASE + DOCK_SPACING) + DOCK_BASE * 0.5
    return DOCK_BASE * (1 + 0.8 * max(0, 1 - abs(x - middle) / 120))
}

dock :: proc(c: ^ui.Context, dt: f32) {
    stage(c, {640, 400}, {direction = .TOP_TO_BOTTOM, gap = 10, padding = ui.PaddingAll(20), align = {x = .CENTER}})
    defer stageEnd(c)
    ui.UiTitle(c, "Dock", 1.3)
    ui.UiLabelDim(c, "Move the pointer to the bottom of the box: the dock shows, its icons grow with the distance of the pointer.", .WORDS)
    ui.UiSwitch(c, "Always visible", &state.dock_always)
    spacer(c)
    box: ui.Rect = state.dock_box
    pointer: ui.Vec2 = c.input.mouse_position
    near: bool = box.z > 0 && pointer.x >= box.x && pointer.x <= box.x + box.z && pointer.y >= box.y && pointer.y <= box.y + box.w
    state.dock_near = near
    state.ids[ID_DOCK + 7] = ui.UiId(c, "##dockbox")
    shown: f32 = ui.UiAnimate(c, ui.UiId(c, "##dockshown"), 1 if near || state.dock_always else 0)
    state.dock_progress += dt * 0.1
    if state.dock_progress > 1 { state.dock_progress = 0 }
    ui.ElementOpen(c, {id = state.ids[ID_DOCK + 7], layout = {size = {ui.Grow(), ui.Fixed(DOCK_BASE * 1.8 + 40)}, direction = .TOP_TO_BOTTOM, align = {x = .CENTER, y = .BOTTOM}}})
    if shown > 0.05 {
        ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = DOCK_SPACING, padding = ui.PaddingAll(8), align = {y = .BOTTOM}}, draw = {kind = .PANEL}})
        for icon, i in DOCK_ICONS {
            side: f32 = dockSize(box, i, pointer.x, near)
            ui.ElementOpen(c, {layout = {size = {ui.Fixed(side), ui.Fit()}, direction = .TOP_TO_BOTTOM, gap = 3, align = {x = .CENTER}}})
            state.ids[ID_DOCK + i] = ui.UiId(c, ui.UiFormat(c, "##dock%d", i))
            ui.ElementOpen(c, {id = state.ids[ID_DOCK + i], layout = {size = {ui.Fixed(side), ui.Fixed(side)}, align = {x = .CENTER, y = .CENTER}}, draw = {kind = .PANEL}})
            ui.UiIcon(c, lucide(icon), side * 0.55)
            ui.ElementClose(c)
            if i == 4 {
                // the download: a thin bar under its icon
                ui.UiPushTag(c, "thin")
                ui.UiProgress(c, "##download", state.dock_progress, 0, 1, {ui.Fixed(side * 0.8), {}})
                ui.UiPopTag(c)
            } else if DOCK_RUNNING[i] {
                ui.ElementOpen(c, {layout = {size = {ui.Fixed(5), ui.Fixed(5)}}, draw = {kind = .FILL, color = {160, 170, 190, 255}}})
                ui.ElementClose(c)
            }
            ui.ElementClose(c)
        }
        ui.ElementClose(c)
    } else {
        ui.ElementOpen(c, {layout = {size = {ui.Fixed(180), ui.Fixed(4)}}, draw = {kind = .FILL, color = {120, 130, 150, 200}}})
        ui.ElementClose(c)
    }
    ui.ElementClose(c)
}

// ---- 13_taskbar ------------------------------------------------------------------------------------------------------------------------------------------

taskbar :: proc(c: ^ui.Context) {
    stage(c, {640, 400}, {direction = .TOP_TO_BOTTOM, gap = 8, padding = ui.PaddingAll(20)})
    defer stageEnd(c)
    ui.UiTitle(c, "Taskbar", 1.3)
    ui.UiSegmented(c, "Workspaces", {"Workspace 1", "Workspace 2"}, &state.workspace)
    ui.UiSeparator(c)
    count: int
    for &window, i in state.windows {
        if window.closed || window.workspace != state.workspace { continue }
        count += 1
        front: bool = state.front == i && !window.minimised
        row(c, 6)
        // the icon of the app, faded while the window is minimised
        ui.UiIcon(c, lucide(window.icon), 0, {128, 134, 148, 130} if window.minimised else {})
        // the title is cut with an ellipsis past its room; a click on it raises the window
        title_id: ui.Id = ui.UiId(c, ui.UiFormat(c, "##title%d", i))
        state.ids[ID_WINDOW + i * 3] = title_id
        if ui.UiInteract(c, title_id).clicked {
            state.front = i
            window.minimised = false
        }
        ui.ElementOpen(c, {id = title_id, layout = {size = {ui.Fixed(330), ui.Fit()}}, hit = {.INTERACTIVE, .NO_FOCUS}})
        if front { ui.UiPushTag(c, "strong") }
        ui.UiLabel(c, window.title, .TRUNCATE)
        if front { ui.UiPopTag(c) }
        ui.ElementClose(c)
        // a bar under the window in front, a dot for the others
        ui.ElementOpen(c, {layout = {size = {ui.Fixed(14), ui.Fixed(3)}}, draw = {kind = .FILL, color = {110, 160, 255, 255} if front else {120, 128, 145, 255} if !window.minimised else {0, 0, 0, 0}}})
        ui.ElementClose(c)
        spacer(c)
        if iconButton(c, ID_WINDOW + i * 3 + 1, ui.UiFormat(c, "minimise%d", i), .MINIMIZE_2) {
            window.minimised = true
            if state.front == i { state.front = -1 }
        }
        if iconButton(c, ID_WINDOW + i * 3 + 2, ui.UiFormat(c, "maximise%d", i), .MINIMIZE_2 if window.maximised else .MAXIMIZE_2) { window.maximised = !window.maximised }
        if iconButton(c, -1, ui.UiFormat(c, "close%d", i), .X) { window.closed = true }
        ui.ElementClose(c)
    }
    if count == 0 { ui.UiLabelDim(c, "No windows on this workspace") }
    spacer(c)
    ui.UiLabelDim(c, ui.UiFormat(c, "%d windows here. Baldr lists them from the compositor; here they are data of the demo.", count), .WORDS)
}

// ---- 24_desktop --------------------------------------------------------------------------------------------------------------------------------------------

DESKTOP_ITEMS: [8]struct { name: string, icon: icons.Icon } = {
    {"Home", .HOUSE}, {"Documents", .FILE_TEXT}, {"Pictures", .IMAGE}, {"Music", .MUSIC}, {"Trash", .TRASH}, {"Notes", .PENCIL}, {"Projects", .FOLDER}, {"Archive", .ARCHIVE},
}

desktop :: proc(c: ^ui.Context, input: ^kit.Input) {
    stage(c, {740, 360}, {direction = .TOP_TO_BOTTOM, gap = 8, padding = ui.PaddingAll(16)})
    defer stageEnd(c)
    ui.UiLabelDim(c, "Icons stay where they are put: drag one to an empty place. Click selects, Ctrl + click adds.", .WORDS)
    for r in 0 ..< DESKTOP_ROWS {
        row(c, 8, {ui.Grow(), ui.Fixed(84)})
        for column in 0 ..< DESKTOP_COLUMNS {
            cell: int = r * DESKTOP_COLUMNS + column
            ui.ElementOpen(c, {layout = {size = {ui.Fixed(110), ui.Fixed(84)}, align = {x = .CENTER, y = .CENTER}}})
            item: int = state.cells[cell] - 1
            if item >= 0 {
                name: string = ui.UiFormat(c, "%s##item%d", DESKTOP_ITEMS[item].name, item)
                state.ids[ID_CELL + cell] = ui.UiId(c, name)
                if ui.UiChip(c, name, state.chosen[item], lucide(DESKTOP_ITEMS[item].icon)) {
                    if !kit.CtrlDown(input) { state.chosen = {} }
                    state.chosen[item] = !state.chosen[item] if kit.CtrlDown(input) else true
                }
                value: int = item
                ui.UiDragSourceValue(c, "icon", &value)
            } else {
                id: ui.Id = ui.UiId(c, ui.UiFormat(c, "##cell%d", cell))
                state.ids[ID_CELL + cell] = id
                ui.UiInteract(c, id)
                ui.ElementOpen(c, {id = id, layout = {size = {ui.Fixed(100), ui.Fixed(40)}}, hit = {.INTERACTIVE, .NO_FOCUS}})
                ui.ElementClose(c)
                payload, dropped := ui.UiDropTarget(c, "icon")
                if dropped && len(payload) >= size_of(int) {
                    moved: int = (cast(^int)raw_data(payload))^
                    for &place in state.cells { if place == moved + 1 { place = 0 } }
                    state.cells[cell] = moved + 1
                    state.moves += 1
                }
            }
            ui.ElementClose(c)
        }
        ui.ElementClose(c)
    }
    spacer(c)
    ui.UiLabelDim(c, ui.UiFormat(c, "Moved %d times", state.moves))
}

// ---- 12_applet ------------------------------------------------------------------------------------------------------------------------------------------------

clock :: proc(c: ^ui.Context) {
    stage(c, {520, 300}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(20)})
    defer stageEnd(c)
    ui.UiTitle(c, "Clock applet", 1.3)
    ui.UiLabelDim(c, "A small program a shell shows inside its bar: the time and the date on one line; its calendar opens away from the bar.", .WORDS)
    row(c, 12, {ui.Grow(), ui.Fixed(44)})
    ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 10, padding = ui.PaddingXY(14, 6), align = {y = .CENTER}}, draw = {kind = .PANEL}})
    ui.UiIcon(c, lucide(.CLOCK))
    ui.UiLabel(c, ui.UiFormat(c, "%02d:%02d", state.minutes / 60, state.minutes % 60))
    state.ids[ID_DAY] = ui.UiId(c, "##calendar")
    ui.UiDateField(c, "##calendar", &state.date, {ui.Fixed(150), {}})
    ui.ElementClose(c)
    ui.ElementClose(c)
    ui.UiLabelDim(c, ui.UiFormat(c, "%04d-%02d-%02d", state.date.year, state.date.month, state.date.day))
}

// ---- the page -----------------------------------------------------------------------------------------------------------------------------------------------------

draw :: proc(ctx: ^kit.Context) {
    state.app.painter.theme = ui_default.THEME_DARK
    ctx.background = kit.Color(state.app.painter.theme.background)
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    metrics: ^ui.Metrics = &c.style.metrics
    ui.ElementOpen(c, {layout = {size = {ui.Fixed(ctx.screen.x), ui.Fixed(ctx.screen.y)}, direction = .TOP_TO_BOTTOM}})
    ui.ElementOpen(c, {
        layout = {size = {ui.Grow(), ui.Fixed(metrics.control_height + 24)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(16, 0), gap = 16, align = {y = .CENTER}},
        draw = {kind = .MENU_BAR},
    })
    ui.UiTitle(c, "Desktop shell", 1.3)
    ui.UiTabBar(c, "##shell", TABS[:], &state.tab)
    ui.ElementClose(c)
    switch state.tab {
    case 0: controlCentre(c)
    case 1: launcher(c, &ctx.input)
    case 2: dock(c, ctx.delta_time)
    case 3: taskbar(c)
    case 4: desktop(c, &ctx.input)
    case 5: clock(c)
    }
    ui.ElementClose(c)
    ui_demo_end(&state.app)
    // where things were in this frame, for the pointer logic of the next one
    state.dock_box, _ = ui.UiElementRect(c, state.ids[ID_DOCK + 7])
    for i in 0 ..< state.result_count { state.result_rects[i], _ = ui.UiElementRect(c, state.result_ids[i]) }
}

// ---- the script -----------------------------------------------------------------------------------------------------------------------------------------------

tab :: proc(index: u32) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, ui.IdFromIndex(index, ui.UiId(&state.app.ctx, "##shell")))
    target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return found && rect.z > 0
}

target2: ui.Vec2

script: []kit.Step = {
    kit.Wait(4),
    // the control centre: a toggle, the sound slider's icon, the Sound page
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_WIFI) }, "the Wi-Fi toggle"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.wifi }, "the toggle turns Wi-Fi off"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_WIFI + 25) }, "the mute icon of the Sound tile"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.muted }, "the icon of the slider mutes"),
    kit.MoveTo({1000, 700}),
    kit.Wait(3),
    kit.Capture("shell_control_centre"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_MORE_SOUND) }, "the arrow of the Sound tile"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.page == 1 && center(ID_OUTPUT_1) }, "the Sound page lists the outputs"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.output == 1 }, "an output is chosen"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_BACK) }, "Back"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.page == 0 }, "back on the tiles"),

    // the launcher: type, walk with the arrows while the field keeps the focus, pin, open
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(1) }, "the Launcher tab"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_QUERY) }, "the search field"),
    kit.ClickAt(&target),
    kit.MoveTo({1000, 700}),
    kit.Wait(2),
    kit.Type("te"),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.result_count == 3 && APPS[state.results[0]].name == "Terminal" }, "the results are the apps that contain the text"),
    kit.Tap(.DOWN),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.current == 1 }, "Down walks to the next result"),
    kit.Tap(.DOWN),
    kit.Wait(2),
    kit.Tap(.UP),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.current == 1 && ui.UiIsFocused(&state.app.ctx, state.ids[ID_QUERY]) }, "the field keeps the focus while the arrows walk"),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Tap(.P),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.pinned[1] && state.results[0] == 1 }, "Ctrl+P pins the result: it goes first"),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.launched == state.results[0] }, "Enter opens the current result"),
    kit.Capture("shell_launcher"),
    kit.Wait(2),

    // the dock: the icons grow under the pointer
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(2) }, "the Dock tab"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 300}),
    kit.Wait(8),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.dock_near }, "the pointer is away from the dock"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        box: ui.Rect = state.dock_box
        target = {box.x + box.z * 0.5, box.y + box.w - 40}
        return box.z > 0
    }, "the dock area"),
    kit.MoveAt(&target),
    kit.Wait(12),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !state.dock_near || !center(ID_DOCK + 2) { return false }
        rect, _ := ui.UiElementRect(&state.app.ctx, state.ids[ID_DOCK + 2])
        far, _ := ui.UiElementRect(&state.app.ctx, state.ids[ID_DOCK + 5])
        return rect.z > DOCK_BASE * 1.4 && far.z < rect.z
    }, "the icon under the pointer is bigger than the one far from it"),
    kit.Capture("shell_dock"),
    kit.Wait(2),

    // the taskbar: minimise, raise, close, the other workspace
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(3) }, "the Taskbar tab"),
    kit.ClickAt(&target),
    kit.MoveTo({1000, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_WINDOW + 1) }, "minimise of the first window"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.windows[0].minimised && state.front == -1 }, "the window is minimised and nothing is in front"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_WINDOW + 3) }, "the title of the second window"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.front == 1 }, "a click on a title raises the window"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return drawn(.SEGMENT, "Workspace 2") }, "the workspaces"),
    kit.ClickAt(&target),
    kit.MoveTo({1000, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.workspace == 1 && center(ID_WINDOW + 6) && !center(ID_WINDOW + 0) }, "the other workspace shows its own windows"),
    kit.Capture("shell_taskbar"),
    kit.Wait(2),

    // the desktop: an icon dragged to an empty place stays there
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(4) }, "the Desktop tab"),
    kit.ClickAt(&target),
    kit.MoveTo({1000, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_CELL + 0) }, "the icon in the first cell"),
    kit.MoveAt(&target),
    kit.Wait(2),
    kit.MouseDownStep(),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !center(ID_CELL + 1) { return false }
        target = target + {0, 0}
        return true
    }, "the empty cell next to it"),
    kit.MoveAt(&target),
    kit.Wait(3),
    kit.MouseUpStep(),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.cells[0] == 0 && state.cells[1] == 1 && state.moves == 1 }, "the icon is in the cell it was dropped on"),
    kit.Capture("shell_desktop"),
    kit.Wait(2),

    // the clock applet: its calendar opens away from it
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(5) }, "the Clock tab"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_DAY) }, "the date field"),
    kit.ClickAt(&target),
    kit.MoveTo({1000, 700}),
    kit.Wait(4),
    kit.Capture("shell_clock"),
    kit.Wait(2),
}
