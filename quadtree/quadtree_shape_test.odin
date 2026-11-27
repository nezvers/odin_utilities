#+build !js
package quadtree

import "core:math"
import "core:mem"
import "core:math/rand"
import "core:slice"
import "core:testing"
import "core:thread"

ShapeTree :: Quadtree(512, 400, 4096)

@(private = "file")
randomShapeRect :: proc(state: rand.Generator, area: Rect, biggest: f32) -> Rect {
    width: f32 = 1 + rand.float32(state) * biggest
    height: f32 = 1 + rand.float32(state) * biggest
    return {area.x + rand.float32(state) * (area.w - width), area.y + rand.float32(state) * (area.h - height), width, height}
}

// An independent segment against rectangle test (not the slab method of the library): an end inside, or a crossing of one of the four edges. Returns the smallest t of a hit.
@(private = "file")
bruteSegmentRect :: proc(a: Vec2, b: Vec2, rect: Rect) -> (t: f32, hit: bool) {
    inside :: proc(point: Vec2, rect: Rect) -> bool {
        return point.x >= rect.x && point.x <= rect.x + rect.w && point.y >= rect.y && point.y <= rect.y + rect.h
    }
    if inside(a, rect) { return 0, true }
    best: f32 = 2
    corners: [4]Vec2 = {{rect.x, rect.y}, {rect.x + rect.w, rect.y}, {rect.x + rect.w, rect.y + rect.h}, {rect.x, rect.y + rect.h}}
    for i in 0 ..< 4 {
        c: Vec2 = corners[i]
        d: Vec2 = corners[(i + 1) % 4]
        r: Vec2 = b - a
        s: Vec2 = d - c
        denominator: f32 = r.x * s.y - r.y * s.x
        if denominator == 0 { continue }
        along: f32 = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denominator
        across: f32 = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / denominator
        if along >= 0 && along <= 1 && across >= 0 && across <= 1 { best = min(best, along) }
    }
    return best, best <= 1
}

@(private = "file")
bruteCircleRect :: proc(center: Vec2, radius: f32, rect: Rect) -> bool {
    nearest: Vec2 = center
    if nearest.x < rect.x { nearest.x = rect.x }
    if nearest.x > rect.x + rect.w { nearest.x = rect.x + rect.w }
    if nearest.y < rect.y { nearest.y = rect.y }
    if nearest.y > rect.y + rect.h { nearest.y = rect.y + rect.h }
    delta: Vec2 = nearest - center
    return delta.x * delta.x + delta.y * delta.y < radius * radius
}

@(private = "file")
fillTree :: proc(tree: ^ShapeTree, rects: []Rect, state: rand.Generator, area: Rect, outside: int) {
    QuadtreeClear(tree)
    for i in 0 ..< len(rects) {
        rects[i] = randomShapeRect(state, area, 90)
        // the last ones lie outside of the bounds: they sit in the border leaves and must still be found
        if i >= len(rects) - outside { rects[i].x += area.w if i % 2 == 0 else -area.w - 100 }
        QuadtreeInsert(tree, rects[i], i)
    }
}

@(test)
test_circle_queries_match_a_brute_force_search :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 6, 6)
    seed: rand.Default_Random_State = rand.create(77)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [300]Rect
    fillTree(tree, rects[:], state, area, 20)
    out: [512]Item
    for _ in 0 ..< 200 {
        center: Vec2 = {rand.float32(state) * 1300 - 150, rand.float32(state) * 800}
        radius: f32 = rand.float32(state) * 200
        count: int = QuadtreeQueryCircle(tree, center, radius, out[:])
        expected: int
        for rect, index in rects {
            if !bruteCircleRect(center, radius, rect) { continue }
            expected += 1
            found: bool
            for i in 0 ..< count { if out[i] == index { found = true } }
            testing.expect(t, found, "a rectangle inside the circle is reported")
        }
        testing.expect_value(t, count, expected)
    }
    testing.expect_value(t, QuadtreeQueryCircle(tree, {500, 400}, 0, out[:]), 0)
}

@(test)
test_segment_queries_match_a_brute_force_search :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 6, 6)
    seed: rand.Default_Random_State = rand.create(78)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [300]Rect
    fillTree(tree, rects[:], state, area, 20)
    out: [512]Item
    for _ in 0 ..< 300 {
        a: Vec2 = {rand.float32(state) * 1300 - 150, rand.float32(state) * 900 - 50}
        b: Vec2 = {rand.float32(state) * 1300 - 150, rand.float32(state) * 900 - 50}
        count: int = QuadtreeQuerySegment(tree, a, b, out[:])
        expected: int
        best: f32 = 2
        for rect, index in rects {
            at, hit := bruteSegmentRect(a, b, rect)
            if !hit { continue }
            expected += 1
            best = min(best, at)
            found: bool
            for i in 0 ..< count { if out[i] == index { found = true } }
            testing.expect(t, found, "a rectangle on the segment is reported")
        }
        testing.expect_value(t, count, expected)
        item, at, hit := QuadtreeSegmentFirst(tree, a, b)
        testing.expect_value(t, hit, best <= 1)
        if hit {
            testing.expect(t, abs(at - best) < 0.0005, "the first hit is the nearest along the segment")
            expected_at, _ := bruteSegmentRect(a, b, rects[item])
            testing.expect(t, abs(expected_at - at) < 0.0005, "the item belongs to the hit")
        }
    }
}

