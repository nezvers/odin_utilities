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
menu_ctx: ui.ElementContext
menu_elements: []ui.Element

init :: proc() {
    background_color = karl2d.LIGHT_BLUE

    ui.ElementReset(&menu_buffer)
    menu_elements = ui.ElementPop(&menu_buffer, len(menu_buffer.buffer))

    
    button_rect:Rect = {10, 10, 150, 25}
    for i:int = 0; i < len(menu_elements); i += 1 {
        elem: ^Element = &menu_elements[i]
        elem.rect = transmute(ui.rectf)button_rect
        elem.update = button_update
        elem.draw = button_draw
        button_rect.y += button_rect.h + 5
    }

    menu_elements[0].text = "New Game"
    menu_elements[1].text = "Continue"
    menu_elements[2].text = "Options"
    menu_elements[3].text = "Exit"
}

finit :: proc() {}

process :: proc() {
    root: ^ui.Element = &menu_elements[0]
    ui.Update(root, menu_elements[:], 0, &menu_ctx)
}

draw :: proc() {
    root: ^ui.Element = &menu_elements[0]
    ui.Draw(root, menu_elements[:], 0, &menu_ctx)
}

button_update :: proc(element: ^Element) {
    
}

button_draw :: proc(element: ^Element) {
    karl2d.draw_rect(transmute(Rect)element.rect, karl2d.LIGHT_GRAY)
    if len(element.text) > 0 {
        font_size: f32 = element.rect.w * 0.8
        text_size:Vec2 = karl2d.measure_text(element.text, font_size, karl2d.FONT_DEFAULT)
        text_position:Vec2 = element.rect.xy + (element.rect.zw - text_size) * 0.5
        karl2d.draw_text(element.text, text_position, font_size, karl2d.BLACK, karl2d.FONT_DEFAULT)
    }
}