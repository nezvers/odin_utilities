#+private file
package demo_common

import astar ".."
import kit "../../demo_kit"

@(private="package")
demo_grid2d_manhattan: kit.Demo = {
    name = "grid 4 way",
    init = init_manhattan,
    finit = finit,
    update = update,
    draw = draw,
    script = script_manhattan,
}

@(private="package")
demo_grid2d_euclidian: kit.Demo = {
    name = "grid 8 way",
    init = init_euclidian,
    finit = finit,
    update = update,
    draw = draw,
    script = script_euclidian,
}

vec2i :: astar.vec2i
Node2D :: astar.Node2D
Position2D :: astar.Position2D

is_8way: bool
CELL_SIZE :: kit.Vec2{30, 30}
GRID_POSITION :: kit.Vec2{100, 100}
GRID_SIZE :: vec2i{8, 6}
GRID_LEN :: GRID_SIZE.x * GRID_SIZE.y
NEIGHBOUR_SIZE :: GRID_LEN * 8     // 8 way needs 8 neighbours per cell (the old demo had 4 and asserted)

// Game map values. 0 is solid. Higher value is higher cost
grid_map: [GRID_LEN]f32 = {
    1, 1, 1, 0, 1, 0, 1, 1,
    1, 0, 1, 1, 1, 0, 1, 0,
    0, 1, 1, 0, 0, 0, 1, 1,
    1, 1, 0, 1, 1, 1, 0, 1,
    1, 0, 1, 1, 0, 1, 0, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
}

// Astar grid
grid_graph: astar.GridGraph2D
grid_nodes: [GRID_LEN]Node2D
neighbour_buffer: [NEIGHBOUR_SIZE]^Node2D
map_nodes: map[vec2i]^Node2D
neighbour_connections: astar.ConnectionSet2D
queue_buffer: [dynamic]^Node2D
end_node: ^Node2D
grid_solve_ok: bool
path_buffer: [GRID_LEN]Position2D
path_result: []Position2D
start_cell: vec2i = {0, 1}
target_cell: vec2i = {7, 0}

load_map :: proc(map_cost: []f32) {
    assert(len(map_cost) >= GRID_LEN)
    for y in 0 ..< GRID_SIZE.y {
        for x in 0 ..< GRID_SIZE.x {
            index: int = x + y * GRID_SIZE.x
            grid_nodes[index] = {
                pos = {x, y},
                cost = grid_map[index],
                neighbours = {},    // will be set in astar.CreateGridGraph
            }
        }
    }
}

astar_solve :: proc(from: vec2i, to: vec2i) {
    path_result = nil
    end_node, grid_solve_ok = astar.SolveGrid(&grid_graph, from, to, queue_buffer)
    if grid_solve_ok {
        path_result = astar.GetPathSlice2D(end_node, path_buffer[:])
    }
}

get_cell :: proc(pos: kit.Vec2) -> (cell: vec2i, ok: bool) {
    // Out of bounds check
    if pos.x < GRID_POSITION.x || pos.y < GRID_POSITION.y { return }
    if pos.x >= GRID_POSITION.x + f32(GRID_SIZE.x) * CELL_SIZE.x { return }
    if pos.y >= GRID_POSITION.y + f32(GRID_SIZE.y) * CELL_SIZE.y { return }
    // Convert to cell position
    relative: kit.Vec2 = pos - GRID_POSITION
    cell = {int(relative.x / CELL_SIZE.x), int(relative.y / CELL_SIZE.y)}
    ok = true
    return
}

// the center of a cell on the screen
cell_center :: proc(cell: vec2i) -> kit.Vec2 {
    return GRID_POSITION + CELL_SIZE * 0.5 + {CELL_SIZE.x * f32(cell.x), CELL_SIZE.y * f32(cell.y)}
}

init_manhattan :: proc(ctx: ^kit.Context) {
    is_8way = false
    init(ctx)
}

init_euclidian :: proc(ctx: ^kit.Context) {
    is_8way = true
    init(ctx)
}

