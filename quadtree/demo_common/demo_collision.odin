#+private file
package demo_common

import "core:fmt"
import "core:math"
import hm "core:container/handle_map"
import qt ".."
import kit "../../demo_kit"

@(private = "package")
demo_collision: kit.Demo = {
    name = "collision",
    init = collisionInit,
    update = collisionUpdate,
    draw = collisionDraw,
    script = collisionScript,
}

// The same as the demo of grid_collision_map: walls are cells of 16 x 16 on a window of 1280 x 720, the player is a box that slides along them. The difference is the broad phase: a quadtree
CELL_SIZE :: 16
GRID_COLUMNS :: 80
GRID_ROWS :: 45
WALL_CAPACITY :: GRID_COLUMNS * GRID_ROWS + 16

PLAYER_SIZE :: qt.Vec2{8, 16}
PLAYER_SPEED :: f32(200.0)
WALL_COLOR :: kit.Color{130, 130, 130, 255}
PLAYER_COLOR :: kit.Color{200, 240, 20, 255}

// A leaf is about 20 x 11 at depth 6: a wall cell touches at most six of them
CollisionTree :: qt.Quadtree(WALL_CAPACITY + 1, 8192, 32768)

// Pre-allocated, no allocations at runtime
collision_tree: CollisionTree
collision_player: qt.Handle
collision_show_tree: bool

// Holds query results
collision_buffer: [64]qt.Handle

collisionInit :: proc(ctx: ^kit.Context) {
    qt.QuadtreeInit(&collision_tree, {0, 0, GRID_COLUMNS * CELL_SIZE, GRID_ROWS * CELL_SIZE}, 8, 6)
    ok: bool
    collision_player, ok = qt.QuadtreeAdd(&collision_tree, {640, 360, PLAYER_SIZE.x, PLAYER_SIZE.y})
    assert(ok)
    collision_show_tree = true
}

collisionUpdate :: proc(ctx: ^kit.Context) {
    if !ctx.ui_hover { collisionEdit(ctx) }
    if kit.KeyPressed(&ctx.input, .G) { collision_show_tree = !collision_show_tree }

    direction: qt.Vec2
    if kit.KeyDown(&ctx.input, .W) { direction.y -= 1 }
    if kit.KeyDown(&ctx.input, .S) { direction.y += 1 }
    if kit.KeyDown(&ctx.input, .A) { direction.x -= 1 }
    if kit.KeyDown(&ctx.input, .D) { direction.x += 1 }
    collisionMoveAndSlide(direction * PLAYER_SPEED * ctx.delta_time)
    qt.QuadtreeCleanup(&collision_tree)
}

// Moves the player axis by axis and pushes it out of the walls it overlaps, so it slides along them. Steps are shorter than half a cell, so a wall cannot be skipped
collisionMoveAndSlide :: proc(delta: qt.Vec2) {
    player: ^qt.Element = qt.QuadtreeGet(&collision_tree, collision_player) or_else nil
    if player == nil { return }
    rect: qt.Rect = player.rect
    longest: f32 = max(abs(delta.x), abs(delta.y))
    steps: int = max(1, int(math.ceil(longest / (CELL_SIZE * 0.5))))
    step: qt.Vec2 = delta / f32(steps)
    for _ in 0 ..< steps {
        if step.x != 0 {
            rect.x += step.x
            collisionResolve(&rect, step.x, true)
        }
        if step.y != 0 {
            rect.y += step.y
            collisionResolve(&rect, step.y, false)
        }
    }
    qt.QuadtreeMove(&collision_tree, collision_player, rect)
}

collisionResolve :: proc(rect: ^qt.Rect, step: f32, along_x: bool) {
    count: int = qt.QuadtreeQuery(&collision_tree, rect^, collision_buffer[:], collision_player)
    for i in 0 ..< count {
        other: ^qt.Element = qt.QuadtreeGet(&collision_tree, collision_buffer[i]) or_continue
        if !qt.RectOverlaps(rect^, other.rect) { continue }
        if along_x {
            rect.x = other.rect.x - rect.w if step > 0 else other.rect.x + other.rect.w
        } else {
            rect.y = other.rect.y - rect.h if step > 0 else other.rect.y + other.rect.h
        }
    }
}

