#+private file
package demo_common

// A table of a hundred thousand rows: only the rows in view are declared, so it costs what a table of twenty rows costs. A click on a header sorts (ascending, descending, back to the order of the data),
// the edge of a header is dragged to resize the column, a click selects a row, the keys, the wheel and the scrollbar move through the rows. The program sorts its own list of row numbers when the
// table says the sorting changed; the table only draws the rows it is told to.

import "core:slice"
import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_table: kit.Demo = {
    name = "table",
    init = init,
    draw = draw,
    script = script,
}

ROWS :: 100000

KINDS: [5]string = {"audio", "image", "text", "binary", "folder"}

State :: struct {
    app: UiDemo,
    table: ui.Table,
    order: [ROWS]int,
}

state: State
sorting_column: int
sorting_descending: bool

sizeOf :: proc(row: int) -> int {
    return (row * 7919) % 100000
}

keyOf :: proc(row: int, column: int) -> int {
    switch column {
    case 1: return sizeOf(row)
    case 2: return row % len(KINDS)
    }
    return row
}

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    ctx.background = {24, 26, 32, 255}
    ui.TableInit(&state.table, {{name = "Name", width = 200}, {name = "Size", width = 120}, {name = "Kind", width = 140}, {name = "Path", width = 260}})
    for i in 0 ..< ROWS { state.order[i] = i }
}

sortRows :: proc() {
    sorting_column, sorting_descending = state.table.sort_column, state.table.sort_descending
    if sorting_column == ui.VIRTUAL_NONE {
        for i in 0 ..< ROWS { state.order[i] = i }
        return
    }
    slice.stable_sort_by(state.order[:], proc(a: int, b: int) -> bool {
        key_a, key_b: int = keyOf(a, sorting_column), keyOf(b, sorting_column)
        return key_a > key_b if sorting_descending else key_a < key_b
    })
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "table demo", {size = {ui.Fixed(640), ui.Fit()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        if ui.UiTable(c, "Files", &state.table, ROWS, 24, {ui.Fixed(600), ui.Fixed(300)}) {
            if state.table.sort_changed { sortRows() }
            for row in state.table.list.first ..< state.table.list.last {
                item: int = state.order[row]
                if ui.UiTableRow(c, &state.table, row) {
                    ui.UiTableText(c, &state.table, 0, ui.UiFormat(c, "file_%06d.dat", item))
                    ui.UiTableText(c, &state.table, 1, ui.UiFormat(c, "%d", sizeOf(item)))
                    ui.UiTableText(c, &state.table, 2, KINDS[item % len(KINDS)])
                    ui.UiTableText(c, &state.table, 3, ui.UiFormat(c, "/data/%s/file_%06d.dat", KINDS[item % len(KINDS)], item))
                }
            }
        }
        ui.UiLabelf(c, "%d rows, the table declares %d of them", ROWS, state.table.list.last - state.table.list.first)
    }
    ui_demo_end(&state.app)
}

// the table is at (10, 10): the header 28 high, the rows 24 high from y 38; the columns 200, 120, 140 wide
script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return state.table.list.first == 0 && state.table.list.last > 8 && state.table.list.last < 20
    }, "only the rows in view are declared"),
    kit.Click({240, 24}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return state.table.sort_column == 1 && sizeOf(state.order[0]) <= sizeOf(state.order[1]) && sizeOf(state.order[1]) <= sizeOf(state.order[ROWS - 1])
    }, "a click on Size sorted ascending"),
    kit.Click({240, 24}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return state.table.sort_descending && sizeOf(state.order[0]) >= sizeOf(state.order[1]) && sizeOf(state.order[0]) > sizeOf(state.order[ROWS - 1])
    }, "the second click: descending"),
    kit.Click({240, 24}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.table.sort_column == ui.VIRTUAL_NONE && state.order[0] == 0 && state.order[ROWS - 1] == ROWS - 1 }, "the third: the order of the data"),
    kit.Click({60, 24}),
    kit.Click({60, 24}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.table.sort_descending && state.order[0] == ROWS - 1 }, "Name descending: the last row is first"),
    kit.MoveTo({207, 24}),
    kit.Wait(3),
    kit.Drag({207, 24}, {247, 24}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.table.columns[0].width == 240 }, "the edge of the header made the column 40 pixels wider"),
    kit.Click({60, 38 + 24 * 3 + 6}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.table.list.selected == 3 }, "a click selected the fourth row"),
    kit.MoveTo({60, 150}),
    kit.Wait(3),
    kit.Scroll(-4),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.table.list.first > 0 }, "the wheel scrolled"),
    kit.Tap(.END),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.table.list.selected == ROWS - 1 && state.table.list.last == ROWS }, "End went to the last row and the view followed"),
    kit.Capture("table"),
    kit.KeyDownStep(.LEFT_SHIFT),
    kit.Wait(1),
    kit.MoveTo({300, 150}),
    kit.Wait(2),
    kit.Scroll(-4),
    kit.Wait(3),
    kit.KeyUpStep(.LEFT_SHIFT),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        x: f32 = ui.UiTableScrollX(&state.app.ctx, &state.table)
        return x > 80 && state.table.content_width == 760
    }, "shift and the wheel scrolled the columns sideways"),
    kit.Capture("table_sideways"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
