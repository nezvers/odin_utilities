package astar

import pq "core:container/priority_queue"
import "core:testing"

vec2i :: [2]int

Position2D :: struct {
    pos:vec2i,  // cell position on grid
    cost:f32,   // additional cost of traversing, but 0 is not walkable (excluded from neighbour list)
}

Node2D :: struct {
    using position: Position2D,   // make pos & cost local variables
    neighbours:[]^Node2D,         // slice of Node pointers assigned from neighbour buffer
    // --- runtime (A*) ---
    g_cost: f32,        // cost from start
    f_cost: f32,        // g + heuristic
    index: int,         // index from start
    previous: ^Node2D,    // previous node
    opened: bool,       // in queue
    closed: bool,       // already processed
}

GridGraph2D :: struct {
	size:vec2i,					// Grid size, x - width, y - height
	nodes:[]Node2D,				// Slice of every position on grid, including non-walkable
	neighbour_buffer:[]^Node2D,	// Buffer holding all neighbour pointers and dstributed to Nodes
	map_nodes:map[vec2i]^Node2D,	// Optional: map of unique Node pointers that have neighbours, meaning all walkable
}

// Heuristic 1
DistanceCost :: proc(from:^vec2i, to:^vec2i)->f32{
    x:= abs(cast(f32)to.x - cast(f32)from.x)
    y:= abs(cast(f32)to.y - cast(f32)from.y)
    return x + y
}

// Heuristic 2
DistanceCostSquared :: proc(from:^vec2i, to:^vec2i)->f32{
    x:= abs(cast(f32)to.x - cast(f32)from.x)
    y:= abs(cast(f32)to.y - cast(f32)from.y)
    return x * x + y * y
}

NodeSort2D :: proc(a,b:^Node2D)->bool{
    return a.f_cost < b.f_cost
}

// Calculate pure path slice
GetPathSlice2D :: proc(end: ^Node2D, buffer: []Position2D)->[]Position2D {
    assert(len(buffer) >= end.index + 1)
    result: = buffer[:(end.index + 1)]
    current: = end
    for i:int = end.index; i > -1; i -= 1 {
        result[i] = current.position
        current = current.previous
    }
    return result
}

// Cache neighbours for Manhattan - 4 way
CreateGridGraph :: proc(grid_size:vec2i, nodes:[]Node2D, neighbour_buffer:[]^Node2D, map_nodes:^map[vec2i]^Node2D = nil)->GridGraph2D {
	assert(len(nodes) >= (grid_size.x * grid_size.y))
	assert(len(neighbour_buffer) >= (grid_size.x * grid_size.y * 4))

	from:int = 0
	for y:int = 0; y < grid_size.y; y += 1 {
		for x:int = 0; x < grid_size.x; x += 1 {
			node:^Node2D = &nodes[x + y * grid_size.x]
			if node.cost == 0 {
				// Skip solid
				continue
			}
			neigbour_count:int = 0

			// LEFT
			if x > 0 {
				left:^Node2D = &nodes[(x - 1) + y * grid_size.x]
				if left.cost > 0 {
					neighbour_buffer[from + neigbour_count] = left
					neigbour_count += 1
				}
			}
			// UP
			if y > 0 {
				up:^Node2D = &nodes[x + (y - 1) * grid_size.x]
				if up.cost > 0 {
					neighbour_buffer[from + neigbour_count] = up
					neigbour_count += 1
				}
			}
			// RIGHT
			if x < (grid_size.x - 1) {
				right:^Node2D = &nodes[(x + 1) + y * grid_size.x]
				if right.cost > 0 {
					neighbour_buffer[from + neigbour_count] = right
					neigbour_count += 1
				}
			}
			// DOWN
			if y < (grid_size.y - 1) {
				down:^Node2D = &nodes[x + (y + 1) * grid_size.x]
				if down.cost > 0 {
					neighbour_buffer[from + neigbour_count] = down
					neigbour_count += 1
				}
			}
			if neigbour_count == 0 {
				continue
			}

			node.neighbours = neighbour_buffer[from:(from + neigbour_count)]
			from += neigbour_count
			
			if map_nodes != nil{
				map_nodes[node.pos] = node
			}
		}
	}

	graph:GridGraph2D = {
		size = grid_size,
		nodes = nodes,
		neighbour_buffer = neighbour_buffer[:from],
	}
	if map_nodes != nil{
		graph.map_nodes = map_nodes^
	}
	return graph
}

