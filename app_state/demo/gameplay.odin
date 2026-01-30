#+private file
package demo

import rl "vendor:raylib"
import as ".."

@(private="package")
state_gameplay:as.AppState = {
    nil,
    nil,
    update,
    draw,
}

update::proc(){
    if rl.IsKeyPressed(rl.KeyboardKey.SPACE){
        as.AppStateChange(&current_state, &state_game_over)
    }
}

draw::proc(){
    rl.DrawText("Gameplay", 100, 100, 50, rl.BLUE)
    rl.DrawText("Press SPACE to change state", 100, 400, 20, rl.BLACK)
}