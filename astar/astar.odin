package astar

// https://github.com/Horryportier/Astar-odin
// https://github.com/rhoeberg/odin-astar

// https://github.com/godotengine/godot/blob/2327a823578a30f09068f97272598521896d5633/core/math/a_star.cpp#L818

vec2i :: [2]int

Position :: struct {
    pos:vec2i,
    cost:int, // additional cost of traversing, but 0 is not traversal (excluded from neighbour list)
}

Node :: struct {
    using position : Position,
    neighbours:[]^Node,
}

// Consider having a temporary global variable for frequently accessed value, like target positon

// Heuristic 1
DistanceCost :: proc(from:^vec2i, to:^vec2i)->int{
    x:= abs(to.x - from.x)
    y:= abs(to.y - from.y)
    return x + y
}

// Heuristic 2
DistanceCostSquared :: proc(from:^vec2i, to:^vec2i)->int{
    x:= abs(to.x - from.x)
    y:= abs(to.y - from.y)
    return x * x + y * y
}

PathPositionSort :: proc(a,b:PathPosition)->bool{
    return a.distance + a.index < b.distance + b.index
}