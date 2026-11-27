# quadtree: to do

Next steps, most valuable first. A task starts with `(high)`, `(medium)` or `(low)`.

- [x] Thread-safe queries: `QuerySession` (caller provided stamps, one per thread) on every query of the three trees
- [x] Circle and segment queries and `SegmentFirst` (ray cast) on the immediate, retained and chunked trees
- [x] Demo `ray cast and nearest` (demo_rays.odin) with a scripted brute force check
- [x] Faster build and queries: loop descent, no marks for rectangle queries, rect copy in links, on the immediate and the retained tree (build 5.9 to 2.1 ms at 50k, grid 1.1; rectangle pass 17.9 to 13.3, grid 10.5)
- [x] Circle queries without marks (ownership of the nearest point, descent like a rectangle): 34 to 24 ms at 50k; segments test the rectangle copy in the link first. Circle iterators on the immediate and retained tree
- [ ] (low) Segment queries are still marked and 1.8x a rectangle pass: a descent that follows the segment through the nodes in order (a DDA like walk) would also make `SegmentFirst` stop early; ownership needs a robust point of the segment
- [x] Nearest and k-nearest on the three trees (`QuadtreeNearest`, `QuadtreeRetainedNearest`, `QuadtreeChunksNearest`)
- [x] Benchmarks against a uniform grid, `grid_collision_map` and brute force (`tool/bench`, findings in README): leaf 8 and depth 8 confirmed as the default
- [x] Iterator queries without a result slice for rectangles and points on the three trees (`QueryIterator`, `QuadtreeChunksIterator`)
- [x] Retained `Move` fast path (same leaves: only the rect copies change), 26% faster for small steps; the rest is cache misses in the link lists (bench: update alone, 165 ns a move against 20 for grid_collision_map)
- [x] Contiguous leaves as an optional compaction step (`QuadtreeCompact` and the retained and chunked versions): queries 10 to 20% faster for 0.7 ms at 50k; a leaf storage redesign (buckets) was not needed
- [ ] (low) Compaction at the end of a split or a Move that changes leaves, so a retained tree stays compact without calling it (measure what it costs `Move` first)
- [ ] (low) Chunked tree: items bigger than `max_item_size` (a fallback list), and a query of many chunks with a limit
- [x] One shared debug draw (`quadtree/kit`) for all demos
- [x] Build from a whole array: tried (top down partition), not faster than insert + compaction, dropped (see AGENTS.md)
- [ ] (low) A build by Morton code sort for static scenes, only if it can beat insert + compaction (2.8 ms at 50k) by a clear margin
