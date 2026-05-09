#+private file
package game

// import "core:fmt"
import "../../../karl2d"
Vec2 :: karl2d.Vec2
Rect :: karl2d.Rect

import input "../../karl2d"
InputID :: input.InputID
InputButton :: input.InputButton
InputAxis :: input.InputAxis
InputNone :: input.InputNone

@(private="package")
action_state: GameState = {
    init,
    finit,
    process,
    draw,
}

InputAction :: struct {
    using action: input.InputAction,
    // Test visualization
    pressed_timer: f32,
    hold_timer: f32,
    release_timer: f32,
}

input_list: []InputAction = {
    {id = karl2d.Keyboard_Key.W, name = "Up"},
    {id = karl2d.Keyboard_Key.S, name = "Down"},
    {id = karl2d.Keyboard_Key.D, name = "Right"},
    {id = karl2d.Keyboard_Key.A, name = "Left"},
    {id = karl2d.Keyboard_Key.Space, name = "Jump"},
}

selected_rebind: ^InputAction = nil
player_rect: Rect = {0, 0, 32, 32}

init :: proc() {
    background_color = karl2d.LIGHT_BLUE
    player_rect.x = 500
    player_rect.y = 400
}

finit :: proc() {}

process :: proc() {
    // To update pressed/ released/ down for analog inputs
    input.UpdateAxis()
    update_player()

    delta_time: f32 = karl2d.get_frame_time()
    for &input in input_list {
        update_timers(&input, delta_time)
    }

    if selected_rebind == nil { return }
    input_id, listen_ok: = input.ListenRebind()
    if !listen_ok { return }
    // TODO: add validation for new input
    // TODO: you can modify default InputAxis.dead_zone
    selected_rebind.id = input_id
    selected_rebind = nil
}

draw :: proc() {
    karl2d.draw_rect(player_rect, karl2d.RL_LIME)

    karl2d.draw_text("Name", {10, 10}, 20, karl2d.BLACK)
    karl2d.draw_text("P", {200, 10}, 20, karl2d.BLACK)
    karl2d.draw_text("D", {225, 10}, 20, karl2d.BLACK)
    karl2d.draw_text("R", {250, 10}, 20, karl2d.BLACK)
    if selected_rebind != nil {
        karl2d.draw_text(selected_rebind.name, {300, 10}, 20, karl2d.BLACK)
    }

	FONT_SIZE :: 20
	BUTTON_SIZE :Vec2: {150, 25}
	BUTTON_PADDING :f32: 2
    mouse_position: = get_local_mouse_position()
    
    is_hovering_buttons = false
    button_rect:Rect = {275, 35, BUTTON_SIZE.x, BUTTON_SIZE.y}
    for i:int; i < len(input_list); i += 1 {
        input: ^InputAction = &input_list[i]
        karl2d.draw_text(input.name, {10, 35 + BUTTON_SIZE.y * cast(f32)i}, 20, karl2d.BLACK)
        karl2d.draw_rect({200, 35 + BUTTON_SIZE.y * cast(f32)i, 20, 20}, karl2d.color_alpha(karl2d.RL_LIME, cast(u8)(255 * input.pressed_timer)))
        karl2d.draw_rect({225, 35 + BUTTON_SIZE.y * cast(f32)i, 20, 20}, karl2d.color_alpha(karl2d.RL_LIME, cast(u8)(255 * input.hold_timer)))
        karl2d.draw_rect({250, 35 + BUTTON_SIZE.y * cast(f32)i, 20, 20}, karl2d.color_alpha(karl2d.RL_LIME, cast(u8)(255 * input.release_timer)))

        karl2d.draw_rect(button_rect, karl2d.LIGHT_GRAY)
        text: string = selected_rebind == input ? "Waiting" : "Rebind"
		karl2d.draw_text(text, {button_rect.x, button_rect.y}, FONT_SIZE, karl2d.BLACK)
		if (check_hover(mouse_position, button_rect)){
            if karl2d.mouse_button_went_up(.Left) {
                if selected_rebind == nil {
                    selected_rebind = input
                }
            }
			is_hovering_buttons = true
		}
		button_rect.y += BUTTON_SIZE.y + BUTTON_PADDING
	}
}

update_timers :: proc(input_action: ^InputAction, delta_time: f32) {
    input_action.pressed_timer -= delta_time * 4
    if input_action.pressed_timer < 0 {
        input_action.pressed_timer = 0
    }

    input_action.release_timer -= delta_time * 4
    if input_action.release_timer < 0 {
        input_action.release_timer = 0
    }

    input_action.hold_timer -= delta_time * 10
    if input_action.hold_timer < 0 {
        input_action.hold_timer = 0
    }

    if input.WentDown(input_action.id) {
        input_action.pressed_timer = 1
    }

    if input.WentUp(input_action.id) {
        input_action.release_timer = 1
    }

    if input.IsHeld(input_action.id) {
        input_action.hold_timer = 1
    }
}

update_player :: proc() {
    delta_time:f32 = karl2d.get_frame_time()
    x: f32 = input.GetValueAxis(input_list[3].id, input_list[2].id)
    y: f32 = input.GetValueAxis(input_list[0].id, input_list[1].id)
    SPEED :: 200
    player_rect.x += x * SPEED * delta_time
    player_rect.y += y * SPEED * delta_time
}