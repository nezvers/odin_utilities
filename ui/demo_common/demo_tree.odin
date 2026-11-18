#+private file
package demo_common

// A tree of folders that are read when they are opened: a folder is a branch without children, and when the tree says it was opened (`view.toggled`) the program adds what it holds.
// Click an arrow to open or close, click a name to select, left and right close and open (or go to the parent and to the first child), up and down move, Enter or a double click activates.

import "core:fmt"
import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_tree: kit.Demo = {
    name = "tree",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    tree: ui.Tree,
    view: ui.TreeView,
    log: [120]u8,
    log_length: int,
}

state: State

FILES: [3]string = {"notes.txt", "mix.wav", "cover.png"}

load :: proc(parent: ui.TreeHandle) {
    node: ^ui.TreeNode = ui.TreeGet(&state.tree, parent)
    name: string = ui.TreeName(node)
    if name == "assets" {
        ui.TreeAdd(&state.tree, parent, "textures", branch = true)
        ui.TreeAdd(&state.tree, parent, "sounds", branch = true)
    }
    for file in FILES { ui.TreeAdd(&state.tree, parent, file) }
    state.log_length = len(fmt.bprintf(state.log[:], "read %s: %d entries", name, node.child_count))
}

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    ctx.background = {24, 26, 32, 255}
    ui.TreeInit(&state.tree)
    ui.TreeViewInit(&state.view)
    ui.TreeAdd(&state.tree, {}, "assets", branch = true)
    src, _ := ui.TreeAdd(&state.tree, {}, "src", branch = true)
    ui.TreeAdd(&state.tree, src, "main.odin")
    ui.TreeAdd(&state.tree, src, "util.odin")
    ui.TreeAdd(&state.tree, {}, "README.md")
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "tree demo", {size = {ui.Fixed(340), ui.Fit()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        ui.UiTree(c, "Files", &state.tree, &state.view, {ui.Fixed(320), ui.Fixed(300)}, 24)
        if toggled := ui.TreeGet(&state.tree, state.view.toggled); toggled != nil && toggled.expanded && toggled.branch && toggled.child_count == 0 {
            load(state.view.toggled)
        }
        ui.UiLabel(c, string(state.log[:state.log_length]))
    }
    ui_demo_end(&state.app)
}

nameOf :: proc(handle: ui.TreeHandle) -> string {
    node: ^ui.TreeNode = ui.TreeGet(&state.tree, handle)
    return ui.TreeName(node) if node != nil else ""
}

// the tree is at (10, 10), rows 24 high; the arrow of a node at depth d is 4 + 16 * d pixels from the left, 16 wide
script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.view.row_count == 3 }, "three rows: everything is closed"),
    kit.Click({22, 22}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.view.row_count == 8 && state.log_length > 0 }, "opening a folder read it: five more rows"),
    kit.Click({38, 46}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.view.row_count == 11 }, "and a folder inside of it"),
    kit.Click({150, 10 + 24 * 3 + 12}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return nameOf(state.view.selected) == "mix.wav" }, "a click on a name selected the file"),
    kit.Tap(.LEFT),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return nameOf(state.view.selected) == "textures" }, "left went to the parent folder"),
    kit.Tap(.LEFT),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.view.row_count == 8 }, "and closed it"),
    kit.Tap(.DOWN),
    kit.Wait(3),
    kit.Capture("tree"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
