package cool_math

import "core:math"
import "base:intrinsics"
import "core:testing"
sqrt::math.sqrt

Vec2Sign::proc(vec:[2]$T) -> [2]T
where intrinsics.type_is_numeric(T)
{
    return {Sign(vec.x), Sign(vec.y)}
}

Vec2Abs::proc(vec:[2]$T) -> [2]T
where intrinsics.type_is_numeric(T)
{
    return {abs(vec.x), abs(vec.y)}
}

// Returns rectangular area of vector
Vec2Area :: proc(vec:[2]$T) -> T
where intrinsics.type_is_numeric(T)
{
    return vec.x * vec.y
}

// Returns magnitude/length of vector
Vec2Mag :: proc(vec:[2]$T) -> T
where intrinsics.type_is_float(T)
{
    mult:= vec * vec
    return math.sqrt(mult.x + mult.y)
}

// Returns magnitude squared of vector (useful for fast comparisons)
Vec2Mag2 :: proc(vec:[2]$T) -> T
where intrinsics.type_is_numeric(T)
{
    mult:= vec * vec
    return mult.x + mult.y
}

// Returns angle of vector in radians
Vec2Angle :: proc(vec:[2]$T) -> T
where intrinsics.type_is_float(T)
{
    return math.atan2(vec.y, vec.x)
}

// Returns normalised version of vector
// TODO: make it usable for ints without double cast
Vec2Norm :: proc(vec:[2]$T) -> [2]T
where intrinsics.type_is_float(T)
{
    r:T = 1.0 / Vec2Mag(vec)
    return {vec.x * r, vec.y * r}
}

// Returns vector at 90 degrees to this one
Vec2Perp :: proc(vec:[2]$T) -> [2]T
where intrinsics.type_is_numeric(T)
{
    return {-vec.y, vec.x}
}

// Rounds both components down
Vec2Floor :: proc(vec:[2]$T) -> [2]T
where intrinsics.type_is_float(T)
{
    return {math.floor(vec.x), math.floor(vec.y)}
}

// Rounds both components up
Vec2Ceil :: proc(vec:[2]$T) -> [2]T
where intrinsics.type_is_float(T)
{
    return {math.ceil(vec.x), math.ceil(vec.y)}
}

// Rounds both components to closest integer
Vec2Round :: proc(vec:[2]$T) -> [2]T
where intrinsics.type_is_float(T)
{
    return {math.round(vec.x), math.round(vec.y)}
}

// Rotate vector by radians
Vec2Rotate :: proc(vec:[2]$T, angle:T) -> [2]T
where intrinsics.type_is_float(T)
{
    sine:T = math.sin(angle)
    cosi:T = math.cos(angle)
    result:[2]T = {
        vec.x * cosi - vec.y * sine,
        vec.x * sine + vec.y * cosi,
    }
    return result
}

Vec2AngleTo::proc(a:[2]$T, b:[2]T)->T
where intrinsics.type_is_float(T)
{
    result:T = math.atan2(
        Vec2Cross(a,b),
        Vec2Dot(a, b),
    )
    return result
}

Vec2AngleToPoint::proc(a:[2]$T, b:[2]T)->T
where intrinsics.type_is_float(T)
{
    result:T = Vec2Angle(b - a)
    return result
}

Vec2Project::proc(a:[2]$T, b:[2]T)->[2]T
where intrinsics.type_is_numeric(T)
{
    result:[2]T = b * (Vec2Dot(a, b) / Vec2Mag2(b))
    return result
}

// Returns 'element-wise' max of a vector and another vector
Vec2Max :: proc(vec1:[2]$T, vec2:[2]T) -> [2]T
where intrinsics.type_is_numeric(T)
{
    return {max(vec1.x, vec2.x), max(vec1.y, vec2.y)}
}

// Returns 'element-wise' min of a vector and another vector
Vec2Min :: proc(vec1:[2]$T, vec2:[2]T) -> [2]T
where intrinsics.type_is_numeric(T)
{
    return {min(vec1.x, vec2.x), min(vec1.y, vec2.y)}
}

// Calculates scalar dot product between a vector and another vector
Vec2Dot :: proc(vec1:[2]$T, vec2:[2]T) -> T
where intrinsics.type_is_numeric(T)
{
    mult:= vec1 * vec2
    return mult.x + mult.y
}

