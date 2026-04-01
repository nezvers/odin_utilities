package input_rebind_raylib

import rl "vendor:raylib"
import "core:math"

InputNone :: u8

@(private)
DEVICE_COUNT :: 4
@(private)
AXIS_COUNT :: 6
@(private)
DEAD_ZONE :: 0.5
@(private)
axis_values: [DEVICE_COUNT * AXIS_COUNT]f32
@(private)
axis_sign: [DEVICE_COUNT * AXIS_COUNT]i8

@(private)
ButtonState :: enum u8 {
    none,
    pressed,
    released,
    held,
}
@(private)
axis_state: [DEVICE_COUNT * AXIS_COUNT]ButtonState

InputAxis :: struct {
    id: rl.GamepadAxis,
    device: i32,
    dead_zone: f32,
    sign: i8,
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

@(private)
GetAxisIndex :: proc(device:i32, id: i32)->i32 {
    // d: = device
    // _ = d
    // i: = id
    // _ = i
    return device * AXIS_COUNT + id
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
        axis_index:i32 = GetAxisIndex(id.device, cast(i32)id.id)
        if axis_state[axis_index] != .pressed { return false }
        value: f32 = axis_values[axis_index]
        sign: i8 = value > DEAD_ZONE ? 1 : value < -DEAD_ZONE ? -1 : 0
        return sign == id.sign
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
        axis_index:i32 = GetAxisIndex(id.device, cast(i32)id.id)
        if axis_state[axis_index] != .released { return false }
        id_sign: = id.sign
        return axis_sign[axis_index] == id_sign
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
        axis_index:i32 = GetAxisIndex(id.device, cast(i32)id.id)
        if axis_index == 1 {
            _ = axis_index
        }
        if !(axis_state[axis_index] == .pressed || axis_state[axis_index] == .held) { return false }
        value: f32 = axis_values[axis_index]
        sign: i8 = value > DEAD_ZONE ? 1 : value < -DEAD_ZONE ? -1 : 0
        return sign == id.sign
    case InputNone:
        return false
    }
    return false
}

// Scans every input possibility
// Listens for first input release or axis past DEAD_ZONE
ListenRebind :: proc()->(value:InputID, ok:bool) {
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

    for device_index in cast(i32)0..<4 {
        if !rl.IsGamepadAvailable(device_index) { continue }
        for id in rl.GamepadButton {
            if rl.IsGamepadButtonReleased(device_index, id) {
                ok = true
                value = InputButton {
                    id = id,
                    device = device_index,
                }
                return
            }
        }

        for id in rl.GamepadAxis {
            axis_index: i32 = GetAxisIndex(device_index, cast(i32)id)
            if axis_state[axis_index] != .released { continue }

            // axis_value: f32 = rl.GetGamepadAxisMovement(device_index, id)
            sign: = axis_sign[axis_index]
            if sign > 0 {
                ok = true
                value = InputAxis {
                    id = id,
                    device = device_index,
                    sign = 1,
                    dead_zone = DEAD_ZONE,
                }
                return
            } else {
                ok = true
                value = InputAxis {
                    id = id,
                    device = device_index,
                    sign = -1,
                    dead_zone = DEAD_ZONE,
                }
                return
            }
        }
    }
    return
}

UpdateAxis :: proc() {
    for device:i32 = 0; device < DEVICE_COUNT; device += 1 {
        if !rl.IsGamepadAvailable(device) { continue }
        for axis in rl.GamepadAxis {
            id: InputAxis = {
                device = device,
                dead_zone = DEAD_ZONE,
                id = axis,
            }
            UpdateAxisState(id)
        }
    }
}

GetAxisState :: proc(device: i32, id: i32)->ButtonState {
    assert(device < DEVICE_COUNT)
    assert(id < AXIS_COUNT)
    // d: = device
    // _ = d
    // i: = id
    // _ = i
    return axis_state[device * id]
}

@(private)
UpdateAxisState :: proc(id: InputAxis) {
    axis_index:i32 = GetAxisIndex(id.device, cast(i32)id.id)
    value: f32 = rl.GetGamepadAxisMovement(id.device, id.id)
    abs: = math.abs(value)
    sign: i8 = value > DEAD_ZONE ? 1 : value < -DEAD_ZONE ? -1 : 0

    value_buffer: f32 = axis_values[axis_index]
    sign_buffer: i8 = value_buffer > DEAD_ZONE ? 1 : value_buffer < -DEAD_ZONE ? -1 : 0

    if sign != sign_buffer {
        if axis_index == 1 {
            _ = axis_index
        }
        if abs < id.dead_zone {
            axis_state[axis_index] = .released
        } else {
            axis_state[axis_index] = .pressed
            axis_sign[axis_index] = sign
        }
    } else
    if abs > id.dead_zone {
        if axis_index == 1 {
            _ = axis_index
        }
        axis_state[axis_index] = .held
        axis_sign[axis_index] = sign
    } else
    if abs < id.dead_zone {
        axis_state[axis_index] = .none
    }
    axis_values[axis_index] = value
}