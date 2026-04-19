package game

import "core:reflect"
import "../../../karl2d"
Vec2 :: karl2d.Vec2
Rect :: karl2d.Rect

GameState :: struct {
    init: proc(),
    finit: proc(),
    update: proc(),
    draw: proc(),
    gui: proc(),
}

state_list: []GameState = {
    placeholder_state,
}

StateIndex :: enum {
    Placeholder,
	COUNT,
}
state_index:StateIndex = StateIndex.Placeholder
button_names: [StateIndex.COUNT]string
is_hovering_buttons: bool = false

current_state: GameState = placeholder_state

change_game_state :: proc(index:StateIndex) {
    if state_list[state_index].finit != nil{
		state_list[state_index].finit()
	}
	state_index = index
	if state_list[state_index].init != nil{
		state_list[state_index].init()
	}
}

init_game_states :: proc() {
    for i:int; i < cast(int)StateIndex.COUNT; i += 1{
		name, _: = reflect.enum_name_from_value(cast(StateIndex)i)
		button_names[i] = name
	}
    change_game_state(state_index)
}

draw_state_menu :: proc() {
    // GUI BUTTONS
    FONT_SIZE :: 20
	BUTTON_SIZE :Vec2: {150, 25}
	BUTTON_PADDING :f32: 2
    window_size: = get_window_size()
    mouse_position: = get_local_mouse_position()
    
    is_hovering_buttons = false
    button_rect:Rect = {window_size.x - BUTTON_SIZE.x - 10, 10, BUTTON_SIZE.x, BUTTON_SIZE.y}
    for i:int; i < cast(int)StateIndex.COUNT; i += 1{
        karl2d.draw_rect(button_rect, karl2d.LIGHT_GRAY)
		karl2d.draw_text(button_names[i], {button_rect.x, button_rect.y}, FONT_SIZE, karl2d.BLACK)
		if (check_hover(mouse_position, button_rect)){
            if karl2d.mouse_button_went_down(.Left) {
                change_game_state(cast(StateIndex)i)
            }
			is_hovering_buttons = true
		}
		button_rect.y += BUTTON_SIZE.y + BUTTON_PADDING
	}
}

check_hover :: proc(p:Vec2, r:Rect)->bool {
    return p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h
}