// Calculates 'scalar' cross product between a vector and another vector (useful for winding orders)
Vec2Cross :: proc(vec1:[2]$T, vec2:[2]T) -> T
where intrinsics.type_is_numeric(T)
{
    // z component of the 3D cross product: x1*y2 - y1*x2 (positive when vec2 is counter clockwise from vec1)
    mult:= vec1.xy * vec2.yx
    return mult.x - mult.y
}

// Treat as polar coordinate (magnitude, angle), return cartesian equivalent (X, Y)
Vec2Cartisian :: proc(vec:[2]$T) -> [2]T
where intrinsics.type_is_float(T)
{
    return {math.cos(vec.y) * vec.x, math.sin(vec.y) * vec.x}
}

// Treat as cartesian coordinate (X, Y), return polar equivalent (magnitude, angle)
Vec2Polar :: proc(vec:[2]$T) -> [2]T
where intrinsics.type_is_float(T)
{
    magnitude:T = Vec2Mag(vec)
    angle:T = Vec2Angle(vec)
    return {magnitude, angle}
}

// Clamp the components of vector in between the 'element-wise' minimum and maximum of 2 other vectors
Vec2Clamp :: proc(val:[2]$T, v_min:[2]T, v_max:[2]T) -> [2]T
where intrinsics.type_is_numeric(T)
{
    result_max:[2]T = Vec2Max(val, v_min)
    result:[2]T = Vec2Min(result_max, v_max)
    return result
}

// Linearly interpolate between vector, and another vector, given normalised parameter 't'
Vec2Lerp :: proc(from:[2]$T, to:[2]T, t:T) -> [2]T
where intrinsics.type_is_float(T)
{
    result:[2]T = from + (to.xy - from.xy) * {t, t}
    return result
}

// Compare if vector is numerically equal to another
Vec2Equal :: proc(vec1:[2]$T, vec2:[2]T) -> bool
where intrinsics.type_is_numeric(T)
{
    return vec1.x == vec2.x && vec1.y == vec2.y
}

// Assuming vector is an incident, given a normal, return the reflection
Vec2Reflect :: proc(v: [2]$T, normal: [2]T) -> [2]T
where intrinsics.type_is_numeric(T)
{
    return 2 * Vec2Dot(v, normal) * normal - v
}

// 
Vec2Bounce :: proc(v:[2]$T, normal:[2]T) -> [2]T
where intrinsics.type_is_numeric(T)
{
    return -Vec2Reflect(v, normal)
}

// 
Vec2Slide :: proc(v:[2]$T, normal:[2]T) -> [2]T
where intrinsics.type_is_numeric(T)
{
    return v - normal * Vec2Dot(v, normal)
}

Vec2LimitLength::proc(v:[2]$T, length:T)->[2]T
where intrinsics.type_is_float(T)
{
    v := v
    l:T = Vec2Mag(v)
    if (l > 0 && length < l){
        v /= l
        v *= length
    }
    return v
}

// --- Tests ---

@(private="file")
near :: proc(a, b: f32, epsilon: f32 = 1e-5) -> bool {
    return abs(a - b) <= epsilon
}

@(test)
test_vec2_measures :: proc(t: ^testing.T) {
    v: [2]f32 = {3, 4}
    testing.expect_value(t, Vec2Mag(v), f32(5))
    testing.expect_value(t, Vec2Mag2(v), f32(25))
    testing.expect_value(t, Vec2Mag2([2]int{3, 4}), 25)
    testing.expect_value(t, Vec2Area([2]int{3, 4}), 12)
    testing.expect_value(t, Vec2Sign([2]f32{-2, 0}), [2]f32{-1, 0})
    testing.expect_value(t, Vec2Abs([2]int{-2, 5}), [2]int{2, 5})
    testing.expect(t, near(Vec2Angle([2]f32{0, 2}), math.PI / 2))
    testing.expect_value(t, Vec2Dot([2]f32{1, 2}, [2]f32{3, 4}), f32(11))
    testing.expect_value(t, Vec2Cross([2]f32{1, 0}, [2]f32{0, 1}), f32(1))         // counter clockwise is positive
    testing.expect_value(t, Vec2Cross([2]f32{0, 1}, [2]f32{1, 0}), f32(-1))
    testing.expect_value(t, Vec2Equal([2]int{1, 2}, [2]int{1, 2}), true)
    testing.expect_value(t, Vec2Equal([2]int{1, 2}, [2]int{1, 3}), false)
}

