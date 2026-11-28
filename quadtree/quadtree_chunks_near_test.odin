#+build !js
package quadtree

import "core:math/rand"
import "core:testing"

NearTestWorld :: QuadtreeChunks(7, 7, 256, 600, 4096)

@(test)
test_a_limited_query_returns_the_chunks_around_the_center_first :: proc(t: ^testing.T) {
    world: ^NearTestWorld = new(NearTestWorld)
    defer free(world)
    QuadtreeChunksInit(world, 100, 30, 4, 5)
    base: f64 = 1_000_000
    QuadtreeChunksStream(world, {base + 50, base + 50}, 3, nil, proc(user: rawptr, cx: int, cy: int) {})
    state: rand.Default_Random_State = rand.create(5)
    generator: rand.Generator = rand.default_random_generator(&state)
    rects: [800]WorldRect
    in_center: int
    center_chunk_x: int = QuadtreeChunksCoord(world, base + 50)
    center_chunk_y: int = QuadtreeChunksCoord(world, base + 50)
    for &rect, i in rects {
        rect = {base - 250 + f64(rand.float32(generator)) * 600, base - 250 + f64(rand.float32(generator)) * 600, 1 + f64(rand.float32(generator)) * 20, 1 + f64(rand.float32(generator)) * 20}
        testing.expect(t, QuadtreeChunksInsert(world, rect, i))
        if QuadtreeChunksCoord(world, rect.x) == center_chunk_x && QuadtreeChunksCoord(world, rect.y) == center_chunk_y { in_center += 1 }
    }
    testing.expect(t, in_center > 5, "the scene has items in the chunk of the center")
    // the query covers everything; the center is inside of its chunk, 20 and more away from the grown boxes of the others
    query: WorldRect = {base - 250, base - 250, 600, 600}
    full: [1024]Item
    total: int = QuadtreeChunksQuery(world, query, full[:])
    testing.expect_value(t, total, len(rects))
    limited: [1024]Item
    count: int = QuadtreeChunksQueryNear(world, query, limited[:in_center])
    testing.expect_value(t, count, in_center)
    // the center of that rectangle is (base + 50, base + 50): every result must be an item of the chunk that holds it
    for i in 0 ..< count {
        rect: WorldRect = rects[limited[i]]
        testing.expect(t, QuadtreeChunksCoord(world, rect.x) == center_chunk_x && QuadtreeChunksCoord(world, rect.y) == center_chunk_y, "the nearest chunk first")
    }
    // the plain query with the same limit does not promise that
    plain: int = QuadtreeChunksQuery(world, query, limited[:in_center])
    testing.expect_value(t, plain, in_center)
    // without a limit both give the same set
    count = QuadtreeChunksQueryNear(world, query, limited[:])
    testing.expect_value(t, count, total)
    // a circle
    count = QuadtreeChunksQueryCircleNear(world, {base + 50, base + 50}, 400, limited[:in_center])
    testing.expect_value(t, count, in_center)
    for i in 0 ..< count {
        rect: WorldRect = rects[limited[i]]
        testing.expect(t, QuadtreeChunksCoord(world, rect.x) == center_chunk_x && QuadtreeChunksCoord(world, rect.y) == center_chunk_y, "the nearest chunk first, circle")
    }
}
