#+ private file
package demo

import "vendor:raylib"
import "core:strings"
import ui "../"
Element :: ui.Element


@(private="package")
main_menu_state: State = {
    init,
    finit,
    update,
    draw,
}

MENU_BTN_COUNT :: 4
menu_buffer: ui.ElementBuffer(MENU_BTN_COUNT)
menu_elements: []ui.Element // hold popped slice
menu_btn_data: [MENU_BTN_COUNT]ElementContext
menu_ctx: ui.GroupComponent


change_to_options :: proc(element: ^Element) {
    state_change(.Main_Menu)
}

exit_game :: proc(element: ^Element) {
    window_exit = true
}

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
        elem.ctx = &menu_btn_data[i]
        // Cleanup
        menu_btn_data[i] = {}
        menu_btn_data[i].group = &menu_ctx
        // Update position for next button
        button_rect.y += button_rect.height + 5
    }

    get_element_context(&menu_elements[0]).label.text = "New Game"
    get_element_context(&menu_elements[1]).label.text = "Continue"
    get_element_context(&menu_elements[2]).label.text = "Options"
    get_element_context(&menu_elements[3]).label.text = "Exit"

    // button callbacks
    get_element_context(&menu_elements[2]).callbacks.released = change_to_options
    get_element_context(&menu_elements[3]).callbacks.released = exit_game

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

    update_layout()
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

update_layout :: proc() {
    if len(menu_elements) != MENU_BTN_COUNT { return }

    window_size:Vector2 = screen_size
    window_rect: ui.rectf = {0, 0, window_size.x, window_size.y}
    button_size:Vector2 = window_size * {0.2, 0.5 * 0.2}
    font_size: f32 = button_size.y * 0.8
    text_size:i32
    button_position: Vector2
    text: cstring
    element: ^Element
    ctx: ^ElementContext

    element = &menu_elements[0]
    button_position = ui.LerpPosition(window_rect, button_size, {0.5, 0.5})
    element.rect = {button_position.x, button_position.y, button_size.x, button_size.y}
    ctx = get_element_context(element)
    text = strings.unsafe_string_to_cstring(ctx.label.text)
    text_size = raylib.MeasureText(text, cast(i32)font_size)
    ctx.label.size = {cast(f32)text_size, font_size}

    element = &menu_elements[1]
    button_position.y += button_size.y + 5
    element.rect = {button_position.x, button_position.y, button_size.x, button_size.y}
    ctx = get_element_context(element)
    text = strings.unsafe_string_to_cstring(ctx.label.text)
    text_size = raylib.MeasureText(text, cast(i32)font_size)
    ctx.label.size = {cast(f32)text_size, font_size}

    element = &menu_elements[2]
    button_position.y += button_size.y + 5
    element.rect = {button_position.x, button_position.y, button_size.x, button_size.y}
    ctx = get_element_context(element)
    text = strings.unsafe_string_to_cstring(ctx.label.text)
    text_size = raylib.MeasureText(text, cast(i32)font_size)
    ctx.label.size = {cast(f32)text_size, font_size}

    element = &menu_elements[3]
    button_position.y += button_size.y + 5
    element.rect = {button_position.x, button_position.y, button_size.x, button_size.y}
    ctx = get_element_context(element)
    text = strings.unsafe_string_to_cstring(ctx.label.text)
    text_size = raylib.MeasureText(text, cast(i32)font_size)
    ctx.label.size = {cast(f32)text_size, font_size}
}
