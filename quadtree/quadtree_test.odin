#+build !js
package quadtree

import "core:math/rand"
import "core:testing"

TestTree :: Quadtree(512, 400, 4096)

@(private = "file")
randomRect :: proc(state: rand.Generator, area: Rect, biggest: f32) -> Rect {
    width: f32 = 1 + rand.float32(state) * biggest
    height: f32 = 1 + rand.float32(state) * biggest
    return {area.x + rand.float32(state) * (area.w - width), area.y + rand.float32(state) * (area.h - height), width, height}
}

// What a brute force search finds: the tree must report exactly these (the item of a rectangle is its index)
@(private = "file")
matches :: proc(t: ^testing.T, tree: ^TestTree, rects: []Rect, rect: Rect) {
    out: [512]Item
    count: int = QuadtreeQuery(tree, rect, out[:])
    expected: int
    for other, index in rects {
        if !RectOverlaps(other, rect) { continue }
        expected += 1
        found: bool
        for i in 0 ..< count { if out[i] == index { found = true } }
        testing.expect(t, found, "an overlapping element is reported")
    }
    testing.expect_value(t, count, expected)
}

@(test)
test_queries_match_a_brute_force_search_over_several_rebuilt_frames :: proc(t: ^testing.T) {
    tree: ^TestTree = new(TestTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeInit(tree, area, 6, 6)
    seed: rand.Default_Random_State = rand.create(1234)
    state: rand.Generator = rand.default_random_generator(&seed)
    rects: [300]Rect
    // every frame has other rectangles and a different count: nothing of the last frame may stay
    for frame in 0 ..< 5 {
        count: int = 300 - frame * 60
        QuadtreeClear(tree)
        for i in 0 ..< count {
            rects[i] = randomRect(state, area, 120)
            testing.expect(t, QuadtreeInsert(tree, rects[i], i))
        }
        testing.expect_value(t, QuadtreeLen(tree), count)
        for _ in 0 ..< 20 { matches(t, tree, rects[:count], randomRect(state, area, 300)) }
    }
}

@(test)
test_a_big_rectangle_is_reported_once_and_the_omitted_one_is_left_out :: proc(t: ^testing.T) {
    tree: ^TestTree = new(TestTree)
    defer free(tree)
    QuadtreeInit(tree, {0, 0, 100, 100}, 1, 5)
    QuadtreeInsert(tree, {1, 1, 98, 98}, 100)
    for i in 0 ..< 20 { QuadtreeInsert(tree, {f32(i) * 4, f32(i) * 4, 2, 2}, i) }
    out: [64]Item
    count: int = QuadtreeQuery(tree, {0, 0, 100, 100}, out[:])
    testing.expect_value(t, count, 21)
    hits: int
    for i in 0 ..< count { if out[i] == 100 { hits += 1 } }
    testing.expect_value(t, hits, 1)
    testing.expect_value(t, QuadtreeQuery(tree, {0, 0, 100, 100}, out[:], 100), 20)
    // the buffer limits the result
    testing.expect_value(t, QuadtreeQuery(tree, {0, 0, 100, 100}, out[:5]), 5)
}

@(test)
test_points_and_rectangles_outside_of_the_tree :: proc(t: ^testing.T) {
    tree: ^TestTree = new(TestTree)
    defer free(tree)
    QuadtreeInit(tree, {0, 0, 100, 100}, 2, 4)
    QuadtreeInsert(tree, {10, 10, 20, 20}, 1)
    QuadtreeInsert(tree, {500, -300, 10, 10}, 2)
    out: [8]Item
    testing.expect_value(t, QuadtreeQueryPoint(tree, {15, 15}, out[:]), 1)
    testing.expect_value(t, out[0], 1)
    testing.expect_value(t, QuadtreeQueryPoint(tree, {30, 15}, out[:]), 0)    // the right edge is outside
    testing.expect_value(t, QuadtreeQueryPoint(tree, {505, -295}, out[:]), 1)
    testing.expect_value(t, out[0], 2)
}

@(test)
test_full_storage_fails_and_changes_nothing :: proc(t: ^testing.T) {
    // few links: a big element needs one in every leaf it overlaps
    Small :: Quadtree(16, 9, 12)
    tree: ^Small = new(Small)
    defer free(tree)
    QuadtreeInit(tree, {0, 0, 100, 100}, 1, 4)
    accepted: [40]bool
    failed: bool
    for i in 0 ..< 40 {
        accepted[i] = QuadtreeInsert(tree, {f32(i % 10) * 9, f32(i / 10) * 20, 30, 30}, i)
        if !accepted[i] { failed = true }
    }
    testing.expect(t, failed, "storage ran out")
    added: int
    for ok in accepted { if ok { added += 1 } }
    testing.expect_value(t, QuadtreeLen(tree), added)
    nodes, links := QuadtreeUsage(tree)
    testing.expect(t, nodes <= 9 && links <= 12)
    // everything that was accepted is found, nothing that failed
    out: [32]Item
    count: int = QuadtreeQuery(tree, {-10, -10, 200, 200}, out[:])
    testing.expect_value(t, count, added)
    for i in 0 ..< count { testing.expect(t, accepted[out[i]]) }
    // a clear gives everything back
    QuadtreeClear(tree)
    nodes, links = QuadtreeUsage(tree)
    testing.expect_value(t, nodes, 1)
    testing.expect_value(t, links, 0)
    testing.expect(t, QuadtreeInsert(tree, {1, 1, 5, 5}, 0))
}
