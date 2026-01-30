#+private file
package demo

import rl "vendor:raylib"
import as ".."

@(private="package")
state_game_over:as.AppState = {
    nil,
    nil,
    update,
    draw,
}

update::proc(){
    if rl.IsKeyPressed(rl.KeyboardKey.SPACE){
        as.AppStateChange(&current_state, &state_title)
    }
}

draw::proc(){
    rl.DrawText("Gameover", 100, 100, 50, rl.RED)
    rl.DrawText("Press SPACE to change state", 100, 400, 20, rl.BLACK)
}