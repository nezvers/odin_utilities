# quadtree: to do

Next steps, most valuable first. A task starts with `(high)`, `(medium)` or `(low)`.

- [x] Thread-safe queries: `QuerySession` (caller provided stamps, one per thread) on every query of the three trees
- [x] Circle and segment queries and `SegmentFirst` (ray cast) on the immediate, retained and chunked trees
- [ ] (medium) A demo for the new queries (a ray cast and a radius query on the collision demo, with a scripted check) and a short benchmark of a session query against the marked one
- [ ] (medium) Nearest and k-nearest query (best first walk with a distance bound)
- [ ] (medium) Benchmarks against `grid_collision_map`, a plain spatial hash and brute force: where the quadtree wins, and the data for the leaf capacity and the maximum depth (now chosen by judgement)
- [ ] (medium) A query without a callback or a result slice for early exit (an iterator), mostly for the retained and chunked trees
- [ ] (low) Retained `Move` fast path: nothing to relink when the new rectangle still fits the leaves it is in (check what `QuadtreeRetainedMove` already does, measure first)
- [ ] (low) Chunked tree: items bigger than `max_item_size` (a fallback list), and a query of many chunks with a limit
- [ ] (low) Build from a sorted array for static scenes (faster than insert one by one); one shared debug draw proc for the demos instead of each drawing the nodes
