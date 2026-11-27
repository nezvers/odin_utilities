#+build !js
package quadtree

import "core:math/rand"
import "core:testing"

RetainedTestTree :: QuadtreeRetained(512, 400, 4096)

@(private = "file")
randomRect :: proc(state: rand.Generator, area: Rect, biggest: f32) -> Rect {
    width: f32 = 1 + rand.float32(state) * biggest
    height: f32 = 1 + rand.float32(state) * biggest
    return {area.x + rand.float32(state) * (area.w - width), area.y + rand.float32(state) * (area.h - height), width, height}
}

// What a brute force search finds: the tree must report exactly these
@(private = "file")
matches :: proc(t: ^testing.T, tree: ^RetainedTestTree, handles: []Handle, rect: Rect) {
    out: [512]Handle
    count: int = QuadtreeRetainedQuery(tree, rect, out[:])
    expected: int
    for handle in handles {
        element, ok := QuadtreeRetainedGet(tree, handle)
        if !ok || !RectOverlaps(element.rect, rect) { continue }
        expected += 1
        found: bool
        for i in 0 ..< count { if out[i] == handle { found = true } }
        testing.expect(t, found, "an overlapping element is reported")
    }
    testing.expect_value(t, count, expected)
}

@(test)
test_retained_queries_match_a_brute_force_search_after_adds_moves_and_removals :: proc(t: ^testing.T) {
    tree: ^RetainedTestTree = new(RetainedTestTree)
    defer free(tree)
    area: Rect = {0, 0, 1000, 800}
    QuadtreeRetainedInit(tree, area, 6, 6)
    seed: rand.Default_Random_State = rand.create(1234)
    state: rand.Generator = rand.default_random_generator(&seed)
    handles: [dynamic]Handle
    defer delete(handles)
    for _ in 0 ..< 300 {
        handle, ok := QuadtreeRetainedAdd(tree, randomRect(state, area, 120))
        testing.expect(t, ok)
        append(&handles, handle)
    }
    for _ in 0 ..< 20 { matches(t, tree, handles[:], randomRect(state, area, 300)) }
    // move a third, remove a third
    for handle, i in handles {
        if i % 3 == 0 { testing.expect(t, QuadtreeRetainedMove(tree, handle, randomRect(state, area, 120))) }
        if i % 3 == 1 { testing.expect(t, QuadtreeRetainedRemove(tree, handle)) }
    }
    QuadtreeRetainedCleanup(tree)
    for _ in 0 ..< 20 { matches(t, tree, handles[:], randomRect(state, area, 300)) }
    testing.expect_value(t, QuadtreeRetainedLen(tree), uint(200))
    // a removed handle is stale
    testing.expect(t, !QuadtreeRetainedRemove(tree, handles[1]))
    _, got := QuadtreeRetainedGet(tree, handles[1])
    testing.expect(t, !got)
}

@(test)
test_retained_a_big_rectangle_is_reported_once_and_the_omitted_one_is_left_out :: proc(t: ^testing.T) {
    tree: ^RetainedTestTree = new(RetainedTestTree)
    defer free(tree)
    QuadtreeRetainedInit(tree, {0, 0, 100, 100}, 1, 5)
    big, _ := QuadtreeRetainedAdd(tree, {1, 1, 98, 98})
    for i in 0 ..< 20 { QuadtreeRetainedAdd(tree, {f32(i) * 4, f32(i) * 4, 2, 2}) }
    out: [64]Handle
    count: int = QuadtreeRetainedQuery(tree, {0, 0, 100, 100}, out[:])
    testing.expect_value(t, count, 21)
    hits: int
    for i in 0 ..< count { if out[i] == big { hits += 1 } }
    testing.expect_value(t, hits, 1)
    testing.expect_value(t, QuadtreeRetainedQuery(tree, {0, 0, 100, 100}, out[:], big), 20)
    // the buffer limits the result
    testing.expect_value(t, QuadtreeRetainedQuery(tree, {0, 0, 100, 100}, out[:5]), 5)
}

