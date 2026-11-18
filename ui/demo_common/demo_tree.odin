#+private file
package demo_common

// A tree of folders that are read when they are opened: a folder is a branch without children, and when the tree says it was opened (`view.toggled`) the program adds what it holds.
// Click an arrow to open or close, click a name to select, left and right close and open (or go to the parent and to the first child), up and down move, Enter or a double click activates.

import "core:fmt"
import "core:strings"
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
    renamed_to: string,                     // the name after the last rename (a constant string in the demo)
    moved: ui.TreeHandle,
}

state: State

FILES: [3]string = {"notes.txt", "mix.wav", "cover.png"}

// the icon of a file by its extension
iconOf :: proc(file: string) -> ui.Icon {
    switch {
    case strings.has_suffix(file, ".txt"), strings.has_suffix(file, ".md"): return .TEXT
    case strings.has_suffix(file, ".wav"): return .AUDIO
    case strings.has_suffix(file, ".png"): return .IMAGE
    }
    return .FILE
}

// a row of the program: the usual row, and after it how many children a folder has
row :: proc(ctx: ^ui.Context, tree: ^ui.Tree, view: ^ui.TreeView, node: ^ui.TreeNode, row: ui.TreeRow, user: rawptr) {
    ui.UiTreeRowDefault(ctx, tree, view, node, row)
    if node.child_count > 0 { ui.UiLabelColored(ctx, ui.UiFormat(ctx, "  %d", node.child_count), {140, 144, 160, 255}) }
}

load :: proc(parent: ui.TreeHandle) {
    node: ^ui.TreeNode = ui.TreeGet(&state.tree, parent)
    name: string = ui.TreeName(node)
    if name == "assets" {
        ui.TreeAdd(&state.tree, parent, "textures", branch = true, icon = .FOLDER)
        ui.TreeAdd(&state.tree, parent, "sounds", branch = true, icon = .FOLDER)
    }
    for file in FILES { ui.TreeAdd(&state.tree, parent, file, icon = iconOf(file)) }
    state.log_length = len(fmt.bprintf(state.log[:], "read %s: %d entries", name, node.child_count))
}

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    ctx.background = {24, 26, 32, 255}
    ui.TreeInit(&state.tree)
    ui.TreeViewInit(&state.view)
    ui.TreeAdd(&state.tree, {}, "assets", branch = true, icon = .FOLDER)
    src, _ := ui.TreeAdd(&state.tree, {}, "src", branch = true, icon = .FOLDER)
    ui.TreeAdd(&state.tree, src, "main.odin", icon = .FILE)
    ui.TreeAdd(&state.tree, src, "util.odin", icon = .FILE)
    ui.TreeAdd(&state.tree, {}, "README.md", icon = .TEXT)
    state.view.row = row
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "tree demo", {size = {ui.Fixed(340), ui.Fit()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        ui.UiTree(c, "Files", &state.tree, &state.view, {ui.Fixed(320), ui.Fixed(300)}, 24)
        if toggled := ui.TreeGet(&state.tree, state.view.toggled); toggled != nil && toggled.expanded && toggled.branch && toggled.child_count == 0 {
            load(state.view.toggled)
        }
        if node := ui.TreeGet(&state.tree, state.view.renamed); node != nil { state.log_length = len(fmt.bprintf(state.log[:], "renamed: %s", ui.TreeName(node))) }
        if node := ui.TreeGet(&state.tree, state.view.renamed); node != nil && ui.TreeName(node) == "data" { state.renamed_to = "data" }
        if state.view.moved != {} { state.moved = state.view.moved }
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
    // F2 edits the name of the selected node (the whole name is selected: typing replaces it), Enter keeps it
    kit.Wait(40),                           // long enough after the last click not to be a double click
    kit.Click({150, 22}),
    kit.Wait(3),
    kit.Tap(.F2),
    kit.Wait(3),
    kit.Type("data"),
    kit.Wait(2),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.view.row_count == 8 }, "the Enter that ended the edit did not close the folder"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.renamed_to == "data" && nameOf(ui.TreeHandle(state.view.selected)) == "data" }, "F2, typing and Enter renamed the folder"),
    // a row is dragged onto a folder: README.md goes into it
    kit.Drag({150, 10 + 24 * 7 + 12}, {150, 22}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        readme: ^ui.TreeNode = ui.TreeGet(&state.tree, state.moved)
        return readme != nil && ui.TreeName(readme) == "README.md" && nameOf(readme.parent) == "data" && state.view.row_count == 8
    }, "dragging README.md onto the folder moved it in"),
    kit.Capture("tree_moved"),
    kit.Wait(1),
    // while a row is dragged a line shows where it would go: the top of the row "notes.txt" is before it
    kit.MoveTo({150, 10 + 24 * 7 + 12}),
    kit.Wait(2),
    kit.MouseDownStep(),
    kit.Wait(1),
    kit.MoveTo({150, 10 + 24 * 5}),
    kit.Wait(1),
    kit.MoveTo({150, 10 + 24 * 3 + 3}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.view.dragging && state.view.drop_zone == .BEFORE }, "the pointer is at the top of a file: the drop goes before it"),
    kit.Capture("tree_dropline"),
    kit.Wait(1),
    kit.MouseUpStep(),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        moved: ^ui.TreeNode = ui.TreeGet(&state.tree, state.moved)
        return moved != nil && ui.TreeName(moved) == "src" && nameOf(moved.parent) == "data" && nameOf(moved.next) == "notes.txt"
    }, "src went in before notes.txt"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
