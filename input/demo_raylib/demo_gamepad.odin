#+private file
package demo_raylib

// The axes and buttons of the gamepads that are connected, with the state input/raylib reads from them (axes as buttons past a dead zone).
// raylib only: it shows what the gamepad API of raylib reports.

import "core:reflect"
import "core:strings"
import rl "vendor:raylib"
import kit "../../demo_kit"
import input "../raylib"

@(private="package")
demo_gamepad: kit.Demo = {
    name = "gamepad",
    init = init,
    update = update,
    draw = draw,
}

axis_names: [6]cstring
button_names: [int(rl.GamepadButton.RIGHT_THUMB) + 1]cstring

init :: proc(ctx: ^kit.Context) {
    for i in 0 ..< len(axis_names) {
        name, _ := reflect.enum_name_from_value(rl.GamepadAxis(i))
        axis_names[i] = strings.clone_to_cstring(name, context.temp_allocator)
    }
    for i in 0 ..< len(button_names) {
        name, _ := reflect.enum_name_from_value(rl.GamepadButton(i))
        button_names[i] = strings.clone_to_cstring(name, context.temp_allocator)
    }
}

update :: proc(ctx: ^kit.Context) {
    input.UpdateAxis()
}

draw :: proc(ctx: ^kit.Context) {
    X :: 250
    for device in i32(0) ..< 4 {
        if !rl.IsGamepadAvailable(device) { continue }
        rl.DrawText(rl.TextFormat("%d", device), X + 30 * device, 10, 20, rl.BLACK)
    }
    for i in 0 ..< len(axis_names) {
        y: i32 = 40 + 25 * i32(i)
        rl.DrawText(axis_names[i], 10, y, 20, rl.BLACK)
        id: rl.GamepadAxis = rl.GamepadAxis(i)
        for device in i32(0) ..< 4 {
            if !rl.IsGamepadAvailable(device) { continue }
            // a rectangle under the value when the axis is held (past a dead zone)
            axis_state := input.GetAxisState(device, i32(id))
            if axis_state == .pressed || axis_state == .held {
                rl.DrawRectangleRec({X, f32(y), 70, 20}, rl.LIGHTGRAY)
            }
            rl.DrawText(rl.TextFormat("%f", rl.GetGamepadAxisMovement(device, id)), X + 30 * device, y, 20, rl.BLACK)
        }
    }
    for i in 0 ..< len(button_names) {
        y: i32 = 190 + 25 * i32(i)
        rl.DrawText(button_names[i], 10, y, 20, rl.BLACK)
        id: rl.GamepadButton = rl.GamepadButton(i)
        for device in i32(0) ..< 4 {
            if !rl.IsGamepadAvailable(device) { continue }
            rl.DrawText("1" if rl.IsGamepadButtonDown(device, id) else "0", X + 30 * device, y, 20, rl.BLACK)
        }
    }
    kit.DrawText(ctx, "gamepad state: connect a gamepad", {600, 10}, 18, kit.GRAY)
}
