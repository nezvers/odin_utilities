package input_rebind_raylib

import rl "vendor:raylib"
import "core:math"

InputNone :: u8

@(private)
DEVICE_COUNT :: 4
@(private)
AXIS_COUNT :: 6
@(private)
axis_state: [DEVICE_COUNT * AXIS_COUNT]f32

InputAxis :: struct {
    id: rl.GamepadAxis,
    device: i32,
    sign: f32,
    dead_zone: f32,
}

InputButton :: struct {
    id: rl.GamepadButton,
    device: i32,
}

InputID :: union {
    InputNone,
    rl.KeyboardKey,
    rl.MouseButton,
    InputButton,
    InputAxis,
}

InputAction :: struct {
    id: InputID,
    name: cstring,
}

IsPressed :: proc(input_id: InputID)->bool {
    switch id in input_id {
    case rl.KeyboardKey:
        return rl.IsKeyPressed(id)
    case rl.MouseButton:
        return rl.IsMouseButtonPressed(id)
    case InputButton:
        return rl.IsGamepadButtonPressed(id.device, id.id)
    case InputAxis:
        // update_axis(id)
        return false
    case InputNone:
        return false
    }
    return false
}

IsReleased :: proc(input_id: InputID)->bool {
    switch id in input_id {
    case rl.KeyboardKey:
        return rl.IsKeyReleased(id)
    case rl.MouseButton:
        return rl.IsMouseButtonReleased(id)
    case InputButton:
        return rl.IsGamepadButtonReleased(id.device, id.id)
    case InputAxis:
        // update_axis(id)
        return false
    case InputNone:
        return false
    }
    return false
}

IsDown :: proc(input_id: InputID)->bool {
    switch id in input_id {
    case rl.KeyboardKey:
        return rl.IsKeyDown(id)
    case rl.MouseButton:
        return rl.IsMouseButtonDown(id)
    case InputButton:
        return rl.IsGamepadButtonDown(id.device, id.id)
    case InputAxis:
        // update_axis(id)
        return false
    case InputNone:
        return false
    }
    return false
}

// Scans every input possibility
// Listens for first input release or axis past DEAD_ZONE
ListenRebind :: proc()->(value:InputID, ok:bool) {
    DEAD_ZONE :: 0.5
    // Test all possible inputs
    
    for id in rl.KeyboardKey {
        if rl.IsKeyReleased(id) {
            ok = true
            value = id
            return
        }
    }

    for id in rl.MouseButton {
        if rl.IsMouseButtonReleased(id) {
            ok = true
            value = id
            return
        }
    }

    for device_index in 0..<4 {
        if !rl.IsGamepadAvailable(cast(i32)device_index) { continue }
        for id in rl.GamepadButton {
            if rl.IsGamepadButtonReleased(cast(i32)device_index, id) {
                ok = true
                value = InputButton {
                    id = id,
                    device = cast(i32)device_index,
                }
                return
            }
        }
    }

    for device_index in 0..<4 {
        if !rl.IsGamepadAvailable(cast(i32)device_index) { continue }
        for id in rl.GamepadAxis {
            axis_value: f32 = rl.GetGamepadAxisMovement(cast(i32)device_index, id)
            if axis_value > DEAD_ZONE {
                ok = true
                value = InputAxis {
                    id = id,
                    device = cast(i32)device_index,
                    sign = 1,
                    dead_zone = DEAD_ZONE,
                }
                return
            } else
            if axis_value < -DEAD_ZONE {
                ok = true
                value = InputAxis {
                    id = id,
                    device = cast(i32)device_index,
                    sign = -1,
                    dead_zone = DEAD_ZONE,
                }
                return
            }
        }
    }
    return
}

update_axis :: proc(id: InputAxis) {
    value: f32 = rl.GetGamepadAxisMovement(id.device, id.id)
    abs: = math.abs(value)
    axis_index:i32 = id.device * cast(i32)id.id
    sign: f32 = value > 0.5 ? 1 : value < 0.5 ? -1 : 0

    value_buffer: f32 = axis_state[axis_index]
    sign_buffer: f32 = value_buffer > 0.5 ? 1 : value_buffer < 0.5 ? -1 : 0
    if sign != sign_buffer {
        axis_state[axis_index] = value
        if abs < id.dead_zone {
            // released
        } else {
            // pressed
        }
    }
}