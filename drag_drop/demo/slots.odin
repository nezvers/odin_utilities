#+private file
package demo

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color

@(private="package")
state_slots : State = {
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

Slot :: struct {
    rect: Rectangle,
    item: ^Item,
}

ITEM_SIZE :Vector2: {40, 40}

item_list : []Item = {
    {rect = {0, 0, ITEM_SIZE.x, ITEM_SIZE.y,}, color = rl.LIME},
    {rect = {0, 0, ITEM_SIZE.x, ITEM_SIZE.y,}, color = rl.GREEN},
}

slot_list: []Slot = {
    {rect = {40, 40, ITEM_SIZE.x, ITEM_SIZE.y,}},
    {rect = {85, 40, ITEM_SIZE.x, ITEM_SIZE.y,}},
    {rect = {40, 85, ITEM_SIZE.x, ITEM_SIZE.y,}},
    {rect = {85, 85, ITEM_SIZE.x, ITEM_SIZE.y,}},
    {rect = {200, 40, ITEM_SIZE.x, ITEM_SIZE.y,}},
    {rect = {245, 40, ITEM_SIZE.x, ITEM_SIZE.y,}},
    {rect = {200, 85, ITEM_SIZE.x, ITEM_SIZE.y,}},
    {rect = {245, 85, ITEM_SIZE.x, ITEM_SIZE.y,}},
}

dragged: ^Item = nil
place_slot: ^Slot = nil

init :: proc() {
    dragged = nil
    place_slot = nil
    
    // reset
    for i:int = 0; i < len(slot_list); i += 1 {
        slot_list[i].item = nil
    }

    // assign items
    slot_list[0].item = &item_list[0]
    slot_list[1].item = &item_list[1]

    // set item positions
    for i:int = 0; i < len(slot_list); i += 1 {
        if slot_list[i].item == nil { continue }
        slot_list[i].item.rect.x = slot_list[i].rect.x
        slot_list[i].item.rect.y = slot_list[i].rect.y
    }
}

finit :: proc() {

}

update :: proc() {
    mouse_pos: Vector2 = rl.GetMousePosition()
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && dragged == nil {
        for i:int = 0; i < len(slot_list); i += 1 {
            if rl.CheckCollisionPointRec(mouse_pos, slot_list[i].rect) {
                if slot_list[i].item == nil { continue }
                place_slot = &slot_list[i]
                dragged = place_slot.item
                dragged.offset = Vector2{dragged.rect.x, dragged.rect.y} - mouse_pos
            }
        }
    }

    if dragged != nil {
        dragged.rect.x = mouse_pos.x + dragged.offset.x
        dragged.rect.y = mouse_pos.y + dragged.offset.y
        if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) {
            place_slot.item = nil
            for i:int = 0; i < len(slot_list); i += 1 {
                if slot_list[i].item != nil { continue }
                if !rl.CheckCollisionPointRec(mouse_pos, slot_list[i].rect) { continue }
                place_slot = &slot_list[i]
            }
            place_slot.item = dragged
            dragged.rect.x = place_slot.rect.x
            dragged.rect.y = place_slot.rect.y
            dragged = nil
        }
    }
}

draw :: proc() {
    for i:int = 0; i < len(slot_list); i += 1 {
        rl.DrawRectangleRec(slot_list[i].rect, rl.DARKGRAY)
        rl.DrawRectangleLinesEx(slot_list[i].rect, 1, rl.BLACK)
    }

    for i:int = 0; i < len(item_list); i += 1 {
        rl.DrawRectangleRec(item_list[i].rect, item_list[i].color)
        rl.DrawRectangleLinesEx(item_list[i].rect, 1, rl.GRAY)
    }
}