@(test)
test_segment_edge_cases :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    QuadtreeInit(tree, {0, 0, 100, 100}, 2, 4)
    QuadtreeInsert(tree, {40, 40, 20, 20}, 1)
    QuadtreeInsert(tree, {80, 10, 10, 10}, 2)
    out: [8]Item
    // a point (zero length), a segment inside a rectangle, one that stops short, one that runs along an edge
    testing.expect_value(t, QuadtreeQuerySegment(tree, {50, 50}, {50, 50}, out[:]), 1)
    testing.expect_value(t, QuadtreeQuerySegment(tree, {45, 45}, {55, 55}, out[:]), 1)
    testing.expect_value(t, QuadtreeQuerySegment(tree, {0, 50}, {39, 50}, out[:]), 0)
    testing.expect_value(t, QuadtreeQuerySegment(tree, {0, 40}, {100, 40}, out[:]), 1)
    // vertical and horizontal ones through both rectangles
    testing.expect_value(t, QuadtreeQuerySegment(tree, {0, 15}, {100, 15}, out[:]), 1)
    item, at, hit := QuadtreeSegmentFirst(tree, {0, 50}, {100, 50})
    testing.expect(t, hit && item == 1 && abs(at - 0.4) < 0.0001, "the ray meets the rectangle at x = 40")
    item, at, hit = QuadtreeSegmentFirst(tree, {50, 50}, {100, 50})
    testing.expect(t, hit && item == 1 && at == 0, "a start inside the rectangle hits at t = 0")
    _, _, hit = QuadtreeSegmentFirst(tree, {0, 90}, {100, 90})
    testing.expect(t, !hit, "a ray that misses everything")
    item, _, hit = QuadtreeSegmentFirst(tree, {0, 50}, {100, 50}, omit = 1)
    testing.expect(t, !hit || item != 1, "an omitted item is not the hit")
    // an element far outside of the bounds sits in a border leaf and is still found
    QuadtreeInsert(tree, {300, 40, 10, 10}, 3)
    testing.expect_value(t, QuadtreeQuerySegment(tree, {0, 45}, {400, 45}, out[:]), 2)
    testing.expect_value(t, QuadtreeQueryCircle(tree, {305, 45}, 8, out[:]), 1)
}

// Threads read the same tree while nothing writes to it: the results equal the single thread ones (segment queries included, they write no marks)
ThreadJob :: struct {
    tree: ^ShapeTree,
    centers: [64]Vec2,
    expected: [64]int,
    wrong: int,
}

@(private = "file")
threadWork :: proc(data: rawptr) {
    job: ^ThreadJob = cast(^ThreadJob)data
    out: [512]Item
    for _ in 0 ..< 200 {
        for center, i in job.centers {
            if QuadtreeQuerySegment(job.tree, center, center + {120, 70}, out[:]) != job.expected[i] { job.wrong += 1 }
        }
    }
}

@(test)
test_threads_query_one_tree_without_sessions :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 6, 6)
    seed: rand.Default_Random_State = rand.create(79)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [400]Rect
    fillTree(tree, rects[:], state, area, 0)
    jobs: [4]^ThreadJob
    threads: [4]^thread.Thread
    for i in 0 ..< 4 {
        jobs[i] = new(ThreadJob)
        jobs[i].tree = tree
        for k in 0 ..< 64 {
            jobs[i].centers[k] = {rand.float32(state) * 1000, rand.float32(state) * 800}
            out: [512]Item
            jobs[i].expected[k] = QuadtreeQuerySegment(tree, jobs[i].centers[k], jobs[i].centers[k] + {120, 70}, out[:])      // the single thread answer, with marks in the tree
        }
    }
    for i in 0 ..< 4 { threads[i] = thread.create_and_start_with_data(jobs[i], threadWork) }
    for i in 0 ..< 4 {
        thread.join(threads[i])
        thread.destroy(threads[i])
        testing.expect_value(t, jobs[i].wrong, 0)
        free(jobs[i])
    }
}

@(test)
test_a_segment_reports_each_item_once_even_for_an_element_in_every_leaf :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 3, 6)
    seed: rand.Default_Random_State = rand.create(80)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [200]Rect
    fillTree(tree, rects[:], state, area, 0)
    QuadtreeInsert(tree, {0, 0, 1000, 800}, 999)            // in every leaf: the dedupe matters
    out: [512]Item
    for _ in 0 ..< 200 {
        rect: Rect = randomShapeRect(state, area, 400)
        center: Vec2 = {rect.x + rect.w * 0.5, rect.y + rect.h * 0.5}
        count: int = QuadtreeQuerySegment(tree, center, center + {rect.w, rect.h}, out[:])
        testing.expect(t, count > 0)
        seen: map[Item]bool
        seen.allocator = context.temp_allocator
        for i in 0 ..< count {
            testing.expect(t, out[i] not_in seen, "each item once")
            seen[out[i]] = true
        }
        testing.expect(t, 999 in seen, "the element that covers the tree is found")
    }
}

