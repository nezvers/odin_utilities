package main

// `odin run quadtree/tool/bench -o:speed [-- --quick]`
//
// Measures the quadtrees against what else a game would use for the same job, on two scenes (uniform and clustered rectangles) of several sizes. Every number is the median of several frames, in
// milliseconds per frame:
//   build    clear and insert everything (an immediate tree, a uniform grid, grid_collision_map rebuilt) or just the insert
//   rects    one query per element, with its rectangle grown by 8 (the neighbour pass of a collision loop)
//   circles  one circle query (radius 24) per element, on the structures that have one
// then the leaf capacity and depth sweep of the quadtree, shape queries and threads, and the cost of moving 1%, 10% and 100% of the elements per frame (retained tree and
// grid_collision_map move them, the immediate tree and the grid rebuild).
// All structures must report the same number of neighbours: a MISMATCH line means a bug in one of them (or in the benchmark). Run with `-o:speed`: a debug build says nothing.

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:slice"
import "core:thread"
import "core:time"
import gcm "../../../grid_collision_map"
import qt "../.."

WORLD :: 4096

Tree :: qt.Quadtree(65536, 60000, 500000)
Retained :: qt.QuadtreeRetained(65000, 60000, 500000)
GridMap :: gcm.GridMap(128, 128, 64, 65000)

Scene :: struct {
    name: string,
    rects: []qt.Rect,
    probes: []qt.Rect,          // the rectangle of each element grown by 8
    centers: []qt.Vec2,
}

FRAMES: int = 9

main :: proc() {
    sizes: []int = {1000, 10000, 50000}
    for argument in os.args[1:] {
        if argument == "--quick" {
            sizes = {1000, 10000}
            FRAMES = 3
        }
    }
    fmt.printfln("quadtree benchmark: %d frames per number (median), milliseconds per frame\n", FRAMES)
    for clustered in ([2]bool{false, true}) {
        for count in sizes {
            scene: Scene = makeScene(count, clustered)
            fmt.printfln("=== %s, %d rectangles (4 to 16 units in a %d x %d world) ===", scene.name, count, WORLD, WORLD)
            runScene(&scene)
            fmt.println()
        }
    }
}

makeScene :: proc(count: int, clustered: bool) -> Scene {
    seed: rand.Default_Random_State = rand.create(u64(count) * 7 + (1 if clustered else 0))
    state: rand.Generator = rand.default_random_generator(&seed)
    scene: Scene = {name = "clustered" if clustered else "uniform"}
    scene.rects = make([]qt.Rect, count)
    scene.probes = make([]qt.Rect, count)
    scene.centers = make([]qt.Vec2, count)
    clusters: [5]qt.Vec2
    for &cluster in clusters { cluster = {400 + rand.float32(state) * (WORLD - 800), 400 + rand.float32(state) * (WORLD - 800)} }
    for i in 0 ..< count {
        w: f32 = 4 + rand.float32(state) * 12
        h: f32 = 4 + rand.float32(state) * 12
        x, y: f32
        if clustered && i % 5 != 0 {
            // four of five elements sit in one of five clusters of radius 300
            cluster: qt.Vec2 = clusters[rand.int_max(5, state)]
            x = cluster.x + (rand.float32(state) * 2 - 1) * 300
            y = cluster.y + (rand.float32(state) * 2 - 1) * 300
        } else {
            x = rand.float32(state) * (WORLD - w)
            y = rand.float32(state) * (WORLD - h)
        }
        x = clamp(x, 0, WORLD - w)
        y = clamp(y, 0, WORLD - h)
        setRect(&scene, i, {x, y, w, h})
    }
    return scene
}

setRect :: proc(scene: ^Scene, index: int, rect: qt.Rect) {
    scene.rects[index] = rect
    scene.probes[index] = {rect.x - 8, rect.y - 8, rect.w + 16, rect.h + 16}
    scene.centers[index] = {rect.x + rect.w * 0.5, rect.y + rect.h * 0.5}
}

CIRCLE_RADIUS :: 24

