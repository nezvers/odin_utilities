#+private file
package demo_common

// Docking: panels in tabs inside of splits, moved by dragging their tabs. The dock is plain data (ui.Dock); the demo only says what is in each panel.
// A tab let go outside of the dock becomes a window; its title docks it again. The script drags a tab to the edge of another panel (it splits it), drags a handle and moves a tab into the middle of a panel (it becomes a tab there).

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_dock: kit.Demo = {
    name = "dock",
    init = init,
    draw = draw,
    script = script,
}

state: UiDemo
dock: ui.Dock
scene, assets, properties, console: int
clicks: int

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    ctx.background = {24, 26, 32, 255}
    ui.DockInit(&dock)
    scene, _ = ui.DockPanelAdd(&dock, "Scene")
    assets, _ = ui.DockPanelAdd(&dock, "Assets")
    properties, _ = ui.DockPanelAdd(&dock, "Properties")
    console, _ = ui.DockPanelAdd(&dock, "Console")
    ui.DockPanelSetClosable(&dock, console)
    ui.DockPanelDock(&dock, properties, ui.DockLeafOf(&dock, scene), .RIGHT)
    ui.DockPanelDock(&dock, console, ui.DockLeafOf(&dock, scene), .BOTTOM)
    dock.nodes[ui.DockLeafOf(&dock, scene)].active = 0
    clicks = 0
}

content :: proc(c: ^ui.Context, dock: ^ui.Dock, panel: int, user: rawptr) {
    switch panel {
    case scene:
        ui.UiLabel(c, "A scene")
        if ui.UiButton(c, "Click me") { clicks += 1 }
        ui.UiLabelf(c, "clicked %d times", clicks)
    case assets:
        for i in 0 ..< 4 { ui.UiLabelf(c, "asset_%d.png", i) }
    case properties:
        ui.UiLabel(c, "Properties")
        ui.UiLabel(c, "name: Player")
    case console:
        ui.UiLabel(c, "> ready")
    }
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx
    if ui.UiWindowResizable(c, "Workspace", nil, nil, {300, 200}, initial_position = {40, 40}, initial_size = {640, 420}) {
        ui.UiDock(c, "dock", &dock, content)
    }
    ui_demo_end(&state)
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Capture("dock_start"),
    // the Assets tab (112..180, 78..106) to the right edge of the Scene panel (50..360, 78..264): the panel is split, Assets gets the right half
    kit.MoveTo({146, 92}),
    kit.Wait(3),
    kit.Drag({146, 92}, {350, 180}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return ui.DockCheck(&dock) && ui.DockLeafOf(&dock, assets) != ui.DockLeafOf(&dock, scene)
    }, "the edge made a split of its own for the dragged panel"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        parent: int = dock.nodes[ui.DockLeafOf(&dock, scene)].parent
        return parent >= 0 && dock.nodes[parent].direction == .HORIZONTAL && dock.nodes[parent].second == ui.DockLeafOf(&dock, assets)
    }, "to the right of Scene, side by side"),
    // Console (the tab at 50..126, 270..298) into the middle of Properties (366..670, 78..450): a tab there
    kit.MoveTo({88, 284}),
    kit.Wait(3),
    kit.Drag({88, 284}, {518, 264}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return ui.DockCheck(&dock) && ui.DockLeafOf(&dock, console) == ui.DockLeafOf(&dock, properties)
    }, "the middle made a tab"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return dock.nodes[ui.DockLeafOf(&dock, console)].active == 1 }, "the dropped tab is the shown one"),
    kit.Wait(3),
    kit.Capture("dock_moved"),
    // the Console tab (468..544, 78..106) onto the left half of the Properties tab (366..466): it goes first
    kit.MoveTo({506, 92}),
    kit.Wait(3),
    kit.Drag({506, 92}, {372, 92}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        leaf: ^ui.DockNode = &dock.nodes[ui.DockLeafOf(&dock, console)]
        return ui.DockCheck(&dock) && int(leaf.panels[0]) == console && int(leaf.panels[1]) == properties
    }, "dropped on the bar: the tab took the place before Properties"),
    kit.Wait(3),
    kit.Capture("dock_reordered"),
    // its close button (the tab is 366..442 now, the button right after it)
    kit.MoveTo({454, 92}),
    kit.Wait(3),
    kit.Click({454, 92}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !ui.DockPanelIsOpen(&dock, console) && ui.DockCheck(&dock) }, "the close button closed the panel"),
    // the Assets tab (212..275, 78..106) let go outside of the dock: a window of its own
    kit.MoveTo({243, 92}),
    kit.Wait(3),
    kit.Drag({243, 92}, {800, 300}, 12),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.DockPanelIsFloating(&dock, assets) && ui.DockCheck(&dock) }, "let go outside the dock the tab became a window"),
    kit.Wait(3),
    kit.Capture("dock_floating"),
    // the bottom right corner of the window (776, 288, 320 x 240): 60 right and 40 down makes it bigger
    kit.MoveTo({1090, 522}),
    kit.Wait(3),
    kit.Drag({1090, 522}, {1150, 562}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return dock.panels[assets].float_size == ui.Vec2{380, 280} }, "the corner resized the window"),
    kit.Capture("dock_resized"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
