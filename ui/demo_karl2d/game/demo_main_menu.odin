#+private file
package game

// import "core:fmt"
import "../../../karl2d"
import ui "../../"
Element :: ui.Element

@(private="package")
main_menu_state: GameState = {
    init,
    finit,
    process,
    draw,
}

menu_buffer: ui.ElementBuffer(4)
menu_ctx: ElementContext
menu_elements: []ui.Element

init :: proc() {
    background_color = karl2d.LIGHT_BLUE

    ui.ElementReset(&menu_buffer)
    menu_elements = ui.ElementPop(&menu_buffer, len(menu_buffer.buffer))
    
    button_rect:Rect = {10, 10, 150, 25}
    for i:int = 0; i < len(menu_elements); i += 1 {
        elem: ^Element = &menu_elements[i]
        elem.rect = transmute(ui.rectf)button_rect
        // Callbacks defined in ui.odin
        elem.update = button_update_events
        elem.draw = button_draw
        elem.ctx = &menu_ctx
        button_rect.y += button_rect.h + 5
    }

    menu_elements[0].text = "New Game"
    menu_elements[1].text = "Continue"
    menu_elements[2].text = "Options"
    menu_elements[3].text = "Exit"

    // Default slection
    menu_ctx.selected = &menu_elements[0]
}

finit :: proc() {}

process :: proc() {
    // Reset pointers that don't carry over frames
    menu_ctx.hover = nil
    menu_ctx.pressed = nil
    menu_ctx.released = nil
    // menu_ctx.selected = nil
    // menu_ctx.held = nil
    menu_ctx.cursor = karl2d.get_mouse_position()
    menu_ctx.input_down = karl2d.mouse_button_is_held(.Left)
    root: ^ui.Element = &menu_elements[0]
    ui.Update(root, menu_elements[:], 0)
}

draw :: proc() {
    root: ^ui.Element = &menu_elements[0]
    ui.Draw(root, menu_elements[:], 0)
}