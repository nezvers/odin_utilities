package grid_collision_map

import "core:testing"

@(private="file")
Grid :: GridMap(10, 10, 4, 64)

@(private="file")
near :: proc(a: f32, b: f32) -> bool {
    return abs(a - b) < 0.0001
}

@(test)
test_add_query_remove :: proc(t: ^testing.T) {
    grid: Grid
    GridMapInit(&grid, {0, 0}, {16, 16})
    wall, ok: = GridMapAdd(&grid, {32, 32, 16, 16})
    testing.expect(t, ok)
    testing.expect(t, GridMapLen(&grid) == 1)

    buffer: [8]Handle
    count: int = GridMapQuery(&grid, {40, 40, 4, 4}, buffer[:])
    testing.expect(t, count == 1 && buffer[0] == wall)

    // Same cell, but not overlapping: broad phase finds it, narrow phase doesn't
    count = GridMapQueryBroad(&grid, {33, 33, 1, 1}, buffer[:])
    testing.expect(t, count == 1)
    count = GridMapQuery(&grid, {0, 0, 16, 16}, buffer[:])
    testing.expect(t, count == 0)

    testing.expect(t, GridMapRemove(&grid, wall))
    testing.expect(t, !GridMapRemove(&grid, wall))
    _, found: = GridMapGet(&grid, wall)
    testing.expect(t, !found)
    count = GridMapQueryBroad(&grid, {0, 0, 160, 160}, buffer[:])
    testing.expect(t, count == 0)
}

@(test)
test_cell_range_edges :: proc(t: ^testing.T) {
    grid: Grid
    GridMapInit(&grid, {0, 0}, {16, 16})
    // Exactly one cell, touching border doesn't cover the next one
    cell_min, cell_max: = GridMapCellRange(&grid, {16, 16, 16, 16})
    testing.expect(t, cell_min == {1, 1} && cell_max == {1, 1})
    // Spans 2x2
    cell_min, cell_max = GridMapCellRange(&grid, {12, 12, 8, 16})
    testing.expect(t, cell_min == {0, 0} && cell_max == {1, 1})
    // Outside is clamped
    cell_min, cell_max = GridMapCellRange(&grid, {-100, -100, 8, 8})
    testing.expect(t, cell_min == {0, 0} && cell_max == {0, 0})
    cell_min, cell_max = GridMapCellRange(&grid, {1000, 1000, 8, 8})
    testing.expect(t, cell_min == {9, 9} && cell_max == {9, 9})
}

@(test)
test_multi_cell_unique :: proc(t: ^testing.T) {
    grid: Grid
    GridMapInit(&grid, {0, 0}, {16, 16})
    _, ok: = GridMapAdd(&grid, {8, 8, 48, 48})
    testing.expect(t, ok)
    buffer: [8]Handle
    count: int = GridMapQueryBroad(&grid, {0, 0, 160, 160}, buffer[:])
    testing.expect(t, count == 1)
}

@(test)
test_move_rebins :: proc(t: ^testing.T) {
    grid: Grid
    GridMapInit(&grid, {0, 0}, {16, 16})
    handle, _: = GridMapAdd(&grid, {0, 0, 8, 16})
    buffer: [8]Handle

    testing.expect(t, GridMapMove(&grid, handle, {100, 100, 8, 16}))
    testing.expect(t, GridMapQueryBroad(&grid, {0, 0, 16, 16}, buffer[:]) == 0)
    testing.expect(t, GridMapQuery(&grid, {100, 100, 8, 8}, buffer[:]) == 1)
}

@(test)
test_slot_full_rolls_back :: proc(t: ^testing.T) {
    grid: Grid
    GridMapInit(&grid, {0, 0}, {16, 16})
    for _ in 0..<4 {
        _, ok: = GridMapAdd(&grid, {0, 0, 4, 4})
        testing.expect(t, ok)
    }
    before: uint = GridMapLen(&grid)
    // Covers full cell and a free one, but the first one is full
    _, ok: = GridMapAdd(&grid, {0, 0, 32, 8})
    testing.expect(t, !ok)
    testing.expect(t, GridMapLen(&grid) == before)
    buffer: [8]Handle
    testing.expect(t, GridMapQueryBroad(&grid, {16, 0, 16, 16}, buffer[:]) == 0)
}

@(test)
test_move_and_slide :: proc(t: ^testing.T) {
    grid: Grid
    GridMapInit(&grid, {0, 0}, {16, 16})
    // Wall column at x = 64
    for y: f32 = 0; y < 160; y += 16 {
        _, ok: = GridMapAdd(&grid, {64, y, 16, 16})
        testing.expect(t, ok)
    }
    player, _: = GridMapAdd(&grid, {40, 40, 8, 16})
    buffer: [16]Handle

    // Move right and down into the wall: stops at the wall and slides down
    result, ok: = GridMapMoveAndSlide(&grid, player, {100, 20}, buffer[:])
    testing.expect(t, ok)
    testing.expect(t, result.hit_x && !result.hit_y)
    testing.expect(t, near(result.rect.x, 56))
    testing.expect(t, near(result.rect.y, 60))

    // Huge step doesn't tunnel
    result, ok = GridMapMoveAndSlide(&grid, player, {-1000, 0}, buffer[:])
    testing.expect(t, ok)
    testing.expect(t, near(result.rect.x, -944))

    collider, found: = GridMapGet(&grid, player)
    testing.expect(t, found && collider.rect == result.rect)
}

@(test)
test_no_tunneling_through_thin_wall :: proc(t: ^testing.T) {
    grid: Grid
    GridMapInit(&grid, {0, 0}, {16, 16})
    _, _ = GridMapAdd(&grid, {80, 0, 2, 160})
    player, _: = GridMapAdd(&grid, {10, 10, 8, 16})
    buffer: [16]Handle
    result, _: = GridMapMoveAndSlide(&grid, player, {500, 0}, buffer[:])
    testing.expect(t, result.hit_x)
    testing.expect(t, near(result.rect.x, 72))
}

@(test)
test_push_out :: proc(t: ^testing.T) {
    push, hit: = RectPushOut({0, 0, 10, 10}, {8, 0, 10, 10})
    testing.expect(t, hit && near(push.x, -2) && push.y == 0)
    _, hit = RectPushOut({0, 0, 10, 10}, {10, 0, 10, 10})
    testing.expect(t, !hit)
}
