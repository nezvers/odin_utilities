#+private file
package demo

import rl "vendor:raylib"
import input "../raylib"
InputID :: input.InputID
InputButton :: input.InputButton
InputAxis :: input.InputAxis
InputNone :: input.InputNone

@(private="package")
state_input_test:State = {
    init,
    finit,
    update,
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
    {id = InputButton{id = rl.GamepadButton.LEFT_FACE_UP, device = 0}, name = "Up"},
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
    // To update pressed/ released/ down for analog inputs
    input.UpdateAxis()

    delta_time: f32 = rl.GetFrameTime()
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

    if input.IsPressed(input_action.id) {
        input_action.pressed_timer = 1
    }

    if input.IsReleased(input_action.id) {
        input_action.release_timer = 1
    }

    if input.IsDown(input_action.id) {
        input_action.hold_timer = 1
    }
}