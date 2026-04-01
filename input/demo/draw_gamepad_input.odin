#+private file
package demo

import "core:reflect"
import "core:strings"
import input "../raylib"

import rl "vendor:raylib"

@(private="package")
state_draw_gamepad_input:State = {
    init,
    finit,
    update,
    draw,
}

// Draw
is_init: bool = false
axis_names: [6]cstring = {}
button_names: [cast(int)rl.GamepadButton.RIGHT_THUMB + 1]cstring = {}

init :: proc() {
    if is_init { return }
    is_init = true
    for i:int; i < 6; i += 1 {
		name, _: = reflect.enum_name_from_value(cast(rl.GamepadAxis)i)
		axis_names[i] = strings.clone_to_cstring(name)
	}

    for i:int; i < (cast(int)rl.GamepadButton.RIGHT_THUMB + 1); i += 1 {
		name, _: = reflect.enum_name_from_value(cast(rl.GamepadButton)i)
		button_names[i] = strings.clone_to_cstring(name)
	}
}

finit :: proc() {}

update :: proc() {
    input.UpdateAxis()
}

draw :: proc() {
    X :: 250
    for device:i32 = 0; device < 4; device += 1 {
        if !rl.IsGamepadAvailable(device) { continue }
        device_t: cstring = rl.TextFormat("%d", device)
        rl.DrawText(device_t, X + 30 * device, 10, 20, rl.BLACK)
    }

    for i:int = 0; i < len(axis_names); i += 1 {
        Y: i32 = 40 + 25 * cast(i32)i
        rl.DrawText(axis_names[i], 10, Y, 20, rl.BLACK)
        id: rl.GamepadAxis = cast(rl.GamepadAxis)i
        for device:i32 = 0; device < 4; device += 1 {
            if !rl.IsGamepadAvailable(device) { continue }
            // Draw rectangle under if axis is held (past a dead zone)
            axis_state: = input.GetAxisState(device, cast(i32)id)
            if axis_state == .pressed || axis_state == .held {
                rect:rl.Rectangle = {X, cast(f32)Y, 70, 20}
                rl.DrawRectangleRec(rect, rl.LIGHTGRAY)
            }
            
            value: f32 = rl.GetGamepadAxisMovement(device, id)
            axis_t: cstring = rl.TextFormat("%f", value)
            rl.DrawText(axis_t, X + 30 * device, Y, 20, rl.BLACK)
        }
    }

    
    for i:int = 0; i < len(button_names); i += 1 {
        Y: i32 = 190 + 25 * cast(i32)i
        rl.DrawText(button_names[i], 10, Y, 20, rl.BLACK)
        id: rl.GamepadButton = cast(rl.GamepadButton)i
        for device:i32 = 0; device < 4; device += 1 {
            if !rl.IsGamepadAvailable(device) { continue }
            held: bool = rl.IsGamepadButtonDown(device, id)
            axis_t: cstring = held ? "1" : "0"
            rl.DrawText(axis_t, X + 30 * device, Y, 20, rl.BLACK)
        }
    }
}