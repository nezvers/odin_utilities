package tween

import "core:math"
import "core:testing"

// Type erased storage for tweened values, every supported type fits in 4 components
Values :: [4]f64

// Types that can be used as a tween property target
ValueKind :: enum {
    NONE,
    F32,
    F64,
    I32,
    F32_2,
    F32_3,
    F32_4,
    I32_2,
    U8_4, // Color
}

// Compile time mapping from type to ValueKind
ValueKindOf :: proc "contextless" ($T:typeid) -> ValueKind {
    when T == f32 {
        return .F32
    } else when T == f64 {
        return .F64
    } else when T == i32 {
        return .I32
    } else when T == [2]f32 {
        return .F32_2
    } else when T == [3]f32 {
        return .F32_3
    } else when T == [4]f32 {
        return .F32_4
    } else when T == [2]i32 {
        return .I32_2
    } else when T == [4]u8 {
        return .U8_4
    } else {
        #panic("tween: unsupported property type, use f32, f64, i32, [2]f32, [3]f32, [4]f32, [2]i32 or [4]u8")
    }
}

// Convert typed value to storage
ValueToStorage :: proc "contextless" (value:$T) -> Values {
    when T == f32 || T == f64 || T == i32 {
        return {cast(f64)value, 0, 0, 0}
    } else when T == [2]f32 || T == [2]i32 {
        return {cast(f64)value.x, cast(f64)value.y, 0, 0}
    } else when T == [3]f32 {
        return {cast(f64)value.x, cast(f64)value.y, cast(f64)value.z, 0}
    } else when T == [4]f32 || T == [4]u8 {
        return {cast(f64)value.x, cast(f64)value.y, cast(f64)value.z, cast(f64)value.w}
    } else {
        #panic("tween: unsupported property type")
    }
}

// Read current value from the property pointer
ValueRead :: proc "contextless" (kind:ValueKind, ptr:rawptr) -> Values {
    switch kind {
    case .NONE:
        return {}
    case .F32:
        return ValueToStorage((cast(^f32)ptr)^)
    case .F64:
        return ValueToStorage((cast(^f64)ptr)^)
    case .I32:
        return ValueToStorage((cast(^i32)ptr)^)
    case .F32_2:
        return ValueToStorage((cast(^[2]f32)ptr)^)
    case .F32_3:
        return ValueToStorage((cast(^[3]f32)ptr)^)
    case .F32_4:
        return ValueToStorage((cast(^[4]f32)ptr)^)
    case .I32_2:
        return ValueToStorage((cast(^[2]i32)ptr)^)
    case .U8_4:
        return ValueToStorage((cast(^[4]u8)ptr)^)
    }
    return {}
}

// Write value into the property pointer. Integer types are rounded
ValueWrite :: proc "contextless" (kind:ValueKind, ptr:rawptr, v:Values) {
    switch kind {
    case .NONE:
    case .F32:
        (cast(^f32)ptr)^ = cast(f32)v.x
    case .F64:
        (cast(^f64)ptr)^ = v.x
    case .I32:
        (cast(^i32)ptr)^ = cast(i32)math.round(v.x)
    case .F32_2:
        (cast(^[2]f32)ptr)^ = {cast(f32)v.x, cast(f32)v.y}
    case .F32_3:
        (cast(^[3]f32)ptr)^ = {cast(f32)v.x, cast(f32)v.y, cast(f32)v.z}
    case .F32_4:
        (cast(^[4]f32)ptr)^ = {cast(f32)v.x, cast(f32)v.y, cast(f32)v.z, cast(f32)v.w}
    case .I32_2:
        (cast(^[2]i32)ptr)^ = {cast(i32)math.round(v.x), cast(i32)math.round(v.y)}
    case .U8_4:
        (cast(^[4]u8)ptr)^ = {ColorChannel(v.x), ColorChannel(v.y), ColorChannel(v.z), ColorChannel(v.w)}
    }
}

@(private="file")
ColorChannel :: proc "contextless" (value:f64) -> u8 {
    return cast(u8)clamp(math.round(value), 0, 255)
}

// --- Tests ---