@(test)
test_vec2_construction_and_rounding :: proc(t: ^testing.T) {
    n: [2]f32 = Vec2Norm([2]f32{0, 5})
    testing.expect(t, near(n.x, 0) && near(n.y, 1))
    testing.expect(t, near(Vec2Mag(Vec2Norm([2]f32{3, 4})), 1))
    testing.expect_value(t, Vec2Perp([2]int{2, 5}), [2]int{-5, 2})
    testing.expect_value(t, Vec2Floor([2]f32{1.7, -1.2}), [2]f32{1, -2})
    testing.expect_value(t, Vec2Ceil([2]f32{1.2, -1.7}), [2]f32{2, -1})
    testing.expect_value(t, Vec2Round([2]f32{1.5, -1.4}), [2]f32{2, -1})

    r: [2]f32 = Vec2Rotate([2]f32{1, 0}, math.PI / 2)
    testing.expect(t, near(r.x, 0) && near(r.y, 1), "a quarter turn counter clockwise")
    testing.expect(t, near(Vec2Mag(Vec2Rotate([2]f32{3, 4}, 1.234)), 5), "rotation keeps the length")
}

@(test)
test_vec2_angles_and_coordinates :: proc(t: ^testing.T) {
    testing.expect(t, near(Vec2AngleTo([2]f32{1, 0}, [2]f32{0, 1}), math.PI / 2))
    testing.expect(t, near(Vec2AngleTo([2]f32{0, 1}, [2]f32{1, 0}), -math.PI / 2))
    testing.expect(t, near(Vec2AngleToPoint([2]f32{1, 1}, [2]f32{1, 5}), math.PI / 2))

    polar: [2]f32 = Vec2Polar([2]f32{0, 2})
    testing.expect(t, near(polar.x, 2) && near(polar.y, math.PI / 2))
    cartesian: [2]f32 = Vec2Cartisian([2]f32{2, math.PI / 2})
    testing.expect(t, near(cartesian.x, 0) && near(cartesian.y, 2))
    back: [2]f32 = Vec2Cartisian(Vec2Polar([2]f32{-3, 4}))
    testing.expect(t, near(back.x, -3) && near(back.y, 4), "polar and back")
}

@(test)
test_vec2_clamp_lerp_and_projection :: proc(t: ^testing.T) {
    testing.expect_value(t, Vec2Max([2]int{1, 9}, [2]int{4, 2}), [2]int{4, 9})
    testing.expect_value(t, Vec2Min([2]int{1, 9}, [2]int{4, 2}), [2]int{1, 2})
    testing.expect_value(t, Vec2Clamp([2]int{-5, 50}, [2]int{0, 0}, [2]int{10, 10}), [2]int{0, 10})
    testing.expect_value(t, Vec2Lerp([2]f32{0, 10}, [2]f32{10, 20}, 0.5), [2]f32{5, 15})
    testing.expect_value(t, Vec2Project([2]f32{3, 4}, [2]f32{2, 0}), [2]f32{3, 0})
}

@(test)
test_vec2_reflect_bounce_slide_limit :: proc(t: ^testing.T) {
    normal: [2]f32 = {0, 1}
    incident: [2]f32 = {1, -1}
    testing.expect_value(t, Vec2Reflect(incident, normal), [2]f32{-1, -1})      // 2(v.n)n - v, the mirror image through the normal
    testing.expect_value(t, Vec2Bounce(incident, normal), [2]f32{1, 1})         // a ball hitting a floor keeps its x and flips its y
    testing.expect_value(t, Vec2Slide([2]f32{3, -2}, normal), [2]f32{3, 0})     // the part along the surface

    limited: [2]f32 = Vec2LimitLength([2]f32{6, 8}, 5)
    testing.expect(t, near(limited.x, 3) && near(limited.y, 4))
    testing.expect_value(t, Vec2LimitLength([2]f32{3, 4}, 10), [2]f32{3, 4})     // shorter than the limit: unchanged
    testing.expect_value(t, Vec2LimitLength([2]f32{0, 0}, 1), [2]f32{0, 0})
}