init :: proc(ctx: ^kit.Context) {
    start_cell = {0, 1}
    target_cell = {7, 0}
    map_nodes = make(map[vec2i]^Node2D)
    load_map(grid_map[:])
    if is_8way {
        // 8-way neighbour caching
        grid_graph = astar.CreateGridGraphEuclidian(GRID_SIZE, grid_nodes[:], neighbour_buffer[:], &map_nodes)
    } else {
        // 4-way neighbour caching
        grid_graph = astar.CreateGridGraph(GRID_SIZE, grid_nodes[:], neighbour_buffer[:], &map_nodes)
    }
    neighbour_connections = astar.CreateConnectionSet2D(grid_nodes[:])
    queue_buffer = make([dynamic]^Node2D)
    reserve(&queue_buffer, len(grid_graph.map_nodes))
    astar_solve(start_cell, target_cell)
}

finit :: proc(ctx: ^kit.Context) {
    delete(neighbour_connections)
    delete(map_nodes)
    delete(queue_buffer)
}

update :: proc(ctx: ^kit.Context) {
    if ctx.ui_hover { return }
    if kit.MousePressed(&ctx.input, .LEFT) {
        cell, ok := get_cell(ctx.input.mouse_position)
        if ok && cell != start_cell {
            start_cell = cell
            astar_solve(start_cell, target_cell)
        }
    }
    if kit.MousePressed(&ctx.input, .RIGHT) {
        cell, ok := get_cell(ctx.input.mouse_position)
        if ok && cell != target_cell {
            target_cell = cell
            astar_solve(start_cell, target_cell)
        }
    }
}

draw :: proc(ctx: ^kit.Context) {
    for &node in grid_nodes {
        rect: kit.Rect = {GRID_POSITION.x + CELL_SIZE.x * f32(node.pos.x), GRID_POSITION.y + CELL_SIZE.y * f32(node.pos.y), CELL_SIZE.x, CELL_SIZE.y}
        kit.DrawRect(ctx, rect, kit.DARK_GRAY if node.cost == 0 else kit.GREEN)
    }
    if grid_solve_ok {
        for i in 0 ..< len(path_result) - 1 {
            kit.DrawLine(ctx, cell_center(path_result[i].pos), cell_center(path_result[i + 1].pos), 1, kit.GRAY)
        }
    }
    kit.DrawCircleOutline(ctx, cell_center(start_cell), 10, 1, kit.RED)
    kit.DrawCircle(ctx, cell_center(target_cell), 7.5, kit.BLUE)
    kit.DrawText(ctx, "A star on a grid: green cells are open, dark ones are solid.  left click: start (red), right click: target (blue)", {10, 10}, 18, kit.DARK_GRAY)
}

path_valid :: proc(allow_diagonal: bool) -> bool {
    if !grid_solve_ok || len(path_result) < 2 { return false }
    if path_result[0].pos != start_cell && path_result[len(path_result) - 1].pos != start_cell { return false }
    for i in 0 ..< len(path_result) - 1 {
        a: vec2i = path_result[i].pos
        b: vec2i = path_result[i + 1].pos
        dx: int = abs(a.x - b.x)
        dy: int = abs(a.y - b.y)
        if dx > 1 || dy > 1 { return false }
        if !allow_diagonal && dx + dy != 1 { return false }
        if grid_map[b.x + b.y * GRID_SIZE.x] == 0 { return false }
    }
    return true
}

script_manhattan: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return path_valid(false) }, "a path is found from (0,1) to (7,0) with 4 way steps over open cells"),
    kit.Click(cell_pixel({5, 5}), .RIGHT),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return target_cell == vec2i{5, 5} && path_valid(false) }, "right click moves the target and the path is solved again"),
    kit.Click(cell_pixel({3, 0}), .RIGHT),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return target_cell == vec2i{3, 0} }, "the target can be a solid cell, the demo does not move it"),
}

script_euclidian: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return path_valid(true) }, "a path is found with diagonal steps allowed"),
    kit.Click(cell_pixel({6, 5}), .LEFT),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return start_cell == vec2i{6, 5} && path_valid(true) }, "left click moves the start"),
}

// a pixel inside of a cell, for a script (a constant expression: the grid is at 100,100 with 30 pixel cells)
cell_pixel :: proc "contextless" (cell: vec2i) -> kit.Vec2 {
    return {100 + 30 * f32(cell.x) + 15, 100 + 30 * f32(cell.y) + 15}
}
