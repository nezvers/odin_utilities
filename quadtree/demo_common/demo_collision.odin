#+private file
package demo_common

import "core:fmt"
import "core:math"
import qt ".."
import kit "../../demo_kit"
import qtkit "../kit"

@(private = "package")
demo_collision: kit.Demo = {
    name = "collision",
    init = collisionInit,
    update = collisionUpdate,
    draw = collisionDraw,
    script = collisionScript,
}

// The same as the demo of grid_collision_map: walls are cells of 16 x 16 on a window of 1280 x 720, the player is a box that slides along them. The difference is the broad phase: a quadtree that is
// rebuilt every frame from the cells (immediate mode). The grid of cells is the only thing that is kept, the tree holds the cell index as its item.
CELL_SIZE :: 16
GRID_COLUMNS :: 80
GRID_ROWS :: 45
GRID_BOUNDS :: qt.Rect{0, 0, GRID_COLUMNS * CELL_SIZE, GRID_ROWS * CELL_SIZE}

PLAYER_SIZE :: qt.Vec2{8, 16}
PLAYER_SPEED :: f32(200.0)
WALL_COLOR :: kit.Color{130, 130, 130, 255}
PLAYER_COLOR :: kit.Color{200, 240, 20, 255}

// A leaf is about 20 x 11 at depth 6: a wall cell touches at most six of them
CollisionTree :: qt.Quadtree(GRID_COLUMNS * GRID_ROWS, 8192, 32768)

// Pre-allocated, no allocations at runtime
collision_tree: CollisionTree
collision_walls: [GRID_COLUMNS * GRID_ROWS]bool
collision_wall_count: int
collision_player: qt.Rect
collision_show_tree: bool

// Holds query results
collision_buffer: [64]qt.Item

collisionInit :: proc(ctx: ^kit.Context) {
    qt.QuadtreeInit(&collision_tree, GRID_BOUNDS, 8, 6)
    collision_walls = {}
    collision_player = {640, 360, PLAYER_SIZE.x, PLAYER_SIZE.y}
    collision_show_tree = true
    collisionRebuild()
}

cellRect :: proc(index: int) -> qt.Rect {
    return {f32((index % GRID_COLUMNS) * CELL_SIZE), f32((index / GRID_COLUMNS) * CELL_SIZE), CELL_SIZE, CELL_SIZE}
}

// The tree is thrown away and filled again with the walls, every frame
collisionRebuild :: proc() {
    qt.QuadtreeClear(&collision_tree)
    collision_wall_count = 0
    for wall, index in collision_walls {
        if !wall { continue }
        collision_wall_count += 1
        qt.QuadtreeInsert(&collision_tree, cellRect(index), index)
    }
}

collisionUpdate :: proc(ctx: ^kit.Context) {
    if !ctx.ui_hover { collisionEdit(ctx) }
    if kit.KeyPressed(&ctx.input, .G) { collision_show_tree = !collision_show_tree }
    collisionRebuild()

    direction: qt.Vec2
    if kit.KeyDown(&ctx.input, .W) { direction.y -= 1 }
    if kit.KeyDown(&ctx.input, .S) { direction.y += 1 }
    if kit.KeyDown(&ctx.input, .A) { direction.x -= 1 }
    if kit.KeyDown(&ctx.input, .D) { direction.x += 1 }
    collisionMoveAndSlide(direction * PLAYER_SPEED * ctx.delta_time)
}

// Moves the player axis by axis and pushes it out of the walls it overlaps, so it slides along them. Steps are shorter than half a cell, so a wall cannot be skipped
collisionMoveAndSlide :: proc(delta: qt.Vec2) {
    rect: qt.Rect = collision_player
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
    collision_player = rect
}

collisionResolve :: proc(rect: ^qt.Rect, step: f32, along_x: bool) {
    count: int = qt.QuadtreeQuery(&collision_tree, rect^, collision_buffer[:])
    for i in 0 ..< count {
        other: qt.Rect = cellRect(collision_buffer[i])
        if !qt.RectOverlaps(rect^, other) { continue }
        if along_x {
            rect.x = other.x - rect.w if step > 0 else other.x + other.w
        } else {
            rect.y = other.y - rect.h if step > 0 else other.y + other.h
        }
    }
}

