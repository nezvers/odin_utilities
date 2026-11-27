#+private file
package demo_common

// A tiny game made of three AppStates: a title, the gameplay (jump over the obstacle) and a game over screen. The states are procs without
// parameters (AppState has no context), so the demo keeps the kit context in a global that it refreshes every frame.

import "core:math/ease"
import "core:math/linalg"
import "core:fmt"
import app_state ".."
import kit "../../demo_kit"

@(private="package")
demo_game_states: kit.Demo = {
    name = "game states",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

state_title: app_state.AppState = {name = "title", enter = title_enter, update = title_update, draw = title_draw}
state_gameplay: app_state.AppState = {name = "gameplay", enter = gameplay_enter, update = gameplay_update, draw = gameplay_draw}
state_game_over: app_state.AppState = {name = "game over", update = game_over_update, draw = game_over_draw}

current_state: app_state.AppStatePtr
ctx_now: ^kit.Context
changes: int                // how many times the state changed

init :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    current_state = &state_title
    changes = 0
    if current_state.enter != nil { current_state.enter() }
}

change :: proc(new_state: ^app_state.AppState) {
    app_state.AppStateChange(&current_state, new_state)
    changes += 1
}

update :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    if current_state.update != nil { current_state.update() }
}

draw :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    if current_state.draw != nil { current_state.draw() }
}

mix :: proc(a: kit.Color, b: kit.Color, t: f32) -> kit.Color {
    return {
        u8(linalg.lerp(f32(a.r), f32(b.r), t)),
        u8(linalg.lerp(f32(a.g), f32(b.g), t)),
        u8(linalg.lerp(f32(a.b), f32(b.b), t)),
        255,
    }
}

// ---- title

TITLE_TEXT :: "Title"
TITLE_FONT_SIZE :: 200
SUBTITLE_TEXT :: "Press SPACE to start!"
SUBTITLE_FONT_SIZE :: 50

title_position_time: f32
title_color: kit.Color
bg_color_time: f32
bg_start_color: kit.Color
bg_target_color: kit.Color

title_enter :: proc() {
    title_position_time = 0
    bg_color_time = 1
    ctx_now.background = kit.DARK_GRAY
    title_color = kit.LIGHT_GRAY
    bg_target_color = ctx_now.background
    bg_start_color = ctx_now.background
}

title_update :: proc() {
    ctx: ^kit.Context = ctx_now
    if kit.KeyPressed(&ctx.input, .SPACE) { change(&state_gameplay) }
    // TIMERS
    if title_position_time < 1 {
        title_position_time += ctx.delta_time
        if title_position_time >= 1 {
            title_position_time = 1
            bg_target_color = kit.RAY_WHITE
            bg_start_color = kit.YELLOW
            bg_color_time = 0
            title_color = kit.BLACK
        }
    }
    if bg_color_time < 1 {
        bg_color_time = min(bg_color_time + ctx.delta_time, 1)
        ctx.background = mix(bg_start_color, bg_target_color, ease.cubic_out(bg_color_time))
    }
}

title_draw :: proc() {
    ctx: ^kit.Context = ctx_now
    title_width: f32 = kit.MeasureText(ctx, TITLE_TEXT, TITLE_FONT_SIZE).x
    title_x: f32 = (ctx.screen.x - title_width) * 0.5
    title_y: f32 = ctx.screen.y / 3 - TITLE_FONT_SIZE * 0.5
    kit.DrawText(ctx, TITLE_TEXT, {title_x, linalg.lerp(f32(-TITLE_FONT_SIZE), title_y, ease.cubic_out(title_position_time))}, TITLE_FONT_SIZE, title_color)
    subtitle_width: f32 = kit.MeasureText(ctx, SUBTITLE_TEXT, SUBTITLE_FONT_SIZE).x
    kit.DrawText(ctx, SUBTITLE_TEXT, {(ctx.screen.x - subtitle_width) * 0.5, ctx.screen.y - ctx.screen.y / 3 - SUBTITLE_FONT_SIZE * 0.5}, SUBTITLE_FONT_SIZE, title_color)
}

// ---- gameplay

