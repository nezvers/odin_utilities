#+private file
package demo

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

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

item : DragRect = {rect = {40, 40, 32, 32,}}
dragged: ^DragRect = nil

init :: proc() {
    dragged = nil
    item.rect.x = 40
    item.rect.y = 40
}

finit :: proc() {

}

update :: proc() {
    mouse_pos: Vector2 = rl.GetMousePosition()
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && dragged == nil {
        if rl.CheckCollisionPointRec(mouse_pos, item.rect) {
            dragged = &item
            dragged.offset = Vector2{dragged.rect.x, dragged.rect.y} - mouse_pos
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
    rl.DrawRectangleRec(item.rect, rl.LIME)
    rl.DrawRectangleLinesEx(item.rect, 1, rl.GRAY)
}