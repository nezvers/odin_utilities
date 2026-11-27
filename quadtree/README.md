# Quadtree
Immediate mode broad phase for 2D rectangles, without allocations: the tree is rebuilt every frame (clear, insert everything, query). Nothing is kept between frames, so there is no remove, no move and no handle to keep valid, and your own arrays stay the owner of the objects.
The size of the tree is given by compile time parameters, all memory is inside of the `Quadtree` value (put it in a global or in your own struct). Functions fail (return false) instead of growing.

`odin run demo_raylib` / `odin run demo_karl2d` / `odin test .`
Demos (the menu of the demo kit switches between them): `chunked world` (an endless world streamed in chunks, see below), `retained crates` (the retained tree, see below), `collision` (the demo of grid_collision_map on a quadtree: paint walls, a box slides along them), `hover circles` (random circles, the mouse asks the tree which one it is over), `ray cast and nearest` (the mouse ends a ray from a point set with the left button: the first hit is red, the crossed boxes orange, a radius around the mouse blue, the three nearest green), `bouncing balls` (balls bounce off the window and each other, hold the left button to spawn more at the mouse). `G` shows the tree.

```odin
import qt "quadtree"

// 1024 elements, 1400 nodes (the root and groups of four), 8192 links (one per element and leaf it overlaps)
tree: qt.Quadtree(1024, 1400, 8192)
buffer: [64]qt.Item   // query results

qt.QuadtreeInit(&tree, {0, 0, 1280, 720}, max_elements = 8, max_depth = 5)

// every frame: throw the old tree away, insert what exists now (the item is yours: here the index in my array)
qt.QuadtreeClear(&tree)
for thing, index in things { qt.QuadtreeInsert(&tree, thing.rect, index) }

count := qt.QuadtreeQuery(&tree, rect, buffer[:], omit = index)   // overlapping elements, each once
count  = qt.QuadtreeQueryPoint(&tree, mouse, buffer[:])           // elements whose rectangle holds the point
count  = qt.QuadtreeQueryCircle(&tree, center, radius, buffer[:]) // elements whose rectangle the circle overlaps
count  = qt.QuadtreeQuerySegment(&tree, a, b, buffer[:])          // elements whose rectangle the segment crosses
item, t, hit := qt.QuadtreeSegmentFirst(&tree, a, b)              // the nearest along the segment (a ray cast): the hit is at a + t * (b - a)
count  = qt.QuadtreeNearest(&tree, point, items[:], distances[:])  // the k nearest (k = the shorter slice), nearest first, with their distances
for i in 0 ..< count { other := &things[buffer[i]] }
```

## Circles, segments and threads (`quadtree_shape.odin`)
Circle and segment queries exist in all three trees (`QuadtreeQueryCircle`, `QuadtreeRetainedQuerySegment`, `QuadtreeChunksSegmentFirst` ...): nodes the shape cannot reach are skipped, so a long diagonal ray visits only the leaves it crosses. The rectangle of an element is what is tested (a circle that only touches an edge does not hit; a segment that touches or runs along an edge does, and one inside a rectangle does). Results come in no order; `SegmentFirst` finds the nearest one without sorting.

Rectangle and point queries of the immediate tree write nothing into the tree (an element is reported by the one leaf that holds the corner of its overlap with the query), so any number of threads may run them at once while nobody changes the tree. Circle and segment queries mark the elements they report (an element sits in several leaves), so two threads must not run them on one tree. Give each thread a `QuerySession` (its own `[]u32` with one entry per element: `E`, or the handle slots of a retained tree) and pass it as `session = &session`: the tree is then only read, any number of threads may query it while nobody changes it. `SegmentFirst` needs no session (a minimum does not need marks).
```odin
stamps: [CAPACITY]u32                       // per thread
session: qt.QuerySession
qt.QuerySessionInit(&session, stamps[:])
count := qt.QuadtreeQueryCircle(&tree, center, 5, buffer[:], session = &session)
```

