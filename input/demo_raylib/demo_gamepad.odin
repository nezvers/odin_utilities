#+private file
package demo_raylib

// The axes and buttons of the gamepads that are connected, with the state input/raylib reads from them (axes as buttons past a dead zone).
// raylib only: it shows what the gamepad API of raylib reports.

import "core:fmt"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"
import kit "../../demo_kit"
import input "../glue_raylib"

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
        kit.DrawText(ctx, fmt.tprintf("%d", device), {f32(X + 30 * device), 10}, 20, kit.BLACK)
    }
    for i in 0 ..< len(axis_names) {
        y: i32 = 40 + 25 * i32(i)
        kit.DrawText(ctx, string(axis_names[i]), {10, f32(y)}, 20, kit.BLACK)
        id: rl.GamepadAxis = rl.GamepadAxis(i)
        for device in i32(0) ..< 4 {
            if !rl.IsGamepadAvailable(device) { continue }
            // a rectangle under the value when the axis is held (past a dead zone)
            axis_state := input.GetAxisState(device, i32(id))
            if axis_state == .pressed || axis_state == .held {
                rl.DrawRectangleRec({X, f32(y), 70, 20}, rl.LIGHTGRAY)
            }
            kit.DrawText(ctx, fmt.tprintf("%f", rl.GetGamepadAxisMovement(device, id)), {f32(X + 30 * device), f32(y)}, 20, kit.BLACK)
        }
    }
    for i in 0 ..< len(button_names) {
        y: i32 = 190 + 25 * i32(i)
        kit.DrawText(ctx, string(button_names[i]), {10, f32(y)}, 20, kit.BLACK)
        id: rl.GamepadButton = rl.GamepadButton(i)
        for device in i32(0) ..< 4 {
            if !rl.IsGamepadAvailable(device) { continue }
            kit.DrawText(ctx, "1" if rl.IsGamepadButtonDown(device, id) else "0", {f32(X + 30 * device), f32(y)}, 20, kit.BLACK)
        }
    }
    kit.DrawText(ctx, "gamepad state: connect a gamepad", {600, 10}, 18, kit.GRAY)
}
