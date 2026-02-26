#+private file
package demo

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

import astar ".."
vec2i :: astar.vec2i
Node :: astar.Node

@(private="package")
state_grid:State = {
	init,
	finit,
	update,
	draw,
}

GRID_SIZE :vec2i: {6,6}
GRID_LEN :: GRID_SIZE.x * GRID_SIZE.y
NEIGHBOUR_SIZE :: GRID_LEN * 4

// Game map values. 0 is solid. Higher value is higher cost
grid_map: [GRID_LEN]int = {
	1, 1, 1, 1, 1, 1,
	1, 0, 1, 1, 1, 1,
	0, 1, 1, 0, 0, 0,
	1, 1, 0, 1, 1, 1,
	1, 0, 1, 1, 0, 1,
	1, 1, 1, 1, 0, 1,
}
// Astar grid
grid_graph: astar.GridGraph
grid_nodes:[GRID_LEN]Node
neighbour_buffer:[NEIGHBOUR_SIZE]^Node

neighbour_connections: astar.ConnectionSet2D

load_map :: proc(map_cost:[]int) {
	assert(len(map_cost) >= (GRID_LEN))

	for y:int = 0; y < GRID_SIZE.y; y += 1 {
		for x:int = 0; x < GRID_SIZE.x; x += 1 {
			index:int = x + y * GRID_SIZE.x
			cost:int = grid_map[index]
			grid_nodes[index] = {
				pos = {x, y},
				cost = cost,
				neighbours = {}, // will be set in astar.InitGridNeighbours
			}
		}
	}
}

init :: proc() {
	load_map(grid_map[:])
	grid_graph = astar.CreateGridGraph(GRID_SIZE, grid_nodes[:], neighbour_buffer[:])
	neighbour_connections = astar.CreateConnectionSet2D(grid_nodes[:])
}

finit :: proc() {
	delete(neighbour_connections)
}

update :: proc(){}

draw :: proc() {
	rect:Rectangle = {100, 100, 30, 30}
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

	draw_connections(neighbour_connections, rect)
}

draw_node :: proc(node:^Node, rect:Rectangle) {
	r := rect
	r.y = rect.y + r.height * cast(f32)node.pos.y
	r.x = rect.x + r.width * cast(f32)node.pos.x
	rl.DrawRectangleRec(r, node.cost == 0 ? rl.DARKGRAY : rl.GREEN)
}

draw_neighbour_connection :: proc(node:^Node, rect:Rectangle) {
	if node.neighbours == nil {
		return
	}
	from:Vector2 = {rect.x + rect.width * cast(f32)node.pos.x, rect.y + rect.height * cast(f32)node.pos.y}
	for i:int = 0; i < len(node.neighbours); i += 1 {
		neighbour:Node = node.neighbours[i]^
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