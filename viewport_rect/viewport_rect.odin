package viewport_rect
import "core:testing"


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
    // divide as floats, the integer division would turn this into the pixel perfect ratio
    x:f32 = cast(f32)window_size.x / cast(f32)view_size.x
    y:f32 = cast(f32)window_size.y / cast(f32)view_size.y
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
    original.h = cast(f32)view_size.y
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
    original.h = cast(f32)view_size.y
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

// --- Tests ---

@(test)
test_viewport_ratios :: proc(t: ^testing.T) {
    testing.expect_value(t, Min(2, 3), f32(2))
    testing.expect_value(t, Max(2, 3), f32(3))

    testing.expect_value(t, ViewportGetAspectratioPixel({320, 180}, {1000, 700}), i32(3))
    testing.expect_value(t, ViewportGetAspectratioPixel({320, 180}, {800, 600}), i32(2))   // the tighter side decides
    testing.expect_value(t, ViewportGetAspectratioPixel({320, 180}, {100, 100}), i32(1))   // never below one pixel

    testing.expect_value(t, ViewportGetAspectratio({320, 180}, {800, 600}), f32(2.5))      // smooth scaling keeps the fraction
    testing.expect_value(t, ViewportGetAspectratio({320, 180}, {0, 0}), f32(0.001))   // never zero
}

@(test)
test_viewport_keep_aspect :: proc(t: ^testing.T) {
    original, scaled: Rect

    ViewportKeepAspectPixel(&original, &scaled, {320, 180}, {1000, 700})
    testing.expect_value(t, original, Rect{0, 0, 320, 180})
    testing.expect_value(t, scaled, Rect{20, 80, 960, 540})                                // centred, integer scale

    ViewportKeepAspect(&original, &scaled, {320, 180}, {800, 600})
    testing.expect_value(t, original, Rect{0, 0, 320, 180})
    testing.expect_value(t, scaled, Rect{0, 75, 800, 450})                                 // bars above and below
}

@(test)
test_viewport_keep_height :: proc(t: ^testing.T) {
    original, scaled: Rect

    ViewportKeepHeight(&original, &scaled, {320, 180}, {800, 600})
    testing.expect_value(t, original, Rect{0, 0, 320, 180})
    testing.expect_value(t, scaled, Rect{0, 75, 800, 450})

    ViewportKeepHeightPixel(&original, &scaled, {320, 180}, {1000, 700})                   // ratio 3
    testing.expect_value(t, original.h, f32(180))
    testing.expect_value(t, original.w, f32(333))                                          // the view grows sideways to fill the window
    testing.expect_value(t, scaled.h, f32(540))
    testing.expect_value(t, scaled.w, f32(999))
}

@(test)
test_viewport_keep_width :: proc(t: ^testing.T) {
    original, scaled: Rect

    ViewportKeepWidth(&original, &scaled, {320, 180}, {800, 600})
    testing.expect_value(t, original.w, f32(320))
    testing.expect_value(t, original.h, f32(240))                                          // grows downward to fill the window
    testing.expect_value(t, scaled, Rect{0, 0, 800, 600})

    ViewportKeepWidthPixel(&original, &scaled, {320, 180}, {800, 600})                     // ratio 2
    testing.expect_value(t, original, Rect{0, 0, 320, 300})
    testing.expect_value(t, scaled, Rect{80, 0, 640, 600})
}
