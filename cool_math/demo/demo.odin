package demo

import rl "vendor:raylib"
import cm ".."

val:i64

game_init :: proc() {
    val = cm.Sign(cast(i64)-4)
    val = cm.Vec2Mag2( [2]i64{4, 0} )
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
