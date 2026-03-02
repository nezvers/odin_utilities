package astar

import pq "core:container/priority_queue"

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
	map_nodes:map[vec2i]^Node2D,	// Hash map of unique Node pointers that have neighbours, meaning all walkable
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

// TODO: modes (Manhattan - 4 way, Euclidean - 8 way)
CreateGridGraph :: proc(grid_size:vec2i, nodes:[]Node2D, neighbour_buffer:[]^Node2D, map_nodes:^map[vec2i]^Node2D)->GridGraph2D {
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
			
			map_nodes[node.pos] = node
		}
	}

	graph:GridGraph2D = {
		size = grid_size,
		nodes = nodes,
		neighbour_buffer = neighbour_buffer[:from],
		map_nodes = map_nodes^,
	}
	return graph
}

// Cache neighbours for 8-way directions
CreateGridGraphEuclidian :: proc(grid_size:vec2i, nodes:[]Node2D, neighbour_buffer:[]^Node2D, map_nodes:^map[vec2i]^Node2D)->GridGraph2D {
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
			
			map_nodes[node.pos] = node
		}
	}

	graph:GridGraph2D = {
		size = grid_size,
		nodes = nodes,
		neighbour_buffer = neighbour_buffer[:from],
		map_nodes = map_nodes^,
	}
	return graph
}

SolveGrid :: proc(
    graph:^GridGraph2D,
    from, to:vec2i,
	queue_buffer: [dynamic]^Node2D, // pre-allocated, at least len(graph.map_nodes)
	allocator := context.allocator,
)->(end:^Node2D, ok:bool){
	assert(cap(queue_buffer) >= len(graph.map_nodes))

	start_node, start_ok := graph.map_nodes[from]
	if !start_ok { return }

	target_node, target_ok := graph.map_nodes[to]
	if !target_ok { return }

	// Reset runtime fields (only walkable nodes)
	for _, node in graph.map_nodes {
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

			tentative_g := current.g_cost + next.cost

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