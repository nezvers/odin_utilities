package astar

Connection2D :: struct{
	from:vec2i, // top-left
	to:vec2i,
}
// Set of each connection once as keys
ConnectionSet2D :: map[Connection2D]struct{}

CreateConnectionSet2D :: proc(nodes:[]Node)->(connections:ConnectionSet2D) {
	for node in nodes {
		for neighbour in node.neighbours {
			connection:Connection2D
			if node.pos.y < neighbour.pos.y {
				connection.from = node.pos
				connection.to = neighbour.pos
			} else if (node.pos.y == neighbour.pos.y) && node.pos.x < neighbour.pos.x {
				connection.from = node.pos
				connection.to = neighbour.pos
			} else {
				connection.from = neighbour.pos
				connection.to = node.pos
			}
			if connection in connections {
				continue
			}
			connections[connection] = {}
		}
	}
	return
}