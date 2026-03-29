#+private file
package demo

import rl "vendor:raylib"
// import as ".."

@(private="package")
state_input_test:State = {
    init,
    finit,
    update,
    draw,
}

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
    rl.KeyboardKey,
    rl.MouseButton,
    InputButton,
    InputAxis,
}

InputAction :: struct {
    id: InputID,
    name: cstring,
    // Test visualization
    pressed_timer: f32,
    hold_timer: f32,
    release_timer: f32,
}

input_list: []InputAction = {
    {id = rl.KeyboardKey.W, name = "Up"},
    {id = rl.KeyboardKey.S, name = "Down"},
    {id = rl.KeyboardKey.D, name = "Right"},
    {id = rl.KeyboardKey.A, name = "Left"},
    {id = rl.KeyboardKey.SPACE, name = "Jump"},
}

selected_rebind: ^InputAction = nil

init::proc(){
    
}

finit::proc(){
    
}

update::proc(){
    delta_time: f32 = rl.GetFrameTime()
    for &input in input_list {
        update_timers(&input, delta_time)
    }

    if selected_rebind == nil { return }
    input_id, listen_ok: = ListenRebind()
    if !listen_ok { return }
    // TODO: add validation for new input
    selected_rebind.id = input_id
    selected_rebind = nil
}

draw::proc(){
    rl.DrawText("Name", 10, 10, 20, rl.BLACK)
    rl.DrawText("P", 200, 10, 20, rl.BLACK)
    rl.DrawText("D", 225, 10, 20, rl.BLACK)
    rl.DrawText("R", 250, 10, 20, rl.BLACK)
    if selected_rebind != nil {
        rl.DrawText(selected_rebind.name, 300, 10, 20, rl.BLACK)
    }
    
    ROW_HEIGHT :: 25
    for i:int = 0; i < len(input_list); i += 1 {
        input: ^InputAction = &input_list[i]
        rl.DrawText(input.name, 10, 35 + ROW_HEIGHT * cast(i32)i, 20, rl.BLACK)
        rl.DrawRectangleRec({200, 35 + ROW_HEIGHT * cast(f32)i, 20, 20}, rl.ColorAlpha(rl.LIME, input.pressed_timer))
        rl.DrawRectangleRec({225, 35 + ROW_HEIGHT * cast(f32)i, 20, 20}, rl.ColorAlpha(rl.LIME, input.hold_timer))
        rl.DrawRectangleRec({250, 35 + ROW_HEIGHT * cast(f32)i, 20, 20}, rl.ColorAlpha(rl.LIME, input.release_timer))

        // SELECT
        text: cstring = selected_rebind == input ? "Waiting" : "Rebind"
        if rl.GuiButton({275, 35 + ROW_HEIGHT * cast(f32)i, 50, 20}, text) {
            if selected_rebind == nil {
                selected_rebind = input
            }
        }
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

    if IsPressed(input_action.id) {
        input_action.pressed_timer = 1
    }

    if IsReleased(input_action.id) {
        input_action.release_timer = 1
    }

    if IsDown(input_action.id) {
        input_action.hold_timer = 1
    }
}

// Listens for first input release or axis past DEAD_ZONE
ListenRebind :: proc()->(value:InputID, ok:bool)                                                         {
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
    }
    return false
}