// The retained tree: the same shapes after adds, removals and moves
@(test)
test_retained_circle_and_segment_queries_match_a_brute_force_search :: proc(t: ^testing.T) {
    tree: ^RetainedTestTree = new(RetainedTestTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeRetainedInit(tree, area, 5, 6)
    seed: rand.Default_Random_State = rand.create(81)
    state: rand.Generator = rand.default_random_generator(&seed)
    handles: [dynamic]Handle
    handles.allocator = context.temp_allocator
    for _ in 0 ..< 300 {
        handle, ok := QuadtreeRetainedAdd(tree, randomShapeRect(state, area, 90))
        testing.expect(t, ok)
        append(&handles, handle)
    }
    // remove some, add others into the freed slots, move a few and put some far outside of the bounds
    for i := 0; i < len(handles); i += 3 {
        QuadtreeRetainedRemove(tree, handles[i])
        handle, _ := QuadtreeRetainedAdd(tree, randomShapeRect(state, area, 90))
        handles[i] = handle
    }
    for i := 1; i < len(handles); i += 7 { QuadtreeRetainedMove(tree, handles[i], randomShapeRect(state, area, 90)) }
    far, _ := QuadtreeRetainedAdd(tree, {1500, 100, 30, 30})
    append(&handles, far)

    out: [512]Handle
    for _ in 0 ..< 150 {
        center: Vec2 = {rand.float32(state) * 1700 - 100, rand.float32(state) * 800}
        radius: f32 = rand.float32(state) * 200
        a: Vec2 = {rand.float32(state) * 1700 - 100, rand.float32(state) * 900 - 50}
        b: Vec2 = {rand.float32(state) * 1700 - 100, rand.float32(state) * 900 - 50}
        circle: int = QuadtreeRetainedQueryCircle(tree, center, radius, out[:])
        segment: int = QuadtreeRetainedQuerySegment(tree, a, b, out[256:])
        expected_circle, expected_segment: int
        best: f32 = 2
        for handle in handles {
            element, _ := QuadtreeRetainedGet(tree, handle)
            if bruteCircleRect(center, radius, element.rect) { expected_circle += 1 }
            at, hit := bruteSegmentRect(a, b, element.rect)
            if hit {
                expected_segment += 1
                best = min(best, at)
            }
        }
        testing.expect_value(t, circle, expected_circle)
        testing.expect_value(t, segment, expected_segment)
        _, at, hit := QuadtreeRetainedSegmentFirst(tree, a, b)
        testing.expect_value(t, hit, best <= 1)
        if hit { testing.expect(t, abs(at - best) < 0.0005, "the first hit is the nearest along the segment") }
    }
}

ShapeWorld :: QuadtreeChunks(5, 5, 256, 200, 2048)

// The chunked world far from the origin (a million units): circles and segments over several chunks, against a brute force search on offsets from that place
@(test)
test_chunked_circle_and_segment_queries_match_a_brute_force_search :: proc(t: ^testing.T) {
    world: ^ShapeWorld = new(ShapeWorld)
    defer free(world)
    BASE :: 1_000_000.0
    QuadtreeChunksInit(world, 100, 30, 4, 5)
    seed: rand.Default_Random_State = rand.create(82)
    state: rand.Generator = rand.default_random_generator(&seed)
    // load the chunks around the base: coordinates 10000 - 2 .. 10000 + 2 (the window is 5 x 5)
    center: WorldVec = {BASE + 50, BASE + 50}
    quadtree_load :: proc(user: rawptr, cx: int, cy: int) {}
    QuadtreeChunksStream(world, center, 2, nil, quadtree_load)
    rects: [400]Rect                  // relative to BASE, in f32
    inserted: int
    for i in 0 ..< len(rects) {
        rects[i] = {rand.float32(state) * 480 - 190, rand.float32(state) * 480 - 190, 1 + rand.float32(state) * 29, 1 + rand.float32(state) * 29}
        world_rect: WorldRect = {BASE + f64(rects[i].x), BASE + f64(rects[i].y), f64(rects[i].w), f64(rects[i].h)}
        if QuadtreeChunksInsert(world, world_rect, i) { inserted += 1 } else { rects[i].w = 0; rects[i].h = 0; rects[i].x = -1e9 }       // outside of the loaded chunks: not in the world
    }
    testing.expect(t, inserted > 300)

    out: [512]Item
    for _ in 0 ..< 200 {
        c: Vec2 = {rand.float32(state) * 400 - 150, rand.float32(state) * 400 - 150}
        radius: f32 = rand.float32(state) * 150
        a: Vec2 = {rand.float32(state) * 400 - 150, rand.float32(state) * 400 - 150}
        b: Vec2 = {rand.float32(state) * 400 - 150, rand.float32(state) * 400 - 150}
        circle: int = QuadtreeChunksQueryCircle(world, {BASE + f64(c.x), BASE + f64(c.y)}, f64(radius), out[:])
        segment: int = QuadtreeChunksQuerySegment(world, {BASE + f64(a.x), BASE + f64(a.y)}, {BASE + f64(b.x), BASE + f64(b.y)}, out[256:])
        expected_circle, expected_segment: int
        best: f32 = 2
        for rect in rects {
            if rect.x < -1e8 { continue }
            if bruteCircleRect(c, radius, rect) { expected_circle += 1 }
            at, hit := bruteSegmentRect(a, b, rect)
            if hit {
                expected_segment += 1
                best = min(best, at)
            }
        }
        testing.expect_value(t, circle, expected_circle)
        testing.expect_value(t, segment, expected_segment)
        _, at, hit := QuadtreeChunksSegmentFirst(world, {BASE + f64(a.x), BASE + f64(a.y)}, {BASE + f64(b.x), BASE + f64(b.y)})
        testing.expect_value(t, hit, best <= 1)
        if hit { testing.expect(t, abs(at - best) < 0.001, "the first hit is the nearest along the segment") }
    }
}

// Nearest and k-nearest against a brute force search. The distances are compared (not the items: equal distances may come in either order), each returned item must have the distance it is reported with
@(private = "file")
bruteDistance :: proc(point: Vec2, rect: Rect) -> f32 {
    return math.sqrt(distanceSquaredToBox(point, {rect.x, rect.y}, {rect.x + rect.w, rect.y + rect.h}))
}

@(private = "file")
checkNearest :: proc(t: ^testing.T, rects: []Rect, point: Vec2, k: int, omit: int, max_distance: f32, items: []int, distances: []f32, count: int) {
    expected: [dynamic]f32
    expected.allocator = context.temp_allocator
    for rect, index in rects {
        if rect.x < -1e8 || index == omit { continue }
        distance: f32 = bruteDistance(point, rect)
        if distance <= max_distance { append(&expected, distance) }
    }
    slice.sort(expected[:])
    want: int = min(k, len(expected))
    testing.expect_value(t, count, want)
    for i in 0 ..< min(count, want) {
        testing.expect(t, abs(distances[i] - expected[i]) <= 0.001 * max(1, expected[i]), "the i-th nearest distance")
        testing.expect(t, abs(bruteDistance(point, rects[items[i]]) - distances[i]) <= 0.001 * max(1, distances[i]), "the item has the reported distance")
        testing.expect(t, items[i] != omit, "the omitted item is left out")
        for j in 0 ..< i { testing.expect(t, items[j] != items[i], "no item twice") }
    }
}

@(test)
test_nearest_queries_match_a_brute_force_search :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 4, 6)
    seed: rand.Default_Random_State = rand.create(83)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [300]Rect
    fillTree(tree, rects[:], state, area, 20)
    retained: ^RetainedTestTree = new(RetainedTestTree)
    defer free(retained)
    QuadtreeRetainedInit(retained, area, 4, 6)
    handles: [300]Handle
    for rect, i in rects { handles[i], _ = QuadtreeRetainedAdd(retained, rect) }
    items: [16]Item
    found: [16]Handle
    distances: [16]f32
    mapped: [16]int
    for _ in 0 ..< 300 {
        point: Vec2 = {rand.float32(state) * 1500 - 250, rand.float32(state) * 1000 - 100}
        k: int = 1 + rand.int_max(12, state)
        omit: int = rand.int_max(300, state) if rand.int_max(2, state) == 0 else -1
        max_distance: f32 = max(f32) if rand.int_max(3, state) != 0 else rand.float32(state) * 300
        count: int = QuadtreeNearest(tree, point, items[:k], distances[:], omit, max_distance)
        checkNearest(t, rects[:], point, k, omit, max_distance, items[:], distances[:], count)

        omit_handle: Handle = handles[omit] if omit >= 0 else HandleNone
        retained_distances: [16]f32
        count = QuadtreeRetainedNearest(retained, point, found[:k], retained_distances[:], omit_handle, max_distance)
        for i in 0 ..< count { for handle, index in handles { if handle == found[i] { mapped[i] = index } } }
        checkNearest(t, rects[:], point, k, omit, max_distance, mapped[:], retained_distances[:], count)
    }
    // nothing to find, no room to answer
    QuadtreeClear(tree)
    testing.expect_value(t, QuadtreeNearest(tree, {1, 1}, items[:], distances[:]), 0)
    QuadtreeInsert(tree, {10, 10, 5, 5}, 1)
    testing.expect_value(t, QuadtreeNearest(tree, {1, 1}, items[:0], distances[:]), 0)
    testing.expect_value(t, QuadtreeNearest(tree, {12, 12}, items[:], distances[:]), 1)
    testing.expect_value(t, distances[0], 0)
}

