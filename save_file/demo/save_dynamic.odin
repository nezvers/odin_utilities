#+private file
package demo

import save_file ".."
import rl "vendor:raylib"
import "core:mem"
import "core:math/rand"

Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color

@(private="package")
state_save_dynamic:State = {
	init,
	finit,
	update,
	draw,
}

SAVE_FILE :: "save_dynamic.bin"

button_save_rect: Rectangle = {10, 40, 100, 25}
button_load_rect: Rectangle = {10, 70, 100, 25}
button_reset_rect: Rectangle = {10, 100, 100, 25}
button_color_rect: Rectangle = {10, 130, 100, 25}

DataType :: enum {
    Rectangle = 1,
}

SaveHeader :: struct {
    type: DataType,
    count: int,
}

SaveGroupProperty :: struct {
    color: Color,
}

SaveRectangles :: struct {
    using header: SaveHeader,
    using group_property: SaveGroupProperty,
    list: [dynamic]Rectangle,
}

save_data: SaveRectangles = {
    header = {type = DataType.Rectangle},
    group_property = {color = rl.LIME},
}

init :: proc() {
	save_data.list = make_dynamic_array([dynamic]Rectangle)
    load()
}

finit :: proc() {
    reset()
	delete(save_data.list)
}

update :: proc() {
	if rl.IsKeyPressed(rl.KeyboardKey.S) {save()}
	if rl.IsKeyPressed(rl.KeyboardKey.L) {load()}
	
	mouse_pos: = rl.GetMousePosition()
    is_hovering:bool =  rl.CheckCollisionPointRec(mouse_pos, button_save_rect) || 
                        rl.CheckCollisionPointRec(mouse_pos, button_load_rect) || 
                        rl.CheckCollisionPointRec(mouse_pos, button_reset_rect) || 
                        rl.CheckCollisionPointRec(mouse_pos, button_color_rect)
	if is_hovering_buttons || is_hovering {
		// skip mouse input
		return
	}

	if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
		// TODO: new item
		rect:Rectangle = {
			mouse_pos.x,
			mouse_pos.y,
			10 + rand.float32() * 100,
			10 + rand.float32() * 100,
		}

		append(&save_data.list, rect)
		count: = len(save_data.list)
		save_data.header.count = count
	}
}

draw :: proc() {
	rl.DrawText("Left mouse - Create", 10, 10, 20, rl.GRAY)
	
	count: = len(save_data.list)
	for i:int = 0; i < count; i += 1 {
		rl.DrawRectangleRec(save_data.list[i], save_data.group_property.color)
	}

	if rl.GuiButton(button_save_rect, "S - Save") {
		save()
	}
	if rl.GuiButton(button_load_rect, "L - Load") {
		load()
	}
	if rl.GuiButton(button_reset_rect, "Reset") {
		reset()
	}
	if rl.GuiButton(button_color_rect, "Random Color") {
		save_data.group_property.color.r = cast(u8)rand.int32_range(0, 255)
		save_data.group_property.color.g = cast(u8)rand.int32_range(0, 255)
		save_data.group_property.color.b = cast(u8)rand.int32_range(0, 255)
	}
}

save :: proc() {
	file_write: = save_file.create(SAVE_FILE)
	defer save_file.close(file_write)
	if file_write != nil {
		// Just in case update header
		save_data.header.count = len(save_data.list)

		save_file.write_append_struct(file_write, &save_data.header)
		save_file.write_append_struct(file_write, &save_data.group_property)
		
		if save_data.header.count < 1 { return }
        data:[]u8 = mem.byte_slice(&save_data.list[0], size_of(Rectangle) * save_data.header.count)
		save_file.write_append(file_write, data[:])
	}
}

load :: proc() {
    reset()
	file_read: = save_file.read_open(SAVE_FILE)
	defer save_file.close(file_read)
	if file_read != nil {
        header: SaveHeader = {}
		save_file.read_struct(file_read, &header)
        if header.type != DataType.Rectangle { return }

        group_property: SaveGroupProperty = {}
		save_file.read_struct(file_read, &group_property)

        save_data.header = header
        save_data.group_property = group_property

        reserve(&save_data.list, header.count)
		// Makes pointer to 0-th element valid
		resize(&save_data.list, header.count)

        data:[]u8 = mem.byte_slice(&save_data.list[0], size_of(Rectangle) * header.count)
		save_file.read_buffer(file_read, data[:])
	}
}

reset :: proc() {
    clear_dynamic_array(&save_data.list)
}