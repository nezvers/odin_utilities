#+private file
package demo

import "core:fmt"
import rl "vendor:raylib"
import cm ".."

@(private="package")
state_jump_height:State = {
    init,
    finit,
    update,
    draw,
}

ground_y:f32 = 600.0
player_rect:Rectangle = {0,0, 32, 32}
is_grounded:bool = false

jump_impulse:f32 = 60
gravity:f32 = 60
target_height:f32 = 64
jump_time:f32 = 100 // Gui workaround for integer use to multiply by 100

velocity:Vector2 = {}

timer:f32 = 0

init :: proc(){
    player_rect.x = screen_size.x * 0.6 - player_rect.width * 0.5
    player_rect.y = ground_y - player_rect.height
}

finit :: proc(){
    
}

update :: proc(){
    delta_time:f32 = rl.GetFrameTime()
    
    // Order of updating velocity matters relative to updating position, applying gravity, collision and jump impulse
    velocity.y += gravity * delta_time

    // collide with floor
    if player_rect.y + player_rect.height >= ground_y {
        player_rect.y = ground_y - player_rect.height
        is_grounded = true
        velocity.y = 0
        timer = 0
    } else {
        timer += delta_time
    }

    // JUMP
    if rl.IsKeyPressed(rl.KeyboardKey.SPACE) && is_grounded{
        is_grounded = false
        // Negative impulse, because up direction is negative
        velocity.y = -jump_impulse
    }

    // Update position
    player_rect.y += velocity.y * delta_time
}

draw :: proc(){
    // ground line
    rl.DrawLineV({0, ground_y}, {screen_size.x, ground_y}, rl.BLACK)
    rl.DrawLineV({player_rect.x - player_rect.width, ground_y - target_height}, {player_rect.x + player_rect.width * 2, ground_y - target_height}, rl.GRAY)
    
    // player
    rl.DrawRectangleRec(player_rect, rl.LIME)

    
    rect_spinner:Rectangle = {100, 10, 100, 25}
    @(static) jump_edit_mode:bool
    jump_int:i32 = cast(i32)jump_impulse
    if rl.GuiSpinner(rect_spinner, "Jump Impulse ", &jump_int, 1, 1000, jump_edit_mode) != 0 {
        jump_edit_mode = !jump_edit_mode
    }
    jump_impulse = cast(f32)jump_int
    
    rect_spinner.y += 30
    @(static) gravity_edit_mode:bool
    gravity_int:i32 = cast(i32)gravity
    if rl.GuiSpinner(rect_spinner, "Gravity ", &gravity_int, 1, 1000, gravity_edit_mode) != 0 {
        gravity_edit_mode = !gravity_edit_mode
    }
    gravity = cast(f32)gravity_int
    
    rect_spinner.y += 30
    @(static) height_edit_mode:bool
    height_int:i32 = cast(i32)target_height
    if rl.GuiSpinner(rect_spinner, "Jump Height ", &height_int, 1, 1000, height_edit_mode) != 0 {
        height_edit_mode = !height_edit_mode
    }
    target_height = cast(f32)height_int
    
    rect_spinner.y += 30
    @(static) time_edit_mode:bool
    time_int:i32 = cast(i32)jump_time
    if rl.GuiSpinner(rect_spinner, "Time ", &time_int, 1, 10000, time_edit_mode) != 0 {
        time_edit_mode = !time_edit_mode
        // if !time_edit_mode{
        //     jump_time = cast(f32)time_int
        // }
    }
    jump_time = cast(f32)time_int

    // Calculation buttons
    rect_buttons:Rectangle = {220, 10, 130, 25}
    if rl.GuiButton(rect_buttons, "Gravity, Time") {
        jump_impulse = cm.get_impulse_time(gravity, jump_time * 0.01)
    }
    
    rect_buttons.y += 30
    if rl.GuiButton(rect_buttons, "Impulse, Time") {
        gravity = cm.get_gravity_time(jump_impulse, jump_time * 0.01)
    }
    
    rect_buttons.y += 30
    if rl.GuiButton(rect_buttons, "Impulse, Gravity") {
        target_height = cm.get_height(jump_impulse, gravity)
    }
    
    rect_buttons.y += 30
    if rl.GuiButton(rect_buttons, "Impulse, Gravity") {
        jump_time = cm.get_time(jump_impulse, gravity) * 100
    }
    
    // 2nd column
    rect_buttons.x += 10 + rect_buttons.width
    rect_buttons.y = 10
    if rl.GuiButton(rect_buttons, "Gravity, Height") {
        jump_impulse = cm.get_impulse_height(target_height, gravity)
    }

    // TIMER
    rl.DrawText(fmt.ctprintf("Time: %v", timer), cast(i32)screen_size.x / 2, 10, 20, rl.GRAY)
}