// Cache neighbours for 8-way directions
CreateGridGraphEuclidian :: proc(grid_size:vec2i, nodes:[]Node2D, neighbour_buffer:[]^Node2D, map_nodes:^map[vec2i]^Node2D = nil)->GridGraph2D {
	assert(len(nodes) >= (grid_size.x * grid_size.y))
	assert(len(neighbour_buffer) >= (grid_size.x * grid_size.y * 8))

	from:int = 0
	for y:int = 0; y < grid_size.y; y += 1 {
		for x:int = 0; x < grid_size.x; x += 1 {
			node:^Node2D = &nodes[x + y * grid_size.x]
			if node.cost == 0 {
				// Skip solid
				continue
			}
			neigbour_count:int = 0
			// 4-way bitmask, don't allow diagonal if blocked by both sides
			blocked:u8

			// LEFT
			if x > 0 {
				left:^Node2D = &nodes[(x - 1) + y * grid_size.x]
				if left.cost > 0 {
					neighbour_buffer[from + neigbour_count] = left
					neigbour_count += 1
				} else {
					blocked |= 1 << 0
				}
			}
			// UP
			if y > 0 {
				up:^Node2D = &nodes[x + (y - 1) * grid_size.x]
				if up.cost > 0 {
					neighbour_buffer[from + neigbour_count] = up
					neigbour_count += 1
				} else {
					blocked |= 1 << 1
				}
			}
			// RIGHT
			if x < (grid_size.x - 1) {
				right:^Node2D = &nodes[(x + 1) + y * grid_size.x]
				if right.cost > 0 {
					neighbour_buffer[from + neigbour_count] = right
					neigbour_count += 1
				} else {
					blocked |= 1 << 2
				}
			}
			// DOWN
			if y < (grid_size.y - 1) {
				down:^Node2D = &nodes[x + (y + 1) * grid_size.x]
				if down.cost > 0 {
					neighbour_buffer[from + neigbour_count] = down
					neigbour_count += 1
				} else {
					blocked |= 1 << 3
				}
			}
			// TOP-LEFT
			if x > 0 && y > 0 && (blocked & 3) != 3 {
				top_left:^Node2D = &nodes[(x - 1) + (y - 1) * grid_size.x]
				if top_left.cost > 0 {
					neighbour_buffer[from + neigbour_count] = top_left
					neigbour_count += 1
				}
			}
			// TOP-RIGHT
			if x < (grid_size.x - 1) && y > 0 && (blocked & 6) != 6 {
				top_right:^Node2D = &nodes[(x + 1) + (y - 1) * grid_size.x]
				if top_right.cost > 0 {
					neighbour_buffer[from + neigbour_count] = top_right
					neigbour_count += 1
				}
			}
			// BOTTOM-RIGHT
			if x < (grid_size.x - 1) && y < (grid_size.y - 1) && (blocked & 12) != 12 {
				bottom_right:^Node2D = &nodes[(x + 1) + (y + 1) * grid_size.x]
				if bottom_right.cost > 0 {
					neighbour_buffer[from + neigbour_count] = bottom_right
					neigbour_count += 1
				}
			}
			// BOTTOM-LEFT
			if x > 0 && y < (grid_size.y - 1) && (blocked & 9) != 9 {
				bottom_left:^Node2D = &nodes[(x - 1) + (y + 1) * grid_size.x]
				if bottom_left.cost > 0 {
					neighbour_buffer[from + neigbour_count] = bottom_left
					neigbour_count += 1
				}
			}

			if neigbour_count == 0 {
				continue
			}

			node.neighbours = neighbour_buffer[from:(from + neigbour_count)]
			from += neigbour_count
			
			if map_nodes != nil{
				map_nodes[node.pos] = node
			}
		}
	}

	graph:GridGraph2D = {
		size = grid_size,
		nodes = nodes,
		neighbour_buffer = neighbour_buffer[:from],
	}
	if map_nodes != nil{
		graph.map_nodes = map_nodes^
	}
	return graph
}

