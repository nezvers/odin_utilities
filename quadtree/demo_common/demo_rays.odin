#+private file
package demo_common

import "core:fmt"
import "core:math"
import "core:math/rand"
import qt ".."
import kit "../../demo_kit"
import qtkit "../kit"

@(private = "package")
demo_rays: kit.Demo = {
    name = "ray cast and nearest",
    init = raysInit,
    update = raysUpdate,
    draw = raysDraw,
    script = raysScript,
}

// A fixed set of rectangles and three questions the tree answers every frame: what does the ray from the origin to the mouse hit first (QuadtreeSegmentFirst) and what does it cross (QuadtreeQuerySegment),
// what lies within a radius of the mouse (QuadtreeQueryCircle), and which three are nearest to the mouse (QuadtreeNearest). The script compares every answer with a brute force over the whole set.
RAYS_COUNT :: 260
RAYS_RADIUS :: 90.0
RAYS_NEAR :: 3
RAYS_SCREEN :: qt.Rect{0, 0, 1280, 720}

RaysTree :: qt.Quadtree(512, 1400, 8192)

rays_tree: RaysTree
rays_boxes: [RAYS_COUNT]qt.Rect
rays_seed: rand.Default_Random_State
rays_random: rand.Generator

rays_origin: qt.Vec2             // set with the left button
rays_end: qt.Vec2                // the mouse
rays_target: qt.Vec2             // where the script points the mouse
rays_hit: qt.Item
rays_hit_t: f32
rays_has_hit: bool
rays_crossed: [64]qt.Item
rays_crossed_count: int
rays_inside: [64]qt.Item
rays_inside_count: int
rays_near: [RAYS_NEAR]qt.Item
rays_near_distance: [RAYS_NEAR]f32
rays_near_count: int

raysInit :: proc(ctx: ^kit.Context) {
    rays_seed = rand.create(20261127)
    rays_random = rand.default_random_generator(&rays_seed)
    raysReset()
}

raysReset :: proc() {
    qt.QuadtreeInit(&rays_tree, RAYS_SCREEN, 6, 6)
    qt.QuadtreeClear(&rays_tree)
    for i in 0 ..< RAYS_COUNT {
        w: f32 = 14 + rand.float32(rays_random) * 46
        h: f32 = 14 + rand.float32(rays_random) * 46
        rays_boxes[i] = {rand.float32(rays_random) * (RAYS_SCREEN.w - w), rand.float32(rays_random) * (RAYS_SCREEN.h - h), w, h}
        qt.QuadtreeInsert(&rays_tree, rays_boxes[i], i)
    }
    rays_origin = {60, 360}
    rays_end = {1220, 360}
    raysAsk()
}

// The three questions
raysAsk :: proc() {
    rays_hit, rays_hit_t, rays_has_hit = qt.QuadtreeSegmentFirst(&rays_tree, rays_origin, rays_end)
    rays_crossed_count = qt.QuadtreeQuerySegment(&rays_tree, rays_origin, rays_end, rays_crossed[:])
    rays_inside_count = qt.QuadtreeQueryCircle(&rays_tree, rays_end, RAYS_RADIUS, rays_inside[:])
    rays_near_count = qt.QuadtreeNearest(&rays_tree, rays_end, rays_near[:], rays_near_distance[:])
}

raysUpdate :: proc(ctx: ^kit.Context) {
    if !ctx.ui_hover && kit.MousePressed(&ctx.input, .LEFT) { rays_origin = ctx.input.mouse_position }
    if kit.KeyPressed(&ctx.input, .R) { raysReset() }
    rays_end = ctx.input.mouse_position
    raysAsk()
}

