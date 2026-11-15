#+private file
package demo_common

import dd ".."
import kit "../../demo_kit"

@(private="package")
demo_slots: kit.Demo = {
    name = "slots",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

Item :: struct {
    using drag: dd.DragRect,
    color: kit.Color,
}

Slot :: struct {
    rect: kit.Rect,
    item: int,          // index of the item in it, -1 empty
}

ITEM_SIZE :: kit.Vec2{40, 40}
items: [2]Item
slots: [8]Slot
dragged: int            // the item that is dragged, -1 none
origin_slot: int        // the slot it was taken from: it goes back there when dropped on nothing

init :: proc(ctx: ^kit.Context) {
    items = {
        {drag = {rect = {0, 0, ITEM_SIZE.x, ITEM_SIZE.y}}, color = kit.GREEN},
        {drag = {rect = {0, 0, ITEM_SIZE.x, ITEM_SIZE.y}}, color = kit.DARK_GREEN},
    }
    positions: [8]kit.Vec2 = {{40, 40}, {85, 40}, {40, 85}, {85, 85}, {200, 40}, {245, 40}, {200, 85}, {245, 85}}
    for i in 0 ..< len(slots) {
        slots[i] = {rect = {positions[i].x, positions[i].y, ITEM_SIZE.x, ITEM_SIZE.y}, item = -1}
    }
    // the first two slots start with an item
    for i in 0 ..< len(items) {
        slots[i].item = i
        dd.DragSnapTo(&items[i].drag, slots[i].rect)
    }
    dragged = -1
    origin_slot = -1
}

slot_at :: proc(point: kit.Vec2) -> int {
    for i in 0 ..< len(slots) {
        if kit.PointInRect(point, slots[i].rect) { return i }
    }
    return -1
}

update :: proc(ctx: ^kit.Context) {
    mouse: kit.Vec2 = ctx.input.mouse_position
    if kit.MousePressed(&ctx.input) && dragged == -1 && !ctx.ui_hover {
        slot: int = slot_at(mouse)
        if slot != -1 && slots[slot].item != -1 {
            origin_slot = slot
            dragged = slots[slot].item
            dd.DragBegin(&items[dragged].drag, mouse)
        }
    }
    if dragged != -1 {
        dd.DragMove(&items[dragged].drag, mouse)
        if kit.MouseReleased(&ctx.input) {
            // an empty slot under the mouse takes it, otherwise it goes back to where it came from
            target: int = slot_at(mouse)
            if target == -1 || (slots[target].item != -1 && target != origin_slot) { target = origin_slot }
            slots[origin_slot].item = -1
            slots[target].item = dragged
            dd.DragSnapTo(&items[dragged].drag, slots[target].rect)
            dd.DragEnd(&items[dragged].drag)
            dragged = -1
        }
    }
}

draw :: proc(ctx: ^kit.Context) {
    for slot in slots {
        kit.DrawRect(ctx, slot.rect, kit.DARK_GRAY)
        kit.DrawRectOutline(ctx, slot.rect, 1, kit.BLACK)
    }
    for item in items {
        kit.DrawRect(ctx, item.rect, item.color)
        kit.DrawRectOutline(ctx, item.rect, 1, kit.GRAY)
    }
    kit.DrawText(ctx, "drag an item to another slot, on a taken slot or on nothing it goes back", {10, 10}, 18, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return slots[0].item == 0 && slots[1].item == 1 && slots[2].item == -1 }, "two items start in the first two slots"),
    // slot 0 is at (40,40), slot 7 at (245,85)
    kit.Drag({50, 50}, {260, 100}, 10),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return slots[0].item == -1 && slots[7].item == 0 && items[0].rect.x == 245 && items[0].rect.y == 85 }, "dropped on an empty slot: it snaps into it"),
    kit.Drag({95, 50}, {50, 50}, 10),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return slots[0].item == 1 && slots[1].item == -1 }, "the second item moves to the slot the first one left"),
    kit.Drag({260, 100}, {600, 600}, 10),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return slots[7].item == 0 }, "dropped on nothing: it goes back to the slot it came from"),
    kit.Drag({260, 100}, {55, 55}, 10),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return slots[7].item == 0 && slots[0].item == 1 }, "dropped on a taken slot: it goes back too"),
}