@(test)
test_value_kind_mapping :: proc(t: ^testing.T) {
    testing.expect_value(t, ValueKindOf(f32), ValueKind.F32)
    testing.expect_value(t, ValueKindOf(f64), ValueKind.F64)
    testing.expect_value(t, ValueKindOf(i32), ValueKind.I32)
    testing.expect_value(t, ValueKindOf([2]f32), ValueKind.F32_2)
    testing.expect_value(t, ValueKindOf([3]f32), ValueKind.F32_3)
    testing.expect_value(t, ValueKindOf([4]f32), ValueKind.F32_4)
    testing.expect_value(t, ValueKindOf([2]i32), ValueKind.I32_2)
    testing.expect_value(t, ValueKindOf([4]u8), ValueKind.U8_4)
}

@(test)
test_value_storage_pads_unused_components :: proc(t: ^testing.T) {
    testing.expect_value(t, ValueToStorage(f32(1.5)), Values{1.5, 0, 0, 0})
    testing.expect_value(t, ValueToStorage(i32(-7)), Values{-7, 0, 0, 0})
    testing.expect_value(t, ValueToStorage([2]f32{1, 2}), Values{1, 2, 0, 0})
    testing.expect_value(t, ValueToStorage([3]f32{1, 2, 3}), Values{1, 2, 3, 0})
    testing.expect_value(t, ValueToStorage([4]u8{10, 20, 30, 255}), Values{10, 20, 30, 255})
}

@(test)
test_value_read_write_round_trip :: proc(t: ^testing.T) {
    f: f32 = 2.5
    d: f64 = -0.125
    i: i32 = 42
    v2: [2]f32 = {1, 2}
    v3: [3]f32 = {1, 2, 3}
    v4: [4]f32 = {1, 2, 3, 4}
    i2: [2]i32 = {-5, 6}
    color: [4]u8 = {1, 2, 3, 4}

    testing.expect_value(t, ValueRead(.F32, &f), Values{2.5, 0, 0, 0})
    testing.expect_value(t, ValueRead(.F64, &d), Values{-0.125, 0, 0, 0})
    testing.expect_value(t, ValueRead(.I32, &i), Values{42, 0, 0, 0})
    testing.expect_value(t, ValueRead(.F32_2, &v2), Values{1, 2, 0, 0})
    testing.expect_value(t, ValueRead(.F32_3, &v3), Values{1, 2, 3, 0})
    testing.expect_value(t, ValueRead(.F32_4, &v4), Values{1, 2, 3, 4})
    testing.expect_value(t, ValueRead(.I32_2, &i2), Values{-5, 6, 0, 0})
    testing.expect_value(t, ValueRead(.U8_4, &color), Values{1, 2, 3, 4})
    testing.expect_value(t, ValueRead(.NONE, &f), Values{})

    ValueWrite(.F32, &f, {9, 0, 0, 0})
    ValueWrite(.F64, &d, {0.5, 0, 0, 0})
    ValueWrite(.F32_2, &v2, {7, 8, 0, 0})
    ValueWrite(.F32_3, &v3, {7, 8, 9, 0})
    ValueWrite(.F32_4, &v4, {5, 6, 7, 8})
    testing.expect_value(t, f, f32(9))
    testing.expect_value(t, d, f64(0.5))
    testing.expect_value(t, v2, [2]f32{7, 8})
    testing.expect_value(t, v3, [3]f32{7, 8, 9})
    testing.expect_value(t, v4, [4]f32{5, 6, 7, 8})

    ValueWrite(.NONE, &f, {1, 1, 1, 1})                                                    // nothing to write to
    testing.expect_value(t, f, f32(9))
}

@(test)
test_value_write_rounds_integers_and_clamps_colors :: proc(t: ^testing.T) {
    i: i32
    ValueWrite(.I32, &i, {2.5, 0, 0, 0})
    testing.expect_value(t, i, i32(3))
    ValueWrite(.I32, &i, {-2.4, 0, 0, 0})
    testing.expect_value(t, i, i32(-2))

    i2: [2]i32
    ValueWrite(.I32_2, &i2, {0.6, -0.6, 0, 0})
    testing.expect_value(t, i2, [2]i32{1, -1})

    color: [4]u8
    ValueWrite(.U8_4, &color, {-30, 127.6, 300, 0.4})                                      // a tween can overshoot, a colour channel cannot
    testing.expect_value(t, color, [4]u8{0, 128, 255, 0})
}