SolveGrid :: proc(
    graph:^GridGraph2D,
    from, to:vec2i,
	queue_buffer: [dynamic]^Node2D, // pre-allocated, at least len(graph.map_nodes)
	allocator := context.allocator,
)->(end:^Node2D, ok:bool){

	start_node, start_ok := graph.map_nodes[from]
	if !start_ok { return }

	target_node, target_ok := graph.map_nodes[to]
	if !target_ok { return }

	// Reset runtime fields (only walkable nodes)
	for &node in graph.nodes {
		node.g_cost = 0
		node.f_cost = 0
		node.previous = nil
		node.opened = false
		node.closed = false
	}

	queue: pq.Priority_Queue(^Node2D)
	// Custom initialization
	queue.queue = queue_buffer
	if queue.queue.allocator.procedure == nil {
		queue.queue.allocator = allocator
	}
	queue.less = NodeSort2D
	queue.swap = pq.default_swap_proc(^Node2D)

	start_node.g_cost = 0
	start_node.f_cost = DistanceCost(&start_node.pos, &target_node.pos)
	start_node.opened = true
	start_node.index = 0

	pq.push(&queue, start_node)

	for pq.len(queue) != 0 {
		current := pq.pop(&queue)
		current.closed = true

		if current == target_node {
			end = current
			ok = true
			break
		}

		for next in current.neighbours {
			if next.closed {
				continue
			}

			tentative_g := current.g_cost
			step_distance: = current.pos - next.pos
			if step_distance.x != 0 && step_distance.y != 0 {
				// diagonal
				tentative_g += next.cost * 1.4142135623730951
			} else {
				tentative_g += next.cost
			}

			if !next.opened || tentative_g < next.g_cost {

				next.previous = current
				next.g_cost = tentative_g
				next.f_cost = tentative_g + DistanceCost(&next.pos, &target_node.pos)
				next.index = current.index + 1

				if !next.opened {
					next.opened = true
					pq.push(&queue, next)
				} else {
					for i:int = pq.len(queue) - 1; i > -1; i -= 1 {
						if queue.queue[i] == next {
							pq.fix(&queue, i)
						}
					}
				}
			}
		}
	}

	return
}

// --- Tests ---

// Grid for the tests: '#' is a wall, anything else walks with cost 1.
@(private="file")
fill_nodes :: proc(nodes: []Node2D, size: vec2i, rows: []string) {
    for y in 0 ..< size.y {
        for x in 0 ..< size.x {
            cost: f32 = 1
            if rows[y][x] == '#' { cost = 0 }
            nodes[x + y * size.x] = {pos = {x, y}, cost = cost}
        }
    }
}

@(test)
test_grid_graph_neighbour_counts :: proc(t: ^testing.T) {
    size: vec2i = {3, 3}
    nodes: [9]Node2D
    buffer: [9 * 8]^Node2D
    fill_nodes(nodes[:], size, {"...", ".#.", "..."})

    graph: GridGraph2D = CreateGridGraph(size, nodes[:], buffer[:])
    testing.expect_value(t, len(nodes[0].neighbours), 2)         // corner
    testing.expect_value(t, len(nodes[1].neighbours), 2)         // edge next to a wall: the wall is not a neighbour
    testing.expect_value(t, len(nodes[4].neighbours), 0)         // the wall has none
    testing.expect_value(t, len(graph.neighbour_buffer), 16)     // 8 walkable cells x 2 neighbours

    open: [9]Node2D
    fill_nodes(open[:], size, {"...", "...", "..."})
    CreateGridGraph(size, open[:], buffer[:])
    testing.expect_value(t, len(open[4].neighbours), 4)          // centre
}

@(test)
test_grid_graph_eight_way_blocks_corner_cutting :: proc(t: ^testing.T) {
    size: vec2i = {3, 3}
    nodes: [9]Node2D
    buffer: [9 * 8]^Node2D
    fill_nodes(nodes[:], size, {"...", "...", "..."})
    CreateGridGraphEuclidian(size, nodes[:], buffer[:])
    testing.expect_value(t, len(nodes[4].neighbours), 8)
    testing.expect_value(t, len(nodes[0].neighbours), 3)

    // a diagonal step between two walls is not allowed
    pinched: [9]Node2D
    fill_nodes(pinched[:], size, {".#.", "#..", "..."})
    CreateGridGraphEuclidian(size, pinched[:], buffer[:])
    testing.expect_value(t, len(pinched[0].neighbours), 0)       // walls right and below, the open diagonal is not reachable

    // with only one side blocked the diagonal is fine
    fill_nodes(pinched[:], size, {".#.", "...", "..."})
    CreateGridGraphEuclidian(size, pinched[:], buffer[:])
    testing.expect_value(t, len(pinched[0].neighbours), 2)       // down and the diagonal
}

@(private="file")
solve :: proc(size: vec2i, rows: []string, from, to: vec2i, eight_way: bool, path: []Position2D) -> (found: []Position2D, ok: bool) {
    nodes := make([]Node2D, size.x * size.y)
    buffer := make([]^Node2D, size.x * size.y * 8)
    map_nodes := make(map[vec2i]^Node2D)
    queue := make([dynamic]^Node2D, 0, size.x * size.y)
    defer { delete(nodes); delete(buffer); delete(map_nodes); delete(queue) }

    fill_nodes(nodes, size, rows)
    graph: GridGraph2D
    if eight_way {
        graph = CreateGridGraphEuclidian(size, nodes, buffer, &map_nodes)
    } else {
        graph = CreateGridGraph(size, nodes, buffer, &map_nodes)
    }
    end, solved := SolveGrid(&graph, from, to, queue)
    if !solved { return }
    return GetPathSlice2D(end, path), true
}

