#+build !js
package quadtree

import "core:math/rand"
import "core:testing"

OversizeTestWorld :: QuadtreeChunks(5, 5, 256, 200, 2048)

@(private = "file")
BASE :: 1_000_000.0

// Items 1000 and up are the big ones (they do not fit `max_item_size` 30)
@(private = "file")
BIG :: 1000

@(private = "file")
big_rects: [6]WorldRect = {
    {BASE - 40, BASE + 20, 600, 40},           // a river along x
    {BASE + 150, BASE - 300, 25, 900},         // a wall along y
    {BASE - 500, BASE - 500, 1200, 1200},      // terrain under everything
    {BASE + 900, BASE + 900, 100, 100},        // far outside of the loaded chunks
    {BASE + 10, BASE + 10, 50, 31},            // just over the limit in one direction
    {BASE + 300, BASE + 300, 31, 20},
}

@(private = "file")
makeWorld :: proc() -> ^OversizeTestWorld {
    world: ^OversizeTestWorld = new(OversizeTestWorld)
    QuadtreeChunksInit(world, 100, 30, 4, 5)
    QuadtreeChunksStream(world, {BASE + 50, BASE + 50}, 2, nil, proc(user: rawptr, cx: int, cy: int) {})
    return world
}

@(private = "file")
overlapsRect :: proc(a: WorldRect, b: WorldRect) -> bool {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

// How many of the results are big items, and which ones (as a bit mask)
@(private = "file")
bigMask :: proc(out: []Item) -> (mask: int) {
    for item in out { if item >= BIG { mask |= 1 << uint(item - BIG) } }
    return
}

@(test)
test_big_items_are_refused_without_a_list_and_found_with_one :: proc(t: ^testing.T) {
    world: ^OversizeTestWorld = makeWorld()
    defer free(world)
    testing.expect(t, !QuadtreeChunksInsert(world, big_rects[0], BIG), "refused without an oversize list")
    storage: [4]OversizeEntry
    QuadtreeChunksOversize(world, storage[:])
    for i in 0 ..< 4 { testing.expect(t, QuadtreeChunksInsert(world, big_rects[i], BIG + i)) }
    testing.expect(t, !QuadtreeChunksInsert(world, big_rects[4], BIG + 4), "the list is full")
    testing.expect_value(t, QuadtreeChunksOversizeCount(world), 4)
    testing.expect_value(t, QuadtreeChunksLen(world), 4)
    out: [16]Item
    count: int = QuadtreeChunksQueryPoint(world, {BASE + 100, BASE + 30}, out[:])
    testing.expect(t, count == 2 && bigMask(out[:count]) == 0b101, "the river and the terrain hold the point")
    // one far outside of every loaded chunk is found too
    count = QuadtreeChunksQuery(world, {BASE + 950, BASE + 950, 10, 10}, out[:])
    testing.expect(t, count == 1 && bigMask(out[:count]) == 0b1000, "only the far one, outside of every loaded chunk")
    QuadtreeChunksOversizeClear(world)
    testing.expect_value(t, QuadtreeChunksQuery(world, {BASE, BASE, 10, 10}, out[:]), 0)
}

@(test)
test_queries_with_big_items_match_a_brute_force_search :: proc(t: ^testing.T) {
    world: ^OversizeTestWorld = makeWorld()
    defer free(world)
    storage: [8]OversizeEntry
    QuadtreeChunksOversize(world, storage[:])
    for rect, i in big_rects { testing.expect(t, QuadtreeChunksInsert(world, rect, BIG + i)) }
    state: rand.Default_Random_State = rand.create(2024)
    generator: rand.Generator = rand.default_random_generator(&state)
    out: [4096]Item
    for _ in 0 ..< 400 {
        x: f64 = BASE - 100 + f64(rand.float32(generator)) * 1200
        y: f64 = BASE - 100 + f64(rand.float32(generator)) * 1200
        // a rectangle
        query: WorldRect = {x, y, 1 + f64(rand.float32(generator)) * 200, 1 + f64(rand.float32(generator)) * 200}
        count: int = QuadtreeChunksQuery(world, query, out[:])
        expected: int
        for rect, i in big_rects { if overlapsRect(rect, query) { expected |= 1 << uint(i) } }
        testing.expect_value(t, bigMask(out[:count]), expected)
        // a point
        count = QuadtreeChunksQueryPoint(world, {x, y}, out[:])
        expected = 0
        for rect, i in big_rects { if x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h { expected |= 1 << uint(i) } }
        testing.expect_value(t, bigMask(out[:count]), expected)
        // a circle
        radius: f64 = 1 + f64(rand.float32(generator)) * 150
        count = QuadtreeChunksQueryCircle(world, {x, y}, radius, out[:])
        expected = 0
        for rect, i in big_rects { if oversizeDistanceSquared({x, y}, rect) < radius * radius { expected |= 1 << uint(i) } }
        testing.expect_value(t, bigMask(out[:count]), expected)
        // a segment: the entry point of the slab test of the reference is replaced here by sampling along it
        end: WorldVec = {x + (f64(rand.float32(generator)) - 0.5) * 800, y + (f64(rand.float32(generator)) - 0.5) * 800}
        count = QuadtreeChunksQuerySegment(world, {x, y}, end, out[:])
        expected = 0
        for rect, i in big_rects {
            for step in 0 ..= 4000 {
                s: f64 = f64(step) / 4000
                px: f64 = x + (end.x - x) * s
                py: f64 = y + (end.y - y) * s
                if px >= rect.x && px <= rect.x + rect.w && py >= rect.y && py <= rect.y + rect.h { expected |= 1 << uint(i); break }
            }
        }
        found: int = bigMask(out[:count])
        // sampling can miss a corner graze: the search may find more, never less
        testing.expect(t, found & expected == expected, "a segment finds every big item that it crosses")
    }
}

@(test)
test_segment_first_and_nearest_know_the_big_items :: proc(t: ^testing.T) {
    world: ^OversizeTestWorld = makeWorld()
    defer free(world)
    storage: [8]OversizeEntry
    QuadtreeChunksOversize(world, storage[:])
    // a small item near the start of a ray and two big ones behind it
    testing.expect(t, QuadtreeChunksInsert(world, {BASE + 60, BASE + 60, 10, 10}, 7))
    testing.expect(t, QuadtreeChunksInsert(world, {BASE + 200, BASE + 40, 40, 400}, BIG))
    testing.expect(t, QuadtreeChunksInsert(world, {BASE + 400, BASE + 40, 40, 400}, BIG + 1))
    item, at, hit := QuadtreeChunksSegmentFirst(world, {BASE + 0, BASE + 65}, {BASE + 500, BASE + 65})
    testing.expect(t, hit && item == 7 && at < 0.2, "the small item is nearer")
    item, at, hit = QuadtreeChunksSegmentFirst(world, {BASE + 100, BASE + 100}, {BASE + 500, BASE + 100})
    testing.expect(t, hit && item == BIG, "the first big item along the ray")
    testing.expect(t, abs(at - 0.25) < 1e-4, "at the right distance")
    item, _, hit = QuadtreeChunksSegmentFirst(world, {BASE + 100, BASE + 100}, {BASE + 500, BASE + 100}, BIG)
    testing.expect(t, hit && item == BIG + 1, "omit works for the list too")
    // the nearest items to a point: a distance to a big rectangle is measured in f64
    found: [3]Item
    distances: [3]f32
    count: int = QuadtreeChunksNearest(world, {BASE + 150, BASE + 100}, found[:], distances[:])
    testing.expect(t, count == 3 && found[0] == BIG && abs(distances[0] - 50) < 1e-3, "the first wall is 50 away")
    count = QuadtreeChunksNearest(world, {BASE + 330, BASE + 100}, found[:], distances[:])
    testing.expect(t, count == 3 && found[0] == BIG + 1 && abs(distances[0] - 70) < 1e-3, "the second wall is nearest at 70")
}

@(test)
test_the_iterator_walks_the_big_items_after_the_chunks :: proc(t: ^testing.T) {
    world: ^OversizeTestWorld = makeWorld()
    defer free(world)
    storage: [8]OversizeEntry
    QuadtreeChunksOversize(world, storage[:])
    testing.expect(t, QuadtreeChunksInsert(world, {BASE + 60, BASE + 60, 10, 10}, 7))
    for rect, i in big_rects { testing.expect(t, QuadtreeChunksInsert(world, rect, BIG + i)) }
    it: QuadtreeChunksIterator
    QuadtreeChunksQueryBegin(&it, world, {BASE + 55, BASE + 55, 20, 20})
    seen: [dynamic]Item
    defer delete(seen)
    for {
        item, ok := QuadtreeChunksQueryNext(world, &it)
        if !ok { break }
        append(&seen, item)
    }
    testing.expect(t, bigMask(seen[:]) == func_mask(BASE + 55, BASE + 55, 20, 20), "the big items that overlap come out of the iterator")
    small: int
    for item in seen { if item == 7 { small += 1 } }
    testing.expect_value(t, small, 1)
    // the same through a point iterator
    QuadtreeChunksQueryPointBegin(&it, world, {BASE + 100, BASE + 30})
    count: int
    for {
        _, ok := QuadtreeChunksQueryNext(world, &it)
        if !ok { break }
        count += 1
    }
    testing.expect_value(t, count, 2)
}

// The big items that overlap a rectangle, as a bit mask (the brute force of the iterator test)
@(private = "file")
func_mask :: proc(x: f64, y: f64, w: f64, h: f64) -> (mask: int) {
    for rect, i in big_rects { if overlapsRect(rect, {x, y, w, h}) { mask |= 1 << uint(i) } }
    return
}
