package astar

// https://github.com/Horryportier/Astar-odin
// https://github.com/rhoeberg/odin-astar

// https://github.com/godotengine/godot/blob/2327a823578a30f09068f97272598521896d5633/core/math/a_star.cpp#L818

vec2i :: [2]int

Position :: struct {
    pos:vec2i,  // cell position on grid
    cost:int,   // additional cost of traversing, but 0 is not walkable (excluded from neighbour list)
}

Node :: struct {
    using position : Position,  // make pos & cost local variables
    neighbours:[]^Node,         // slice of Node pointers assigned from neighbour buffer
}

PathPosition :: struct {
	distance: f32,		// to target
	total_cost: f32,	// path index
	node: ^Node,		// Node pointer of that position
	previous: ^Node,	// Node pointer of previous position, used as key in history map
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

// Used in Priority_Queue, true closer to be next popped
PathPositionSort :: proc(a,b:PathPosition)->bool{
    af := a.total_cost + a.distance
    bf := b.total_cost + b.distance
    return af < bf
}