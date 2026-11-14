package geometry2d
import "core:testing"

// AABB - Axis Aligned Bounding Box
// Based on - https://github.com/OneLoneCoder/Javidx9/blob/master/PixelGameEngine/SmallerProjects/OneLoneCoder_PGE_Rectangles.cpp

AABBResult :: struct{
    hit:bool,
    point:vec2,
    normal:vec2,
    t:f32,
}

AABBRayRect :: proc(r:Ray, rect:Rect)->(result:AABBResult){
    // Cache division
    inv_dir:vec2 = 1.0 / r.zw

    // Calculate intersections with rectangle bounding axes
    t_near:vec2 = (rect.xy - r.xy) * inv_dir
    t_far:vec2 = (rect.xy + rect.zw - r.xy) * inv_dir

    if (isnan(t_far.y) || isnan(t_far.x)){
        return
    }
    if (isnan(t_near.y) || isnan(t_near.x)){
        return
    }

    // Sort distances
    if t_near.x > t_far.x {
        temp: = t_near.x
        t_near.x = t_far.x
        t_far.x = temp
    }
    if t_near.y > t_far.y {
        temp: = t_near.y
        t_near.y = t_far.y
        t_far.y = temp
    }

    // Early rejection
    if (t_near.x > t_far.y || t_near.y > t_far.x) {
        return
    }

    // Closest 'time' will be the first contact
    t_hit_near:f32 = max(t_near.x, t_near.y)
    // Furthest 'time' is contact on opposite side of target
    t_hit_far:f32 = min(t_far.x, t_far.y)

    // Reject if ray direction is pointing away from object
    if (t_hit_far < 0) {
        return
    }

    // Invalit t
    if t_hit_near > 1.0 || t_hit_near < 0.0 {
        return
    }

    // Contact point of collision from parametric line equation
    result.point = r.xy + (t_hit_near * r.zw)

    result.t = t_hit_near // TODO: test if not bigger than 1.0
    result.hit = true

    if (t_near.x > t_near.y) {
        if (r.z < 0) {
            result.normal = {1, 0}
        } else {
            result.normal = {-1, 0}
        }
    } else
    if (t_near.x < t_near.y) {
        if (r.w < 0) {
            result.normal = {1, 0}
        } else {
            result.normal = {-1, 0}
        }
    }

    return
}

AABBRectRect :: proc(rect1:Rect, rect2:Rect, dir:vec2)->(result:AABBResult) {
    if (dir.x == 0 && dir.y == 0) {
        return
    }
    half_size:vec2 = rect1.zw * 0.5
    expanded_rect:Rect
    expanded_rect.xy = rect2.xy - half_size
    expanded_rect.zw = rect2.zw + rect1.zw

    ray:Ray
    ray.xy = rect1.xy + half_size
    ray.zw = dir
    result = AABBRayRect(ray, expanded_rect)
    return
}

// --- Tests ---

@(test)
test_aabb_ray_rect :: proc(t: ^testing.T) {
    rect: Rect = {10, 0, 10, 10}
    hit: AABBResult = AABBRayRect(RayNew({0, 5}, {20, 0}), rect)
    testing.expect_value(t, hit.hit, true)
    testing.expect_value(t, hit.point, vec2{10, 5})
    testing.expect_value(t, hit.t, f32(0.5))
    testing.expect_value(t, hit.normal, vec2{-1, 0})

    testing.expect_value(t, AABBRayRect(RayNew({0, 50}, {20, 0}), rect).hit, false)   // passes above
    testing.expect_value(t, AABBRayRect(RayNew({0, 5}, {5, 0}), rect).hit, false)     // too short to reach
    testing.expect_value(t, AABBRayRect(RayNew({30, 5}, {20, 0}), rect).hit, false)   // pointing away

    from_below: AABBResult = AABBRayRect(RayNew({15, 20}, {0, -20}), rect)
    testing.expect_value(t, from_below.hit, true)
    testing.expect_value(t, from_below.point, vec2{15, 10})
}

@(test)
test_aabb_rect_rect :: proc(t: ^testing.T) {
    wall: Rect = {10, 0, 5, 20}
    mover: Rect = {0, 5, 4, 4}
    hit: AABBResult = AABBRectRect(mover, wall, {10, 0})
    testing.expect_value(t, hit.hit, true)
    testing.expect_value(t, hit.normal, vec2{-1, 0})
    testing.expect(t, abs(hit.t - 0.6) < 1e-4, "stops with the right edge on the wall")

    testing.expect_value(t, AABBRectRect(mover, wall, {0, 0}).hit, false)
    testing.expect_value(t, AABBRectRect(mover, wall, {0, 10}).hit, false)
}
