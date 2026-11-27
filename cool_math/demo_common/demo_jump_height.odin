#+private file
package demo_common

import "core:fmt"
import cm ".."
import kit "../../demo_kit"

@(private="package")
demo_jump_height: kit.Demo = {
    name = "jump height",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

ground_y: f32 = 600.0
player_rect: kit.Rect = {0, 0, 32, 32}
is_grounded: bool = false
jump_impulse: f32 = 60
gravity: f32 = 60
target_height: f32 = 64
jump_time: f32 = 100        // in hundredths of a second, the spinner shows whole numbers
velocity: kit.Vec2 = {}
timer: f32 = 0

init :: proc(ctx: ^kit.Context) {
    ground_y = 600
    jump_impulse = 60
    gravity = 60
    target_height = 64
    jump_time = 100
    velocity = {}
    timer = 0
    is_grounded = false
    player_rect.x = ctx.screen.x * 0.6 - player_rect.z * 0.5
    player_rect.y = ground_y - player_rect.w
}

update :: proc(ctx: ^kit.Context) {
    delta_time: f32 = ctx.delta_time
    // Order of updating velocity matters relative to updating position, applying gravity, collision and jump impulse
    velocity.y += gravity * delta_time

    // collide with floor
    if player_rect.y + player_rect.w >= ground_y {
        player_rect.y = ground_y - player_rect.w
        is_grounded = true
        velocity.y = 0
        timer = 0
    } else {
        timer += delta_time
    }

    // JUMP
    if kit.KeyPressed(&ctx.input, .SPACE) && is_grounded {
        is_grounded = false
        // Negative impulse, because up direction is negative
        velocity.y = -jump_impulse
    }

    // Update position
    player_rect.y += velocity.y * delta_time
}

SPINNER_X :: 10
BUTTON_X :: 260

draw :: proc(ctx: ^kit.Context) {
    // ground line and the height the jump should reach
    kit.DrawLine(ctx, {0, ground_y}, {ctx.screen.x, ground_y}, 1, kit.BLACK)
    kit.DrawLine(ctx, {player_rect.x - player_rect.z, ground_y - target_height}, {player_rect.x + player_rect.z * 2, ground_y - target_height}, 1, kit.GRAY)
    kit.DrawRect(ctx, player_rect, {158, 255, 0, 255})

    spinner: kit.Rect = {SPINNER_X, 10, 240, 25}
    kit.Spinner(ctx, spinner, "Jump Impulse", &jump_impulse, 1, 1, 1000)
    spinner.y += 30
    kit.Spinner(ctx, spinner, "Gravity", &gravity, 1, 1, 1000)
    spinner.y += 30
    kit.Spinner(ctx, spinner, "Jump Height", &target_height, 1, 1, 1000)
    spinner.y += 30
    kit.Spinner(ctx, spinner, "Time", &jump_time, 1, 1, 10000)

    // Calculation buttons: set one value from two others
    buttons: kit.Rect = {BUTTON_X, 10, 130, 25}
    if kit.Button(ctx, buttons, "Gravity, Time") { jump_impulse = cm.get_impulse_time(gravity, jump_time * 0.01) }
    buttons.y += 30
    if kit.Button(ctx, buttons, "Impulse, Time") { gravity = cm.get_gravity_time(jump_impulse, jump_time * 0.01) }
    buttons.y += 30
    if kit.Button(ctx, buttons, "Impulse, Gravity") { target_height = cm.get_height(jump_impulse, gravity) }
    buttons.y += 30
    if kit.Button(ctx, buttons, "Impulse, Gravity (T)") { jump_time = cm.get_time(jump_impulse, gravity) * 100 }
    // 2nd column
    buttons.x += 10 + buttons.z
    buttons.y = 10
    if kit.Button(ctx, buttons, "Gravity, Height") { jump_impulse = cm.get_impulse_height(target_height, gravity) }

    kit.DrawText(ctx, fmt.tprintf("Time: %.2f", timer), {ctx.screen.x * 0.5, 10}, 20, kit.GRAY)
    kit.DrawText(ctx, "space: jump", {ctx.screen.x * 0.5, 40}, 18, kit.GRAY)
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return is_grounded }, "starts on the ground"),
    // let the demo compute an impulse for the wanted height: the "Gravity, Height" button of the second column
    kit.Click({BUTTON_X + 140 + 10, 20}),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(jump_impulse - cm.get_impulse_height(target_height, gravity)) < 0.001 }, "the button sets the impulse from the height and the gravity"),
    kit.Tap(.SPACE),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !is_grounded && velocity.y < 0 }, "space jumps"),
    kit.Wait(240),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return is_grounded }, "and the player comes down"),
    // the jump reaches the height the formula said: watch the top of it
    kit.Tap(.SPACE),
    kit.Wait(85),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_rect.y + player_rect.w < ground_y - target_height * 0.9 }, "at the top the jump has reached the wanted height"),
    kit.Wait(240),
    kit.Click({SPINNER_X + 220, 20}),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return jump_impulse > 0 }, "the plus of a spinner changes the value"),
    kit.Wait(2),
    kit.Capture("cool_math_jump_height_end"),
    kit.Wait(1),
}
