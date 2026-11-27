#+private file
package demo_common

import "core:fmt"
import "core:math"
import "core:math/rand"
import qt ".."
import kit "../../demo_kit"
import qtkit "../kit"

@(private = "package")
demo_chunks: kit.Demo = {
    name = "chunked world",
    init = chunksInit,
    update = chunksUpdate,
    draw = chunksDraw,
    script = chunksScript,
}

// A world without an edge: chunks of 256 units, each with its own tree, a window of 9 x 9 chunks kept loaded around the player (the square of 4 chunks on each side), objects generated from the chunk
// coordinate when it loads (nothing is stored for the rest of the world). The player starts half a million units from the origin, T jumps millions of units away: the positions are f64 and the trees only see
// small local offsets, so the precision is the same everywhere. WASD walks, the mouse points at objects, G shows the trees and chunk borders.
CHUNK_SIZE :: 256.0
RADIUS :: 4
RING :: 2 * RADIUS + 1
PER_CHUNK :: 60
OBJECT_MIN :: 8.0
OBJECT_MAX :: 40.0
PLAYER_SIZE :: 16.0
PLAYER_SPEED :: 600.0
VIEW_WIDTH :: 1280.0
VIEW_HEIGHT :: 720.0
START :: qt.WorldVec{500_000.5, 500_000.5}

ChunkWorld :: qt.QuadtreeChunks(RING, RING, 128, 500, 3000)

Object :: struct {
    rect: qt.WorldRect,
    color: kit.Color,
}

chunks_world: ChunkWorld
chunks_objects: [RING * RING * PER_CHUNK]Object     // the item of a tree is the index here: the slot of the chunk in the ring times PER_CHUNK plus the number
chunks_player: qt.WorldRect
chunks_seed: rand.Default_Random_State
chunks_random: rand.Generator
chunks_show_tree: bool

chunks_view: qt.WorldRect                           // what the window shows, in world units
chunks_view_items: [2048]qt.Item
chunks_view_count: int
chunks_touched: [64]qt.Item                         // objects under the player
chunks_touched_count: int
chunks_hovered: qt.Item = qt.ITEM_NONE              // object under the mouse
chunks_hover_candidates: int
chunks_loaded: int                                  // chunks loaded / unloaded in the last frame and in total
chunks_unloaded: int
chunks_loaded_total: int
chunks_unloaded_total: int
chunks_remember: int                                // the script remembers a number here
chunks_target: qt.Vec2                              // where the script points the mouse (screen)

chunksSlot :: proc(cx: int, cy: int) -> int {
    return (((cy % RING) + RING) % RING) * RING + ((cx % RING) + RING) % RING
}

// The content of a chunk comes from its coordinate, so it is the same every time it loads
chunksFill :: proc(user: rawptr, cx: int, cy: int) {
    seed: rand.Default_Random_State = rand.create(u64(i64(cx)) * 73856093 ~ u64(i64(cy)) * 19349663 + 7)
    random: rand.Generator = rand.default_random_generator(&seed)
    slot: int = chunksSlot(cx, cy)
    for i in 0 ..< PER_CHUNK {
        item: int = slot * PER_CHUNK + i
        // the corner is inside of the chunk, the size may reach into the next one
        rect: qt.WorldRect = {
            (f64(cx) + f64(rand.float32(random))) * CHUNK_SIZE,
            (f64(cy) + f64(rand.float32(random))) * CHUNK_SIZE,
            OBJECT_MIN + f64(rand.float32(random)) * (OBJECT_MAX - OBJECT_MIN),
            OBJECT_MIN + f64(rand.float32(random)) * (OBJECT_MAX - OBJECT_MIN),
        }
        chunks_objects[item] = {rect, hoverColor(rand.float32(random))}
        qt.QuadtreeChunksInsert(&chunks_world, rect, item)
    }
}

chunksInit :: proc(ctx: ^kit.Context) {
    chunks_seed = rand.create(4242)
    chunks_random = rand.default_random_generator(&chunks_seed)
    chunksReset()
    chunks_show_tree = true
}

chunksReset :: proc() {
    qt.QuadtreeChunksInit(&chunks_world, CHUNK_SIZE, OBJECT_MAX, 8, 5)
    chunks_player = {START.x, START.y, PLAYER_SIZE, PLAYER_SIZE}
    chunks_loaded_total = 0
    chunks_unloaded_total = 0
    chunks_hovered = qt.ITEM_NONE
}