@(test)
test_solve_straight_and_around_walls :: proc(t: ^testing.T) {
    path: [64]Position2D

    open: []string = {".....", ".....", ".....", ".....", "....."}
    found, ok := solve({5, 5}, open, {0, 0}, {4, 4}, false, path[:])
    testing.expect(t, ok)
    testing.expect_value(t, len(found), 9)                       // 4 right + 4 down, plus the start
    testing.expect_value(t, found[0].pos, vec2i{0, 0})
    testing.expect_value(t, found[len(found) - 1].pos, vec2i{4, 4})
    for i in 1 ..< len(found) {
        step: vec2i = found[i].pos - found[i - 1].pos
        testing.expect_value(t, abs(step.x) + abs(step.y), 1)    // every step is one cell, no diagonals
    }

    walled: []string = {"..#..", "..#..", "..#..", "..#..", "....."}
    around, around_ok := solve({5, 5}, walled, {0, 0}, {4, 0}, false, path[:])
    testing.expect(t, around_ok)
    testing.expect_value(t, len(around), 13)                     // down 4, across 4, up 4, plus the start
    for position in around {
        testing.expect(t, walled[position.pos.y][position.pos.x] != '#', "the path never enters a wall")
    }
}

@(test)
test_solve_eight_way_takes_the_diagonal :: proc(t: ^testing.T) {
    path: [64]Position2D
    open: []string = {".....", ".....", ".....", ".....", "....."}
    found, ok := solve({5, 5}, open, {0, 0}, {4, 4}, true, path[:])
    testing.expect(t, ok)
    testing.expect_value(t, len(found), 5)
}

@(test)
test_solve_fails_cleanly :: proc(t: ^testing.T) {
    path: [64]Position2D
    sealed: []string = {"..#..", "..#..", "..#..", "..#..", "..#.."}
    _, ok := solve({5, 5}, sealed, {0, 0}, {4, 0}, false, path[:])
    testing.expect(t, !ok, "no way through")

    _, into_wall := solve({5, 5}, sealed, {0, 0}, {2, 2}, false, path[:])
    testing.expect(t, !into_wall, "a wall is not a destination")

    start_wall: []string = {"#....", ".....", ".....", ".....", "....."}
    _, from_wall := solve({5, 5}, start_wall, {0, 0}, {4, 4}, false, path[:])
    testing.expect(t, !from_wall, "a wall is not a start")

    open: []string = {".....", ".....", ".....", ".....", "....."}
    same, same_ok := solve({5, 5}, open, {2, 2}, {2, 2}, false, path[:])
    testing.expect(t, same_ok)
    testing.expect_value(t, len(same), 1)
}

@(test)
test_solve_prefers_cheap_cells :: proc(t: ^testing.T) {
    size: vec2i = {3, 3}
    nodes: [9]Node2D
    buffer: [9 * 8]^Node2D
    map_nodes := make(map[vec2i]^Node2D)
    queue := make([dynamic]^Node2D, 0, 9)
    defer { delete(map_nodes); delete(queue) }
    fill_nodes(nodes[:], size, {"...", "...", "..."})
    nodes[1].cost = 10                                           // mud on the direct route over the top
    nodes[4].cost = 10                                           // and in the middle
    graph: GridGraph2D = CreateGridGraph(size, nodes[:], buffer[:], &map_nodes)

    end, ok := SolveGrid(&graph, {0, 0}, {2, 0}, queue)
    testing.expect(t, ok)
    path: [16]Position2D
    found: []Position2D = GetPathSlice2D(end, path[:])
    for position in found {
        testing.expect(t, position.pos != vec2i{1, 0} && position.pos != vec2i{1, 1}, "walks around the mud")
    }
    testing.expect_value(t, len(found), 7)                       // down 2, across 2, up 2, plus the start
}

@(test)
test_heuristics_and_connection_set :: proc(t: ^testing.T) {
    from, to: vec2i = {1, 2}, {4, 6}
    testing.expect_value(t, DistanceCost(&from, &to), f32(7))
    testing.expect_value(t, DistanceCostSquared(&from, &to), f32(25))

    size: vec2i = {3, 3}
    nodes: [9]Node2D
    buffer: [9 * 8]^Node2D
    fill_nodes(nodes[:], size, {"...", "...", "..."})
    CreateGridGraph(size, nodes[:], buffer[:])
    connections: ConnectionSet2D = CreateConnectionSet2D(nodes[:])
    defer delete(connections)
    testing.expect_value(t, len(connections), 12)                // each of the 12 edges of a 3x3 grid exactly once
}
