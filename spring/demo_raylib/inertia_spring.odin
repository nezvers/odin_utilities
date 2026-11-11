#+private file
package demo_raylib

import sp ".."
import rl "vendor:raylib"

@(private="package")
state_inertia_spring:State = {
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

    damping:f32 = 10
    freq:f32 = 1
    sp.InertiaSpring(&position.x, &velocity.x, target_position.x, freq, damping, delta_time)
    sp.InertiaSpring(&position.y, &velocity.y, target_position.y, freq, damping, delta_time)
}


draw::proc(){
    rl.DrawCircleV(position, 10, rl.PINK)
}
