package astar

import pq "core:container/priority_queue"

PathPosition :: struct {
	distance: int, // cumulative from start position
	node: ^Node,
	previous: ^Node,
}

GridGraph :: struct {
	size:vec2i,
	nodes:[]Node,
	neighbour_buffer:[]^Node,
	map_nodes:map[vec2i]^Node,	// unique Nodes that have neighbours
}

CreateGridGraph :: proc(grid_size:vec2i, nodes:[]Node, neighbour_buffer:[]^Node, map_nodes:^map[vec2i]^Node)->GridGraph {
	assert(len(nodes) >= (grid_size.x * grid_size.y))
	assert(len(neighbour_buffer) >= (grid_size.x * grid_size.y * 4))

	from:int = 0
	for y:int = 0; y < grid_size.y; y += 1 {
		for x:int = 0; x < grid_size.x; x += 1 {
			node:^Node = &nodes[x + y * grid_size.x]
			if node.cost == 0 {
				// Skip solid
				continue
			}
			neigbour_count:int = 0

			// LEFT
			if x > 0 {
				left:^Node = &nodes[(x - 1) + y * grid_size.x]
				if left.cost > 0 {
					neighbour_buffer[from + neigbour_count] = left
					neigbour_count += 1
				}
			}
			// UP
			if y > 0 {
				up:^Node = &nodes[x + (y - 1) * grid_size.x]
				if up.cost > 0 {
					neighbour_buffer[from + neigbour_count] = up
					neigbour_count += 1
				}
			}
			// RIGHT
			if x < (grid_size.x - 1) {
				right:^Node = &nodes[(x + 1) + y * grid_size.x]
				if right.cost > 0 {
					neighbour_buffer[from + neigbour_count] = right
					neigbour_count += 1
				}
			}
			// DOWN
			if y < (grid_size.y - 1) {
				down:^Node = &nodes[x + (y + 1) * grid_size.x]
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

	graph:GridGraph = {
		size = grid_size,
		nodes = nodes,
		neighbour_buffer = neighbour_buffer[:from],
		map_nodes = map_nodes^,
	}
	return graph
}

SolveGrid :: proc(graph:GridGraph, from:vec2i, to:vec2i)->(history:map[^Node]PathPosition, current_node:^Node, ok:bool) {
	start_node, current_ok: = graph.map_nodes[from]
	if !current_ok {
		return
	}
	target_pos:vec2i = to
	_, target_ok: = graph.map_nodes[to]
	if !target_ok {
		return
	}
	
	queue: pq.Priority_Queue(PathPosition)
	pq.init(&queue, PathPositionSort, pq.default_swap_proc(PathPosition))
	defer pq.destroy(&queue)
	
	current_node = start_node
	current_position: PathPosition = {0, current_node, nil}
	pq.push(&queue, current_position)
	
	history[current_node] = current_position

	for pq.len(queue) != 0 {
		current_position = pq.pop(&queue)
		current_node = current_position.node
		if current_node.pos == target_pos {
			ok = true
			break 
		} // success
		
		for next_node in current_node.neighbours {
			is_used: = next_node in history
			if is_used { continue }
			next: = PathPosition{
				distance = DistanceCostSquared(&current_node.pos, &target_pos) + next_node.cost,
				node = next_node,
				previous = current_node,
			}
			history[next_node] = next
			pq.push(&queue, next)
		}
	}
	
	return
}