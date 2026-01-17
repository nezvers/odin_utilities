package geometry2d

// pos = x, y
// dir = z, w
Ray :: [4]f32

RayNew::proc(pos:vec2, vector:vec2)->Ray{
    return {pos.x, pos.y, vector.x, vector.y}
}