@(test)
test_retained_points_and_rectangles_outside_of_the_tree :: proc(t: ^testing.T) {
    tree: ^RetainedTestTree = new(RetainedTestTree)
    defer free(tree)
    QuadtreeRetainedInit(tree, {0, 0, 100, 100}, 2, 4)
    inside, _ := QuadtreeRetainedAdd(tree, {10, 10, 20, 20})
    far, _ := QuadtreeRetainedAdd(tree, {500, -300, 10, 10})
    out: [8]Handle
    testing.expect_value(t, QuadtreeRetainedQueryPoint(tree, {15, 15}, out[:]), 1)
    testing.expect(t, out[0] == inside)
    testing.expect_value(t, QuadtreeRetainedQueryPoint(tree, {30, 15}, out[:]), 0)    // the right edge is outside
    testing.expect_value(t, QuadtreeRetainedQueryPoint(tree, {505, -295}, out[:]), 1)
    testing.expect(t, out[0] == far)
    testing.expect(t, QuadtreeRetainedMove(tree, far, {-80, 90, 5, 5}))
    testing.expect_value(t, QuadtreeRetainedQueryPoint(tree, {-78, 92}, out[:]), 1)
}

@(test)
test_retained_full_storage_fails_and_changes_nothing :: proc(t: ^testing.T) {
    // few links: a big element needs one in every leaf it overlaps
    Small :: QuadtreeRetained(16, 9, 12)
    tree: ^Small = new(Small)
    defer free(tree)
    QuadtreeRetainedInit(tree, {0, 0, 100, 100}, 1, 4)
    added: [dynamic]Handle
    defer delete(added)
    failed: bool
    for i in 0 ..< 40 {
        handle, ok := QuadtreeRetainedAdd(tree, {f32(i % 10) * 9, f32(i / 10) * 20, 30, 30})
        if ok { append(&added, handle) } else { failed = true }
    }
    testing.expect(t, failed, "storage ran out")
    testing.expect_value(t, QuadtreeRetainedLen(tree), uint(len(added)))
    nodes, links := QuadtreeRetainedUsage(tree)
    testing.expect(t, nodes <= 9 && links <= 12)
    // everything that was accepted can be found and removed again, and then nothing is left in use
    out: [32]Handle
    testing.expect_value(t, QuadtreeRetainedQuery(tree, {-10, -10, 200, 200}, out[:]), len(added))
    for handle in added { testing.expect(t, QuadtreeRetainedRemove(tree, handle)) }
    QuadtreeRetainedCleanup(tree)
    nodes, links = QuadtreeRetainedUsage(tree)
    testing.expect_value(t, nodes, 1)
    testing.expect_value(t, links, 0)
}

@(test)
test_retained_cleanup_gives_the_nodes_back :: proc(t: ^testing.T) {
    tree: ^RetainedTestTree = new(RetainedTestTree)
    defer free(tree)
    QuadtreeRetainedInit(tree, {0, 0, 100, 100}, 2, 6)
    handles: [dynamic]Handle
    defer delete(handles)
    for i in 0 ..< 40 {
        handle, _ := QuadtreeRetainedAdd(tree, {f32(i) * 2.4, f32(i) * 2.4, 2, 2})
        append(&handles, handle)
    }
    grown, _ := QuadtreeRetainedUsage(tree)
    testing.expect(t, grown > 1, "the tree divided")
    for handle in handles { QuadtreeRetainedRemove(tree, handle) }
    QuadtreeRetainedCleanup(tree)
    nodes, links := QuadtreeRetainedUsage(tree)
    testing.expect_value(t, nodes, 1)
    testing.expect_value(t, links, 0)
    // the freed groups are used again, not new ones
    for i in 0 ..< 40 { QuadtreeRetainedAdd(tree, {f32(i) * 2.4, f32(i) * 2.4, 2, 2}) }
    again, _ := QuadtreeRetainedUsage(tree)
    testing.expect_value(t, again, grown)
}
