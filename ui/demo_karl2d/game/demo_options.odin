#+private file
package game

// import "core:fmt"
import "../../../karl2d"
import ui "../../"
Element :: ui.Element

@(private="package")
options_state: GameState = {
    init,
    finit,
    process,
    draw,
}

MENU_BTN_COUNT :: 4
menu_buffer: ui.ElementBuffer(MENU_BTN_COUNT)
menu_elements: []ui.Element // hold popped slice
menu_btn_data: [MENU_BTN_COUNT]ElementContext
menu_ctx: ui.GroupComponent

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
        elem.ctx = &menu_btn_data[i]
        // Cleanup
        menu_btn_data[i] = {}
        menu_btn_data[i].group = &menu_ctx
        // Update position for next button
        button_rect.y += button_rect.h + 5
    }

    // TODO: translation/localization
    menu_elements[0].text = "Graphics"
    menu_elements[1].text = "Audio"
    menu_elements[2].text = "Controls"
    menu_elements[3].text = "Back"

    // Default selection
    selected_set(&menu_ctx, &menu_elements[0])

    // Generate neighbours
    for i:int = 0; i < MENU_BTN_COUNT; i += 1 {
        ctx: ^ElementContext = cast(^ElementContext)menu_elements[i].ctx
        neighbours: ^NeighborsComponent = &ctx.neighbours

        next:int = (i + 1) % MENU_BTN_COUNT
        previous:int = (i + MENU_BTN_COUNT - 1) % MENU_BTN_COUNT
        neighbours.next = &menu_elements[next]
        neighbours.previous = &menu_elements[previous]
    }
}

finit :: proc() {}

process :: proc() {
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
    menu_ctx.cursor = karl2d.get_mouse_position()
    menu_ctx.input_down = karl2d.mouse_button_is_held(.Left)

    if karl2d.key_went_down(.S) || karl2d.key_went_down(.Down) {
        if menu_ctx.selected != nil {
            selected_next(&menu_ctx)
        }
    }
    if karl2d.key_went_down(.W) || karl2d.key_went_down(.Up) {
        if menu_ctx.selected != nil {
            selected_previous(&menu_ctx)
        }
    }

    if karl2d.key_is_held(.Space) || karl2d.key_is_held(.Enter) {
        selected_hold(&menu_ctx)
    }
}