// ------------------------------------------------------------------------------------------------------------------------

now :: proc() -> time.Tick {
    return time.tick_now()
}

elapsed :: proc(start: time.Tick) -> f64 {
    return time.duration_milliseconds(time.tick_since(start))
}

median :: proc(samples: []f64) -> f64 {
    sorted: []f64 = slice.clone(samples, context.temp_allocator)
    slice.sort(sorted)
    return sorted[len(sorted) / 2]
}

Row :: struct {
    name: string,
    build, rects, circles: f64,
    neighbours: int,            // the sum of the results of the rectangle pass, to compare the structures
    dropped: int,               // elements that did not fit
}

printHeader :: proc() {
    fmt.printfln("%-34s %9s %9s %9s %12s", "structure", "build", "rects", "circles", "neighbours")
}

printRow :: proc(row: Row) {
    circles: string = fmt.tprintf("%9.3f", row.circles) if row.circles >= 0 else "        -"
    note: string = fmt.tprintf("  (%d did not fit)", row.dropped) if row.dropped > 0 else ""
    fmt.printfln("%-34s %9.3f %9.3f %s %12d%s", row.name, row.build, row.rects, circles, row.neighbours, note)
}

runScene :: proc(scene: ^Scene) {
    count: int = len(scene.rects)
    printHeader()
    rows: [dynamic]Row
    rows.allocator = context.temp_allocator

    // brute force is quadratic: only for small scenes
    if count <= 10000 { append(&rows, benchBrute(scene)) }
    for cell in ([]f32{16, 32, 64}) { append(&rows, benchGrid(scene, cell)) }
    append(&rows, benchGridMap(scene))
    tree: ^Tree = new(Tree)
    defer free(tree)
    best: Row = {rects = max(f64)}
    for config in ([][2]int{{4, 10}, {8, 8}, {8, 10}, {16, 8}, {32, 8}, {16, 6}}) {
        row: Row = benchTree(scene, tree, config[0], config[1])
        append(&rows, row)
        if row.build + row.rects < best.build + best.rects { best = row }
    }
    append(&rows, benchTree(scene, tree, 8, 8, true))
    retained: ^Retained = new(Retained)
    defer free(retained)
    append(&rows, benchRetained(scene, retained, 8, 8))
    append(&rows, benchRetained(scene, retained, 8, 8, true))
    for row in rows { printRow(row) }
    fmt.printfln("best quadtree configuration here: %s", best.name)

    // every structure must report the same neighbours
    reference: int = -1
    for row in rows {
        if row.dropped > 0 { continue }
        if reference < 0 { reference = row.neighbours }
        if row.neighbours != reference { fmt.printfln("MISMATCH: %s found %d neighbours, others %d", row.name, row.neighbours, reference) }
    }

    benchShapes(scene, tree)
    benchMoves(scene, tree, retained)
}

// ------------------------------------------------------------------------------------------------------------------------

benchBrute :: proc(scene: ^Scene) -> Row {
    row: Row = {name = "brute force", circles = -1}
    build: [dynamic]f64
    build.allocator = context.temp_allocator
    queries: [dynamic]f64
    queries.allocator = context.temp_allocator
    for _ in 0 ..< min(FRAMES, 3) {
        start: time.Tick = now()
        total: int
        for probe, i in scene.probes {
            for other, j in scene.rects {
                if j != i && qt.RectOverlaps(other, probe) { total += 1 }
            }
        }
        append(&queries, elapsed(start))
        row.neighbours = total
    }
    row.rects = median(queries[:])
    return row
}

// A uniform grid built by counting (two passes, fixed arrays), the usual baseline: an element is in every cell it overlaps, a mark array removes duplicates
Grid :: struct {
    cell: f32,
    columns: int,
    start: []i32,               // cells + 1 offsets into `items`
    cursor: []i32,
    items: []i32,
    marks: []u32,
    mark: u32,
}

