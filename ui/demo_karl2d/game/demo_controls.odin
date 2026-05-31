#+private file
package game

// import "core:fmt"
import "../../../karl2d"
import ui "../../"
Element :: ui.Element

@(private="package")
controls_state: GameState = {
    init,
    finit,
    process,
    draw,
    update_layout,
}

MENU_BTN_COUNT :: 4
menu_buffer: ui.ElementBuffer(MENU_BTN_COUNT)
menu_elements: []ui.Element // hold popped slice
menu_btn_data: [MENU_BTN_COUNT]ElementContext
menu_ctx: ui.GroupComponent


change_to_options :: proc(element: ^Element) {
    change_game_state(.Options)
}

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
    get_element_context(&menu_elements[0]).label.text = "Back"
    get_element_context(&menu_elements[1]).label.text = "W = Up"
    get_element_context(&menu_elements[2]).label.text = "A = Left"
    get_element_context(&menu_elements[3]).label.text = "D = Right"
    get_element_context(&menu_elements[4]).label.text = "S = Down"
    get_element_context(&menu_elements[5]).label.text = "Space = Action"

    // Default selection
    selected_set(&menu_ctx, &menu_elements[0])

    // Callbacks
    get_element_context(&menu_elements[3]).callbacks.released = change_to_options // Back

    // Generate neighbours
    for i:int = 0; i < 1; i += 1 {
        ctx: ^ElementContext = cast(^ElementContext)menu_elements[i].ctx
        neighbours: ^NeighborsComponent = &ctx.neighbours

        next:int = (i + 1) % 1
        previous:int = (i + 1 - 1) % 1
        neighbours.next = &menu_elements[next]
        neighbours.previous = &menu_elements[previous]
    }

    update_layout()
}

finit :: proc() {}

process :: proc() {
    // Reset pointers that don't carry over frames
    menu_ctx.hover = nil
    menu_ctx.pressed = nil
    menu_ctx.released = nil
    // menu_ctx.selected = nil
    // menu_ctx.held = nil

    update_navigation(&menu_ctx)

    // TODO: skip when transitioning
    root: ^ui.Element = &menu_elements[0]
    ui.Update(root, menu_elements[:], 0)
}

draw :: proc() {
    root: ^ui.Element = &menu_elements[0]
    ui.Draw(root, menu_elements[:], 0)
}

update_layout :: proc() {
    if len(menu_elements) != MENU_BTN_COUNT { return }

    BTN_OFFSET :: 1.1
    window_size:Vec2 = get_window_size()
    window_rect: ui.rectf = {0, 0, window_size.x, window_size.y}
    button_size:Vec2 = window_size * {0.4, 0.5 * 0.2}
    font_size: f32 = button_size.y * 0.8
    text_size:Vec2
    element: ^Element
    ctx: ^ElementContext
    button_origin: Vec2 = ui.LerpPosition(window_rect, button_size, {0.5, 0.5})
    button_position: Vec2 = button_origin

    element = &menu_elements[0]
    button_position.y = button_origin.y + (button_size.y * BTN_OFFSET) * 3
    element.rect = {button_position.x, button_position.y, button_size.x, button_size.y}
    ctx = get_element_context(element)
    text_size = karl2d.measure_text(ctx.label.text, font_size, karl2d.FONT_DEFAULT)
    ctx.label.size = text_size


    element = &menu_elements[1]
    button_position.y = button_origin.y + (button_size.y * BTN_OFFSET) * 1
    element.rect = {button_position.x, button_position.y, button_size.x, button_size.y}
    ctx = get_element_context(element)
    text_size = karl2d.measure_text(ctx.label.text, font_size, karl2d.FONT_DEFAULT)
    ctx.label.size = text_size
}