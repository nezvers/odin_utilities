#+private file
package demo_common

import "core:fmt"
import "core:math"
import "core:math/rand"
import qt ".."
import kit "../../demo_kit"
import qtkit "../kit"

@(private = "package")
demo_retained: kit.Demo = {
    name = "retained crates",
    init = retainedInit,
    update = retainedUpdate,
    draw = retainedDraw,
    script = retainedScript,
}

// The retained tree (quadtree_retained.odin) lives between frames: the crates are added once and stay in it, only the few wanderers are moved with their handle every frame. A rebuilt tree
// would insert every crate again each frame; here the cost follows what changes. LMB adds a crate (a new handle), RMB removes the crate under the mouse (found with a point query).
// The crate a wanderer overlaps is found with a query and lights up.
WANDERERS :: 10
CRATE_START :: 300
CRATE_CAPACITY :: 512
THING_CAPACITY :: WANDERERS + CRATE_CAPACITY
WANDERER_SIZE :: 14.0
WANDERER_SPEED_MIN :: 90.0
WANDERER_SPEED_MAX :: 220.0
CRATE_SIZE_MIN :: 12.0
CRATE_SIZE_MAX :: 36.0
AREA :: qt.Rect{0, 0, 1280, 720}

// Wanderers are the first WANDERERS slots, crates the rest. `handle` is the stable reference into the tree, `Element.ptr` points back here
Thing :: struct {
    handle: qt.Handle,
    rect: qt.Rect,
    velocity: qt.Vec2,
    alive: bool,
    lit: bool,
}

RetainedTree :: qt.QuadtreeRetained(THING_CAPACITY + 1, 2200, 12288)

retained_tree: RetainedTree
retained_things: [THING_CAPACITY]Thing
retained_free: [THING_CAPACITY]int      // slots of removed crates, taken again by the next add
retained_free_count: int
retained_used: int                      // slots handed out so far
retained_seed: rand.Default_Random_State
retained_random: rand.Generator
retained_show_tree: bool

retained_moves: int                     // tree operations of the last frame
retained_lit_events: int                // wanderer touches a crate: counted over time
retained_crates: int
retained_remember: int                  // the script remembers a number here
retained_removed: qt.Handle             // the handle of the crate removed last: stale now

retainedInit :: proc(ctx: ^kit.Context) {
    retained_seed = rand.create(31337)
    retained_random = rand.default_random_generator(&retained_seed)
    retainedReset()
    retained_show_tree = true
}

retainedReset :: proc() {
    qt.QuadtreeRetainedInit(&retained_tree, AREA, 8, 6)
    retained_free_count = 0
    retained_used = WANDERERS
    retained_crates = 0
    retained_lit_events = 0
    for i in 0 ..< WANDERERS {
        angle: f32 = rand.float32(retained_random) * math.TAU
        speed: f32 = WANDERER_SPEED_MIN + rand.float32(retained_random) * (WANDERER_SPEED_MAX - WANDERER_SPEED_MIN)
        thing: ^Thing = &retained_things[i]
        thing^ = {
            rect = {rand.float32(retained_random) * (AREA.w - WANDERER_SIZE), rand.float32(retained_random) * (AREA.h - WANDERER_SIZE), WANDERER_SIZE, WANDERER_SIZE},
            velocity = {math.cos(angle), math.sin(angle)} * speed,
            alive = true,
        }
        ok: bool
        thing.handle, ok = qt.QuadtreeRetainedAdd(&retained_tree, thing.rect, thing)
        assert(ok)
    }
    for _ in 0 ..< CRATE_START {
        size: f32 = CRATE_SIZE_MIN + rand.float32(retained_random) * (CRATE_SIZE_MAX - CRATE_SIZE_MIN)
        retainedAddCrate({rand.float32(retained_random) * (AREA.w - size) + size * 0.5, rand.float32(retained_random) * (AREA.h - size) + size * 0.5}, size)
    }
}

