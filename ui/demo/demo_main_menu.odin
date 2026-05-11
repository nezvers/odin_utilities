#+ private file
package demo

import "vendor:raylib"
import ui "../"
Element :: ui.Element


@(private="package")
main_menu_state: State = {
    init,
    finit,
    update,
    draw,
}

menu_buffer: ui.ElementBuffer(4)
menu_ctx: ElementContext
menu_elements: []ui.Element

init :: proc() {
    ui.ElementReset(&menu_buffer)
    menu_elements = ui.ElementPop(&menu_buffer, len(menu_buffer.buffer))
    
    button_rect:Rectangle = {10, 10, 150, 25}
    for i:int = 0; i < len(menu_elements); i += 1 {
        elem: ^Element = &menu_elements[i]
        elem.rect = transmute(ui.rectf)button_rect
        // Callbacks defined in ui.odin
        elem.update = button_update_events
        elem.draw = button_draw
        elem.ctx = &menu_ctx
        button_rect.y += button_rect.height + 5
    }

    menu_elements[0].text = "New Game"
    menu_elements[1].text = "Continue"
    menu_elements[2].text = "Options"
    menu_elements[3].text = "Exit"

    // Default selection
    selected_set(&menu_ctx, &menu_elements[0])

    menu_elements[0].neighbours.next = &menu_elements[1]
    menu_elements[0].neighbours.previous = &menu_elements[3]
    menu_elements[1].neighbours.next = &menu_elements[2]
    menu_elements[1].neighbours.previous = &menu_elements[0]
    menu_elements[2].neighbours.next = &menu_elements[3]
    menu_elements[2].neighbours.previous = &menu_elements[1]
    menu_elements[3].neighbours.next = &menu_elements[0]
    menu_elements[3].neighbours.previous = &menu_elements[2]
}

finit :: proc() {}

update :: proc() {
     // Reset pointers that don't carry over frames
    menu_ctx.hover = nil
    menu_ctx.pressed = nil
    menu_ctx.released = nil
    // menu_ctx.selected = nil
    // menu_ctx.held = nil

    update_navigation()

    // TODO: skip when transitioning
    root: ^ui.Element = &menu_elements[0]
    ui.Update(root, menu_elements[:], 0)
}

draw :: proc() {
    root: ^ui.Element = &menu_elements[0]
    ui.Draw(root, menu_elements[:], 0)
}

update_navigation :: proc() {
    menu_ctx.cursor = raylib.GetMousePosition()
    menu_ctx.input_down = raylib.IsMouseButtonDown(.LEFT)

    if raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.DOWN) {
        if menu_ctx.selected != nil {
            selected_next(&menu_ctx)
        }
    }
    if raylib.IsKeyPressed(.W) || raylib.IsKeyPressed(.UP) {
        if menu_ctx.selected != nil {
            selected_previous(&menu_ctx)
        }
    }

    if raylib.IsKeyDown(.SPACE) || raylib.IsKeyDown(.ENTER) {
        selected_hold(&menu_ctx)
    }
}
