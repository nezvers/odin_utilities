package demo

import as ".."
import rl "vendor:raylib"
Vector2 :: rl.Vector2

current_state:as.AppStatePtr = &state_title
background_color: rl.Color = rl.WHITE

screen_size:Vector2

game_init :: proc() {
	screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
    if current_state.enter != nil {
        current_state.enter()
    }
}

game_shutdown :: proc() {
	if current_state.exit != nil {
        current_state.exit()
    }
}

update :: proc() {
	if rl.IsWindowResized() {
		screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
	}
    if current_state.update != nil {
        current_state.update()
    }
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(background_color)

    if current_state.draw != nil {
        current_state.draw()
    }

    rl.EndDrawing()
}
