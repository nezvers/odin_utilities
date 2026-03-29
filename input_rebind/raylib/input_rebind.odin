package input_rebind_raylib

import rl "vendor:raylib"

InputNone :: u8

InputAxis :: struct {
    id: rl.GamepadAxis,
    device: i32,
    sign: f32,
    previous: f32,
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
        // TODO: track values and depending on previous value determine if just pressed
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
        // TODO: track values and depending on previous value determine if just pressed
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
        // TODO: track values and depending on previous value determine if just pressed
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
                    previous = 0,
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
                    previous = 0,
                }
                return
            }
        }
    }
    return
}