@(test)
test_chunked_nearest_matches_a_brute_force_search_far_from_the_origin :: proc(t: ^testing.T) {
    world: ^ShapeWorld = new(ShapeWorld)
    defer free(world)
    BASE :: 1_000_000.0
    QuadtreeChunksInit(world, 100, 30, 4, 5)
    seed: rand.Default_Random_State = rand.create(84)
    state: rand.Generator = rand.default_random_generator(&seed)
    QuadtreeChunksStream(world, {BASE + 50, BASE + 50}, 2, nil, proc(user: rawptr, cx: int, cy: int) {})
    rects: [300]Rect
    for i in 0 ..< len(rects) {
        rects[i] = {rand.float32(state) * 480 - 190, rand.float32(state) * 480 - 190, 1 + rand.float32(state) * 29, 1 + rand.float32(state) * 29}
        if !QuadtreeChunksInsert(world, {BASE + f64(rects[i].x), BASE + f64(rects[i].y), f64(rects[i].w), f64(rects[i].h)}, i) { rects[i].x = -1e9 }
    }
    items: [16]Item
    distances: [16]f32
    for _ in 0 ..< 200 {
        point: Vec2 = {rand.float32(state) * 600 - 250, rand.float32(state) * 600 - 250}
        k: int = 1 + rand.int_max(10, state)
        max_distance: f32 = max(f32) if rand.int_max(3, state) != 0 else rand.float32(state) * 200
        count: int = QuadtreeChunksNearest(world, {BASE + f64(point.x), BASE + f64(point.y)}, items[:k], distances[:], ITEM_NONE, f64(max_distance))
        checkNearest(t, rects[:], point, k, -1, max_distance, items[:], distances[:], count)
    }
}

