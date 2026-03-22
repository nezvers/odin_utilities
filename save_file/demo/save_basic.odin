#+private file
package demo

import save_file ".."
// import "core:strings"
// import "core:fmt"
import rl "vendor:raylib"
import "core:mem"

Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

@(private="package")
state_save_basic:State = {
	init,
	finit,
	update,
	draw,
}

test_rect: Rectangle = {10, 10, 200, 100}

init :: proc() {

}

finit :: proc() {}
update :: proc() {
	if rl.IsKeyPressed(rl.KeyboardKey.S) {save()}
	if rl.IsKeyPressed(rl.KeyboardKey.L) {load()}
	if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
		mouse: = rl.GetMousePosition()
		test_rect.x = mouse.x
		test_rect.y = mouse.y
	}
}

draw :: proc() {
	rl.DrawRectangleRec(test_rect, rl.LIME)
}

save :: proc() {
	file_write: = save_file.create("output.bin")
	defer save_file.close(file_write)
	if file_write != nil {
		data := mem.byte_slice(&test_rect, size_of(Rectangle))
		save_file.write_append(file_write, data[:])
	}
}

load :: proc() {
	file_read: = save_file.read_open("output.bin")
	defer save_file.close(file_read)
	if file_read != nil {
		data := mem.byte_slice(&test_rect, size_of(Rectangle))
		save_file.read_buffer(file_read, data[:])
	}
}