collisionEdit :: proc(ctx: ^kit.Context) {
    mouse_position: kit.Vec2 = ctx.input.mouse_position
    cell_x: int = int(math.floor(mouse_position.x / CELL_SIZE))
    cell_y: int = int(math.floor(mouse_position.y / CELL_SIZE))
    in_grid: bool = cell_x >= 0 && cell_y >= 0 && cell_x < GRID_COLUMNS && cell_y < GRID_ROWS
    cell: int = cell_y * GRID_COLUMNS + cell_x

    // A wall cannot be painted over the player
    if in_grid && kit.MouseDown(&ctx.input, .LEFT) && !qt.RectOverlaps(cellRect(cell), collision_player) {
        collision_walls[cell] = true
    }
    if in_grid && kit.MouseDown(&ctx.input, .RIGHT) { collision_walls[cell] = false }

    if kit.MousePressed(&ctx.input, .MIDDLE) || kit.KeyPressed(&ctx.input, .E) {
        // Place the player centered on the mouse where it does not overlap walls (the tree of the last frame is still the one of the walls)
        rect: qt.Rect = {mouse_position.x - PLAYER_SIZE.x * 0.5, mouse_position.y - PLAYER_SIZE.y * 0.5, PLAYER_SIZE.x, PLAYER_SIZE.y}
        if qt.QuadtreeQuery(&collision_tree, rect, collision_buffer[:]) == 0 { collision_player = rect }
    }
}

collisionDraw :: proc(ctx: ^kit.Context) {
    if collision_show_tree { qtkit.DrawQuadtree(ctx, &collision_tree) }
    for wall, index in collision_walls {
        if wall { kit.DrawRect(ctx, transmute(kit.Rect)cellRect(index), WALL_COLOR) }
    }
    kit.DrawRect(ctx, transmute(kit.Rect)collision_player, PLAYER_COLOR)
    kit.DrawRectOutline(ctx, transmute(kit.Rect)collision_player, 1, kit.DARK_GRAY)

    nodes, links := qt.QuadtreeUsage(&collision_tree)
    kit.DrawText(ctx, "quadtree collision: LMB paint wall, RMB erase, MMB or E place player, WASD move, G tree", {10, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("walls = %v (tree rebuilt every frame), nodes = %v, links = %v", collision_wall_count, nodes, links), {10, 36}, 20, kit.DARK_GRAY)
}

collisionScript: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return collision_wall_count == 0 && qt.QuadtreeLen(&collision_tree) == 0 }, "the tree starts without walls"),
    // paint a wall: a vertical line of cells at x 700, from y 300 to y 420
    kit.Drag({700, 300}, {700, 420}, 20),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return collision_wall_count >= 8 && qt.QuadtreeLen(&collision_tree) == collision_wall_count }, "dragging with the left button paints a wall of cells, the rebuilt tree holds them"),
    // walk into it: the player starts at x 640 and is 8 wide, the wall begins at x 688 (the cell of 700)
    kit.MoveTo({100, 100}),
    kit.Hold(.D, 60),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return collision_player.x > 660 && collision_player.x + PLAYER_SIZE.x <= 688.01 }, "the player stops at the wall and slides along it"),
    // walk around: down out of the wall, then right
    kit.Hold(.S, 60),
    kit.Hold(.D, 60),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return collision_player.x > 700 }, "below the wall the player gets past it"),
    // erase a cell with the right button
    kit.Click({700, 310}, .RIGHT),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return qt.QuadtreeLen(&collision_tree) < 9 + 9 && qt.QuadtreeLen(&collision_tree) == collision_wall_count }, "the right button erases, the tree follows"),
    kit.Click({300, 300}, .MIDDLE),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(collision_player.x - 296) < 0.01 }, "middle click puts the player on the mouse"),
}