gridCells :: proc(grid: ^Grid, rect: qt.Rect) -> (x0, y0, x1, y1: int) {
    x0 = clamp(int(rect.x / grid.cell), 0, grid.columns - 1)
    y0 = clamp(int(rect.y / grid.cell), 0, grid.columns - 1)
    x1 = clamp(int((rect.x + rect.w) / grid.cell), 0, grid.columns - 1)
    y1 = clamp(int((rect.y + rect.h) / grid.cell), 0, grid.columns - 1)
    return
}

gridBuild :: proc(grid: ^Grid, rects: []qt.Rect) {
    for &offset in grid.start { offset = 0 }
    for rect in rects {
        x0, y0, x1, y1 := gridCells(grid, rect)
        for y in y0 ..= y1 { for x in x0 ..= x1 { grid.start[y * grid.columns + x + 1] += 1 } }
    }
    for i in 1 ..< len(grid.start) { grid.start[i] += grid.start[i - 1] }
    copy(grid.cursor, grid.start[:len(grid.cursor)])
    for rect, index in rects {
        x0, y0, x1, y1 := gridCells(grid, rect)
        for y in y0 ..= y1 {
            for x in x0 ..= x1 {
                cell: int = y * grid.columns + x
                grid.items[grid.cursor[cell]] = i32(index)
                grid.cursor[cell] += 1
            }
        }
    }
}

gridQuery :: proc(grid: ^Grid, rects: []qt.Rect, probe: qt.Rect, omit: int) -> int {
    grid.mark += 1
    count: int
    x0, y0, x1, y1 := gridCells(grid, probe)
    for y in y0 ..= y1 {
        for x in x0 ..= x1 {
            cell: int = y * grid.columns + x
            for link in grid.start[cell] ..< grid.start[cell + 1] {
                index: i32 = grid.items[link]
                if grid.marks[index] == grid.mark || int(index) == omit { continue }
                grid.marks[index] = grid.mark
                if qt.RectOverlaps(rects[index], probe) { count += 1 }
            }
        }
    }
    return count
}

benchGrid :: proc(scene: ^Scene, cell: f32) -> Row {
    count: int = len(scene.rects)
    columns: int = int(WORLD / cell)
    grid: Grid = {cell = cell, columns = columns}
    grid.start = make([]i32, columns * columns + 1)
    grid.cursor = make([]i32, columns * columns)
    grid.items = make([]i32, count * 12)
    grid.marks = make([]u32, count)
    defer { delete(grid.start); delete(grid.cursor); delete(grid.items); delete(grid.marks) }
    row: Row = {name = fmt.tprintf("uniform grid, cells of %d", int(cell)), circles = -1}
    build, queries: [dynamic]f64
    build.allocator = context.temp_allocator
    queries.allocator = context.temp_allocator
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        gridBuild(&grid, scene.rects)
        append(&build, elapsed(start))
    }
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        total: int
        for probe, i in scene.probes { total += gridQuery(&grid, scene.rects, probe, i) }
        append(&queries, elapsed(start))
        row.neighbours = total
    }
    row.build = median(build[:])
    row.rects = median(queries[:])
    return row
}

benchGridMap :: proc(scene: ^Scene) -> Row {
    world: ^GridMap = new(GridMap)
    defer free(world)
    handles: []gcm.Handle = make([]gcm.Handle, len(scene.rects))
    defer delete(handles)
    gcm.GridMapInit(world, {0, 0}, {32, 32})
    row: Row = {name = "grid_collision_map, cells of 32", circles = -1}
    build, queries: [dynamic]f64
    build.allocator = context.temp_allocator
    queries.allocator = context.temp_allocator
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        gcm.GridMapClear(world)
        dropped: int
        for rect, i in scene.rects {
            ok: bool
            handles[i], ok = gcm.GridMapAdd(world, {rect.x, rect.y, rect.w, rect.h})
            if !ok { dropped += 1 }
        }
        append(&build, elapsed(start))
        row.dropped = dropped
    }
    out: [256]gcm.Handle
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        total: int
        for probe, i in scene.probes { total += gcm.GridMapQuery(world, {probe.x, probe.y, probe.w, probe.h}, out[:], handles[i]) }
        append(&queries, elapsed(start))
        row.neighbours = total
    }
    row.build = median(build[:])
    row.rects = median(queries[:])
    return row
}

