#+private file
package demo

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

import astar ".."
vec2i :: astar.vec2i
Node2D :: astar.Node2D
Position2D :: astar.Position2D

@(private="package")
state_grid2d_manhattan:State = {
	init_manhattan,
	finit,
	update,
	draw,
}
@(private="package")
state_grid2d_euclidian:State = {
	init_euclidian,
	finit,
	update,
	draw,
}

is_8way:bool

CELL_SIZE :Vector2: {30, 30}
GRID_POSITION :Vector2: {100, 100}
GRID_SIZE :vec2i: {8,6}
GRID_LEN :: GRID_SIZE.x * GRID_SIZE.y
NEIGHBOUR_SIZE :: GRID_LEN * 4

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
grid_nodes:[GRID_LEN]Node2D
neighbour_buffer:[NEIGHBOUR_SIZE]^Node2D
map_nodes:map[vec2i]^Node2D

neighbour_connections: astar.ConnectionSet2D

queue_buffer: [dynamic]^Node2D
end_node:^Node2D
grid_solve_ok:bool
path_buffer: [GRID_LEN]Position2D
path_result: []Position2D

start_cell:vec2i = {0,1}
target_cell:vec2i = {7,0}

load_map :: proc(map_cost:[]f32) {
	assert(len(map_cost) >= (GRID_LEN))

	for y:int = 0; y < GRID_SIZE.y; y += 1 {
		for x:int = 0; x < GRID_SIZE.x; x += 1 {
			index:int = x + y * GRID_SIZE.x
			cost:f32 = grid_map[index]
			grid_nodes[index] = {
				pos = {x, y},
				cost = cost,
				neighbours = {}, // will be set in astar.InitGridNeighbours
			}
		}
	}
}

astar_solve :: proc(from: vec2i, to: vec2i) {
	if is_8way{
		end_node, grid_solve_ok = astar.SolveGrid(&grid_graph, from, to, queue_buffer)
	} else {
		end_node, grid_solve_ok = astar.SolveGrid(&grid_graph, from, to, queue_buffer)
	}
	if grid_solve_ok {
		path_result = astar.GetPathSlice2D(end_node, path_buffer[:])
	}
}

get_cell :: proc(pos:Vector2)->(cell:vec2i, ok:bool) {
	// Out of bounds check
	if pos.x < GRID_POSITION.x {
		return
	}
	if pos.y < GRID_POSITION.y {
		return
	}
	if pos.x > GRID_POSITION.x + cast(f32)GRID_SIZE.x * CELL_SIZE.x {
		return
	}
	if pos.y > GRID_POSITION.y + cast(f32)GRID_SIZE.y * CELL_SIZE.y {
		return
	}
	// Convert to cell position
	relative:Vector2 = pos - GRID_POSITION
	cell = {cast(int)(relative.x / CELL_SIZE.x), cast(int)(relative.y / CELL_SIZE.y)}
	ok = true
	return
}

init_manhattan :: proc() {
	is_8way = false
	map_nodes = make(map[vec2i]^Node2D)
	load_map(grid_map[:])

	// 4-way neighbour caching
	grid_graph = astar.CreateGridGraph(GRID_SIZE, grid_nodes[:], neighbour_buffer[:], &map_nodes)
	neighbour_connections = astar.CreateConnectionSet2D(grid_nodes[:])

	queue_buffer = make([dynamic]^Node2D)
	reserve(&queue_buffer, len(grid_graph.map_nodes))
	astar_solve(start_cell, target_cell)
}

init_euclidian :: proc() {
	is_8way = true
	map_nodes = make(map[vec2i]^Node2D)
	load_map(grid_map[:])

	// 8-way neighbour caching
	grid_graph = astar.CreateGridGraphEuclidian(GRID_SIZE, grid_nodes[:], neighbour_buffer[:], &map_nodes)
	neighbour_connections = astar.CreateConnectionSet2D(grid_nodes[:])

	queue_buffer = make([dynamic]^Node2D)
	reserve(&queue_buffer, len(grid_graph.map_nodes))
	astar_solve(start_cell, target_cell)
}

