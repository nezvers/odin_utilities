package demo

import "core:math"
import sp ".."
import rl "vendor:raylib"

state_inertia_spring:State = {
    init_inertia_spring,
    nil,
    update_inertia_spring,
    draw_inertia_spring,
}

init_inertia_spring::proc(){
	circle_velocity = {}
	circle_position = {}
}

update_inertia_spring::proc(){
    
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


draw_inertia_spring::proc(){
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

// Frame independent lerp
expDecay::proc(a:f32, b:f32, decay:f32, dt:f32)->f32{
    // Freya Holmér "Lerp smoothing is broken" - https://youtu.be/LSNQuFEDOyQ?t=2987
    return b + (a - b) * math.exp(-decay * dt)
}

lerp::proc(a:f32, b:f32, t:f32)->f32{
    return a + (b - a) * t
}

inverseLerp::proc(a:f32, b:f32, t:f32)->f32{
    diff:f32 = b - a
    if diff == 0 {
        return 1
    }
    return (t - a) / diff
}

remap::proc(iMin:f32, iMax:f32, oMin:f32, oMax:f32, v:f32)->f32{
    t: = inverseLerp(iMin, iMax, v)
    t = clamp(t, 0, 1)
    return lerp(oMin, oMax, t)
}