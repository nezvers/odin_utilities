package demo

import rl "vendor:raylib"
import gm ".." // geometry2d

state_aabb:State = {
    enter = state_enter_aabb,
    exit = state_exit_aabb,
    update = state_update_aabb,
    draw = state_draw_aabb,
}

AABBState::struct{
    pos_a:vec2,
    pos_b:vec2,
}
aabb_state_data:AABBState

state_enter_aabb :: proc() {
    aabb_state_data.pos_a = {100,100}
    aabb_state_data.pos_b = {400,100}
}

state_exit_aabb :: proc() {
    
}

state_update_aabb :: proc() {
    if is_hovering_buttons {
        return
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
        aabb_state_data.pos_a = rl.GetMousePosition()
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
        aabb_state_data.pos_b = rl.GetMousePosition()
    }
}

state_draw_aabb :: proc() {
    mouse_pos:Vector2 = rl.GetMousePosition()

    size:vec2 = {100, 100}
    shape_a: gm.Rect = {aabb_state_data.pos_a.x, aabb_state_data.pos_a.y, size.x, size.y}
    shape_b: gm.Rect = {aabb_state_data.pos_b.x, aabb_state_data.pos_b.y, size.x, size.y}
    offset:vec2 = size * 0.5
    center_a:vec2 = aabb_state_data.pos_a + offset
    vector:vec2 = mouse_pos - center_a
    
   aabb_result: = gm.AABBRectRect(shape_a, shape_b, vector)
    
    rl.DrawLineV(center_a, mouse_pos, rl.DARKGRAY)
    rl.DrawRectangleLinesEx(transmute(Rectangle)shape_a, 1, rl.LIGHTGRAY)
    rl.DrawRectangleLinesEx(transmute(Rectangle)shape_b, 1, rl.LIGHTGRAY)

    if aabb_result.hit {
        stop_pos:vec2 = aabb_result.point
        shape_a.xy = stop_pos - offset
        rl.DrawRectangleLinesEx(transmute(Rectangle)shape_a, 1, rl.RED)
    } else {
        shape_a.xy = mouse_pos - offset
        rl.DrawRectangleLinesEx(transmute(Rectangle)shape_a, 1, rl.GRAY)
    }
}