// A crate centered at the point. Returns false when no slot or no storage is left
retainedAddCrate :: proc(center: qt.Vec2, size: f32) -> bool {
    slot: int
    if retained_free_count > 0 {
        slot = retained_free[retained_free_count - 1]
    } else if retained_used < THING_CAPACITY {
        slot = retained_used
    } else {
        return false
    }
    thing: ^Thing = &retained_things[slot]
    rect: qt.Rect = {center.x - size * 0.5, center.y - size * 0.5, size, size}
    handle, ok := qt.QuadtreeRetainedAdd(&retained_tree, rect, thing)
    if !ok { return false }
    if retained_free_count > 0 { retained_free_count -= 1 } else { retained_used += 1 }
    thing^ = {handle = handle, rect = rect, alive = true}
    retained_crates += 1
    return true
}

// The crate under the point, nil for none (wanderers are skipped)
retainedCrateAt :: proc(point: qt.Vec2) -> ^Thing {
    buffer: [32]qt.Handle
    count: int = qt.QuadtreeRetainedQueryPoint(&retained_tree, point, buffer[:])
    for i in 0 ..< count {
        element: ^qt.RetainedElement = qt.QuadtreeRetainedGet(&retained_tree, buffer[i]) or_continue
        thing: ^Thing = cast(^Thing)element.ptr
        if thing != nil && int(uintptr(thing) - uintptr(&retained_things[0])) / size_of(Thing) >= WANDERERS { return thing }
    }
    return nil
}

retainedRemoveCrate :: proc(thing: ^Thing) {
    retained_removed = thing.handle
    qt.QuadtreeRetainedRemove(&retained_tree, thing.handle)
    thing.alive = false
    thing.lit = false
    retained_free[retained_free_count] = int(uintptr(thing) - uintptr(&retained_things[0])) / size_of(Thing)
    retained_free_count += 1
    retained_crates -= 1
}

retainedUpdate :: proc(ctx: ^kit.Context) {
    mouse: qt.Vec2 = ctx.input.mouse_position
    if !ctx.ui_hover {
        if kit.MousePressed(&ctx.input, .LEFT) {
            size: f32 = CRATE_SIZE_MIN + rand.float32(retained_random) * (CRATE_SIZE_MAX - CRATE_SIZE_MIN)
            retainedAddCrate(mouse, size)
        }
        if kit.MousePressed(&ctx.input, .RIGHT) {
            crate: ^Thing = retainedCrateAt(mouse)
            if crate != nil { retainedRemoveCrate(crate) }
        }
    }
    if kit.KeyPressed(&ctx.input, .R) { retainedReset() }
    if kit.KeyPressed(&ctx.input, .G) { retained_show_tree = !retained_show_tree }

    // the only tree work of the frame: move the wanderers
    dt: f32 = min(ctx.delta_time, 1.0 / 30.0)
    retained_moves = 0
    for &thing in retained_things[:WANDERERS] {
        thing.rect.x += thing.velocity.x * dt
        thing.rect.y += thing.velocity.y * dt
        if thing.rect.x < 0 { thing.rect.x = 0; thing.velocity.x = abs(thing.velocity.x) }
        if thing.rect.x > AREA.w - thing.rect.w { thing.rect.x = AREA.w - thing.rect.w; thing.velocity.x = -abs(thing.velocity.x) }
        if thing.rect.y < 0 { thing.rect.y = 0; thing.velocity.y = abs(thing.velocity.y) }
        if thing.rect.y > AREA.h - thing.rect.h { thing.rect.y = AREA.h - thing.rect.h; thing.velocity.y = -abs(thing.velocity.y) }
        qt.QuadtreeRetainedMove(&retained_tree, thing.handle, thing.rect)
        retained_moves += 1
    }
    qt.QuadtreeRetainedCleanup(&retained_tree)

    // crates under a wanderer light up
    for &thing in retained_things[WANDERERS:retained_used] { thing.lit = false }
    buffer: [32]qt.Handle
    for &wanderer in retained_things[:WANDERERS] {
        count: int = qt.QuadtreeRetainedQuery(&retained_tree, wanderer.rect, buffer[:], wanderer.handle)
        for i in 0 ..< count {
            element: ^qt.RetainedElement = qt.QuadtreeRetainedGet(&retained_tree, buffer[i]) or_continue
            thing: ^Thing = cast(^Thing)element.ptr
            if thing != nil && !thing.lit && int(uintptr(thing) - uintptr(&retained_things[0])) / size_of(Thing) >= WANDERERS {
                thing.lit = true
                retained_lit_events += 1
            }
        }
    }
}

