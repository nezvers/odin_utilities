#+private file
package demo_common

import "core:fmt"
import "core:math/rand"
import qt ".."
import kit "../../demo_kit"
import qtkit "../kit"

@(private = "package")
demo_hover: kit.Demo = {
    name = "hover circles",
    init = hoverInit,
    update = hoverUpdate,
    draw = hoverDraw,
    script = hoverScript,
}

// Circles of random size at random places. The tree is rebuilt every frame with the bounding box of every live circle (the item is its slot); the circle itself is the narrow phase.
// The mouse asks the tree for the boxes under it, then only those few are tested with the real shape.
CIRCLE_CAPACITY :: 512
CIRCLE_START :: 250
CIRCLE_RADIUS_MIN :: 6.0
CIRCLE_RADIUS_MAX :: 26.0
SCREEN :: qt.Rect{0, 0, 1280, 720}

Circle :: struct {
    center: qt.Vec2,
    radius: f32,
    color: kit.Color,
    alive: bool,
}

HoverTree :: qt.Quadtree(CIRCLE_CAPACITY, 1400, 8192)

hover_tree: HoverTree
hover_circles: [CIRCLE_CAPACITY]Circle
hover_alive: int                     // live circles
hover_free: [CIRCLE_CAPACITY]int     // slots of removed circles, taken again by the next spawn
hover_free_count: int
hover_used: int                      // slots handed out from the array so far
hover_seed: rand.Default_Random_State
hover_random: rand.Generator

hover_picked: ^Circle                // the circle under the mouse
hover_candidates: int                // boxes under the mouse: what the tree made of the whole set
hover_show_tree: bool
hover_target: qt.Vec2                // where the script points the mouse

hoverCount :: proc() -> int {
    return hover_alive
}

circleBox :: proc(circle: ^Circle) -> qt.Rect {
    return {circle.center.x - circle.radius, circle.center.y - circle.radius, circle.radius * 2, circle.radius * 2}
}

// The tree is thrown away and filled again with the live circles, every frame
hoverRebuild :: proc() {
    qt.QuadtreeClear(&hover_tree)
    for &circle, slot in hover_circles[:hover_used] {
        if circle.alive { qt.QuadtreeInsert(&hover_tree, circleBox(&circle), slot) }
    }
}

hoverInit :: proc(ctx: ^kit.Context) {
    hover_seed = rand.create(20260127)
    hover_random = rand.default_random_generator(&hover_seed)
    hoverReset()
    hover_show_tree = true
}

hoverReset :: proc() {
    qt.QuadtreeInit(&hover_tree, SCREEN, 8, 5)
    hover_free_count = 0
    hover_used = 0
    hover_alive = 0
    hover_picked = nil
    for _ in 0 ..< CIRCLE_START {
        radius: f32 = CIRCLE_RADIUS_MIN + rand.float32(hover_random) * (CIRCLE_RADIUS_MAX - CIRCLE_RADIUS_MIN)
        center: qt.Vec2 = {radius + rand.float32(hover_random) * (SCREEN.w - 2 * radius), radius + rand.float32(hover_random) * (SCREEN.h - 2 * radius)}
        hoverSpawn(center, radius)
    }
    hoverRebuild()
}

hoverSpawn :: proc(center: qt.Vec2, radius: f32) -> bool {
    slot: int
    if hover_free_count > 0 {
        hover_free_count -= 1
        slot = hover_free[hover_free_count]
    } else if hover_used < CIRCLE_CAPACITY {
        slot = hover_used
        hover_used += 1
    } else {
        return false
    }
    hue: f32 = rand.float32(hover_random)
    hover_circles[slot] = {center = center, radius = radius, alive = true, color = hoverColor(hue)}
    hover_alive += 1
    return true
}

@(private = "package")
hoverColor :: proc(hue: f32) -> kit.Color {
    // three phase shifted waves: a color wheel without a conversion
    wave :: proc(x: f32) -> u8 {
        v: f32 = x - f32(int(x))
        v = abs(v * 2 - 1)
        return u8(110 + v * 120)
    }
    return {wave(hue), wave(hue + 0.333), wave(hue + 0.666), 255}
}

// The circle (not only its box) that holds the point; the one drawn last wins
hoverFind :: proc(point: qt.Vec2) -> (found: ^Circle, candidates: int) {
    buffer: [64]qt.Item
    count: int = qt.QuadtreeQueryPoint(&hover_tree, point, buffer[:])
    best: int = -1
    for i in 0 ..< count {
        slot: int = buffer[i]
        circle: ^Circle = &hover_circles[slot]
        offset: qt.Vec2 = point - circle.center
        if offset.x * offset.x + offset.y * offset.y > circle.radius * circle.radius { continue }
        if slot > best {
            best = slot
            found = circle
        }
    }
    return found, count
}

