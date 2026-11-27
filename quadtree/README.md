# Quadtree
Immediate mode broad phase for 2D rectangles, without allocations: the tree is rebuilt every frame (clear, insert everything, query). Nothing is kept between frames, so there is no remove, no move and no handle to keep valid, and your own arrays stay the owner of the objects.
The size of the tree is given by compile time parameters, all memory is inside of the `Quadtree` value (put it in a global or in your own struct). Functions fail (return false) instead of growing.

`odin run demo_raylib` / `odin run demo_karl2d` / `odin test .`
Demos (the menu of the demo kit switches between them): `collision` (the demo of grid_collision_map on a quadtree: paint walls, a box slides along them), `hover circles` (random circles, the mouse asks the tree which one it is over), `bouncing balls` (balls bounce off the window and each other, hold the left button to spawn more at the mouse). `G` shows the tree.

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
for i in 0 ..< count { other := &things[buffer[i]] }
```

## Parts
- `Item` - an `int` you choose, usually the index in your array. It is what a query gives back, so no lookup is needed.
- Tree - an element is stored in every leaf it overlaps (one link each); a leaf with more than `max_elements` splits unless it is at `max_depth`. The nodes come four at a time.
- `QuadtreeClear` - first call of every frame, only resets counters. `QuadtreeInsert` fails when the elements, the nodes or the links are full, and changes nothing. A leaf that cannot split (no nodes or links left) just holds more.
- `QuadtreeQuery` - elements whose rectangle overlaps a rectangle, `QuadtreeQueryPoint` - that hold a point. Results are limited by the size of the buffer you pass.
- `QuadtreeVisit` (draw or count the nodes), `QuadtreeUsage` (nodes and links in use, to size `N` and `L`), `QuadtreeLen`.
- `RectOverlaps`, `RectContainsPoint` - narrow phase helpers. Touching edges are not overlapping.

## Notes
- Elements outside of `bounds` work: they sit in the border leaves.
- This is a broad phase: the rectangle is what the tree knows, a circle or a polygon is tested by you on the results (see `hover circles`).
- The tree answers for the rectangles of the moment it was built. Insert again after things moved if a later query must see the new places (the demos build once per frame, between moving and colliding).
- Sizing: a leaf at `max_depth` is `bounds / 2^max_depth` wide; `QuadtreeUsage` tells how much of `N` and `L` a scene needs.

## Credit
The structure and the leaf/link bookkeeping follow the quadtree of "dragon-energy" from the Stack Overflow answer
[Efficient (and well explained) implementation of a quadtree for 2D collision detection](https://stackoverflow.com/questions/41946007/efficient-and-well-explained-implementation-of-a-quadtree-for-2d-collision-det)
(C, via [nezvers/quadtree](https://github.com/nezvers/quadtree); the author allows any use, Stack Overflow code is CC BY-SA 4.0). This is a rewrite in Odin: fixed storage, immediate mode, float rectangles, recursion instead of lists of leaves.
