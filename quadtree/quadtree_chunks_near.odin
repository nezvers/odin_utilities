package quadtree

// Queries of a chunked world with a small `out` over a big area (a wide rectangle, a long segment): the plain queries walk the chunks in coordinate order, so when `out` fills up the results
// come from the top left chunks and say nothing about what is near the center. These versions visit the chunks nearest to the center of the query first (the distance of the center to the
// chunk square grown by `max_item_size`), so a limited result holds what is around the player. The list of oversize items is scanned after the chunks, so a full `out` can cut it: give `out`
// room for it or use the plain query. Costs a sort of the candidate chunks (at most W * H, insertion sort), so use the plain query when `out` is large enough for everything.

// Like QuadtreeChunksQuery, nearest chunks first
QuadtreeChunksQueryNear :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), rect: WorldRect, out: []Item, omit: Item = ITEM_NONE) -> int {
    return chunksQueryNear(world, {kind = .RECT, rect = rect}, out, omit)
}

// Like QuadtreeChunksQueryCircle, nearest chunks first (the center of the circle is the center of the query)
QuadtreeChunksQueryCircleNear :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), center: WorldVec, radius: f64, out: []Item, omit: Item = ITEM_NONE) -> int {
    probe: ChunkProbe = {kind = .CIRCLE, rect = {center.x - radius, center.y - radius, radius * 2, radius * 2}, center = center, radius = radius}
    return chunksQueryNear(world, probe, out, omit)
}

@(private)
chunksQueryNear :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), probe: ChunkProbe, out: []Item, omit: Item) -> int {
    probe := probe
    found: [W * H]^QuadtreeChunk(E, N, L)
    candidates: int = chunksCandidates(world, &probe, found[:])
    center: WorldVec = {probe.rect.x + probe.rect.w * 0.5, probe.rect.y + probe.rect.h * 0.5}
    distance: [W * H]f64
    // insertion sort by the distance of the center to the box of the chunk
    for i in 0 ..< candidates {
        chunk: ^QuadtreeChunk(E, N, L) = found[i]
        x0: f64 = f64(chunk.cx) * world.chunk_size
        y0: f64 = f64(chunk.cy) * world.chunk_size
        dx: f64 = center.x - clamp(center.x, x0, x0 + world.chunk_size + world.max_item_size)
        dy: f64 = center.y - clamp(center.y, y0, y0 + world.chunk_size + world.max_item_size)
        squared: f64 = dx * dx + dy * dy
        j: int = i
        for j > 0 && distance[j - 1] > squared {
            found[j] = found[j - 1]
            distance[j] = distance[j - 1]
            j -= 1
        }
        found[j] = chunk
        distance[j] = squared
    }
    count: int
    for i in 0 ..< candidates {
        if count >= len(out) { break }
        local: Probe = chunksProbeLocal(world, found[i], &probe)
        count += treeQuery(&found[i].tree, local, out[count:], omit)
    }
    count += oversizeQuery(world, &probe, out[count:], omit)
    return count
}