chunksCenter :: proc() -> qt.WorldVec {
    return {chunks_player.x + chunks_player.w * 0.5, chunks_player.y + chunks_player.h * 0.5}
}

// World to window: the subtraction is done in f64 before the number gets small
chunksScreen :: proc(x: f64, y: f64) -> qt.Vec2 {
    center: qt.WorldVec = chunksCenter()
    return {f32(x - center.x) + VIEW_WIDTH * 0.5, f32(y - center.y) + VIEW_HEIGHT * 0.5}
}

chunksScreenRect :: proc(rect: qt.WorldRect) -> kit.Rect {
    corner: qt.Vec2 = chunksScreen(rect.x, rect.y)
    return {corner.x, corner.y, f32(rect.w), f32(rect.h)}
}

chunksUpdate :: proc(ctx: ^kit.Context) {
    if kit.KeyPressed(&ctx.input, .R) { chunksReset() }
    if kit.KeyPressed(&ctx.input, .G) { chunks_show_tree = !chunks_show_tree }
    if kit.KeyPressed(&ctx.input, .T) {
        // far away in a random direction
        chunks_player.x = (f64(rand.float32(chunks_random)) - 0.5) * 8_000_000
        chunks_player.y = (f64(rand.float32(chunks_random)) - 0.5) * 8_000_000
    }
    direction: qt.Vec2
    if kit.KeyDown(&ctx.input, .W) { direction.y -= 1 }
    if kit.KeyDown(&ctx.input, .S) { direction.y += 1 }
    if kit.KeyDown(&ctx.input, .A) { direction.x -= 1 }
    if kit.KeyDown(&ctx.input, .D) { direction.x += 1 }
    chunks_player.x += f64(direction.x * PLAYER_SPEED * ctx.delta_time)
    chunks_player.y += f64(direction.y * PLAYER_SPEED * ctx.delta_time)

    // keep the window of chunks around the player, the fill proc generates what is new
    chunks_loaded, chunks_unloaded = qt.QuadtreeChunksStream(&chunks_world, chunksCenter(), RADIUS, nil, chunksFill)
    chunks_loaded_total += chunks_loaded
    chunks_unloaded_total += chunks_unloaded

    center: qt.WorldVec = chunksCenter()
    chunks_view = {center.x - VIEW_WIDTH * 0.5, center.y - VIEW_HEIGHT * 0.5, VIEW_WIDTH, VIEW_HEIGHT}
    chunks_view_count = qt.QuadtreeChunksQuery(&chunks_world, chunks_view, chunks_view_items[:])
    chunks_touched_count = qt.QuadtreeChunksQuery(&chunks_world, chunks_player, chunks_touched[:])

    // the point of the mouse in the world, and the object that really holds it (the last one drawn wins)
    mouse: qt.Vec2 = ctx.input.mouse_position
    point: qt.WorldVec = {center.x + f64(mouse.x - VIEW_WIDTH * 0.5), center.y + f64(mouse.y - VIEW_HEIGHT * 0.5)}
    buffer: [32]qt.Item
    count: int = qt.QuadtreeChunksQueryPoint(&chunks_world, point, buffer[:])
    chunks_hover_candidates = count
    chunks_hovered = qt.ITEM_NONE
    for i in 0 ..< count { chunks_hovered = max(chunks_hovered, buffer[i]) }
}

