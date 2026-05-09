package input_karl2d

import "../../karl2d"
import "core:math"

@(private)
ButtonState :: enum u8 {
    none,
    pressed,
    released,
    held,
}
@(private) DEVICE_COUNT :: 4
@(private) AXIS_COUNT :: 6
@(private) DEAD_ZONE :: 0.5
@(private) axis_state: [DEVICE_COUNT * AXIS_COUNT]ButtonState
@(private) axis_values: [DEVICE_COUNT * AXIS_COUNT]f32
@(private) axis_sign: [DEVICE_COUNT * AXIS_COUNT]i8

// Gamepad axis inputs
InputAxis :: struct {
    id: karl2d.Gamepad_Axis,
    device: i32,
    dead_zone: f32,
    sign: i8,
}

// Gamepad button inputs
InputButton :: struct {
    id: karl2d.Gamepad_Button,
    device: i32,
}

InputNone :: u8
// Union of different input types and can be used for rebinding
InputID :: union {
    InputNone,
    karl2d.Keyboard_Key,
    karl2d.Mouse_Button,
    InputButton,
    InputAxis,
}

InputAction :: struct {
    id: InputID,
    name: string,
}

// Check if input is just pressed
WentDown :: proc(input_id: InputID)->bool {
    switch id in input_id {
    case karl2d.Keyboard_Key:
        return karl2d.key_went_down(id)
    case karl2d.Mouse_Button:
        return karl2d.mouse_button_went_down(id)
    case InputButton:
        return karl2d.gamepad_button_went_down(cast(int)id.device, id.id)
    case InputAxis:
        if GetAxisState(id.device, cast(i32)id.id) != .pressed { return false }
        axis_index:i32 = GetAxisIndex(id.device, cast(i32)id.id)
        value: f32 = axis_values[axis_index]
        sign: i8 = GetAxisSign(value)
        return sign == id.sign
    case InputNone:
        return false
    }
    return false
}

// Check if input is just released
WentUp :: proc(input_id: InputID)->bool {
    switch id in input_id {
    case karl2d.Keyboard_Key:
        return karl2d.key_went_up(id)
    case karl2d.Mouse_Button:
        return karl2d.mouse_button_went_up(id)
    case InputButton:
        return karl2d.gamepad_button_went_up(cast(int)id.device, id.id)
    case InputAxis:
        axis_index:i32 = GetAxisIndex(id.device, cast(i32)id.id)
        if GetAxisState(id.device, cast(i32)id.id) != .released { return false }
        id_sign: = id.sign
        return axis_sign[axis_index] == id_sign
    case InputNone:
        return false
    }
    return false
}

// Check if input is just pressed or held
IsHeld :: proc(input_id: InputID)->bool {
    switch id in input_id {
    case karl2d.Keyboard_Key:
        return karl2d.key_is_held(id)
    case karl2d.Mouse_Button:
        return karl2d.mouse_button_is_held(id)
    case InputButton:
        return karl2d.gamepad_button_is_held(cast(int)id.device, id.id)
    case InputAxis:
        if !(GetAxisState(id.device, cast(i32)id.id) == .pressed || GetAxisState(id.device, cast(i32)id.id) == .held) { return false }
        axis_index:i32 = GetAxisIndex(id.device, cast(i32)id.id)
        value: f32 = axis_values[axis_index]
        sign: i8 = GetAxisSign(value)
        return sign == id.sign
    case InputNone:
        return false
    }
    return false
}

// Read float value from inputs
GetValue :: proc(input_id: InputID)->f32 {
    switch id in input_id {
    case karl2d.Keyboard_Key:
        return karl2d.key_is_held(id) ? 1 : 0
    case karl2d.Mouse_Button:
        return karl2d.mouse_button_is_held(id) ? 1 : 0
    case InputButton:
        return karl2d.gamepad_button_is_held(cast(int)id.device, id.id) ? 1 : 0
    case InputAxis:
        axis_index:i32 = GetAxisIndex(id.device, cast(i32)id.id)
        value: f32 = axis_values[axis_index]
        abs: f32 = math.abs(value)
        if abs < id.dead_zone { return 0 }

        sign: i8 = GetAxisSign(value)
        if sign != id.sign { return 0 }
        
        // TODO: improve logic
        // lerp from dead_zone
        return ((abs - id.dead_zone) / (1 - id.dead_zone)) * cast(f32)sign
    case InputNone:
        return 0
    }
    return 0
}

// Read float value for directions -1 to 1
GetValueAxis :: proc(negative: InputID, positive: InputID)->f32 {
    return GetValue(positive) - GetValue(negative)
}

// Scans every input possibility
// Listens for first input release or axis past DEAD_ZONE
ListenRebind :: proc()->(value:InputID, ok:bool) {
    for id in karl2d.Keyboard_Key {
        if karl2d.key_went_up(id) {
            ok = true
            value = id
            return
        }
    }

    for id in karl2d.Mouse_Button {
        if karl2d.mouse_button_went_up(id) {
            ok = true
            value = id
            return
        }
    }

    for device_index in cast(i32)0..<4 {
        if !karl2d.is_gamepad_active(cast(int)device_index) { continue }
        for id in karl2d.Gamepad_Button {
            if karl2d.gamepad_button_went_up(cast(int)device_index, id) {
                ok = true
                value = InputButton {
                    id = id,
                    device = device_index,
                }
                return
            }
        }

        for id in karl2d.Gamepad_Axis {
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

// Update axis state to read them also as button state
UpdateAxis :: proc() {
    for device:i32 = 0; device < DEVICE_COUNT; device += 1 {
        if !karl2d.is_gamepad_active(cast(int)device) { continue }
        for axis in karl2d.Gamepad_Axis {
            id: InputAxis = {
                device = device,
                dead_zone = DEAD_ZONE,
                id = axis,
            }
            UpdateAxisState(id)
        }
    }
}

// Read axis state as button if UpdateAxis has been called at update beginning
GetAxisState :: proc(device: i32, id: i32)->ButtonState {
    assert(device < DEVICE_COUNT)
    assert(id < AXIS_COUNT)
    axis_index: i32 = GetAxisIndex(device, id)
    return axis_state[axis_index]
}

@(private)
GetAxisIndex :: proc(device:i32, id: i32)->i32 {
    return device * AXIS_COUNT + id
}


@(private) GetAxisSign :: proc(value: f32)->i8 {
    sign: i8 = value > DEAD_ZONE ? 1 : value < -DEAD_ZONE ? -1 : 0
    return sign
}

// Logic for comparing axis previous value to determine its button state
@(private) UpdateAxisState :: proc(id: InputAxis) {
    axis_index:i32 = GetAxisIndex(id.device, cast(i32)id.id)
    value: f32 = karl2d.get_gamepad_axis(cast(int)id.device, id.id)
    abs: = math.abs(value)
    sign: i8 = GetAxisSign(value)

    value_buffer: f32 = axis_values[axis_index]
    sign_buffer: i8 = GetAxisSign(value_buffer)

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