raysDraw :: proc(ctx: ^kit.Context) {
    qtkit.DrawQuadtree(ctx, &rays_tree)
    for box in rays_boxes { kit.DrawRect(ctx, transmute(kit.Rect)box, kit.Color{200, 200, 205, 255}) }
    // within the radius: blue, crossed by the ray: orange outline, the first one hit: red, the nearest to the mouse: green outline with the distance
    for i in 0 ..< rays_inside_count { kit.DrawRect(ctx, transmute(kit.Rect)rays_boxes[rays_inside[i]], kit.Color{90, 140, 230, 255}) }
    for i in 0 ..< rays_crossed_count { kit.DrawRectOutline(ctx, transmute(kit.Rect)rays_boxes[rays_crossed[i]], 2, kit.ORANGE) }
    if rays_has_hit { kit.DrawRect(ctx, transmute(kit.Rect)rays_boxes[rays_hit], kit.Color{220, 60, 60, 255}) }
    kit.DrawCircleOutline(ctx, rays_end, RAYS_RADIUS, 1, kit.Color{90, 140, 230, 255})
    for i in 0 ..< rays_near_count {
        box: qt.Rect = rays_boxes[rays_near[i]]
        kit.DrawRectOutline(ctx, transmute(kit.Rect)box, 3, kit.Color{40, 170, 80, 255})
        kit.DrawText(ctx, fmt.tprintf("%d: %.0f", i + 1, rays_near_distance[i]), {box.x, box.y - 18}, 16, kit.Color{20, 110, 50, 255})
    }
    end: qt.Vec2 = rays_end
    if rays_has_hit { end = rays_origin + (rays_end - rays_origin) * rays_hit_t }
    kit.DrawLine(ctx, rays_origin, end, 2, kit.BLACK)
    if rays_has_hit { kit.DrawCircle(ctx, end, 5, kit.Color{220, 60, 60, 255}) }
    kit.DrawCircle(ctx, rays_origin, 5, kit.BLACK)
    kit.DrawText(ctx, "ray cast and nearest: the mouse is the end of the ray and the center of the circle, LMB moves the ray origin, R new random set", {10, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("the ray crosses %d, the first hit is %s (red); %d in the circle (blue); the %d nearest to the mouse (green)", rays_crossed_count, fmt.tprintf("#%d", rays_hit) if rays_has_hit else "none", rays_inside_count, rays_near_count), {10, 36}, 20, kit.DARK_GRAY)
}

// ------------------------------------------------------------------------------------------------------------------------
// The brute force the script compares with, written without the tree and without the slab test: the segment is sampled

raysBoxDistance :: proc(point: qt.Vec2, box: qt.Rect) -> f32 {
    dx: f32 = point.x - clamp(point.x, box.x, box.x + box.w)
    dy: f32 = point.y - clamp(point.y, box.y, box.y + box.h)
    return math.sqrt(dx * dx + dy * dy)
}

raysInsideBox :: proc(point: qt.Vec2, box: qt.Rect) -> bool {
    return point.x >= box.x && point.x <= box.x + box.w && point.y >= box.y && point.y <= box.y + box.h
}

// The first box a walk along the segment enters, in steps of a tenth of a unit: close to the exact answer, never equal to it by construction
raysSampledFirst :: proc() -> (item: int, ok: bool) {
    steps: int = int(math.round(math.sqrt(math.pow(rays_end.x - rays_origin.x, 2) + math.pow(rays_end.y - rays_origin.y, 2)) * 10)) + 1
    for step in 0 ..= steps {
        point: qt.Vec2 = rays_origin + (rays_end - rays_origin) * (f32(step) / f32(steps))
        for box, i in rays_boxes { if raysInsideBox(point, box) { return i, true } }
    }
    return 0, false
}

raysChecked :: proc() -> bool {
    // the circle: exactly the boxes closer than the radius
    expected: int
    for box in rays_boxes { if raysBoxDistance(rays_end, box) < RAYS_RADIUS { expected += 1 } }
    if expected != rays_inside_count { return false }
    // nearest: the three smallest distances
    distances: [RAYS_COUNT]f32
    for box, i in rays_boxes { distances[i] = raysBoxDistance(rays_end, box) }
    for pass in 0 ..< RAYS_NEAR {
        smallest: int = pass
        for i in pass + 1 ..< RAYS_COUNT { if distances[i] < distances[smallest] { smallest = i } }
        distances[pass], distances[smallest] = distances[smallest], distances[pass]
        if pass >= rays_near_count || abs(rays_near_distance[pass] - distances[pass]) > 0.01 { return false }
    }
    // the ray: its first hit is the box a sampled walk enters first (a box the walk skips between two samples is the only allowed difference, so the point of the hit must be on the box)
    sampled, found := raysSampledFirst()
    if found != rays_has_hit { return false }
    if !found { return true }
    point: qt.Vec2 = rays_origin + (rays_end - rays_origin) * rays_hit_t
    return raysBoxDistance(point, rays_boxes[rays_hit]) < 0.01 && (sampled == rays_hit || raysBoxDistance(point, rays_boxes[sampled]) < 0.5)
}

raysScript: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return qt.QuadtreeLen(&rays_tree) == RAYS_COUNT }, "the set is in the tree"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return raysChecked() }, "the start ray, circle and nearest agree with a brute force"),
    // a few other rays and mouse places, left button moves the origin
    kit.Click({100, 100}, .LEFT),
    kit.MoveTo({1000, 600}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return rays_origin == {100, 100} && rays_end == {1000, 600} }, "the left button moves the origin, the mouse is the end"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return raysChecked() && rays_crossed_count >= 1 }, "a long diagonal ray crosses boxes and agrees with a brute force"),
    kit.Click({1200, 80}, .LEFT),
    kit.MoveTo({50, 700}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return raysChecked() }, "the other diagonal agrees too"),
    // the mouse outside of the window: the tree still answers (the border leaves)
    kit.MoveTo({-200, 900}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return raysChecked() && rays_near_count == RAYS_NEAR }, "a mouse outside of the window still finds its nearest boxes"),
    kit.Tap(.R),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return qt.QuadtreeLen(&rays_tree) == RAYS_COUNT && raysChecked() }, "R makes a new set that still agrees"),
}
