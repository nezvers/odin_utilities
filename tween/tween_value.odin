package tween

// import "core:math/ease"
import "base:intrinsics"

Value :: struct($T:typeid) {
    ptr: ^T,
    from: T,
    to: T,
    lerp: proc "contextless" (p: f32) -> f32, // math/ease or custom
}

// Generic function
TweenValue :: proc {
    TweenFloat,
    TweenFloat2,
    TweenFloat4,
    TweenInt,
    TweenInt2,
    TweenInt4,
}

TweenValueUpdate :: proc(tween: ^Tween, delta_time: f32) {
	
}

TweenFloat :: proc(value: Value($T), t: f32) where intrinsics.type_is_float(T) {
    value.ptr^ = value.from + (value.to - value.from) * value.lerp(t)
}

TweenFloat2 :: proc(value: Value([2]$T), t: f32) where intrinsics.type_is_float(T) {
    value.ptr^ = value.from + (value.to - value.from) * value.lerp(t)
}

TweenFloat4 :: proc(value: Value([4]$T), t: f32) where intrinsics.type_is_float(T) {
    value.ptr^ = value.from + (value.to - value.from) * value.lerp(t)
}

TweenInt :: proc(value: Value($T), t: f32) where intrinsics.type_is_integer(T) {
    value.ptr^ = value.from + cast(T)(cast(f32)(value.to - value.from) * value.lerp(t))
}

TweenInt2 :: proc(value: Value([2]$T), t: f32) where intrinsics.type_is_integer(T) {
    value.ptr^ = value.from + cast([2]T)(cast([2]f32)(value.to - value.from) * value.lerp(t))
}

TweenInt4 :: proc(value: Value([4]$T), t: f32) where intrinsics.type_is_integer(T) {
    value.ptr^ = value.from + cast([4]T)(cast([4]f32)(value.to - value.from) * value.lerp(t))
}