package demo

import sp ".."
import rl "vendor:raylib"

state_damped_spring:State = {
    init_damped_spring,
    nil,
    update_damped_spring,
    draw_damped_spring,
}

init_damped_spring::proc(){
	circle_velocity = {}
	circle_position = {}
}

update_damped_spring::proc(){
    
    delta_time:f32 = rl.GetFrameTime()
	target_position:rl.Vector2 = rl.GetMousePosition()
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT){
        circle_position = target_position
    }
    springParams:sp.DampedSpringMotionParams = {}
    sp.CalcDampedSpringMotionParams(&springParams, delta_time, 50, 2)
    sp.UpdateDampedSpringMotion(&circle_position.x, &circle_velocity.x, target_position.x, &springParams)
    sp.UpdateDampedSpringMotion(&circle_position.y, &circle_velocity.y, target_position.y, &springParams)
}

draw_damped_spring::proc(){
    rl.DrawCircleV(circle_position, 10, rl.PINK)
}