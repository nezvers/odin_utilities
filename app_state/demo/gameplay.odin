#+private file
package demo

import as ".."
import rl "vendor:raylib"
Rectangle :: rl.Rectangle
Vector2 :: rl.Vector2

@(private="package")
game_score: i32 = 0

JUMP_FORCE :: 500
GRAVITY :: 700
OBSTACLE_SPEED :: 600

floor_y: f32
velocity_y: f32 = 0
is_grounded: bool = true
player_rect: Rectangle = {50, 0, 40, 60}

obstacle_rect: Rectangle = {20, 0, 40, 40}

@(private="package")
state_gameplay:as.AppState = {
    init,
    nil,
    update,
    draw,
    "gameplay",
}

init :: proc() {
    game_score = 0
    background_color = rl.RAYWHITE

    floor_y = screen_size.y - screen_size.y * 0.3
    player_ground: f32 = floor_y - player_rect.height
    player_rect.y = player_ground
    is_grounded = true

    obstacle_rect.x = screen_size.x + obstacle_rect.width
    obstacle_rect.y = floor_y - obstacle_rect.height
}

update::proc(){
    if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE){
        as.AppStateChange(&current_state, &state_game_over)
    }

    floor_y = screen_size.y - screen_size.y * 0.3
    player_ground: f32 = floor_y - player_rect.height

    delta_time: f32 = rl.GetFrameTime()
    velocity_y += GRAVITY * delta_time

    if rl.IsKeyPressed(rl.KeyboardKey.SPACE) && is_grounded {
        is_grounded = false
        velocity_y = -JUMP_FORCE
    }

    player_rect.y += velocity_y * delta_time

    if player_rect.y >= player_ground {
        player_rect.y = player_ground
        velocity_y = 0
        if !is_grounded {
            is_grounded = true
        }
    }

    obstacle_rect.y = floor_y - obstacle_rect.height
    obstacle_rect.x -= OBSTACLE_SPEED * delta_time

    if obstacle_rect.x <= -obstacle_rect.width {
        obstacle_rect.x = screen_size.x + obstacle_rect.width
        game_score += 1
    }

    if rl.CheckCollisionRecs(player_rect, obstacle_rect) {
        // GAME OVER
        as.AppStateChange(&current_state, &state_game_over)
    }
}

draw::proc(){
    floor_rect: Rectangle = {0, floor_y, screen_size.x, screen_size.y}
    rl.DrawRectangleRec(floor_rect, rl.LIGHTGRAY)
    
    rl.DrawRectangleRec(obstacle_rect, rl.RED)
    rl.DrawRectangleRec(player_rect, rl.DARKGRAY)

    score_text: cstring = rl.TextFormat("SCORE: %d", game_score)
    rl.DrawText(score_text, 10, 10, 30, rl.DARKGRAY)
}