retainedDraw :: proc(ctx: ^kit.Context) {
    if retained_show_tree { qtkit.DrawQuadtreeRetained(ctx, &retained_tree) }
    for &thing in retained_things[WANDERERS:retained_used] {
        if !thing.alive { continue }
        kit.DrawRect(ctx, transmute(kit.Rect)thing.rect, kit.ORANGE if thing.lit else kit.Color{130, 130, 130, 255})
        kit.DrawRectOutline(ctx, transmute(kit.Rect)thing.rect, 1, kit.DARK_GRAY)
    }
    for &thing in retained_things[:WANDERERS] {
        kit.DrawRect(ctx, transmute(kit.Rect)thing.rect, kit.Color{50, 100, 230, 255})
        kit.DrawRectOutline(ctx, transmute(kit.Rect)thing.rect, 2, kit.BLACK)
    }
    nodes, links := qt.QuadtreeRetainedUsage(&retained_tree)
    kit.DrawText(ctx, "retained crates: blue wanderers are moved in the tree, LMB add a crate, RMB remove, R reset, G tree", {10, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("crates = %v, tree operations this frame = %v moves (a rebuilt tree would insert %v), nodes = %v, links = %v", retained_crates, retained_moves, retained_crates + WANDERERS, nodes, links), {10, 36}, 20, kit.DARK_GRAY)
}

// The tree holds exactly the live things, and every wanderer's rectangle in the tree is the one it has
retainedConsistent :: proc(ctx: ^kit.Context) -> bool {
    if int(qt.QuadtreeRetainedLen(&retained_tree)) != retained_crates + WANDERERS { return false }
    for &wanderer in retained_things[:WANDERERS] {
        element: ^qt.RetainedElement = qt.QuadtreeRetainedGet(&retained_tree, wanderer.handle) or_return
        if element.rect != wanderer.rect { return false }
    }
    everything: [THING_CAPACITY]qt.Handle
    return qt.QuadtreeRetainedQuery(&retained_tree, AREA, everything[:]) == retained_crates + WANDERERS
}

retainedScript: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return retained_crates == CRATE_START && retainedConsistent(ctx) }, "the crates and wanderers are added once and are in the tree"),
    kit.Wait(180),
    kit.Check(retainedConsistent, "after three seconds of moving only the wanderers the tree is still exact"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return retained_moves == WANDERERS && retained_lit_events > 0 }, "a frame moves only the wanderers, and they found crates to light up"),
    // add a crate with the left button, remove it with the right button: the old handle must be stale
    kit.Check(proc(ctx: ^kit.Context) -> bool { retained_remember = retained_crates; return true }, "remember the number of crates"),
    kit.Click({640, 360}, .LEFT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return retained_crates == retained_remember + 1 && retainedConsistent(ctx) }, "the left button adds a crate to the tree"),
    kit.Click({640, 360}, .RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return retained_crates == retained_remember && retainedConsistent(ctx) }, "the right button removes the crate under the mouse"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        _, found := qt.QuadtreeRetainedGet(&retained_tree, retained_removed)
        return !found
    }, "the handle of the removed crate is stale"),
    kit.Tap(.R),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return retained_crates == CRATE_START && retainedConsistent(ctx) }, "R starts again"),
}