## Chunked world (`quadtree_chunks.odin`)
For a big or endless world: `QuadtreeChunks(W, H, E, N, L)` is a W x H ring of chunks, every chunk has its own immediate tree in local coordinates, positions are `f64` (`WorldRect`, `WorldVec`). Memory follows the loaded window, and a world millions of units from the origin keeps the same precision, because a tree only sees small offsets.
```odin
world: qt.QuadtreeChunks(9, 9, 128, 500, 3000)    // 9 x 9 chunks, each tree: 128 items, 500 nodes, 3000 links
qt.QuadtreeChunksInit(&world, chunk_size = 256, max_item_size = 40)

// every frame: keep the square of 4 chunks around the player loaded, `fill` inserts the items of a new chunk
qt.QuadtreeChunksStream(&world, player_center, 4, user, fill)                // fill :: proc(user: rawptr, cx, cy: int) { ... qt.QuadtreeChunksInsert(&world, rect, item) }
count := qt.QuadtreeChunksQuery(&world, view_rect, buffer[:])                // items from all loaded chunks, each once
```
- An item lives in ONE chunk, the one with its top left corner, and may stick out of it by up to `max_item_size` (a loose grid): no copies per chunk, no duplicates in results. A query looks at the chunks that can reach into it. A bigger item is refused: keep terrain and huge triggers in a separate list.
- `Load` / `Unload` / `IsLoaded` / `Stream` (loads and unloads around a center, `fill` / `drop` callbacks), `Clear` (empties every loaded chunk but keeps it loaded: a second world of moving things, refilled each frame), `Query` / `QueryPoint` / `QueryCircle` / `QuerySegment` / `SegmentFirst`, `Visit` (nodes in world coordinates), `Usage` (also the largest chunk, to size E, N, L), `Coord`, `Bounds`.
- The ring needs 2 * radius + 1 <= W and <= H; two loaded chunks may not share a slot (`Load` says no, `Stream` unloads first).

## Retained mode (`quadtree_retained.odin`)
The same tree that lives between frames: `QuadtreeRetained(E, N, L)` with `QuadtreeRetainedInit / Add / Remove / Get / Move / Query / QueryPoint / QueryCircle / QuerySegment / SegmentFirst / Cleanup / Visit / Usage / Len / Clear`. `Add` gives a stable `Handle` (`core:container/handle_map`, generation checked: a removed handle is stale), `ptr` carries your data, `Move` and `Remove` change one element without a rebuild. Use it when most of the scene stays put and few things move (the `retained crates` demo moves 10 wanderers among 300 crates); when most things move every frame, the immediate tree above is simpler.
`QuadtreeRetainedMove` that runs out of links does not move and keeps the element where it was; only when it cannot even be put back it is removed (the handle is then stale). Both trees share `Rect`, `Vec2`, `RectOverlaps`, `RectContainsPoint` and `QuadtreeNodeProc`.

## Iterators (`quadtree_iterator.odin`)
A rectangle or point query without a result slice, for early exit: `QuadtreeQueryBegin(&it, &tree, rect, omit = me)` and then `for item in QuadtreeQueryNext(&tree, &it) { if wanted(item) { break } }` (`QuadtreeQueryPointBegin`, the `QuadtreeRetained...` pair with handles, `QuadtreeChunksQueryBegin` / `QuadtreeChunksQueryNext` with `QuadtreeChunksIterator`). The iterator is a plain value with a small fixed stack: nothing to free, drop it any time, any number may run at once (one per thread). The tree must not change while one is active. Circle and segment queries have no iterator (they mark elements, which an abandoned iterator could not clean up).

## Nearest and k-nearest
`QuadtreeNearest(&tree, point, items[:], distances[:], omit = me, max_distance = 200)` (also `QuadtreeRetainedNearest` with handles and `QuadtreeChunksNearest` with world `f64` positions) gives the `k` closest elements, `k` being the length of the shorter slice (one element each for the closest one), nearest first, with the distance to their rectangle (0 when the point is inside). The walk visits the nearest child first and skips nodes that cannot beat the k-th best: no heap, no allocation, no marks, so it only reads the tree and is thread safe. A `max_distance` makes it cheaper when nothing far away matters (the chunked world then skips whole chunks). Ties: of equal distances either one may come.

