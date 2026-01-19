package demo

import rl "vendor:raylib"
import gm ".." // geometry2d

state_intersets:State = {
    enter = state_enter_intersets,
    exit = state_exit_intersets,
    update = state_update_intersets,
    draw = state_draw_intersets,
}

IntersetsState::struct{
    pos_a:vec2,
    pos_b:vec2,
}
intersets_state_data:IntersetsState

state_enter_intersets :: proc() {
    intersets_state_data.pos_a = {100,100}
    intersets_state_data.pos_b = {400,300}
}

state_exit_intersets :: proc() {
    
}

state_update_intersets :: proc() {
    if is_hovering_buttons {
        return
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
        intersets_state_data.pos_a = rl.GetMousePosition()
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
        intersets_state_data.pos_b = rl.GetMousePosition()
    }
}

state_draw_intersets :: proc() {
    mouse_pos:Vector2 = rl.GetMousePosition()

    size:f32 = 100
    shape_a: gm.Line
    shape_a.xy = intersets_state_data.pos_a
    shape_a.zw = mouse_pos

    shape_b: gm.Circle
    shape_b.xy = intersets_state_data.pos_b
    shape_b.z = size
    
   points, point_count: = gm.IntersectsLineCircle(shape_a, shape_b)
    
    rl.DrawLineV(shape_a.xy, mouse_pos, rl.DARKGRAY)
    rl.DrawCircleLinesV(shape_b.xy, size, rl.LIGHTGRAY)

    for i:int = 0; i < point_count; i += 1 {
        pos:vec2 = points[i]
        rl.DrawCircleV(pos, 5, rl.RED)
    }
}