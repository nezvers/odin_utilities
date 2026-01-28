package demo

import fabrik ".."
import rl "vendor:raylib"

POINT_COUNT :: 6

point_list:[POINT_COUNT]rl.Vector2 = {
	{100.0, 100.0},
	{120.0, 100.0},
	{135.0, 100.0},
	{180.0, 100.0},
	{225.0, 100.0},
	{250.0, 100.0},
}

// gets initialized in game_init()
total_length:f32
length_buffer:[POINT_COUNT - 1]f32
start_fabrik:rl.Vector2
end_fabrik:rl.Vector2


game_init :: proc() {
    total_length = fabrik.calculate_lengths(point_list[:], length_buffer[:])
    start_fabrik = point_list[len(point_list)-1]
    end_fabrik = point_list[0]

	// Initialize length buffer for pulling back
	_ = fabrik.calculate_lengths(point_list[:], length_buffer[:])
}

update :: proc() {
    if (rl.IsMouseButtonDown(rl.MouseButton.LEFT)){
		fabrik.fabrik(point_list[:], length_buffer[:], rl.GetMousePosition(), 4, 0.01)
		return
	}
    if (rl.IsMouseButtonDown(rl.MouseButton.RIGHT)){
		// Use FABRIK method to pull points. Requires initialized length buffer.
		fabrik.pull_back(point_list[:], length_buffer[:], rl.GetMousePosition())
		return
	}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

    draw_lines(point_list[:])

    rl.EndDrawing()
}

draw_lines::proc(slice:[]rl.Vector2){
	LINE_COUNT:= len(slice)-1
	percent:f32 = 0.0
	for i in 0..< LINE_COUNT {
		percent = f32(i) / f32(LINE_COUNT -1)
		rl.DrawLineV(slice[i], slice[i+1], rl.ColorLerp(rl.WHITE, rl.RED, percent))
	}
}

game_shutdown :: proc() {
    
}
