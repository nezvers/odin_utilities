package demo

import rl "vendor:raylib"

import spring ".."


spring_params:spring.SpringParams = {}
spring_cache:[4 * 60]f32
spring_min:f32
spring_max:f32

calculate_spring::proc(){
	position:f32 = 0.0
	target:f32 = 1.0
	spring_min = 0.0
	spring_max = 1.0

	for i in 0..<len(spring_cache){
		spring_cache[i] = position
		if (position < spring_min) {
			spring_min = position
		} else
		if (position > spring_max) {
			spring_max = position
		}
		position = spring.Spring(&spring_params, 0.016, position, target)
	}
}

game_init :: proc() {
	spring_params.k = 37.24
	spring_params.m = 0.3
	spring_params.zeta = 1.7
	spring_params.omega = 6.0
	spring_params.category = spring.SpringCategory.UnderdampedStable
	calculate_spring()
}

update :: proc() {
    if (rl.IsMouseButtonDown(rl.MouseButton.LEFT)){
		
	}
    if (rl.IsMouseButtonDown(rl.MouseButton.RIGHT)){

	}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)



	x:i32 = 10
	y:i32 = 400
	scale:f32 = -100.0
	
	rl.DrawLine(x, y, x + 60 * 4, y, rl.DARKGRAY)
	rl.DrawLine(x, y + i32(scale), x + 60 * 4, y + i32(scale), rl.GRAY)

	for i in 0..< (len(spring_cache) - 1) {
		y1:i32 = i32(spring_cache[i] * scale) + y
		y2:i32 = i32(spring_cache[i + 1] * scale) + y
		x1:i32 = x + i32(i)
		x2:i32 = x1 + 1
		rl.DrawLine(x1, y1, x2, y2, rl.WHITE)
	}

    rl.EndDrawing()
}


game_shutdown :: proc() {
    
}
