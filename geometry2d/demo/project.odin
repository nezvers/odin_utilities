package demo

import rl "vendor:raylib"
import gm ".." // geometry2d

state_project:State = {
    enter = state_enter_project,
    exit = state_exit_project,
    update = state_update_project,
    draw = state_draw_project,
}

ProjectState::struct{
    pos_a:vec2,
    pos_b:vec2,
}
project_state_data:ProjectState

state_enter_project :: proc() {
    project_state_data.pos_a = {100,200}
    project_state_data.pos_b = {500,300}
}

state_exit_project :: proc() {
    
}

state_update_project :: proc() {
    if is_hovering_buttons {
        return
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
        project_state_data.pos_a = rl.GetMousePosition()
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
        project_state_data.pos_b = rl.GetMousePosition()
    }
}

state_draw_project :: proc() {
    mouse_pos:Vector2 = rl.GetMousePosition()

    shape_a: gm.Circle = {project_state_data.pos_a.x, project_state_data.pos_a.y, 100}
    shape_b: gm.Circle = {project_state_data.pos_b.x, project_state_data.pos_b.y, 100}
    vector:vec2 = mouse_pos - project_state_data.pos_a
    ray: gm.Ray = {project_state_data.pos_a.x, project_state_data.pos_a.y, vector.x, vector.y}
    project_result: = gm.ProjectCircleCircle(shape_a, shape_b, ray)
    
    rl.DrawLineV(shape_a.xy, mouse_pos, rl.DARKGRAY)
    rl.DrawCircleLinesV(shape_a.xy, shape_a.z, rl.LIGHTGRAY)
    rl.DrawCircleLinesV(shape_b.xy, shape_b.z, rl.LIGHTGRAY)

    if project_result.hit {
        stop_pos:vec2 = project_result.point
        rl.DrawCircleLinesV(stop_pos, shape_a.z, rl.RED)
    } else {
        rl.DrawCircleLinesV(mouse_pos, shape_a.z, rl.GRAY)
    }
}