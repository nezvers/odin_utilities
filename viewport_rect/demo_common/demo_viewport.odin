#+private file
package demo_common

// The game has a fixed size (320 x 180) and is fitted into the window by one of six rules. No render texture: the scene is drawn straight
// into the projected rectangle with a clip, scaled by the ratio of the two rectangles.

import "core:fmt"
import vp ".."
import kit "../../demo_kit"

@(private="package")
demo_viewport: kit.Demo = {
    name = "viewport",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

view_rect: vp.Rect              // the game, in its own pixels
projected_rect: vp.Rect         // where it is on the window
view_size: vp.Vector2i = {320, 180}
window_size: vp.Vector2i
scaler: [6]proc(^vp.Rect, ^vp.Rect, vp.Vector2i, vp.Vector2i)
scale_index: u8 = 0
mode_names: [6]string = {"Keep aspect (pixel)", "Keep height (pixel)", "Keep width (pixel)", "Keep aspect", "Keep height", "Keep width"}

init :: proc(ctx: ^kit.Context) {
    ctx.background = kit.LIGHT_GRAY
    scaler[0] = vp.ViewportKeepAspectPixel
    scaler[1] = vp.ViewportKeepHeightPixel
    scaler[2] = vp.ViewportKeepWidthPixel
    scaler[3] = vp.ViewportKeepAspect
    scaler[4] = vp.ViewportKeepHeight
    scaler[5] = vp.ViewportKeepWidth
    scale_index = 0
    window_size = {i32(ctx.screen.x), i32(ctx.screen.y)}
    update_resolution()
}

update :: proc(ctx: ^kit.Context) {
    if kit.KeyPressed(&ctx.input, .TAB) {
        scale_index = (scale_index + 1) % 6
        update_resolution()
    }
    size: vp.Vector2i = {i32(ctx.screen.x), i32(ctx.screen.y)}
    if size != window_size {
        window_size = size
        update_resolution()
    }
}

update_resolution :: proc() {
    // Call viewport rectangle calculation
    scaler[scale_index](&view_rect, &projected_rect, view_size, window_size)
}

draw :: proc(ctx: ^kit.Context) {
    projected: kit.Rect = {projected_rect.x, projected_rect.y, projected_rect.w, projected_rect.h}
    kit.DrawRect(ctx, projected, kit.WHITE)
    kit.ClipBegin(ctx, projected)
    // the scene: a circle at the mouse, in the pixels of the game, then to the window
    view_position: kit.Vec2 = screen_to_view(ctx.input.mouse_position)
    ratio: kit.Vec2 = {projected_rect.w / view_rect.w, projected_rect.h / view_rect.h}
    kit.DrawCircle(ctx, {projected_rect.x + view_position.x * ratio.x, projected_rect.y + view_position.y * ratio.y}, 20 * ratio.x, kit.GREEN)
    kit.ClipEnd(ctx)
    kit.DrawRectOutline(ctx, projected, 1, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("%s    TAB to change    game %dx%d on %dx%d", mode_names[scale_index], view_size.x, view_size.y, window_size.x, window_size.y), {10, 10}, 20, kit.BLACK)
}

// A point of the window in the pixels of the game
screen_to_view :: proc(point: kit.Vec2) -> kit.Vec2 {
    relative_position: kit.Vec2 = {point.x - projected_rect.x, point.y - projected_rect.y}
    ratio: kit.Vec2 = {view_rect.w / projected_rect.w, view_rect.h / projected_rect.h}
    return relative_position * ratio
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return projected_rect.w > 0 && projected_rect.w <= f32(window_size.x) && projected_rect.h <= f32(window_size.y) }, "the game fits in the window"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        // keep aspect (pixel): whole multiples of the game size, 16:9 stays
        return projected_rect.w / view_rect.w == projected_rect.h / view_rect.h
    }, "pixel scaling keeps the aspect"),
    // the center of the projected rectangle is the center of the game
    kit.MoveTo({640, 360}),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        center: kit.Vec2 = screen_to_view({projected_rect.x + projected_rect.w * 0.5, projected_rect.y + projected_rect.h * 0.5})
        return abs(center.x - 160) < 0.01 && abs(center.y - 90) < 0.01
    }, "the middle of the projected rectangle is the middle of the game"),
    kit.Tap(.TAB), kit.Tap(.TAB), kit.Tap(.TAB), kit.Tap(.TAB),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return scale_index == 4 }, "tab goes through the rules"),
    kit.Tap(.TAB), kit.Tap(.TAB),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return scale_index == 0 }, "and starts over after six"),
    kit.Wait(2),
    kit.Capture("viewport_rect_viewport_end"),
    kit.Wait(1),
}
