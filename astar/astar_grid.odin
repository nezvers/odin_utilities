package astar

// import pq "core:container/priority_queue"


InitGridNeighbours :: proc(grid_size:vec2i, nodes:[]Node, neighbour_buffer:[]^Node)->(count:int) {
	assert(len(nodes) >= (grid_size.x * grid_size.y))
	assert(len(neighbour_buffer) >= (grid_size.x * grid_size.y * 4))

	from:int = 0
	for y:int = 0; y < grid_size.y; y += 1 {
		for x:int = 0; x < grid_size.x; x += 1 {
			node:^Node = &nodes[x + y * grid_size.x]
			if node.weight == 0 {
				// Skip solid
				continue
			}
			neigbour_count:int = 0

			// LEFT
			if x > 0 {
				left:^Node = &nodes[(x - 1) + y * grid_size.x]
				if left.weight > 0 {
					neighbour_buffer[from + neigbour_count] = left
					neigbour_count += 1
				}
			}
			// UP
			if y > 0 {
				up:^Node = &nodes[x + (y - 1) * grid_size.x]
				if up.weight > 0 {
					neighbour_buffer[from + neigbour_count] = up
					neigbour_count += 1
				}
			}
			// RIGHT
			if x < (grid_size.x - 1) {
				right:^Node = &nodes[(x + 1) + y * grid_size.x]
				if right.weight > 0 {
					neighbour_buffer[from + neigbour_count] = right
					neigbour_count += 1
				}
			}
			// DOWN
			if y < (grid_size.y - 1) {
				down:^Node = &nodes[x + (y + 1) * grid_size.x]
				if down.weight > 0 {
					neighbour_buffer[from + neigbour_count] = down
					neigbour_count += 1
				}
			}
			if neigbour_count == 0 {
				continue
			}

			node.neighbours = neighbour_buffer[from:(from + neigbour_count)]
			from += neigbour_count
		}
	}
	count = from
	return
}