// Iterators: the same hits as the slice queries, each once, with early exit and two running at the same time
@(test)
test_iterators_give_the_same_hits_as_the_slice_queries :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 4, 6)
    seed: rand.Default_Random_State = rand.create(85)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [300]Rect
    fillTree(tree, rects[:], state, area, 20)
    retained: ^RetainedTestTree = new(RetainedTestTree)
    defer free(retained)
    QuadtreeRetainedInit(retained, area, 4, 6)
    handles: [300]Handle
    for rect, i in rects { handles[i], _ = QuadtreeRetainedAdd(retained, rect) }
    out: [512]Item
    out_retained: [512]Handle
    for round in 0 ..< 300 {
        rect: Rect = randomShapeRect(state, {-200, -100, 1500, 1000}, 400 if round % 3 != 0 else 40)
        omit: int = rand.int_max(300, state) if round % 2 == 0 else -1
        expected: int = QuadtreeQuery(tree, rect, out[:], omit)
        seen: [300]bool
        count: int
        it: QueryIterator
        QuadtreeQueryBegin(&it, tree, rect, omit)
        for item in QuadtreeQueryNext(tree, &it) {
            testing.expect(t, !seen[item], "an item comes once")
            seen[item] = true
            count += 1
        }
        testing.expect_value(t, count, expected)
        for i in 0 ..< expected { testing.expect(t, seen[out[i]], "the iterator found what the query found") }

        omit_handle: Handle = handles[omit] if omit >= 0 else HandleNone
        expected_retained: int = QuadtreeRetainedQuery(retained, rect, out_retained[:], omit_handle)
        count = 0
        QuadtreeRetainedQueryBegin(&it, retained, rect, omit_handle)
        for _ in QuadtreeRetainedQueryNext(retained, &it) { count += 1 }
        testing.expect_value(t, count, expected_retained)

        point: Vec2 = {rect.x, rect.y}
        expected = QuadtreeQueryPoint(tree, point, out[:])
        count = 0
        QuadtreeQueryPointBegin(&it, tree, point)
        for _ in QuadtreeQueryNext(tree, &it) { count += 1 }
        testing.expect_value(t, count, expected)
        count = 0
        QuadtreeRetainedQueryPointBegin(&it, retained, point)
        for _ in QuadtreeRetainedQueryNext(retained, &it) { count += 1 }
        testing.expect_value(t, count, QuadtreeRetainedQueryPoint(retained, point, out_retained[:]))
    }
    // early exit after the first hit, and two iterators of one tree at the same time
    everything: Rect = {-5000, -5000, 10000, 10000}
    a, b: QueryIterator
    QuadtreeQueryBegin(&a, tree, everything)
    QuadtreeQueryBegin(&b, tree, everything)
    first, _ := QuadtreeQueryNext(tree, &a)
    count_b: int
    for _ in QuadtreeQueryNext(tree, &b) { count_b += 1 }
    count_a: int = 1
    for _ in QuadtreeQueryNext(tree, &a) { count_a += 1 }
    testing.expect(t, first >= 0 && first < 300)
    testing.expect_value(t, count_a, 300)
    testing.expect_value(t, count_b, 300)
    // an empty tree and a miss
    QuadtreeClear(tree)
    QuadtreeQueryBegin(&a, tree, everything)
    _, ok := QuadtreeQueryNext(tree, &a)
    testing.expect(t, !ok)
}

