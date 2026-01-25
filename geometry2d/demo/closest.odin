#+private file
package demo

import rl "vendor:raylib"
import gm ".." // geometry2d

@(private="package")
state_closest:State = {
    enter,
    nil,
    update,
    draw,
}

pos_a:vec2
pos_b:vec2
pos_c:vec2

enter :: proc() {
    pos_a = {100,100}
    pos_b = {400,100}
    pos_c = {400,400}
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

    shape_a: gm.Line = {pos_a.x, pos_a.y, mouse_pos.x, mouse_pos.y}
    shape_b: gm.Line = {
        pos_b.x, 
        pos_b.y, 
        pos_c.x, 
        pos_c.y,
    }
    
    rl.DrawLineV(shape_a.xy, shape_a.zw, rl.DARKGRAY)
    rl.DrawLineV(shape_b.xy, shape_b.zw, rl.DARKGRAY)

    point:vec2 = gm.ClosestLineLine(shape_a, shape_b)
    rl.DrawCircleV(point, 5, rl.RED)
}