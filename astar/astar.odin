package astar

vec2i :: [2]int

Position :: struct {
    pos:vec2i,  // cell position on grid
    cost:int,   // additional cost of traversing, but 0 is not walkable (excluded from neighbour list)
}

Node :: struct {
    using position: Position,   // make pos & cost local variables
    neighbours:[]^Node,         // slice of Node pointers assigned from neighbour buffer
    // --- runtime (A*) ---
    g_cost: f32,        // cost from start
    f_cost: f32,        // g + heuristic
    index: int,         // index from start
    previous: ^Node,    // previous node
    opened: bool,       // in queue
    closed: bool,       // already processed
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

NodeSort :: proc(a,b:^Node)->bool{
    return a.f_cost < b.f_cost
}

// Calculate pure path slice
GetPathSlice :: proc(end: ^Node, buffer: []vec2i)->[]vec2i {
    assert(len(buffer) >= end.index + 1)
    result: = buffer[:(end.index + 1)]
    current: = end
    for i:int = end.index; i > -1; i -= 1 {
        result[i] = current.pos
        current = current.previous
    }
    return result
}