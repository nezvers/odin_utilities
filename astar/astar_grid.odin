package astar

import pq "core:container/priority_queue"

GridGraph :: struct {
	size:vec2i,					// Grid size, x - width, y - height
	nodes:[]Node,				// Slice of every position on grid, including non-walkable
	neighbour_buffer:[]^Node,	// Buffer holding all neighbour pointers and dstributed to Nodes
	map_nodes:map[vec2i]^Node,	// Hash map of unique Node pointers that have neighbours, meaning all walkable
}

// TODO: modes (Manhattan - 4 way, Euclidean - 8 way)
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
	start_node, start_ok: = graph.map_nodes[from]
	if !start_ok {
		return
	}
	target_pos:vec2i = to
	_, target_ok: = graph.map_nodes[to]
	if !target_ok {
		return
	}
	
	queue: pq.Priority_Queue(PathPosition)
	// Init with sorting comparison PathPositionSort
	pq.init(
		&queue, 
		PathPositionSort, 
		pq.default_swap_proc(PathPosition),
		len(graph.map_nodes),
	)
	defer pq.destroy(&queue)
	
	start_position:PathPosition =  {
		distance   = DistanceCost(&start_node.pos, &target_pos),
		total_cost = 0,
		node       = start_node,
		previous   = nil,
	}
	// Initial position
	pq.push(&queue, start_position)
	history[start_node] = start_position

	current_position: PathPosition
	for pq.len(queue) != 0 {
		current_position = pq.pop(&queue)
		current_node = current_position.node
		if current_node.pos == target_pos {
			// success
			ok = true
			break
		}
		
		for next_node in current_node.neighbours {
			total_cost: = current_position.total_cost + cast(f32)next_node.cost
			
			next_pos, is_used: = history[next_node]
			if is_used && next_pos.total_cost <= total_cost {continue }
			
			next: = PathPosition{
				distance = DistanceCost(&next_node.pos, &target_pos),
				total_cost = total_cost,
				node = next_node,
				previous = current_node,
			}
			history[next_node] = next
			pq.push(&queue, next)
		}
	}
	
	return
}


SolveGridStatic :: proc(
    graph:^GridGraph,
    from, to:vec2i,
	queue_buffer: [dynamic]^Node, // pre-allocated, at least len(graph.map_nodes)
)->(end:^Node, ok:bool){
	assert(cap(queue_buffer) >= len(graph.map_nodes))

	start_node, start_ok := graph.map_nodes[from]
	if !start_ok { return }

	target_node, target_ok := graph.map_nodes[to]
	if !target_ok { return }

	// Reset runtime fields (only walkable nodes)
	for _, node in graph.map_nodes {
		node.g_cost = 0
		node.f_cost = 0
		node.parent = nil
		node.opened = false
		node.closed = false
	}

	queue: pq.Priority_Queue(^Node)
	queue.queue = queue_buffer
	queue.less = NodeSort
	queue.swap = pq.default_swap_proc(^Node)

	start_node.g_cost = 0
	start_node.f_cost = DistanceCost(&start_node.pos, &target_node.pos)
	start_node.opened = true

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

			tentative_g := current.g_cost + cast(f32)next.cost

			if !next.opened || tentative_g < next.g_cost {

				next.parent = current
				next.g_cost = tentative_g
				next.f_cost = tentative_g + DistanceCost(&next.pos, &target_node.pos)

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