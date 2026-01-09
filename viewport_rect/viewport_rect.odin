package viewport_rect


Rect :: struct {
    x:f32,
    y:f32,
    w:f32, // width
    h:f32, // height
}

Vector2i :: [2]i32

Min :: proc(a:f32, b:f32)->f32 {
    return a < b ? a : b
}

Max :: proc(a:f32, b:f32)->f32 {
    return a > b ? a : b
}

ViewportGetAspectratioPixel :: proc(view_size:Vector2i, window_size:Vector2i)->i32{
    x:i32 = window_size.x / view_size.x
    y:i32 = window_size.y / view_size.y
    result:i32 = (x < y) ? x : y
    return (result > 1) ? result : 1
}

ViewportGetAspectratio :: proc(view_size:Vector2i, window_size:Vector2i)->f32{
    x:f32 = cast(f32)(window_size.x / view_size.x)
    y:f32 = cast(f32)(window_size.y / view_size.y)
    result:f32 = (x < y) ? x : y
    return (result > 0.001) ? result : 0.001
}

// Keep aspect
ViewportKeepAspectPixel :: proc(original: ^Rect, scaled: ^Rect, view_size:Vector2i, window_size:Vector2i){
    ratio: = ViewportGetAspectratioPixel(view_size, window_size)
    original.w = cast(f32)view_size.x
    original.h = cast(f32)view_size.y
    original.x = 0.0
    original.y = 0.0

    scaled.w = cast(f32)(view_size.x * ratio)
    scaled.h = cast(f32)(view_size.y * ratio)
    scaled.x = cast(f32)cast(i32)((cast(f32)window_size.x - scaled.w) * 0.5)
    scaled.y = cast(f32)cast(i32)((cast(f32)window_size.y - scaled.h) * 0.5)
}

ViewportKeepAspect :: proc(original: ^Rect, scaled: ^Rect, view_size:Vector2i, window_size:Vector2i){
    ratio: = ViewportGetAspectratio(view_size, window_size)
    original.w = cast(f32)view_size.x
    original.h = cast(f32)view_size.y
    original.x = 0.0
    original.y = 0.0

    scaled.w = (cast(f32)view_size.x * ratio)
    scaled.h = (cast(f32)view_size.y * ratio)
    scaled.x = cast(f32)cast(i32)((cast(f32)window_size.x - scaled.w) * 0.5)
    scaled.y = cast(f32)cast(i32)((cast(f32)window_size.y - scaled.h) * 0.5)
}

// Keep height
ViewportKeepHeightPixel :: proc(original: ^Rect, scaled: ^Rect, view_size:Vector2i, window_size:Vector2i){
    ratio: = ViewportGetAspectratioPixel(view_size, window_size)
    original.w = cast(f32)(window_size.x / ratio)
    original.h = cast(f32)window_size.y
    original.x = 0.0
    original.y = 0.0

    scaled.w = original.w * cast(f32)ratio
    scaled.h = original.h * cast(f32)ratio
    scaled.x = cast(f32)cast(i32)((cast(f32)window_size.x - scaled.w) * 0.5)
    scaled.y = cast(f32)cast(i32)((cast(f32)window_size.y - scaled.h) * 0.5)
}

ViewportKeepHeight :: proc(original: ^Rect, scaled: ^Rect, view_size:Vector2i, window_size:Vector2i){
    ratio: = ViewportGetAspectratio(view_size, window_size)
    original.w = (cast(f32)window_size.x / ratio)
    original.h = cast(f32)window_size.y
    original.x = 0.0
    original.y = 0.0

    scaled.w = original.w * ratio
    scaled.h = original.h * ratio
    scaled.x = cast(f32)cast(i32)((cast(f32)window_size.x - scaled.w) * 0.5)
    scaled.y = cast(f32)cast(i32)((cast(f32)window_size.y - scaled.h) * 0.5)
}

// Keep width
ViewportKeepWidthPixel :: proc(original: ^Rect, scaled: ^Rect, view_size:Vector2i, window_size:Vector2i){
    ratio: = ViewportGetAspectratioPixel(view_size, window_size)
    original.w = cast(f32)view_size.x
    original.h = cast(f32)(window_size.y / ratio)
    original.x = 0.0
    original.y = 0.0

    scaled.w = cast(f32)cast(i32)(original.w * cast(f32)ratio)
    scaled.h = cast(f32)cast(i32)(original.h * cast(f32)ratio)
    scaled.x = cast(f32)cast(i32)((cast(f32)window_size.x - scaled.w) * 0.5)
    scaled.y = cast(f32)cast(i32)((cast(f32)window_size.y - scaled.h) * 0.5)
}

ViewportKeepWidth :: proc(original: ^Rect, scaled: ^Rect, view_size:Vector2i, window_size:Vector2i){
    ratio: = ViewportGetAspectratio(view_size, window_size)
    original.w = cast(f32)view_size.x
    original.h = (cast(f32)window_size.y / ratio)
    original.x = 0.0
    original.y = 0.0

    scaled.w = (original.w * ratio)
    scaled.h = (original.h * ratio)
    scaled.x = cast(f32)cast(i32)((cast(f32)window_size.x - scaled.w) * 0.5)
    scaled.y = cast(f32)cast(i32)((cast(f32)window_size.y - scaled.h) * 0.5)
}