finit :: proc() {
	delete(neighbour_connections)
	delete(map_nodes)
	delete(queue_buffer)
}

update :: proc() {
	if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
		mouse: = rl.GetMousePosition()
		cell, ok: = get_cell(mouse)
		if ok && cell != start_cell {
			start_cell = cell
			astar_solve(start_cell, target_cell)
		}
	}
	if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
		mouse: = rl.GetMousePosition()
		cell, ok: = get_cell(mouse)
		if ok && cell != target_cell {
			target_cell = cell
			astar_solve(start_cell, target_cell)
		}
	}
}

draw :: proc() {
	rect:Rectangle = {GRID_POSITION.x, GRID_POSITION.y, CELL_SIZE.x, CELL_SIZE.y}
	for &node in grid_nodes {
		draw_node(&node, rect)
	}

	rect.x += rect.width * 0.5
	rect.y += rect.height * 0.5
	/*
	for &node in grid_nodes {
		draw_neighbour_connection(&node, rect)
	}
	*/

	// draw_connections(neighbour_connections, rect)
	if grid_solve_ok {
		// draw_path_nodes(end_node, rect)
		draw_path(path_result, rect)
	}

	start_point: Vector2 = {rect.x + rect.width * cast(f32)start_cell.x, rect.y + rect.height * cast(f32)start_cell.y}
	target_point: Vector2 = {rect.x + rect.width * cast(f32)target_cell.x, rect.y + rect.height * cast(f32)target_cell.y}
	rl.DrawCircleLinesV(start_point, 10, rl.RED)
	rl.DrawCircleV(target_point, 7.5, rl.BLUE)
}

draw_node :: proc(node:^Node2D, rect:Rectangle) {
	r := rect
	r.y = rect.y + r.height * cast(f32)node.pos.y
	r.x = rect.x + r.width * cast(f32)node.pos.x
	rl.DrawRectangleRec(r, node.cost == 0 ? rl.DARKGRAY : rl.GREEN)
}

draw_neighbour_connection :: proc(node:^Node2D, rect:Rectangle) {
	if node.neighbours == nil {
		return
	}
	from:Vector2 = {rect.x + rect.width * cast(f32)node.pos.x, rect.y + rect.height * cast(f32)node.pos.y}
	for i:int = 0; i < len(node.neighbours); i += 1 {
		neighbour:Node2D = node.neighbours[i]^
		to:Vector2 = {rect.x + rect.width * cast(f32)neighbour.pos.x, rect.y + rect.height * cast(f32)neighbour.pos.y}
		rl.DrawLineV(from, to, rl.GRAY)
	}
}

draw_connections :: proc(connections:astar.ConnectionSet2D, rect:Rectangle) {
	for key in connections {
		from:Vector2 = {rect.x + rect.width * cast(f32)key.from.x, rect.y + rect.height * cast(f32)key.from.y}
		to:Vector2 = {rect.x + rect.width * cast(f32)key.to.x, rect.y + rect.height * cast(f32)key.to.y}
		rl.DrawLineV(from, to, rl.GRAY)
	}
}

draw_path_nodes :: proc(last:^Node2D, rect:Rectangle) {
	assert(last != nil)
	point:vec2i = last.pos
	previous: ^Node2D = last.previous
	for previous != nil {
		from:Vector2 = {rect.x + rect.width * cast(f32)point.x, rect.y + rect.height * cast(f32)point.y}
		point = previous.pos
		
		to:Vector2 = {rect.x + rect.width * cast(f32)point.x, rect.y + rect.height * cast(f32)point.y}
		rl.DrawLineV(from, to, rl.GRAY)
		previous = previous.previous
	}
}

draw_path :: proc(path: []Position2D, rect:Rectangle) {
	for i:int = 0; i < len(path) - 1; i += 1 {
		from:Vector2 = {rect.x + rect.width * cast(f32)path[i].pos.x, rect.y + rect.height * cast(f32)path[i].pos.y}
		to:Vector2 = {rect.x + rect.width * cast(f32)path[i + 1].pos.x, rect.y + rect.height * cast(f32)path[i + 1].pos.y}
		rl.DrawLineV(from, to, rl.GRAY)
	}
}