hoverUpdate :: proc(ctx: ^kit.Context) {
    mouse: qt.Vec2 = ctx.input.mouse_position
    if !ctx.ui_hover {
        if kit.MousePressed(&ctx.input, .LEFT) {
            radius: f32 = CIRCLE_RADIUS_MIN + rand.float32(hover_random) * (CIRCLE_RADIUS_MAX - CIRCLE_RADIUS_MIN)
            hoverSpawn(mouse, radius)
        }
        if kit.MousePressed(&ctx.input, .RIGHT) {
            // the tree of this moment still answers for the circles before the click
            hover_picked, _ = hoverFind(mouse)
            if hover_picked != nil {
                hover_picked.alive = false
                hover_alive -= 1
                hover_free[hover_free_count] = int(uintptr(hover_picked) - uintptr(&hover_circles[0])) / size_of(Circle)
                hover_free_count += 1
            }
        }
    }
    if kit.KeyPressed(&ctx.input, .R) { hoverReset() }
    if kit.KeyPressed(&ctx.input, .G) { hover_show_tree = !hover_show_tree }
    // rebuild after every change, then ask
    hoverRebuild()
    hover_picked, hover_candidates = hoverFind(mouse)
}

hoverDraw :: proc(ctx: ^kit.Context) {
    if hover_show_tree { qtkit.DrawQuadtree(ctx, &hover_tree) }
    for &circle in hover_circles[:hover_used] {
        if !circle.alive { continue }
        kit.DrawCircle(ctx, circle.center, circle.radius, circle.color)
    }
    // what the tree answered for the mouse: the boxes it found, then the circle that really holds the point
    mouse: qt.Vec2 = ctx.input.mouse_position
    buffer: [64]qt.Item
    count: int = qt.QuadtreeQueryPoint(&hover_tree, mouse, buffer[:])
    for i in 0 ..< count {
        kit.DrawRectOutline(ctx, transmute(kit.Rect)circleBox(&hover_circles[buffer[i]]), 1, kit.ORANGE)
    }
    if hover_picked != nil {
        kit.DrawCircle(ctx, hover_picked.center, hover_picked.radius, kit.WHITE)
        kit.DrawCircleOutline(ctx, hover_picked.center, hover_picked.radius, 3, kit.BLACK)
    }
    kit.DrawText(ctx, "hover circles: move the mouse over a circle, LMB spawn, RMB erase, R new random set, G tree", {10, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("circles = %v (tree rebuilt every frame), boxes under the mouse = %v (instead of testing all %v)", hoverCount(), hover_candidates, hoverCount()), {10, 36}, 20, kit.DARK_GRAY)
}

// The middle of the first circle: the script puts the mouse there
hoverAim :: proc(ctx: ^kit.Context) -> bool {
    for &circle in hover_circles[:hover_used] {
        if circle.alive {
            hover_target = circle.center
            return true
        }
    }
    return false
}

hoverScript: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return hoverCount() == CIRCLE_START && qt.QuadtreeLen(&hover_tree) == CIRCLE_START }, "the random set is spawned and in the tree"),
    kit.Check(hoverAim, "there is a circle to point at"),
    kit.MoveAt(&hover_target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if hover_picked == nil { return false }
        offset: qt.Vec2 = hover_target - hover_picked.center
        return offset.x * offset.x + offset.y * offset.y <= hover_picked.radius * hover_picked.radius
    }, "the circle under the mouse is found, and it really holds the mouse"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return hover_candidates >= 1 && hover_candidates < CIRCLE_START / 4 }, "the tree gives a few boxes, not the whole set"),
    kit.MoveTo({-50, -50}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return hover_picked == nil }, "nothing is picked outside of the window"),
    // erase the first circle with the right button, spawn one with the left
    kit.ClickAt(&hover_target, .RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return hoverCount() == CIRCLE_START - 1 && qt.QuadtreeLen(&hover_tree) == CIRCLE_START - 1 }, "the right button erases the circle under the mouse, the tree follows"),
    kit.Click({640, 360}, .LEFT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return hoverCount() == CIRCLE_START && qt.QuadtreeLen(&hover_tree) == CIRCLE_START }, "the left button spawns a circle at the mouse"),
    kit.Tap(.R),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return hoverCount() == CIRCLE_START }, "R makes a new set"),
}
