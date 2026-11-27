# Quadtree
Immediate mode broad phase for 2D rectangles, without allocations: the tree is rebuilt every frame (clear, insert everything, query). Nothing is kept between frames, so there is no remove, no move and no handle to keep valid, and your own arrays stay the owner of the objects.
The size of the tree is given by compile time parameters, all memory is inside of the `Quadtree` value (put it in a global or in your own struct). Functions fail (return false) instead of growing.

`odin run demo_raylib` / `odin run demo_karl2d` / `odin test .`
Demos (the menu of the demo kit switches between them): `chunked world` (an endless world streamed in chunks, see below), `retained crates` (the retained tree, see below), `collision` (the demo of grid_collision_map on a quadtree: paint walls, a box slides along them), `hover circles` (random circles, the mouse asks the tree which one it is over), `bouncing balls` (balls bounce off the window and each other, hold the left button to spawn more at the mouse). `G` shows the tree.

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

## Benchmark (`tool/bench`)
`odin run tool/bench -o:speed` (add `-- --quick` for the small scenes) compares the trees with a uniform grid, `grid_collision_map` and brute force on uniform and clustered scenes of 1k, 10k and 50k rectangles (4 to 16 units in a 4096 world), checks that every structure reports the same neighbours, and measures sessions with threads and moving elements. Findings on the development PC (ms per frame, one neighbour query per element):
- For many small, similar sized rectangles a plain uniform grid wins: 50k uniform: grid build 1.1 and queries 10.6, quadtree build 5.5 and queries 17.9. Clustered 50k: grid (cells of 16) 34 against quadtree 54, but `grid_collision_map` falls to 108 (its cells fill up and 189 items did not fit) and a bad cell size costs a grid 2x. The quadtree needs no cell size and never loses elements, a grid needs a size that fits the scene.
- Use the quadtree for scenes with very different sizes, huge empty areas or clusters, where one cell size cannot fit (and for the circle, segment and ray queries, which a grid does not have); use a grid when the sizes are alike and dense.
- Leaf capacity 8 and depth 8 is a good default: 4 builds and queries slower, 16 and 32 build faster but query slower (32 is 20 to 25% slower on queries), depth 6 collapses on clustered data (2x slower queries), depth 10 changes nothing on uniform data and builds slower on clustered.
- Rectangle queries need no marks and no session. Each link keeps a copy of the rectangle (24 bytes per link, size `L` with `QuadtreeUsage`): a leaf is tested without touching the scattered elements (queries 5 to 10% faster, a rectangle pass of 50k uniform rectangles 15.9 ms against the grid's 10.5). Circle and segment queries still use marks.
- Sessions (circle and segment queries) cost 5 to 10% on one thread (19.1 against 17.9 at 50k) and scale with threads: 2 threads 9.8, 4 threads 5.0, 8 threads 2.9 ms for the 50k uniform pass (6x). Small scenes (1000) are too short to gain from threads.
- Moving: rebuilding the immediate tree costs the same at any percentage; the retained tree is faster only while few move (19.6 against 23.8 at 1%) and slower when all move (32.6): it is not worth it unless most things stay put.
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
