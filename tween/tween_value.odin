package tween

import "core:math"

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
