#+private file
package demo

import rl "vendor:raylib"
import gm ".." // geometry2d

@(private="package")
state_intersets:State = {
    enter,
    nil,
    update,
    draw,
}

pos_a:vec2
pos_b:vec2

enter :: proc() {
    pos_a = {100,100}
    pos_b = {400,300}
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

    size:f32 = 100
    shape_a: gm.Line
    shape_a.xy = pos_a
    shape_a.zw = mouse_pos

    shape_b: gm.Circle
    shape_b.xy = pos_b
    shape_b.z = size
    
   points, point_count: = gm.IntersectsLineCircle(shape_a, shape_b)
    
    rl.DrawLineV(shape_a.xy, mouse_pos, rl.DARKGRAY)
    rl.DrawCircleLinesV(shape_b.xy, size, rl.LIGHTGRAY)

    for i:int = 0; i < point_count; i += 1 {
        pos:vec2 = points[i]
        rl.DrawCircleV(pos, 5, rl.RED)
    }
}