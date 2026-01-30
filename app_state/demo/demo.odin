package demo

import rl "vendor:raylib"
import as ".."

current_state:as.AppStatePtr = &state_title

game_init :: proc() {
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
    if current_state.update != nil {
        current_state.update()
    }
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)

    if current_state.draw != nil {
        current_state.draw()
    }

    rl.EndDrawing()
}