@(test)
test_chunked_iterators_give_the_same_hits_as_the_slice_queries :: proc(t: ^testing.T) {
    world: ^ShapeWorld = new(ShapeWorld)
    defer free(world)
    BASE :: 1_000_000.0
    QuadtreeChunksInit(world, 100, 30, 4, 5)
    seed: rand.Default_Random_State = rand.create(86)
    state: rand.Generator = rand.default_random_generator(&seed)
    QuadtreeChunksStream(world, {BASE + 50, BASE + 50}, 2, nil, proc(user: rawptr, cx: int, cy: int) {})
    for i in 0 ..< 400 {
        QuadtreeChunksInsert(world, {BASE + f64(rand.float32(state) * 480 - 190), BASE + f64(rand.float32(state) * 480 - 190), f64(1 + rand.float32(state) * 29), f64(1 + rand.float32(state) * 29)}, i)
    }
    out: [512]Item
    for round in 0 ..< 200 {
        // the last rounds are rectangles bigger than the window: the iterator walks the slots instead of the coordinates
        size: f64 = f64(rand.float32(state) * 200) if round < 180 else 2000
        rect: WorldRect = {BASE + f64(rand.float32(state) * 500 - 250), BASE + f64(rand.float32(state) * 500 - 250), size, size}
        expected: int = QuadtreeChunksQuery(world, rect, out[:])
        seen: map[Item]bool
        seen.allocator = context.temp_allocator
        it: QuadtreeChunksIterator
        QuadtreeChunksQueryBegin(&it, world, rect)
        for item in QuadtreeChunksQueryNext(world, &it) {
            testing.expect(t, item not_in seen, "an item comes once")
            seen[item] = true
        }
        testing.expect_value(t, len(seen), expected)
        for i in 0 ..< expected { testing.expect(t, out[i] in seen, "the iterator found what the query found") }
        count: int
        point: WorldVec = {rect.x, rect.y}
        QuadtreeChunksQueryPointBegin(&it, world, point)
        for _ in QuadtreeChunksQueryNext(world, &it) { count += 1 }
        testing.expect_value(t, count, QuadtreeChunksQueryPoint(world, point, out[:]))
    }
}

// Small steps take the fast path of Move (same leaves: only the rectangle copies change), bigger ones relink: queries must stay exact through a long walk of both
@(test)
test_retained_moves_by_small_and_big_steps_keep_every_query_exact :: proc(t: ^testing.T) {
    tree: ^RetainedTestTree = new(RetainedTestTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeRetainedInit(tree, area, 4, 6)
    seed: rand.Default_Random_State = rand.create(87)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [300]Rect
    handles: [300]Handle
    for i in 0 ..< len(rects) {
        rects[i] = randomShapeRect(state, area, 60)
        handles[i], _ = QuadtreeRetainedAdd(tree, rects[i])
    }
    links_before: int
    _, links_before = QuadtreeRetainedUsage(tree)
    out: [512]Handle
    for round in 0 ..< 60 {
        step: f32 = 2 if round % 10 != 9 else 120
        for i in 0 ..< len(rects) {
            rects[i].x = clamp(rects[i].x + (rand.float32(state) * 2 - 1) * step, -50, area.w + 20)
            rects[i].y = clamp(rects[i].y + (rand.float32(state) * 2 - 1) * step, -50, area.h + 20)
            testing.expect(t, QuadtreeRetainedMove(tree, handles[i], rects[i]), "the move works")
            element, _ := QuadtreeRetainedGet(tree, handles[i])
            testing.expect(t, element.rect == rects[i], "the element has the new rectangle")
        }
        query: Rect = randomShapeRect(state, area, 300)
        expected: int
        for rect in rects { if RectOverlaps(rect, query) { expected += 1 } }
        testing.expect_value(t, QuadtreeRetainedQuery(tree, query, out[:]), expected)
        center: Vec2 = {query.x, query.y}
        expected = 0
        for rect in rects { if bruteCircleRect(center, 90, rect) { expected += 1 } }
        testing.expect_value(t, QuadtreeRetainedQueryCircle(tree, center, 90, out[:]), expected)
        expected = 0
        for rect in rects { if RectContainsPoint(rect, center) { expected += 1 } }
        testing.expect_value(t, QuadtreeRetainedQueryPoint(tree, center, out[:]), expected)
    }
    // nothing leaked: every element still has links, and the count of links is of the same order as at the start
    _, links_after := QuadtreeRetainedUsage(tree)
    testing.expect(t, links_after > 0 && links_after < links_before * 3, "the links are not leaking")
}

// Compaction moves the links of every leaf next to each other: queries answer the same, and the tree keeps working (inserts, removes, moves, cleanup) afterwards
@(test)
test_compaction_keeps_every_query_and_the_tree_usable :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 4, 6)
    seed: rand.Default_Random_State = rand.create(88)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [400]Rect
    fillTree(tree, rects[:200], state, area, 10)
    scratch: [4096]Link
    _, links_before := QuadtreeUsage(tree)
    out_before, out_after: [512]Item
    queries: [20]Rect
    for &query in queries { query = randomShapeRect(state, {-100, -100, 1300, 1000}, 300) }
    counts: [20]int
    for query, i in queries { counts[i] = QuadtreeQuery(tree, query, out_before[:]) }
    QuadtreeCompact(tree, scratch[:])
    _, links_after := QuadtreeUsage(tree)
    testing.expect_value(t, links_after, links_before)
    for query, i in queries { testing.expect_value(t, QuadtreeQuery(tree, query, out_after[:]), counts[i]) }
    // more elements after the compaction, then everything against a brute force search
    for i in 200 ..< 400 {
        rects[i] = randomShapeRect(state, area, 90)
        testing.expect(t, QuadtreeInsert(tree, rects[i], i))
    }
    for query in queries {
        expected: int
        for rect in rects { if RectOverlaps(rect, query) { expected += 1 } }
        testing.expect_value(t, QuadtreeQuery(tree, query, out_after[:]), expected)
    }
    // a second compaction of a tree that grew since
    QuadtreeCompact(tree, scratch[:])
    for query in queries {
        expected: int
        for rect in rects { if RectOverlaps(rect, query) { expected += 1 } }
        testing.expect_value(t, QuadtreeQuery(tree, query, out_after[:]), expected)
    }
}

