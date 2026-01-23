package demo

import rl "vendor:raylib"
import gm ".." // geometry2d

state_closest:State = {
    enter = state_enter_closest,
    exit = state_exit_closest,
    update = state_update_closest,
    draw = state_draw_closest,
}

ClosestState::struct{
    pos_a:vec2,
    pos_b:vec2,
    pos_c:vec2,
}
closest_state_data:ClosestState

state_enter_closest :: proc() {
    closest_state_data.pos_a = {100,100}
    closest_state_data.pos_b = {400,100}
    closest_state_data.pos_c = {400,400}
}

state_exit_closest :: proc() {
    
}

state_update_closest :: proc() {
    if is_hovering_buttons {
        return
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
        closest_state_data.pos_a = rl.GetMousePosition()
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
        closest_state_data.pos_b = rl.GetMousePosition()
    }
}

state_draw_closest :: proc() {
    mouse_pos:Vector2 = rl.GetMousePosition()

    shape_a: gm.Line = {closest_state_data.pos_a.x, closest_state_data.pos_a.y, mouse_pos.x, mouse_pos.y}
    shape_b: gm.Line = {
        closest_state_data.pos_b.x, 
        closest_state_data.pos_b.y, 
        closest_state_data.pos_c.x, 
        closest_state_data.pos_c.y,
    }
    
    rl.DrawLineV(shape_a.xy, shape_a.zw, rl.DARKGRAY)
    rl.DrawLineV(shape_b.xy, shape_b.zw, rl.DARKGRAY)

    point:vec2 = gm.ClosestLineLine(shape_a, shape_b)
    rl.DrawCircleV(point, 5, rl.RED)
}