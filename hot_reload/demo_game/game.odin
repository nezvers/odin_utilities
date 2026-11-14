// The game that the demos load as a DLL. It has no framework in it: drawing and time come through api.Host.
// Change BOX_COLOR or BOX_SPEED, press the Reload button of the demo and see that the box keeps its place and the frame counter keeps counting.
package demo_game

import "base:runtime"
import "core:fmt"
import api "api"
import hot_reload ".."

// Build knobs of the hot reload tests: they change the size or the layout of Memory on purpose
DEMO_PAD :: #config(DEMO_PAD, 0)
DEMO_FLOAT_COUNTER :: #config(DEMO_FLOAT_COUNTER, false)
Counter :: f64 when DEMO_FLOAT_COUNTER else int

// --- Edit and Reload ---
BOX_COLOR :: api.Color{230, 120, 40, 255}
BOX_SPEED :: f32(220)
BOX_SIZE :: f32(60)

Memory :: struct {
    allocator: runtime.Allocator,
    counter: Counter,           // frames since the memory was created
    box_position: api.Vec2,
    box_direction: api.Vec2,
    _pad: [DEMO_PAD]u8,
}

// Globals live in the DLL and are lost on reload, anything that has to survive belongs in Memory
memory: ^Memory
host: ^api.Host

@(export)
game_init :: proc(host_pointer: rawptr, allocator: runtime.Allocator) {
    host = cast(^api.Host)host_pointer
    memory = new(Memory, allocator)
    memory.allocator = allocator
    memory.box_position = {100, 100}
    memory.box_direction = {1, 0.6}
}

@(export)
game_destroy :: proc() {
    free(memory, memory.allocator)
    memory = nil
}

@(export)
game_update :: proc() -> bool {
    delta_time: f32 = host.frame_time()
    size: api.Vec2 = host.screen_size()

    memory.counter += 1
    memory.box_position += memory.box_direction * BOX_SPEED * delta_time
    if memory.box_position.x < 0 || memory.box_position.x + BOX_SIZE > size.x {
        memory.box_direction.x = -memory.box_direction.x
        memory.box_position.x = clamp(memory.box_position.x, 0, size.x - BOX_SIZE)
    }
    if memory.box_position.y < 0 || memory.box_position.y + BOX_SIZE > size.y {
        memory.box_direction.y = -memory.box_direction.y
        memory.box_position.y = clamp(memory.box_position.y, 0, size.y - BOX_SIZE)
    }

    host.draw_rect({memory.box_position.x, memory.box_position.y, BOX_SIZE, BOX_SIZE}, BOX_COLOR)
    buffer: [64]u8
    host.draw_text(fmt.bprintf(buffer[:], "frames in memory: %d", int(memory.counter)), {10, 10}, 20, {20, 20, 20, 255})
    if host.report != nil {
        host.report(int(memory.counter))
    }
    return true
}

@(export)
game_memory :: proc() -> rawptr {
    return memory
}

@(export)
game_memory_size :: proc() -> int {
    return size_of(Memory)
}

@(export)
game_memory_layout :: proc() -> u64 {
    return hot_reload.LayoutHash(Memory)
}

// Nothing in the globals of this game needs to be freed
@(export)
game_release :: proc() {
}

@(export)
game_reloaded :: proc(memory_pointer: rawptr, host_pointer: rawptr) {
    memory = cast(^Memory)memory_pointer
    host = cast(^api.Host)host_pointer
}
