#+private file
package demo

import rl "vendor:raylib"
import gm ".." // geometry2d

@(private="package")
state_project:State = {
    enter,
    nil,
    update,
    draw,
}

pos_a:vec2
pos_b:vec2

enter :: proc() {
    pos_a = {100,200}
    pos_b = {500,300}
}

update :: proc() {
    if is_hovering_buttons {
        return
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
        pos_a = rl.GetMousePosition()
    }
    if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
        pos_b = rl.GetMousePosition()
    }
}

draw :: proc() {
    mouse_pos:Vector2 = rl.GetMousePosition()

    shape_a: gm.Circle = {pos_a.x, pos_a.y, 100}
    shape_b: gm.Circle = {pos_b.x, pos_b.y, 100}
    vector:vec2 = mouse_pos - pos_a
    ray: gm.Ray = {pos_a.x, pos_a.y, vector.x, vector.y}
    project_result: = gm.ProjectCircleCircle(shape_a, shape_b, ray)
    
    rl.DrawLineV(shape_a.xy, mouse_pos, rl.DARKGRAY)
    rl.DrawCircleLinesV(shape_a.xy, shape_a.z, rl.LIGHTGRAY)
    rl.DrawCircleLinesV(shape_b.xy, shape_b.z, rl.LIGHTGRAY)

    if project_result.hit {
        stop_pos:vec2 = project_result.point
        rl.DrawCircleLinesV(stop_pos, shape_a.z, rl.RED)
    }
}