chunksDraw :: proc(ctx: ^kit.Context) {
    if chunks_show_tree { qtkit.DrawQuadtreeChunks(ctx, &chunks_world, chunksCenter(), {VIEW_WIDTH * 0.5, VIEW_HEIGHT * 0.5}) }
    for i in 0 ..< chunks_view_count {
        item: qt.Item = chunks_view_items[i]
        object: ^Object = &chunks_objects[item]
        touched: bool
        for j in 0 ..< chunks_touched_count { if chunks_touched[j] == item { touched = true } }
        kit.DrawRect(ctx, chunksScreenRect(object.rect), kit.ORANGE if touched else object.color)
    }
    if chunks_hovered != qt.ITEM_NONE {
        kit.DrawRectOutline(ctx, chunksScreenRect(chunks_objects[chunks_hovered].rect), 3, kit.BLACK)
    }
    kit.DrawRect(ctx, chunksScreenRect(chunks_player), kit.WHITE)
    kit.DrawRectOutline(ctx, chunksScreenRect(chunks_player), 2, kit.BLACK)

    nodes, links, most_nodes, most_links := qt.QuadtreeChunksUsage(&chunks_world)
    kit.DrawText(ctx, "chunked world: WASD walk, T jump millions of units away, mouse points at an object, G trees, R start", {10, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("player = (%.1f, %.1f)   chunks loaded = %v (this frame +%v -%v, total %v)   objects = %v", chunks_player.x, chunks_player.y, qt.QuadtreeChunksLoadedCount(&chunks_world), chunks_loaded, chunks_unloaded, chunks_loaded_total, qt.QuadtreeChunksLen(&chunks_world)), {10, 36}, 20, kit.DARK_GRAY)
    kit.DrawText(ctx, fmt.tprintf("in view = %v, touching the player = %v, boxes under the mouse = %v   nodes = %v (most in a chunk %v), links = %v (%v)", chunks_view_count, chunks_touched_count, chunks_hover_candidates, nodes, most_nodes, links, most_links), {10, 62}, 20, kit.DARK_GRAY)
}

// What a brute force search over every object in the window finds: the world must report the same ones
chunksMatchesBruteForce :: proc(ctx: ^kit.Context) -> bool {
    expected: int
    for &object in chunks_objects {
        rect: qt.WorldRect = object.rect
        if rect.x < chunks_view.x + chunks_view.w && rect.x + rect.w > chunks_view.x && rect.y < chunks_view.y + chunks_view.h && rect.y + rect.h > chunks_view.y { expected += 1 }
    }
    return expected == chunks_view_count && expected > 0
}

chunksFull :: proc(ctx: ^kit.Context) -> bool {
    return qt.QuadtreeChunksLoadedCount(&chunks_world) == RING * RING && qt.QuadtreeChunksLen(&chunks_world) == RING * RING * PER_CHUNK
}

// The first visible object: the script points the mouse at its middle
chunksAim :: proc(ctx: ^kit.Context) -> bool {
    if chunks_view_count == 0 { return false }
    rect: qt.WorldRect = chunks_objects[chunks_view_items[0]].rect
    chunks_target = chunksScreen(rect.x + rect.w * 0.5, rect.y + rect.h * 0.5)
    return true
}

chunksScript: []kit.Step = {
    kit.Wait(2),
    kit.Check(chunksFull, "the 9 x 9 window of chunks around the player is loaded and filled"),
    kit.Check(chunksMatchesBruteForce, "a query of the view finds the same objects as a brute force search"),
    kit.Check(chunksAim, "there is an object to point at"),
    kit.MoveAt(&chunks_target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if chunks_hovered == qt.ITEM_NONE { return false }
        rect: qt.WorldRect = chunks_objects[chunks_hovered].rect
        point: qt.Vec2 = chunks_target
        corner: qt.Vec2 = chunksScreen(rect.x, rect.y)
        return point.x >= corner.x && point.x < corner.x + f32(rect.w) && point.y >= corner.y && point.y < corner.y + f32(rect.h)
    }, "the object under the mouse is found at half a million units from the origin"),
    // walk right for two seconds: about five chunks of streaming
    kit.Hold(.D, 120),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return chunks_player.x > START.x + 1000 && chunks_loaded_total > RING * RING }, "walking streams new chunks in"),
    kit.Check(chunksFull, "the window is full again after the walk"),
    kit.Check(chunksMatchesBruteForce, "still the same as a brute force search after streaming"),
    // jump millions of units: everything is replaced
    kit.Check(proc(ctx: ^kit.Context) -> bool { chunks_remember = chunks_unloaded_total; return true }, "remember how many chunks were unloaded so far"),
    kit.Tap(.T),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(chunks_player.x - START.x) > 100_000 && chunks_unloaded_total - chunks_remember == RING * RING }, "a jump replaces the whole window"),
    kit.Check(chunksFull, "the window is full far away too"),
    kit.Check(chunksMatchesBruteForce, "and queries still match a brute force search there"),
    kit.Tap(.R),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return math.abs(chunks_player.x - START.x) < 1 && chunksFull(ctx) }, "R goes back to the start"),
}