benchTree :: proc(scene: ^Scene, tree: ^Tree, max_elements: int, max_depth: int, compact: bool = false) -> Row {
    qt.QuadtreeInit(tree, {0, 0, WORLD, WORLD}, max_elements, max_depth)
    row: Row = {name = fmt.tprintf("quadtree, leaf %d, depth %d%s", max_elements, max_depth, ", compacted" if compact else "")}
    build, queries, circles: [dynamic]f64
    build.allocator = context.temp_allocator
    queries.allocator = context.temp_allocator
    circles.allocator = context.temp_allocator
    scratch: []qt.Link
    if compact { scratch = make([]qt.Link, len(tree.links)) }
    defer delete(scratch)
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        qt.QuadtreeClear(tree)
        dropped: int
        for rect, i in scene.rects { if !qt.QuadtreeInsert(tree, rect, i) { dropped += 1 } }
        if compact { qt.QuadtreeCompact(tree, scratch) }
        append(&build, elapsed(start))
        row.dropped = dropped
    }
    out: [512]qt.Item
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        total: int
        for probe, i in scene.probes { total += qt.QuadtreeQuery(tree, probe, out[:], omit = i) }
        append(&queries, elapsed(start))
        row.neighbours = total
    }
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        total: int
        for center in scene.centers { total += qt.QuadtreeQueryCircle(tree, center, CIRCLE_RADIUS, out[:]) }
        append(&circles, elapsed(start))
        if total < 0 { fmt.println(total) }       // keeps the loop alive
    }
    row.build = median(build[:])
    row.rects = median(queries[:])
    row.circles = median(circles[:])
    return row
}

benchRetained :: proc(scene: ^Scene, tree: ^Retained, max_elements: int, max_depth: int, compact: bool = false) -> Row {
    qt.QuadtreeRetainedInit(tree, {0, 0, WORLD, WORLD}, max_elements, max_depth)
    row: Row = {name = fmt.tprintf("retained quadtree, leaf %d, depth %d%s", max_elements, max_depth, ", compacted" if compact else ""), circles = -1}
    handles: []qt.Handle = make([]qt.Handle, len(scene.rects))
    defer delete(handles)
    scratch: []qt.RetainedLink
    if compact { scratch = make([]qt.RetainedLink, len(tree.links)) }
    defer delete(scratch)
    build, queries: [dynamic]f64
    build.allocator = context.temp_allocator
    queries.allocator = context.temp_allocator
    for _ in 0 ..< FRAMES {
        qt.QuadtreeRetainedClear(tree)
        start: time.Tick = now()
        dropped: int
        for rect, i in scene.rects {
            ok: bool
            handles[i], ok = qt.QuadtreeRetainedAdd(tree, rect)
            if !ok { dropped += 1 }
        }
        if compact { qt.QuadtreeRetainedCompact(tree, scratch) }
        append(&build, elapsed(start))
        row.dropped = dropped
    }
    out: [512]qt.Handle
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        total: int
        for probe, i in scene.probes { total += qt.QuadtreeRetainedQuery(tree, probe, out[:], handles[i]) }
        append(&queries, elapsed(start))
        row.neighbours = total
    }
    row.build = median(build[:])
    row.rects = median(queries[:])
    return row
}

// ------------------------------------------------------------------------------------------------------------------------
// Shape queries and threads: segment, circle and rectangle passes, the rectangle pass split over threads (no query writes into the tree, so no session is needed)

QueryJob :: struct {
    tree: ^Tree,
    scene: ^Scene,
    from, to: int,
    total: int,
}

queryWork :: proc(data: rawptr) {
    job: ^QueryJob = cast(^QueryJob)data
    out: [512]qt.Item
    total: int
    for i in job.from ..< job.to { total += qt.QuadtreeQuery(job.tree, job.scene.probes[i], out[:], omit = i) }
    job.total = total
}