JUMP_FORCE :: 500
GRAVITY :: 700
OBSTACLE_SPEED :: 600
SPAWN_X :: 1280            // not the width of the window: the same distance, so the same timing, in every window

game_score: i32
floor_y: f32
velocity_y: f32
is_grounded: bool = true
player_rect: kit.Rect = {50, 0, 40, 60}
obstacle_rect: kit.Rect = {20, 0, 40, 40}

gameplay_enter :: proc() {
    ctx: ^kit.Context = ctx_now
    game_score = 0
    ctx.background = kit.RAY_WHITE
    floor_y = ctx.screen.y - ctx.screen.y * 0.3
    player_rect.y = floor_y - player_rect.w
    velocity_y = 0
    is_grounded = true
    obstacle_rect.x = SPAWN_X + obstacle_rect.z
    obstacle_rect.y = floor_y - obstacle_rect.w
}

gameplay_update :: proc() {
    ctx: ^kit.Context = ctx_now
    if kit.KeyPressed(&ctx.input, .BACKSPACE) { change(&state_game_over) }    // leave by hand (escape closes a demo window)

    floor_y = ctx.screen.y - ctx.screen.y * 0.3
    player_ground: f32 = floor_y - player_rect.w
    velocity_y += GRAVITY * ctx.delta_time
    if kit.KeyPressed(&ctx.input, .SPACE) && is_grounded {
        is_grounded = false
        velocity_y = -JUMP_FORCE
    }
    player_rect.y += velocity_y * ctx.delta_time
    if player_rect.y >= player_ground {
        player_rect.y = player_ground
        velocity_y = 0
        is_grounded = true
    }

    obstacle_rect.y = floor_y - obstacle_rect.w
    obstacle_rect.x -= OBSTACLE_SPEED * ctx.delta_time
    if obstacle_rect.x <= -obstacle_rect.z {
        obstacle_rect.x = SPAWN_X + obstacle_rect.z
        game_score += 1
    }
    if rects_overlap(player_rect, obstacle_rect) {
        change(&state_game_over)        // GAME OVER
    }
}

rects_overlap :: proc(a: kit.Rect, b: kit.Rect) -> bool {
    return a.x < b.x + b.z && a.x + a.z > b.x && a.y < b.y + b.w && a.y + a.w > b.y
}

gameplay_draw :: proc() {
    ctx: ^kit.Context = ctx_now
    kit.DrawRect(ctx, {0, floor_y, ctx.screen.x, ctx.screen.y}, kit.LIGHT_GRAY)
    kit.DrawRect(ctx, obstacle_rect, kit.RED)
    kit.DrawRect(ctx, player_rect, kit.DARK_GRAY)
    kit.DrawText(ctx, fmt.tprintf("SCORE: %d", game_score), {10, 10}, 30, kit.DARK_GRAY)
    kit.DrawText(ctx, "SPACE: jump over the obstacle", {10, 50}, 20, kit.GRAY)
}

// ---- game over

game_over_update :: proc() {
    if kit.KeyPressed(&ctx_now.input, .SPACE) { change(&state_title) }
}

game_over_draw :: proc() {
    kit.DrawText(ctx_now, "Gameover", {100, 100}, 50, kit.RED)
    kit.DrawText(ctx_now, "Press SPACE to change state", {100, 400}, 20, kit.BLACK)
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return current_state == &state_title }, "starts on the title"),
    kit.Wait(70),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return title_position_time == 1 && title_color == kit.BLACK }, "the title falls into place and the colors change"),
    kit.Tap(.SPACE),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return current_state == &state_gameplay && game_score == 0 }, "space starts the game: the title state exited, the gameplay state entered"),
    // jump over the first obstacle: it needs about 2 seconds to arrive, the jump lasts 1.4
    kit.Wait(80),
    kit.Tap(.SPACE),
    kit.Wait(120),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return current_state == &state_gameplay && game_score == 1 }, "the jump clears the obstacle and scores"),
    // stand still: the next one hits
    kit.Wait(150),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return current_state == &state_game_over }, "hit by the obstacle: game over"),
    kit.Tap(.SPACE),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return current_state == &state_title && changes == 3 }, "space goes back to the title"),
    kit.Wait(2),
    kit.Capture("app_state_game_states_end"),
    kit.Wait(1),
}
