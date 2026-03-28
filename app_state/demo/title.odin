#+private file
package demo

import "core:math/linalg"
import "core:math/ease"
import as ".."
import rl "vendor:raylib"
Color :: rl.Color
Vector2 :: rl.Vector2

@(private="package")
state_title:as.AppState = {
    init,
    nil,
    update,
    draw,
}

TITLE_TEXT :: "Title"
TITLE_FONT_SIZE :: 200
SUBTITLE_TEXT :: "Press SPACE to start!"
SUBTITLE_FONT_SIZE :: 50

title_position_time: f32
title_color: Color
bg_color_time: f32
bg_start_color: Color
bg_target_color: Color

init :: proc() {
    title_position_time = 0
    bg_color_time = 1
    background_color = rl.DARKGRAY
    title_color = rl.LIGHTGRAY
    bg_target_color = background_color
    bg_start_color = background_color
}

update::proc(){
    if rl.IsKeyPressed(rl.KeyboardKey.SPACE){
        as.AppStateChange(&current_state, &state_gameplay)
    }

    // TIMERS
    delta_time: f32 = rl.GetFrameTime()
    if title_position_time < 1 {
        title_position_time += delta_time * 1
        if title_position_time >= 1 {
            title_position_time = 1
            // TODO: Arrived event
            bg_target_color = rl.RAYWHITE
            bg_start_color = rl.YELLOW
            bg_color_time = 0
            title_color = rl.BLACK
        }
    }

    if bg_color_time < 1 {
        bg_color_time += delta_time * 1
        if bg_color_time >= 1 {
            bg_color_time = 1
            // TODO: Arrived event
        }
        background_color = rl.ColorLerp(
            bg_start_color, 
            bg_target_color, 
            ease.cubic_out(bg_color_time),
        )
    }
}

draw::proc(){
    title_width: i32 = rl.MeasureText(TITLE_TEXT, TITLE_FONT_SIZE)
    title_x: f32 = (screen_size.x - cast(f32)title_width) * 0.5
    title_y: f32 = (screen_size.y / 3) - TITLE_FONT_SIZE * 0.5
    title_pos: Vector2 = {
        title_x, 
        linalg.lerp(
            cast(f32)-TITLE_FONT_SIZE, 
            title_y, 
            ease.cubic_out(title_position_time),
        ),
    }

    
    subtitle_width: i32 = rl.MeasureText(SUBTITLE_TEXT, SUBTITLE_FONT_SIZE)
    subtitle_x: f32 = (screen_size.x - cast(f32)subtitle_width) * 0.5
    subtitle_y: f32 = (screen_size.y - screen_size.y / 3) - SUBTITLE_FONT_SIZE * 0.5


    rl.DrawText(TITLE_TEXT, cast(i32)title_pos.x, cast(i32)title_pos.y, TITLE_FONT_SIZE, title_color)
    rl.DrawText(SUBTITLE_TEXT, cast(i32)subtitle_x, cast(i32)subtitle_y, SUBTITLE_FONT_SIZE, title_color)
}

