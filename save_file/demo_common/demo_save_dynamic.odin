#+private file
package demo_common

// Save and load a list of unknown length: a header says what it is and how many, then a group property, then the items as one block of bytes.

import "core:math/rand"
import "core:mem"
import "core:os"
import save_file ".."
import kit "../../demo_kit"

@(private="package")
demo_save_dynamic: kit.Demo = {
    name = "dynamic",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

SAVE_FILE :: "save_dynamic.bin"
SAVE_BUTTON :: kit.Rect{10, 40, 100, 25}
LOAD_BUTTON :: kit.Rect{10, 70, 100, 25}
RESET_BUTTON :: kit.Rect{10, 100, 100, 25}
COLOR_BUTTON :: kit.Rect{10, 130, 100, 25}

DataType :: enum {
    Rectangle = 1,
}

SaveHeader :: struct {
    type: DataType,
    count: int,
}

SaveGroupProperty :: struct {
    color: kit.Color,
}

SaveRectangles :: struct {
    using header: SaveHeader,
    using group_property: SaveGroupProperty,
    list: [dynamic]kit.Rect,
}

save_data: SaveRectangles

init :: proc(ctx: ^kit.Context) {
    save_data = {header = {type = .Rectangle}, group_property = {color = kit.GREEN}}
    save_data.list = make_dynamic_array([dynamic]kit.Rect)
    load()
}

finit :: proc(ctx: ^kit.Context) {
    reset()
    delete(save_data.list)
}

update :: proc(ctx: ^kit.Context) {
    if kit.KeyPressed(&ctx.input, .S) { save() }
    if kit.KeyPressed(&ctx.input, .L) { load() }
    mouse: kit.Vec2 = ctx.input.mouse_position
    over_button: bool = kit.PointInRect(mouse, SAVE_BUTTON) || kit.PointInRect(mouse, LOAD_BUTTON) || kit.PointInRect(mouse, RESET_BUTTON) || kit.PointInRect(mouse, COLOR_BUTTON)
    if ctx.ui_hover || over_button { return }       // skip mouse input

    if kit.MousePressed(&ctx.input, .LEFT) {
        rect: kit.Rect = {mouse.x, mouse.y, 10 + rand.float32() * 100, 10 + rand.float32() * 100}
        append(&save_data.list, rect)
        save_data.header.count = len(save_data.list)
    }
}

draw :: proc(ctx: ^kit.Context) {
    kit.DrawText(ctx, "Left mouse - Create", {10, 10}, 20, kit.GRAY)
    for rect in save_data.list {
        kit.DrawRect(ctx, rect, save_data.group_property.color)
    }
    if kit.Button(ctx, SAVE_BUTTON, "S - Save") { save() }
    if kit.Button(ctx, LOAD_BUTTON, "L - Load") { load() }
    if kit.Button(ctx, RESET_BUTTON, "Reset") { reset() }
    if kit.Button(ctx, COLOR_BUTTON, "Random Color") {
        save_data.group_property.color.r = u8(rand.int32_range(0, 255))
        save_data.group_property.color.g = u8(rand.int32_range(0, 255))
        save_data.group_property.color.b = u8(rand.int32_range(0, 255))
    }
}

save :: proc() {
    file_write := save_file.create(SAVE_FILE)
    defer save_file.close(file_write)
    if file_write != nil {
        // Just in case update the header
        save_data.header.count = len(save_data.list)
        save_file.write_append_struct(file_write, &save_data.header)
        save_file.write_append_struct(file_write, &save_data.group_property)
        if save_data.header.count < 1 { return }
        data: []u8 = mem.byte_slice(&save_data.list[0], size_of(kit.Rect) * save_data.header.count)
        save_file.write_append(file_write, data[:])
    }
}

load :: proc() {
    reset()
    file_read := save_file.read_open(SAVE_FILE)
    defer save_file.close(file_read)
    if file_read != nil {
        header: SaveHeader = {}
        save_file.read_struct(file_read, &header)
        if header.type != DataType.Rectangle || header.count < 1 { return }
        group_property: SaveGroupProperty = {}
        save_file.read_struct(file_read, &group_property)
        save_data.header = header
        save_data.group_property = group_property
        reserve(&save_data.list, header.count)
        // Makes the pointer to the 0-th element valid
        resize(&save_data.list, header.count)
        data: []u8 = mem.byte_slice(&save_data.list[0], size_of(kit.Rect) * header.count)
        save_file.read_buffer(file_read, data[:])
    }
}

reset :: proc() {
    clear_dynamic_array(&save_data.list)
}

script: []kit.Step = {
    kit.Wait(2),
    // start without a save file: init loads the one of an earlier run
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        os.remove(SAVE_FILE)
        reset()
        return true
    }, "(no save file)"),
    kit.Click({400, 300}),
    kit.Click({500, 400}),
    kit.Click({600, 200}),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return len(save_data.list) == 3 && save_data.header.count == 3 }, "every click creates a rectangle"),
    kit.Click({60, 143}),                       // Random Color
    kit.Tap(.S),                                // save the three
    kit.Click({700, 500}),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return len(save_data.list) == 4 }, "one more"),
    kit.Click({60, 113}),                       // Reset
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return len(save_data.list) == 0 }, "reset clears the list"),
    kit.Tap(.L),                                // load
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return len(save_data.list) == 3 && save_data.list[0].x == 400 && save_data.list[2].x == 600 && save_data.header.count == 3
    }, "load brings back the three that were saved, in order, not the fourth"),
}
