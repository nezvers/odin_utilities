#+private file
package demo

import "core:math"
import sp ".."
import rl "vendor:raylib"

@(private="package")
state_inertia_spring:State = {
    init,
    nil,
    update,
    draw,
}

init::proc(){
	circle_velocity = {}
	circle_position = {}
}

update::proc(){
    
    delta_time:f32 = rl.GetFrameTime()
	target_position:rl.Vector2 = rl.GetMousePosition()
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT){
        circle_position = target_position
    }

    damping:f32 = 10
    freq:f32 = 1
    sp.InertiaSpring(&circle_position.x, &circle_velocity.x, target_position.x, freq, damping, delta_time)
    sp.InertiaSpring(&circle_position.y, &circle_velocity.y, target_position.y, freq, damping, delta_time)
}


draw::proc(){
    rl.DrawCircleV(circle_position, 10, rl.PINK)
}

// Linear motion
MoveToward::proc(a:f32, b:f32, speed:f32, dt:f32)->f32{
    v: = b - a
    stepDist: = speed * dt
    if (stepDist >= abs(v)){
        return b
    }
    return a + math.sign(v) * stepDist
}