## Benchmark (`tool/bench`)
`odin run tool/bench -o:speed` (add `-- --quick` for the small scenes) compares the trees with a uniform grid, `grid_collision_map` and brute force on uniform and clustered scenes of 1k, 10k and 50k rectangles (4 to 16 units in a 4096 world), checks that every structure reports the same neighbours, and measures sessions with threads and moving elements. Findings on the development PC (ms per frame, one neighbour query per element):
- For many small, similar sized rectangles a plain uniform grid is still a little faster: 50k uniform: grid build 1.1 and rectangle pass 10.5, quadtree build 2.1 and pass 13.3. Clustered 50k: grid (cells of 32) 40 and (cells of 16) 34, quadtree 44 (build 2.4); `grid_collision_map` falls to 107 there (its cells fill up and 189 items did not fit) and a bad cell size costs a grid 2x. The quadtree needs no cell size and never loses elements, a grid needs a size that fits the scene.
- Use the quadtree for scenes with very different sizes, huge empty areas or clusters, where one cell size cannot fit (and for the circle, segment, ray and nearest queries, which a grid does not have); use a grid when the sizes are alike and dense and only rectangles are asked.
- Leaf capacity 8 and depth 8 is a good default: 4 builds and queries slower, 16 and 32 build faster (1.8 and 1.4 ms) but query slower (16 to 20% for 32), depth 6 collapses on clustered data (2x slower queries), depth 10 changes nothing on uniform data and builds slower on clustered.
- What made the tree fast (build 5.9 to 2.1 ms, rectangle pass 17.9 to 13.3, retained tree 5.8 to 2.1 and 19 to 13): the descent follows a rectangle that fits one quadrant in a loop (no recursion, no four way test), rectangle and point queries write no marks (the leaf that holds the corner of the overlap reports the element, so no session is needed and any number of threads may query), and every link keeps a copy of the rectangle (24 bytes per link: size `L` with `QuadtreeUsage`), so a leaf is tested without touching the scattered elements. Circle and segment queries still use marks.
- Threads: the rectangle pass of 50k uniform rectangles takes 13.4 ms on one thread, 7.2 on 2, 3.7 on 4 and 2.1 on 8 (6.3x); small scenes (1000) are too short to gain from threads. A session for circle and segment queries costs nothing measurable (34.1 ms marked and with a session).
- Moving (update + the rectangle pass, 50k uniform): rebuilding the immediate tree costs the same at any percentage (15.6 ms); the retained tree is a little faster while few move (13.5 at 1%) and slower when all move (25.2), grid_collision_map moves in 12 to 13.5: the retained tree is worth it only when most things stay put.
- The retained tree queries as fast as the immediate one.

## Parts
- `Item` - an `int` you choose, usually the index in your array. It is what a query gives back, so no lookup is needed.
- Tree - an element is stored in every leaf it overlaps (one link each); a leaf with more than `max_elements` splits unless it is at `max_depth`. The nodes come four at a time.
- `QuadtreeClear` - first call of every frame, only resets counters. `QuadtreeInsert` fails when the elements, the nodes or the links are full, and changes nothing. A leaf that cannot split (no nodes or links left) just holds more.
- `QuadtreeQuery` - elements whose rectangle overlaps a rectangle, `QuadtreeQueryPoint` - that hold a point. Results are limited by the size of the buffer you pass.
- `QuadtreeVisit` (draw or count the nodes), `QuadtreeUsage` (nodes and links in use, to size `N` and `L`), `QuadtreeLen`.
- `RectOverlaps`, `RectContainsPoint` - narrow phase helpers. Touching edges are not overlapping.

## Notes
- Elements outside of `bounds` work: they sit in the border leaves.
- This is a broad phase: the rectangle is what the tree knows. A circle or segment query tests the rectangles of the elements; if your objects are circles or polygons, test them yourself on the results (see `hover circles`).
- The tree answers for the rectangles of the moment it was built. Insert again after things moved if a later query must see the new places (the demos build once per frame, between moving and colliding).
- Sizing: a leaf at `max_depth` is `bounds / 2^max_depth` wide; `QuadtreeUsage` tells how much of `N` and `L` a scene needs.

## Credit
The structure and the leaf/link bookkeeping follow the quadtree of "dragon-energy" from the Stack Overflow answer
[Efficient (and well explained) implementation of a quadtree for 2D collision detection](https://stackoverflow.com/questions/41946007/efficient-and-well-explained-implementation-of-a-quadtree-for-2d-collision-det)
(C, via [nezvers/quadtree](https://github.com/nezvers/quadtree); the author allows any use, Stack Overflow code is CC BY-SA 4.0). This is a rewrite in Odin: fixed storage, immediate mode, float rectangles, recursion instead of lists of leaves.