@(test)
test_retained_compaction_after_churn_keeps_handles_and_queries :: proc(t: ^testing.T) {
    tree: ^RetainedTestTree = new(RetainedTestTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeRetainedInit(tree, area, 4, 6)
    seed: rand.Default_Random_State = rand.create(89)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [300]Rect
    alive: [300]bool
    handles: [300]Handle
    for i in 0 ..< len(rects) {
        rects[i] = randomShapeRect(state, area, 80)
        handles[i], _ = QuadtreeRetainedAdd(tree, rects[i])
        alive[i] = true
    }
    scratch: [4096]RetainedLink
    out: [512]Handle
    check :: proc(t: ^testing.T, tree: ^RetainedTestTree, rects: []Rect, alive: []bool, state: rand.Generator, out: []Handle) {
        for _ in 0 ..< 20 {
            query: Rect = randomShapeRect(state, {-100, -100, 1300, 1000}, 300)
            expected: int
            for rect, i in rects { if alive[i] && RectOverlaps(rect, query) { expected += 1 } }
            testing.expect_value(t, QuadtreeRetainedQuery(tree, query, out), expected)
        }
    }
    for round in 0 ..< 4 {
        // churn: removes, adds into the freed slots and moves scatter the links, then compact
        for i in 0 ..< len(rects) {
            switch (i + round) % 5 {
            case 0:
                if alive[i] { QuadtreeRetainedRemove(tree, handles[i]); alive[i] = false }
            case 1:
                if !alive[i] {
                    rects[i] = randomShapeRect(state, area, 80)
                    handles[i], _ = QuadtreeRetainedAdd(tree, rects[i])
                    alive[i] = true
                }
            case 2:
                if alive[i] {
                    rects[i] = randomShapeRect(state, area, 80)
                    QuadtreeRetainedMove(tree, handles[i], rects[i])
                }
            }
        }
        check(t, tree, rects[:], alive[:], state, out[:])
        QuadtreeRetainedCompact(tree, scratch[:])
        check(t, tree, rects[:], alive[:], state, out[:])
        QuadtreeRetainedCleanup(tree)
        check(t, tree, rects[:], alive[:], state, out[:])
        for i in 0 ..< len(rects) {
            if !alive[i] { continue }
            element, ok := QuadtreeRetainedGet(tree, handles[i])
            testing.expect(t, ok && element.rect == rects[i], "the handle still names its element")
        }
    }
}

@(test)
test_chunked_compaction_keeps_queries :: proc(t: ^testing.T) {
    world: ^ShapeWorld = new(ShapeWorld)
    defer free(world)
    BASE :: 1_000_000.0
    QuadtreeChunksInit(world, 100, 30, 4, 5)
    seed: rand.Default_Random_State = rand.create(90)
    state: rand.Generator = rand.default_random_generator(&seed)
    QuadtreeChunksStream(world, {BASE + 50, BASE + 50}, 2, nil, proc(user: rawptr, cx: int, cy: int) {})
    for i in 0 ..< 400 {
        QuadtreeChunksInsert(world, {BASE + f64(rand.float32(state) * 480 - 190), BASE + f64(rand.float32(state) * 480 - 190), f64(1 + rand.float32(state) * 29), f64(1 + rand.float32(state) * 29)}, i)
    }
    _, _, _, most_links := QuadtreeChunksUsage(world)
    scratch: []Link = make([]Link, most_links)
    defer delete(scratch)
    out_before, out_after: [512]Item
    for _ in 0 ..< 30 {
        rect: WorldRect = {BASE + f64(rand.float32(state) * 500 - 250), BASE + f64(rand.float32(state) * 500 - 250), f64(rand.float32(state) * 200), f64(rand.float32(state) * 200)}
        before: int = QuadtreeChunksQuery(world, rect, out_before[:])
        QuadtreeChunksCompact(world, scratch)
        testing.expect_value(t, QuadtreeChunksQuery(world, rect, out_after[:]), before)
    }
}

// No query writes into the tree: its bytes stay as they were after rectangle, point, circle and segment queries, so threads may run them side by side
@(test)
test_queries_leave_the_tree_untouched :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 4, 6)
    seed: rand.Default_Random_State = rand.create(91)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [300]Rect
    fillTree(tree, rects[:], state, area, 10)
    before: ^ShapeTree = new(ShapeTree)
    defer free(before)
    before^ = tree^
    out: [512]Item
    for _ in 0 ..< 100 {
        point: Vec2 = {rand.float32(state) * 1000, rand.float32(state) * 800}
        QuadtreeQuery(tree, randomShapeRect(state, area, 200), out[:])
        QuadtreeQueryPoint(tree, point, out[:])
        QuadtreeQueryCircle(tree, point, 60, out[:])
        QuadtreeQuerySegment(tree, point, point + {90, 50}, out[:])
    }
    testing.expect(t, mem.compare_ptrs(tree, before, size_of(ShapeTree)) == 0, "the tree is byte for byte the same")
}

