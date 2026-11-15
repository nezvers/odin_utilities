#+private file
package demo_common

import dd ".."
import kit "../../demo_kit"

@(private="package")
demo_simple: kit.Demo = {
    name = "simple",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

Item :: struct {
    using drag: dd.DragRect,
    color: kit.Color,
}

START_ITEMS :: [2]Item{
    {drag = {rect = {40, 40, 32, 32}}, color = kit.GREEN},
    {drag = {rect = {80, 80, 32, 32}}, color = kit.DARK_GREEN},
}
items: [2]Item
dragged: int        // index of the item that is dragged, -1 none

init :: proc(ctx: ^kit.Context) {
    items = START_ITEMS
    dragged = -1
}

update :: proc(ctx: ^kit.Context) {
    mouse: kit.Vec2 = ctx.input.mouse_position
    if kit.MousePressed(&ctx.input) && dragged == -1 && !ctx.ui_hover {
        for i in 0 ..< len(items) {
            if dd.DragHit(items[i].drag, mouse) {
                dragged = i
                dd.DragBegin(&items[i].drag, mouse)
            }
        }
    }
    if dragged != -1 {
        dd.DragMove(&items[dragged].drag, mouse)
        if kit.MouseReleased(&ctx.input) {
            dd.DragEnd(&items[dragged].drag)
            dragged = -1
        }
    }
}

draw :: proc(ctx: ^kit.Context) {
    for item in items {
        kit.DrawRect(ctx, item.rect, item.color)
        kit.DrawRectOutline(ctx, item.rect, 1, kit.GRAY)
    }
    kit.DrawText(ctx, "drag the squares with the left mouse button", {10, 10}, 18, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Drag({50, 50}, {300, 200}, 10),
    kit.Wait(1),
    // grabbed at (50,50) on the corner offset (-10,-10): it ends where the mouse ended, with the same offset
    kit.Check(proc(ctx: ^kit.Context) -> bool { return items[0].rect.x == 290 && items[0].rect.y == 190 && dragged == -1 }, "the item moved with the mouse and was let go"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return items[1].rect.x == 80 && items[1].rect.y == 80 }, "the other item did not move"),
    kit.Click({600, 500}),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return dragged == -1 }, "a click on empty space grabs nothing"),
}
