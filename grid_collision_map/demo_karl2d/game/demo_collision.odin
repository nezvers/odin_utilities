#+private file
package game

import gcm "../.."
import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import "../../../karl2d"

@(private="package")
collision_state: GameState = {
    init,
    finit,
    process,
    draw,
}

// Grid covers the whole 1280x720 window
CELL_SIZE :: 16
GRID_COLUMNS :: 80
GRID_ROWS :: 45
// Boxes that can share a cell
CELL_CAPACITY :: 8
// Every cell can hold a wall and one extra for the player
COLLIDER_CAPACITY :: GRID_COLUMNS * GRID_ROWS + 16
PLAYER_SIZE :gcm.Vec2: {8, 16}
PLAYER_SPEED :f32: 200.0

WALL_COLOR :karl2d.Color: {130, 130, 130, 255}
PLAYER_COLOR :karl2d.Color: {200, 240, 20, 255}

// Pre-allocated, no allocations at runtime
world: gcm.GridMap(GRID_COLUMNS, GRID_ROWS, CELL_CAPACITY, COLLIDER_CAPACITY)
player: gcm.Handle
// Holds query results
query_buffer: [64]gcm.Handle

init :: proc() {
    background_color = karl2d.WHITE
    gcm.GridMapInit(&world, {0, 0}, {CELL_SIZE, CELL_SIZE})
    ok: bool
    player, ok = gcm.GridMapAdd(&world, {640, 360, PLAYER_SIZE.x, PLAYER_SIZE.y})
    assert(ok)
}

finit :: proc() {}

process :: proc() {
    mouse_position: Vec2 = karl2d.get_mouse_position()

    if !is_hovering_buttons {
        edit(mouse_position)
    }

    // Move player
    direction: gcm.Vec2
    if karl2d.key_is_held(.W) { direction.y -= 1 }
    if karl2d.key_is_held(.S) { direction.y += 1 }
    if karl2d.key_is_held(.A) { direction.x -= 1 }
    if karl2d.key_is_held(.D) { direction.x += 1 }
    delta: gcm.Vec2 = direction * PLAYER_SPEED * karl2d.get_frame_time()
    gcm.GridMapMoveAndSlide(&world, player, delta, query_buffer[:])
}

edit :: proc(mouse_position: Vec2) {
    cell_x: int = cast(int)math.floor(mouse_position.x / CELL_SIZE)
    cell_y: int = cast(int)math.floor(mouse_position.y / CELL_SIZE)
    in_grid: bool = cell_x >= 0 && cell_y >= 0 && cell_x < GRID_COLUMNS && cell_y < GRID_ROWS
    cell_rect: gcm.Rect = {cast(f32)(cell_x * CELL_SIZE), cast(f32)(cell_y * CELL_SIZE), CELL_SIZE, CELL_SIZE}

    if in_grid && karl2d.mouse_button_is_held(.Left) {
        // Paint a wall unless the cell is taken. Player is ignored by the query, but not allowed to be painted over
        player_collider: ^gcm.Collider = gcm.GridMapGet(&world, player) or_else nil
        is_free: bool = gcm.GridMapQuery(&world, cell_rect, query_buffer[:], player) == 0
        if is_free && !gcm.RectOverlaps(cell_rect, player_collider.rect) {
            gcm.GridMapAdd(&world, cell_rect)
        }
    }

    if in_grid && karl2d.mouse_button_is_held(.Right) {
        count: int = gcm.GridMapQuery(&world, cell_rect, query_buffer[:], player)
        for i: int = 0; i < count; i += 1 {
            gcm.GridMapRemove(&world, query_buffer[i])
        }
    }

    if karl2d.mouse_button_went_down(.Middle) || karl2d.key_went_down(.E) {
        // Place player centered on the mouse where it doesn't overlap walls
        rect: gcm.Rect = {mouse_position.x - PLAYER_SIZE.x * 0.5, mouse_position.y - PLAYER_SIZE.y * 0.5, PLAYER_SIZE.x, PLAYER_SIZE.y}
        if gcm.GridMapQuery(&world, rect, query_buffer[:], player) == 0 {
            gcm.GridMapMove(&world, player, rect)
        }
    }
}

draw :: proc() {
    grid_rect: gcm.Rect = gcm.GridMapRect(&world)
    for x: int = 0; x <= GRID_COLUMNS; x += 1 {
        karl2d.draw_line({cast(f32)(x * CELL_SIZE), 0}, {cast(f32)(x * CELL_SIZE), grid_rect.h}, 1, karl2d.LIGHT_GRAY)
    }
    for y: int = 0; y <= GRID_ROWS; y += 1 {
        karl2d.draw_line({0, cast(f32)(y * CELL_SIZE)}, {grid_rect.w, cast(f32)(y * CELL_SIZE)}, 1, karl2d.LIGHT_GRAY)
    }

    // Colliders are stored in handle map
    it: = hm.iterator_make(&world.colliders)
    for collider, handle in hm.iterate(&it) {
        if handle == player { continue }
        karl2d.draw_rect(cast(Rect)collider.rect, WALL_COLOR)
    }
    player_collider: ^gcm.Collider = gcm.GridMapGet(&world, player) or_else nil
    karl2d.draw_rect(cast(Rect)player_collider.rect, PLAYER_COLOR)
    karl2d.draw_rect_outline(cast(Rect)player_collider.rect, 1, karl2d.DARK_GRAY)

    karl2d.draw_text("grid collision map: LMB paint wall, RMB erase, MMB or E place player, WASD move", {10, 10}, 20, karl2d.BLACK)
    karl2d.draw_text(fmt.tprintf("colliders = %v", gcm.GridMapLen(&world)), {10, 36}, 20, karl2d.DARK_GRAY)
}
