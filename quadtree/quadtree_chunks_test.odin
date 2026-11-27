#+build !js
package quadtree

import "core:math/rand"
import "core:testing"

// 7 x 7 ring of chunks of 100 units, items up to 30
ChunkTestWorld :: QuadtreeChunks(7, 7, 256, 600, 4096)

@(private = "file")
Thing :: struct {
    rect: WorldRect,
    alive: bool,
}

// Items are indices into this array, like the demo. Every thing sits in a loaded chunk by construction
@(private = "file")
fillThings :: proc(t: ^testing.T, world: ^ChunkTestWorld, things: []Thing, origin: WorldVec, state: rand.Generator) {
    for &thing, index in things {
        x: f64 = origin.x + f64(rand.float32(state)) * 600
        y: f64 = origin.y + f64(rand.float32(state)) * 600
        thing = {rect = {x, y, 1 + f64(rand.float32(state)) * 29, 1 + f64(rand.float32(state)) * 29}, alive = true}
        testing.expect(t, QuadtreeChunksInsert(world, thing.rect, index))
    }
}

@(private = "file")
matches :: proc(t: ^testing.T, world: ^ChunkTestWorld, things: []Thing, rect: WorldRect) {
    out: [512]Item
    count: int = QuadtreeChunksQuery(world, rect, out[:])
    seen: [512]bool
    expected: int
    for thing in things {
        if !thing.alive { continue }
        overlaps: bool = thing.rect.x < rect.x + rect.w && thing.rect.x + thing.rect.w > rect.x && thing.rect.y < rect.y + rect.h && thing.rect.y + thing.rect.h > rect.y
        if overlaps { expected += 1 }
    }
    for i in 0 ..< count {
        testing.expect(t, !seen[out[i]], "every item is reported once")
        seen[out[i]] = true
    }
    // f32 local coordinates may disagree with the f64 test on a touching edge: allow one of difference per query
    testing.expect(t, abs(count - expected) <= 1, "the chunks find what a brute force search finds")
}

@(test)
test_chunks_match_a_brute_force_search_near_the_origin_and_far_away :: proc(t: ^testing.T) {
    world: ^ChunkTestWorld = new(ChunkTestWorld)
    defer free(world)
    seed: rand.Default_Random_State = rand.create(99)
    state: rand.Generator = rand.default_random_generator(&seed)
    // the second place is 50 million units away: an f32 tree could not tell 0.01 apart there
    for origin in ([]WorldVec{{-300, -300}, {50_000_000, -73_000_000}}) {
        QuadtreeChunksInit(world, 100, 30, 6, 5)
        for cy in -3 ..= 3 {
            for cx in -3 ..= 3 {
                testing.expect(t, QuadtreeChunksLoad(world, QuadtreeChunksCoord(world, origin.x) + cx + 3, QuadtreeChunksCoord(world, origin.y) + cy + 3))
            }
        }
        things: [400]Thing
        fillThings(t, world, things[:], {origin.x + 0, origin.y + 0}, state)
        testing.expect_value(t, QuadtreeChunksLen(world), 400)
        for _ in 0 ..< 40 {
            query: WorldRect = {origin.x + f64(rand.float32(state)) * 600 - 50, origin.y + f64(rand.float32(state)) * 600 - 50, 1 + f64(rand.float32(state)) * 200, 1 + f64(rand.float32(state)) * 200}
            matches(t, world, things[:], query)
        }
        // a rectangle that covers more chunks than the window has slots
        matches(t, world, things[:], {origin.x - 5000, origin.y - 5000, 12000, 12000})
    }
}

@(test)
test_an_item_that_sticks_out_of_its_chunk_is_found_from_the_next_one :: proc(t: ^testing.T) {
    world: ^ChunkTestWorld = new(ChunkTestWorld)
    defer free(world)
    QuadtreeChunksInit(world, 100, 30, 4, 4)
    for cx in 0 ..< 3 { testing.expect(t, QuadtreeChunksLoad(world, cx, 0)) }
    // starts in chunk 0 (x = 90), reaches x = 115
    testing.expect(t, QuadtreeChunksInsert(world, {90, 10, 25, 10}, 7))
    out: [8]Item
    testing.expect_value(t, QuadtreeChunksQuery(world, {110, 5, 20, 20}, out[:]), 1)    // the query lies in chunk 1 only
    testing.expect_value(t, out[0], 7)
    testing.expect_value(t, QuadtreeChunksQueryPoint(world, {112, 15}, out[:]), 1)
    testing.expect_value(t, QuadtreeChunksQueryPoint(world, {116, 15}, out[:]), 0)
    testing.expect_value(t, QuadtreeChunksQuery(world, {0, 0, 300, 100}, out[:], 7), 0)  // omit
    // too big, and in a chunk that is not loaded: refused
    testing.expect(t, !QuadtreeChunksInsert(world, {10, 10, 31, 5}, 8))
    testing.expect(t, !QuadtreeChunksInsert(world, {450, 10, 5, 5}, 9))
}

