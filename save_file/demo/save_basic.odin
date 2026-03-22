#+private file
package demo

import save_file ".."
import rl "vendor:raylib"

Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

@(private="package")
state_save_basic:State = {
	init,
	finit,
	update,
	draw,
}

test_rect: Rectangle = {400, 300, 200, 100}
button_save_rect: Rectangle = {10, 40, 100, 25}
button_load_rect: Rectangle = {10, 70, 100, 25}

init :: proc() {

}

finit :: proc() {}
update :: proc() {
	if rl.IsKeyPressed(rl.KeyboardKey.S) {save()}
	if rl.IsKeyPressed(rl.KeyboardKey.L) {load()}
	
	mouse_pos: = rl.GetMousePosition()
	if rl.CheckCollisionPointRec(mouse_pos, button_save_rect) || rl.CheckCollisionPointRec(mouse_pos, button_load_rect) {
		// skip moving logic
		return
	}

	if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
		test_rect.x = mouse_pos.x
		test_rect.y = mouse_pos.y
	}
}

draw :: proc() {
	rl.DrawText("Left mouse - Move", 10, 10, 20, rl.GRAY)
	rl.DrawRectangleRec(test_rect, rl.LIME)
	if rl.GuiButton(button_save_rect, "S - Save") {
		save()
	}
	if rl.GuiButton(button_load_rect, "L - Load") {
		load()
	}
}

save :: proc() {
	file_write: = save_file.create("output.bin")
	defer save_file.close(file_write)
	if file_write != nil {
		save_file.write_append_struct(file_write, &test_rect)
	}
}

load :: proc() {
	file_read: = save_file.read_open("output.bin")
	defer save_file.close(file_read)
	if file_read != nil {
		save_file.read_struct(file_read, &test_rect)
	}
}