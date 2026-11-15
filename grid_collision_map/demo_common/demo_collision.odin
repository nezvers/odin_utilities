#+private file
package demo_common

import "core:fmt"
import "core:math"
import hm "core:container/handle_map"
import gcm ".."
import kit "../../demo_kit"

@(private="package")
demo_collision: kit.Demo = {
    name = "collision",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

// Grid covers the whole 1280x720 window
CELL_SIZE :: 16
GRID_COLUMNS :: 80
GRID_ROWS :: 45
// Boxes that can share a cell
CELL_CAPACITY :: 8
// Every cell can hold a wall and one extra for the player
COLLIDER_CAPACITY :: GRID_COLUMNS * GRID_ROWS + 16

PLAYER_SIZE :: gcm.Vec2{8, 16}
PLAYER_SPEED :: f32(200.0)
WALL_COLOR :: kit.Color{130, 130, 130, 255}
PLAYER_COLOR :: kit.Color{200, 240, 20, 255}

// Pre-allocated, no allocations at runtime
world: gcm.GridMap(GRID_COLUMNS, GRID_ROWS, CELL_CAPACITY, COLLIDER_CAPACITY)
player: gcm.Handle

// Holds query results
query_buffer: [64]gcm.Handle

init :: proc(ctx: ^kit.Context) {
    gcm.GridMapInit(&world, {0, 0}, {CELL_SIZE, CELL_SIZE})
    ok: bool
    player, ok = gcm.GridMapAdd(&world, {640, 360, PLAYER_SIZE.x, PLAYER_SIZE.y})
    assert(ok)
}

update :: proc(ctx: ^kit.Context) {
    if !ctx.ui_hover { edit(ctx) }

    // Move player
    direction: gcm.Vec2
    if kit.KeyDown(&ctx.input, .W) { direction.y -= 1 }
    if kit.KeyDown(&ctx.input, .S) { direction.y += 1 }
    if kit.KeyDown(&ctx.input, .A) { direction.x -= 1 }
    if kit.KeyDown(&ctx.input, .D) { direction.x += 1 }
    delta: gcm.Vec2 = direction * PLAYER_SPEED * ctx.delta_time
    gcm.GridMapMoveAndSlide(&world, player, delta, query_buffer[:])
}

edit :: proc(ctx: ^kit.Context) {
    mouse_position: kit.Vec2 = ctx.input.mouse_position
    cell_x: int = int(math.floor(mouse_position.x / CELL_SIZE))
    cell_y: int = int(math.floor(mouse_position.y / CELL_SIZE))
    in_grid: bool = cell_x >= 0 && cell_y >= 0 && cell_x < GRID_COLUMNS && cell_y < GRID_ROWS
    cell_rect: gcm.Rect = {f32(cell_x * CELL_SIZE), f32(cell_y * CELL_SIZE), CELL_SIZE, CELL_SIZE}

    if in_grid && kit.MouseDown(&ctx.input, .LEFT) {
        // Paint a wall unless the cell is taken. Player is ignored by the query, but not allowed to be painted over
        player_collider: ^gcm.Collider = gcm.GridMapGet(&world, player) or_else nil
        is_free: bool = gcm.GridMapQuery(&world, cell_rect, query_buffer[:], player) == 0
        if is_free && !gcm.RectOverlaps(cell_rect, player_collider.rect) {
            gcm.GridMapAdd(&world, cell_rect)
        }
    }

    if in_grid && kit.MouseDown(&ctx.input, .RIGHT) {
        count: int = gcm.GridMapQuery(&world, cell_rect, query_buffer[:], player)
        for i in 0 ..< count {
            gcm.GridMapRemove(&world, query_buffer[i])
        }
    }

    if kit.MousePressed(&ctx.input, .MIDDLE) || kit.KeyPressed(&ctx.input, .E) {
        // Place player centered on the mouse where it does not overlap walls
        rect: gcm.Rect = {mouse_position.x - PLAYER_SIZE.x * 0.5, mouse_position.y - PLAYER_SIZE.y * 0.5, PLAYER_SIZE.x, PLAYER_SIZE.y}
        if gcm.GridMapQuery(&world, rect, query_buffer[:], player) == 0 {
            gcm.GridMapMove(&world, player, rect)
        }
    }
}

draw :: proc(ctx: ^kit.Context) {
    grid_rect: gcm.Rect = gcm.GridMapRect(&world)
    for x in 0 ..= GRID_COLUMNS {
        kit.DrawLine(ctx, {f32(x * CELL_SIZE), 0}, {f32(x * CELL_SIZE), grid_rect.h}, 1, kit.LIGHT_GRAY)
    }
    for y in 0 ..= GRID_ROWS {
        kit.DrawLine(ctx, {0, f32(y * CELL_SIZE)}, {grid_rect.w, f32(y * CELL_SIZE)}, 1, kit.LIGHT_GRAY)
    }

    // Colliders are stored in handle map
    it := hm.iterator_make(&world.colliders)
    for collider, handle in hm.iterate(&it) {
        if handle == player { continue }
        kit.DrawRect(ctx, transmute(kit.Rect)collider.rect, WALL_COLOR)
    }
    player_collider: ^gcm.Collider = gcm.GridMapGet(&world, player) or_else nil
    kit.DrawRect(ctx, transmute(kit.Rect)player_collider.rect, PLAYER_COLOR)
    kit.DrawRectOutline(ctx, transmute(kit.Rect)player_collider.rect, 1, kit.DARK_GRAY)

    kit.DrawText(ctx, "grid collision map: LMB paint wall, RMB erase, MMB or E place player, WASD move", {10, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("colliders = %v", gcm.GridMapLen(&world)), {10, 36}, 20, kit.DARK_GRAY)
}

player_x :: proc() -> f32 {
    collider, ok := gcm.GridMapGet(&world, player)
    return collider.rect.x if ok else -1
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return gcm.GridMapLen(&world) == 1 }, "the grid starts with the player only"),
    // paint a wall: a vertical line of cells at x 700, from y 300 to y 420
    kit.Drag({700, 300}, {700, 420}, 20),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return gcm.GridMapLen(&world) >= 8 }, "dragging with the left button paints a wall of cells"),
    // walk into it: the player starts at x 640 and is 8 wide, the wall begins at x 688 (the cell of 700)
    kit.MoveTo({100, 100}),
    kit.Hold(.D, 60),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_x() > 660 && player_x() + PLAYER_SIZE.x <= 688.01 }, "the player stops at the wall and slides along it"),
    // walk around: down out of the wall, then right
    kit.Hold(.S, 60),
    kit.Hold(.D, 60),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_x() > 700 }, "below the wall the player gets past it"),
    // erase a cell with the right button
    kit.Click({700, 310}, .RIGHT),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return gcm.GridMapLen(&world) < 9 + 9 }, "the right button erases"),
    kit.Click({300, 300}, .MIDDLE),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(player_x() - 296) < 0.01 }, "middle click puts the player on the mouse"),
}
