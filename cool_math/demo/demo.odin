package demo

import rl "vendor:raylib"
import cm ".."

val:f64

game_init :: proc() {
    val = cm.fast_exp(0.1)
}

game_shutdown :: proc() {
	
}

update :: proc() {

}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)


    rl.EndDrawing()
}