@(test)
test_circle_iterators_give_the_same_hits_as_the_circle_query :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 4, 6)
    seed: rand.Default_Random_State = rand.create(92)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [300]Rect
    fillTree(tree, rects[:], state, area, 15)
    retained: ^RetainedTestTree = new(RetainedTestTree)
    defer free(retained)
    QuadtreeRetainedInit(retained, area, 4, 6)
    for rect in rects { QuadtreeRetainedAdd(retained, rect) }
    out: [512]Item
    out_retained: [512]Handle
    for _ in 0 ..< 200 {
        center: Vec2 = {rand.float32(state) * 1500 - 250, rand.float32(state) * 1000 - 100}
        radius: f32 = rand.float32(state) * 250
        seen: [300]bool
        count: int
        it: QueryIterator
        QuadtreeQueryCircleBegin(&it, tree, center, radius)
        for item in QuadtreeQueryNext(tree, &it) {
            testing.expect(t, !seen[item], "an item comes once")
            seen[item] = true
            count += 1
        }
        testing.expect_value(t, count, QuadtreeQueryCircle(tree, center, radius, out[:]))
        count = 0
        QuadtreeRetainedQueryCircleBegin(&it, retained, center, radius)
        for _ in QuadtreeRetainedQueryNext(retained, &it) { count += 1 }
        testing.expect_value(t, count, QuadtreeRetainedQueryCircle(retained, center, radius, out_retained[:]))
    }
}

// Rounding stress for the owner point of a segment: axis aligned segments, segments through the exact corners of a grid of rectangles and a tree far from the origin, where one unit in the last place is large
@(test)
test_segments_through_corners_and_far_from_the_origin_are_found_exactly_once :: proc(t: ^testing.T) {
    tree: ^ShapeTree = new(ShapeTree)
    defer free(tree)
    bases: []f32 = {0, 4096, 100000, -100000}
    for base in bases {
        QuadtreeClear(tree)
        QuadtreeInit(tree, {base, base, 512, 512}, 4, 6)
        rects: [64]Rect
        for i in 0 ..< 64 { rects[i] = {base + f32(i % 8) * 64, base + f32(i / 8) * 64, 64, 64} }       // edges and corners shared by neighbours
        for rect, i in rects { QuadtreeInsert(tree, rect, i) }
        out: [128]Item
        for step in 0 ..< 600 {
            a: Vec2 = {base + f32(step % 9) * 64, base + f32(step / 9 % 9) * 64}                 // exact corners
            b: Vec2 = {base + f32((step * 7) % 9) * 64, base + f32((step * 5 + 3) % 9) * 64}
            if step % 4 == 1 { b.y = a.y }
            if step % 4 == 2 { b.x = a.x }
            if step % 4 == 3 { a += {0.1, 0.07}; b += {0.13, 0.03} }
            count: int = QuadtreeQuerySegment(tree, a, b, out[:])
            expected: int
            probe: Probe = probeSegment(a, b)
            for rect in rects {
                if probeHitsRect(&probe, rect) { expected += 1 }       // the contract: the same test as the element test, so a hit on a corner or an edge is judged like the query does
            }
            testing.expect_value(t, count, expected)
            seen: [64]bool
            for i in 0 ..< count {
                testing.expect(t, !seen[out[i]], "each item once")
                seen[out[i]] = true
            }
        }
    }
}