@(test)
test_load_unload_and_the_ring_slots :: proc(t: ^testing.T) {
    world: ^ChunkTestWorld = new(ChunkTestWorld)
    defer free(world)
    QuadtreeChunksInit(world, 100, 30, 4, 4)
    testing.expect(t, QuadtreeChunksLoad(world, 2, 3))
    testing.expect(t, QuadtreeChunksInsert(world, {250, 350, 5, 5}, 1))
    testing.expect(t, QuadtreeChunksLoad(world, 2, 3), "loading a loaded chunk keeps it")
    testing.expect_value(t, QuadtreeChunksLen(world), 1)
    // (2 + 7, 3) is the same slot: refused until the first one is unloaded
    testing.expect(t, !QuadtreeChunksLoad(world, 9, 3))
    testing.expect(t, QuadtreeChunksUnload(world, 2, 3))
    testing.expect(t, !QuadtreeChunksUnload(world, 2, 3))
    testing.expect(t, QuadtreeChunksLoad(world, 9, 3))
    testing.expect_value(t, QuadtreeChunksLen(world), 0)
    out: [4]Item
    testing.expect_value(t, QuadtreeChunksQuery(world, {200, 300, 100, 100}, out[:]), 0)   // chunk (2, 3) is gone, the slot now belongs to (9, 3)
    // negative coordinates use the same ring
    testing.expect(t, QuadtreeChunksLoad(world, -1, -1))
    testing.expect(t, QuadtreeChunksInsert(world, {-50, -50, 5, 5}, 2))
    testing.expect_value(t, QuadtreeChunksQueryPoint(world, {-48, -48}, out[:]), 1)
    // clear keeps chunks loaded
    QuadtreeChunksClear(world)
    testing.expect_value(t, QuadtreeChunksLen(world), 0)
    testing.expect_value(t, QuadtreeChunksLoadedCount(world), 2)
}

@(private = "file")
StreamCount :: struct {
    filled: int,
    dropped: int,
}

@(private = "file")
streamFill :: proc(user: rawptr, cx: int, cy: int) {
    (cast(^StreamCount)user).filled += 1
}

@(private = "file")
streamDrop :: proc(user: rawptr, cx: int, cy: int) {
    (cast(^StreamCount)user).dropped += 1
}

@(test)
test_stream_follows_the_center :: proc(t: ^testing.T) {
    world: ^ChunkTestWorld = new(ChunkTestWorld)
    defer free(world)
    QuadtreeChunksInit(world, 100, 30, 4, 4)
    counts: StreamCount
    loaded, unloaded := QuadtreeChunksStream(world, {50, 50}, 3, &counts, streamFill, streamDrop)
    testing.expect_value(t, loaded, 49)
    testing.expect_value(t, unloaded, 0)
    testing.expect_value(t, QuadtreeChunksLoadedCount(world), 49)
    // nothing changes while the center stays in its chunk
    loaded, unloaded = QuadtreeChunksStream(world, {80, 20}, 3, &counts, streamFill, streamDrop)
    testing.expect_value(t, loaded + unloaded, 0)
    // one chunk to the right: a column goes, a column comes
    loaded, unloaded = QuadtreeChunksStream(world, {150, 50}, 3, &counts, streamFill, streamDrop)
    testing.expect_value(t, loaded, 7)
    testing.expect_value(t, unloaded, 7)
    testing.expect_value(t, counts.filled, 56)
    testing.expect_value(t, counts.dropped, 7)
    testing.expect(t, QuadtreeChunksIsLoaded(world, 4, 0))
    testing.expect(t, !QuadtreeChunksIsLoaded(world, -3, 0))
    // a jump across the world replaces everything
    loaded, unloaded = QuadtreeChunksStream(world, {9_000_000, -4_000_000}, 3, &counts, streamFill, streamDrop)
    testing.expect_value(t, loaded, 49)
    testing.expect_value(t, unloaded, 49)
    testing.expect_value(t, QuadtreeChunksLoadedCount(world), 49)
}

@(private = "file")
countNode :: proc(user: rawptr, rect: WorldRect, depth: int, leaf: bool, count: int) {
    if leaf { (cast(^int)user)^ += 1 }
}

@(test)
test_visit_reports_world_coordinates :: proc(t: ^testing.T) {
    world: ^ChunkTestWorld = new(ChunkTestWorld)
    defer free(world)
    QuadtreeChunksInit(world, 100, 30, 4, 4)
    testing.expect(t, QuadtreeChunksLoad(world, 5, 6))
    leaves: int
    QuadtreeChunksVisit(world, &leaves, countNode)
    testing.expect_value(t, leaves, 1)
    first: WorldRect
    QuadtreeChunksVisit(world, &first, proc(user: rawptr, rect: WorldRect, depth: int, leaf: bool, count: int) { (cast(^WorldRect)user)^ = rect })
    testing.expect_value(t, first, WorldRect{500, 600, 100, 100})
}
