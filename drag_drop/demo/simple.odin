#+private file
package demo

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color

@(private="package")
state_simple : State = {
    init,
    finit,
    update,
    draw,
}

DragRect :: struct {
    rect: Rectangle,
    offset: Vector2,
}

Item :: struct {
    using drag_rect: DragRect,
    color: Color,
}

item_list : []Item = {
    {rect = {40, 40, 32, 32,}, color = rl.LIME},
    {rect = {80, 80, 32, 32,}, color = rl.GREEN},
}
dragged: ^DragRect = nil

init :: proc() {
    dragged = nil
}

finit :: proc() {

}

update :: proc() {
    mouse_pos: Vector2 = rl.GetMousePosition()
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && dragged == nil {
        for i:int = 0; i < len(item_list); i += 1 {
            if rl.CheckCollisionPointRec(mouse_pos, item_list[i].rect) {
                dragged = &item_list[i]
                dragged.offset = Vector2{dragged.rect.x, dragged.rect.y} - mouse_pos
            }
        }
    }

    if dragged != nil {
        dragged.rect.x = mouse_pos.x + dragged.offset.x
        dragged.rect.y = mouse_pos.y + dragged.offset.y
        if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) {
            dragged = nil
        }
    }
}

draw :: proc() {
    for i:int = 0; i < len(item_list); i += 1 {
        rl.DrawRectangleRec(item_list[i].rect, item_list[i].color)
        rl.DrawRectangleLinesEx(item_list[i].rect, 1, item_list[i].color)
    }
}