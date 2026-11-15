#+private file
package demo_common

// Save and load one struct: the rectangle is written to a file as its bytes and read back.

import save_file ".."
import kit "../../demo_kit"

@(private="package")
demo_save_basic: kit.Demo = {
    name = "basic",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

SAVE_FILE :: "save_simple.bin"
START_RECT :: kit.Rect{400, 300, 200, 100}
test_rect: kit.Rect = START_RECT
SAVE_BUTTON :: kit.Rect{10, 40, 100, 25}
LOAD_BUTTON :: kit.Rect{10, 70, 100, 25}

init :: proc(ctx: ^kit.Context) {
    test_rect = START_RECT
    load()
}

update :: proc(ctx: ^kit.Context) {
    if kit.KeyPressed(&ctx.input, .S) { save() }
    if kit.KeyPressed(&ctx.input, .L) { load() }
    mouse: kit.Vec2 = ctx.input.mouse_position
    if ctx.ui_hover || kit.PointInRect(mouse, SAVE_BUTTON) || kit.PointInRect(mouse, LOAD_BUTTON) { return }    // skip moving logic
    if kit.MouseDown(&ctx.input, .LEFT) {
        test_rect.x = mouse.x
        test_rect.y = mouse.y
    }
}

draw :: proc(ctx: ^kit.Context) {
    kit.DrawText(ctx, "Left mouse - Move", {10, 10}, 20, kit.GRAY)
    kit.DrawRect(ctx, test_rect, kit.GREEN)
    if kit.Button(ctx, SAVE_BUTTON, "S - Save") { save() }
    if kit.Button(ctx, LOAD_BUTTON, "L - Load") { load() }
}

save :: proc() {
    file_write := save_file.create(SAVE_FILE)
    defer save_file.close(file_write)
    if file_write != nil {
        save_file.write_append_struct(file_write, &test_rect)
    }
}

load :: proc() {
    file_read := save_file.read_open(SAVE_FILE)
    defer save_file.close(file_read)
    if file_read != nil {
        save_file.read_struct(file_read, &test_rect)
    }
}

script: []kit.Step = {
    kit.Wait(2),
    // move the rectangle: it goes to the mouse while the left button is held
    kit.MoveTo({300, 300}), kit.MouseDownStep(), kit.Wait(1), kit.MoveTo({500, 450}), kit.Wait(1), kit.MouseUpStep(), kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return test_rect.x == 500 && test_rect.y == 450 }, "the rectangle follows the mouse"),
    kit.Tap(.S),                                // save
    kit.MoveTo({300, 300}), kit.MouseDownStep(), kit.Wait(1), kit.MoveTo({200, 200}), kit.Wait(1), kit.MouseUpStep(), kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return test_rect.x == 200 && test_rect.y == 200 }, "and moves again"),
    kit.Tap(.L),                                // load
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return test_rect == kit.Rect{500, 450, 200, 100} }, "load brings back what was saved"),
    kit.Click(kit.Vec2{60, 82}),                // the load button with the mouse, the rectangle is not moved by this click
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return test_rect.x == 500 }, "a click on a button does not move the rectangle"),
}
