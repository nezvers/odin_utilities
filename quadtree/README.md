# Quadtree
Broad phase for 2D rectangles in a quadtree, without allocations. The size of the tree is given by compile time parameters, all memory is inside of the `Quadtree` value (put it in a global or in your own struct). Functions fail (return false) instead of growing.

`odin run demo_raylib` / `odin run demo_karl2d` / `odin test .`
Demos (the menu of the demo kit switches between them): `collision` (the demo of grid_collision_map on a quadtree: paint walls, a box slides along them), `hover circles` (random circles, the mouse asks the tree which one it is over), `bouncing balls` (balls bounce off the window and each other, hold the left button to spawn more at the mouse). `G` shows the tree.

```odin
import qt "quadtree"

// 1023 elements (the map keeps one slot as the "no handle"), 1400 nodes (the root and groups of four), 8192 links (one per element and leaf it overlaps)
tree: qt.Quadtree(1024, 1400, 8192)
buffer: [64]qt.Handle   // query results

qt.QuadtreeInit(&tree, {0, 0, 1280, 720}, max_elements = 8, max_depth = 5)
handle, ok := qt.QuadtreeAdd(&tree, {100, 100, 20, 20}, ptr = &my_thing)

// every frame, for what moved
qt.QuadtreeMove(&tree, handle, new_rect)
qt.QuadtreeCleanup(&tree)                       // merge empty leaves, the nodes can be used again

count := qt.QuadtreeQuery(&tree, rect, buffer[:], omit = handle)    // overlapping elements, each once
count  = qt.QuadtreeQueryPoint(&tree, mouse, buffer[:])             // elements whose rectangle holds the point
```

## Parts
- `Element` - rectangle + `ptr` for your data, stored in `core:container/handle_map` (a `Handle` stays safe after removal).
- Tree - an element is stored in every leaf it overlaps (one link each); a leaf with more than `max_elements` splits unless it is at `max_depth`. The nodes come four at a time.
- `QuadtreeAdd` / `Remove` / `Get` / `Move` - `Add` fails when the map, the nodes or the links are full, and changes nothing. A leaf that cannot split (no nodes or links left) just holds more.
- `QuadtreeQuery` - elements whose rectangle overlaps a rectangle, `QuadtreeQueryPoint` - that hold a point. Results are limited by the size of the buffer you pass.
- `QuadtreeCleanup`, `QuadtreeVisit` (draw or count the nodes), `QuadtreeUsage` (nodes and links in use, to size `N` and `L`).
- `RectOverlaps`, `RectContainsPoint` - narrow phase helpers. Touching edges are not overlapping.

## Notes
- Elements outside of `bounds` work: they sit in the border leaves.
- This is a broad phase: the rectangle is what the tree knows, a circle or a polygon is tested by you on the results (see `hover circles`).
- `QuadtreeMove` that fails because the links ran out removes the element (the old handle is then stale).
- Sizing: a leaf at `max_depth` is `bounds / 2^max_depth` wide; `QuadtreeUsage` tells how much of `N` and `L` a scene needs.

## Credit
The structure and the leaf/link bookkeeping follow the quadtree of "dragon-energy" from the Stack Overflow answer
[Efficient (and well explained) implementation of a quadtree for 2D collision detection](https://stackoverflow.com/questions/41946007/efficient-and-well-explained-implementation-of-a-quadtree-for-2d-collision-det)
(C, via [nezvers/quadtree](https://github.com/nezvers/quadtree); the author allows any use, Stack Overflow code is CC BY-SA 4.0). This is a rewrite in Odin: fixed storage, handle map, float rectangles, recursion instead of lists of leaves.
