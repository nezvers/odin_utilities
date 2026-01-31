#+private file
package demo

import sp ".."
import rl "vendor:raylib"

@(private="package")
state_box2d:State = {
    init,
    nil,
    update,
    draw,
}

position:rl.Vector2 = 0.0
velocity:rl.Vector2 = {}

init::proc(){
	velocity = {}
	position = {}
}

update::proc(){
    
    delta_time:f32 = rl.GetFrameTime()
	target_position:rl.Vector2 = rl.GetMousePosition()
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT){
        position = target_position
    }

    HERTZ:f32: 0.4
    DAMPING:f32: 1.5
    offset:rl.Vector2 = position - target_position
    velocity = {
        sp.SpringDamper(HERTZ, DAMPING, offset.x, velocity.x, delta_time),
        sp.SpringDamper(HERTZ, DAMPING, offset.y, velocity.y, delta_time),
    }
    position += velocity
}


draw::proc(){
    rl.DrawCircleV(position, 10, rl.PINK)
}
