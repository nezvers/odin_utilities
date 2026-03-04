package quadtree

// x, y, halfWidth, halfHeight
AABB :: [4]f32

AABBCollide :: proc(a,b: AABB)->bool {
    return abs(a.x - b.x) < (a.z + b.z) && abs(a.y - b.y) < (a.w + b.w)
}