benchShapes :: proc(scene: ^Scene, tree: ^Tree) {
    count: int = len(scene.rects)
    qt.QuadtreeInit(tree, {0, 0, WORLD, WORLD}, 8, 8)
    for rect, i in scene.rects { qt.QuadtreeInsert(tree, rect, i) }
    out: [512]qt.Item
    marked: [dynamic]f64
    marked.allocator = context.temp_allocator
    expected: int
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        total: int
        for probe, i in scene.probes { total += qt.QuadtreeQuery(tree, probe, out[:], omit = i) }
        append(&marked, elapsed(start))
        expected = total
    }
    segment_pass, circle_pass: [dynamic]f64
    segment_pass.allocator = context.temp_allocator
    circle_pass.allocator = context.temp_allocator
    for _ in 0 ..< FRAMES {
        start: time.Tick = now()
        for center in scene.centers { qt.QuadtreeQuerySegment(tree, center, center + {40, 25}, out[:]) }
        append(&segment_pass, elapsed(start))
        start = now()
        for center in scene.centers { qt.QuadtreeQueryCircle(tree, center, CIRCLE_RADIUS, out[:]) }
        append(&circle_pass, elapsed(start))
    }
    fmt.printfln("\nqueries on the tree (leaf 8, depth 8):")
    fmt.printfln("  segment pass (no marks)             %8.3f", median(segment_pass[:]))
    fmt.printfln("  circle pass (no marks)              %8.3f", median(circle_pass[:]))
    fmt.printfln("  rectangle pass (no marks)           %8.3f", median(marked[:]))
    for threads in ([]int{1, 2, 4, 8}) {
        samples: [dynamic]f64
        samples.allocator = context.temp_allocator
        ok: bool = true
        for _ in 0 ..< FRAMES {
            jobs: []QueryJob = make([]QueryJob, threads, context.temp_allocator)
            handles: []^thread.Thread = make([]^thread.Thread, threads, context.temp_allocator)
            start: time.Tick = now()
            for t in 0 ..< threads {
                jobs[t] = {tree = tree, scene = scene, from = count * t / threads, to = count * (t + 1) / threads}
                handles[t] = thread.create_and_start_with_data(&jobs[t], queryWork)
            }
            total: int
            for t in 0 ..< threads {
                thread.join(handles[t])
                thread.destroy(handles[t])
                total += jobs[t].total
            }
            append(&samples, elapsed(start))
            if total != expected { ok = false }
        }
        fmt.printfln("  rectangle pass, %d thread%s%s %8.3f%s", threads, "" if threads == 1 else "s", " (wall time)" if threads > 1 else "            ", median(samples[:]), "" if ok else "   MISMATCH")
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// Moving elements: `percent` of them take a small step each frame, then the rectangle pass runs. The immediate tree and the grid rebuild, the retained tree and grid_collision_map move.

benchMoves :: proc(scene: ^Scene, tree: ^Tree, retained: ^Retained) {
    benchMovesBy(scene, tree, retained, 1.5)
    benchMovesBy(scene, tree, retained, 6)
}

// `step`: how far an element moves in x and y at most (units; elements are 4 to 16 wide, the leaves of the default tree about 16 at the deepest level)
benchMovesBy :: proc(scene: ^Scene, tree: ^Tree, retained: ^Retained, step: f32) {
    count: int = len(scene.rects)
    fmt.printfln("\nmoving elements by up to %.1f units: update and the rectangle pass | the update alone, per frame:", step)
    fmt.printfln("  %-34s %9s %9s %9s   | %9s %9s %9s", "", "1%", "10%", "100%", "1%", "10%", "100%")
    handles: []qt.Handle = make([]qt.Handle, count)
    gcm_handles: []gcm.Handle = make([]gcm.Handle, count)
    defer { delete(handles); delete(gcm_handles) }
    world: ^GridMap = new(GridMap)
    defer free(world)
    names: [3]string = {"immediate quadtree (rebuild)", "retained quadtree (move)", "grid_collision_map (move)"}
    results: [3][3]f64
    updates: [3][3]f64
    for percent, column in ([]int{1, 10, 100}) {
        // a private copy of the scene so each run starts from the same places
        copy_scene: Scene = scene^
        copy_scene.rects = slice.clone(scene.rects)
        copy_scene.probes = slice.clone(scene.probes)
        copy_scene.centers = slice.clone(scene.centers)
        defer { delete(copy_scene.rects); delete(copy_scene.probes); delete(copy_scene.centers) }
        qt.QuadtreeRetainedInit(retained, {0, 0, WORLD, WORLD}, 8, 8)
        gcm.GridMapInit(world, {0, 0}, {32, 32})
        for rect, i in copy_scene.rects {
            handles[i], _ = qt.QuadtreeRetainedAdd(retained, rect)
            gcm_handles[i], _ = gcm.GridMapAdd(world, {rect.x, rect.y, rect.w, rect.h})
        }
        seed: rand.Default_Random_State = rand.create(99)
        state: rand.Generator = rand.default_random_generator(&seed)
        moving: int = max(1, count * percent / 100)
        out: [512]qt.Item
        out_handles: [512]qt.Handle
        out_gcm: [256]gcm.Handle
        samples: [3][dynamic]f64
        updated: [3][dynamic]f64
        for &list in samples { list.allocator = context.temp_allocator }
        for &list in updated { list.allocator = context.temp_allocator }
        for frame in 0 ..< FRAMES {
            // the same steps for every structure of a frame
            first: int = (frame * moving) % count
            for k in 0 ..< moving {
                i: int = (first + k) % count
                rect: qt.Rect = copy_scene.rects[i]
                rect.x = clamp(rect.x + (rand.float32(state) * 2 - 1) * step, 0, WORLD - rect.w)
                rect.y = clamp(rect.y + (rand.float32(state) * 2 - 1) * step, 0, WORLD - rect.h)
                setRect(&copy_scene, i, rect)
            }
            start: time.Tick = now()
            qt.QuadtreeClear(tree)
            for rect, i in copy_scene.rects { qt.QuadtreeInsert(tree, rect, i) }
            append(&updated[0], elapsed(start))
            total: int
            for probe, i in copy_scene.probes { total += qt.QuadtreeQuery(tree, probe, out[:], omit = i) }
            append(&samples[0], elapsed(start))

            // the retained structures see the same moves (their rectangles are one frame behind the copy: bring them up to date, timed)
            start = now()
            for k in 0 ..< moving {
                i: int = (first + k) % count
                qt.QuadtreeRetainedMove(retained, handles[i], copy_scene.rects[i])
            }
            append(&updated[1], elapsed(start))
            for probe, i in copy_scene.probes { total += qt.QuadtreeRetainedQuery(retained, probe, out_handles[:], handles[i]) }
            append(&samples[1], elapsed(start))

            start = now()
            for k in 0 ..< moving {
                i: int = (first + k) % count
                r: qt.Rect = copy_scene.rects[i]
                gcm.GridMapMove(world, gcm_handles[i], {r.x, r.y, r.w, r.h})
            }
            append(&updated[2], elapsed(start))
            for probe, i in copy_scene.probes { total += gcm.GridMapQuery(world, {probe.x, probe.y, probe.w, probe.h}, out_gcm[:], gcm_handles[i]) }
            append(&samples[2], elapsed(start))
            if total < 0 { fmt.println(total) }
        }
        for row in 0 ..< 3 {
            results[row][column] = median(samples[row][:])
            updates[row][column] = median(updated[row][:])
        }
    }
    for row in 0 ..< 3 {
        fmt.printfln("  %-34s %9.3f %9.3f %9.3f   | %9.3f %9.3f %9.3f", names[row], results[row][0], results[row][1], results[row][2], updates[row][0], updates[row][1], updates[row][2])
    }
}