collisionEdit :: proc(ctx: ^kit.Context) {
    mouse_position: kit.Vec2 = ctx.input.mouse_position
    cell_x: int = int(math.floor(mouse_position.x / CELL_SIZE))
    cell_y: int = int(math.floor(mouse_position.y / CELL_SIZE))
    in_grid: bool = cell_x >= 0 && cell_y >= 0 && cell_x < GRID_COLUMNS && cell_y < GRID_ROWS
    cell_rect: qt.Rect = {f32(cell_x * CELL_SIZE), f32(cell_y * CELL_SIZE), CELL_SIZE, CELL_SIZE}

    if in_grid && kit.MouseDown(&ctx.input, .LEFT) {
        // Paint a wall unless the cell is taken. The player is ignored by the query, but cannot be painted over
        player: ^qt.Element = qt.QuadtreeGet(&collision_tree, collision_player) or_else nil
        is_free: bool = qt.QuadtreeQuery(&collision_tree, cell_rect, collision_buffer[:], collision_player) == 0
        if is_free && !qt.RectOverlaps(cell_rect, player.rect) {
            qt.QuadtreeAdd(&collision_tree, cell_rect)
        }
    }

    if in_grid && kit.MouseDown(&ctx.input, .RIGHT) {
        count: int = qt.QuadtreeQuery(&collision_tree, cell_rect, collision_buffer[:], collision_player)
        for i in 0 ..< count { qt.QuadtreeRemove(&collision_tree, collision_buffer[i]) }
    }

    if kit.MousePressed(&ctx.input, .MIDDLE) || kit.KeyPressed(&ctx.input, .E) {
        // Place the player centered on the mouse where it does not overlap walls
        rect: qt.Rect = {mouse_position.x - PLAYER_SIZE.x * 0.5, mouse_position.y - PLAYER_SIZE.y * 0.5, PLAYER_SIZE.x, PLAYER_SIZE.y}
        if qt.QuadtreeQuery(&collision_tree, rect, collision_buffer[:], collision_player) == 0 {
            qt.QuadtreeMove(&collision_tree, collision_player, rect)
        }
    }
}

collisionDraw :: proc(ctx: ^kit.Context) {
    if collision_show_tree { qt.QuadtreeVisit(&collision_tree, ctx, drawNode) }

    // Walls are the elements, the player is the one the demo kept the handle of
    it := hm.iterator_make(&collision_tree.elements)
    for element, handle in hm.iterate(&it) {
        if handle == collision_player { continue }
        kit.DrawRect(ctx, transmute(kit.Rect)element.rect, WALL_COLOR)
    }
    player: ^qt.Element = qt.QuadtreeGet(&collision_tree, collision_player) or_else nil
    kit.DrawRect(ctx, transmute(kit.Rect)player.rect, PLAYER_COLOR)
    kit.DrawRectOutline(ctx, transmute(kit.Rect)player.rect, 1, kit.DARK_GRAY)

    nodes, links := qt.QuadtreeUsage(&collision_tree)
    kit.DrawText(ctx, "quadtree collision: LMB paint wall, RMB erase, MMB or E place player, WASD move, G tree", {10, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("elements = %v, nodes = %v, links = %v", qt.QuadtreeLen(&collision_tree), nodes, links), {10, 36}, 20, kit.DARK_GRAY)
}

collisionPlayerX :: proc() -> f32 {
    player, ok := qt.QuadtreeGet(&collision_tree, collision_player)
    return player.rect.x if ok else -1
}

collisionScript: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return qt.QuadtreeLen(&collision_tree) == 1 }, "the tree starts with the player only"),
    // paint a wall: a vertical line of cells at x 700, from y 300 to y 420
    kit.Drag({700, 300}, {700, 420}, 20),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return qt.QuadtreeLen(&collision_tree) >= 8 }, "dragging with the left button paints a wall of cells"),
    // walk into it: the player starts at x 640 and is 8 wide, the wall begins at x 688 (the cell of 700)
    kit.MoveTo({100, 100}),
    kit.Hold(.D, 60),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return collisionPlayerX() > 660 && collisionPlayerX() + PLAYER_SIZE.x <= 688.01 }, "the player stops at the wall and slides along it"),
    // walk around: down out of the wall, then right
    kit.Hold(.S, 60),
    kit.Hold(.D, 60),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return collisionPlayerX() > 700 }, "below the wall the player gets past it"),
    // erase a cell with the right button
    kit.Click({700, 310}, .RIGHT),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return qt.QuadtreeLen(&collision_tree) < 9 + 9 }, "the right button erases"),
    kit.Click({300, 300}, .MIDDLE),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(collisionPlayerX() - 296) < 0.01 }, "middle click puts the player on the mouse"),
}
