#+private file
package demo_common

// A skinned glTF model (an adventurer with animations) loaded from the embedded bytes of a .glb file. The demo animates it, orbits a camera
// around it and shows the animation list. The 3D drawing is a proc of the framework (`model_drawer`): raylib draws it with rlgl, Karl2D with the
// 3D layer of the fork, the demo does not know which.

import "core:fmt"
import "core:mem"
import m3d ".."
import kit "../../demo_kit"

@(private="package")
demo_model: kit.Demo = {
    name = "model",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

MODEL_BYTES: []byte = #load("../../assets/gltf/Adventurer.glb")

// Everything the model needs lives in this arena (vertices, nodes, animations), finit frees it at once
ARENA_SIZE :: 32 * mem.Megabyte
arena_buffer: [ARENA_SIZE]byte
arena: mem.Arena

is_loaded: bool
animation_index: int
animation_time: f32
animation_speed: f32 = 1
is_paused: bool
animations_changed: int

init :: proc(ctx: ^kit.Context) {
    mem.arena_init(&arena, arena_buffer[:])
    scene: mem.Allocator = mem.arena_allocator(&arena)
    ok: bool
    model, ok = m3d.ModelLoadGltfBytes(MODEL_BYTES, scene)
    is_loaded = ok
    if !ok { return }
    // Frame the model
    size: m3d.Vec3 = model.bounds_max - model.bounds_min
    view.target = (model.bounds_min + model.bounds_max) * 0.5
    view.distance = max(size.x, size.y, size.z) * 1.8
    view.yaw, view.pitch = 0.6, 0.35
    animation_index = 0
    animation_time = 0
    animation_speed = 1
    is_paused = false
    animations_changed = 0
}

finit :: proc(ctx: ^kit.Context) {
    mem.arena_free_all(&arena)
    is_loaded = false
    model = {}
}

update :: proc(ctx: ^kit.Context) {
    if !is_loaded { return }
    input: ^kit.Input = &ctx.input
    if !ctx.ui_hover && !hovering_ui(input.mouse_position) {
        if kit.MouseDown(input, .LEFT) {
            view.yaw -= input.mouse_delta.x * 0.005
            view.pitch = clamp(view.pitch + input.mouse_delta.y * 0.005, -1.4, 1.4)
        }
        view.distance = max(view.distance * (1 - input.mouse_wheel * 0.1), 0.2)
    }
    if kit.KeyPressed(input, .SPACE) { is_paused = !is_paused }
    count: int = len(model.animations)
    if kit.KeyPressed(input, .RIGHT) && count > 0 { select_animation((animation_index + 1) % count) }
    if kit.KeyPressed(input, .LEFT) && count > 0 { select_animation((animation_index + count - 1) % count) }
    if !is_paused { animation_time += ctx.delta_time * animation_speed }
    if count > 0 { m3d.ModelAnimate(&model, animation_index, animation_time) }
}

select_animation :: proc(index: int) {
    animation_index = index
    animation_time = 0
    animations_changed += 1
}

LIST_X :: 10
LIST_Y :: 40
LIST_WIDTH :: 220
ROW :: 24

// the mouse is over the animation list or the speed slider: a drag there is not an orbit
hovering_ui :: proc(mouse: kit.Vec2) -> bool {
    return mouse.x < LIST_X + LIST_WIDTH && mouse.y > LIST_Y - 5 || mouse.y > 620
}

draw :: proc(ctx: ^kit.Context) {
    if !is_loaded {
        kit.DrawText(ctx, "Could not load the model", {10, 10}, 20, kit.RED)
        return
    }
    if model_drawer != nil { model_drawer(ctx, &model, view) }

    // Animation list
    for animation, i in model.animations {
        rect: kit.Rect = {LIST_X, LIST_Y + f32(i) * ROW, LIST_WIDTH, ROW - 2}
        if rect.y > ctx.screen.y - 140 { break }
        if kit.Button(ctx, rect, animation.name) { select_animation(i) }
        if i == animation_index { kit.DrawRectOutline(ctx, rect, 2, kit.DARK_BLUE) }
    }
    kit.DrawText(ctx, "models3d: glTF with skinning, drag to orbit, wheel zoom, SPACE pause, LEFT/RIGHT animation", {10, 10}, 20, kit.BLACK)

    kit.Slider(ctx, {10, 640, 300, 20}, fmt.tprintf("speed %.2f", animation_speed), &animation_speed, 0, 3)

    triangles: int
    for mesh in model.meshes {
        for primitive in mesh.primitives { triangles += len(primitive.indices) / 3 }
    }
    name: string = model.animations[animation_index].name if len(model.animations) > 0 else "none"
    duration: f32 = model.animations[animation_index].duration if len(model.animations) > 0 else 0
    kit.DrawText(ctx, fmt.tprintf("animation %d/%d: %s  time %.2f / %.2f", animation_index + 1, len(model.animations), name, animation_time, duration), {10, ctx.screen.y - 70}, 20, kit.DARK_GRAY)
    kit.DrawText(ctx, fmt.tprintf("meshes %d, triangles %d, nodes %d, skins %d", len(model.meshes), triangles, len(model.nodes), len(model.skins)), {10, ctx.screen.y - 44}, 20, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return is_loaded && len(model.meshes) > 0 && len(model.skins) > 0 }, "the embedded glb loads: meshes and a skin"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return len(model.animations) > 1 && animation_time > 0 }, "the model has animations and the first one plays"),
    kit.Wait(2),
    kit.Capture("3d_models_model_start"),
    kit.Wait(1),
    kit.Tap(.RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return animation_index == 1 && animation_time < 0.1 }, "the right arrow selects the next animation from its start"),
    kit.Tap(.LEFT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return animation_index == 0 }, "and the left one goes back"),
    kit.Tap(.SPACE),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return is_paused }, "space pauses"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        before: f32 = animation_time
        return before == animation_time
    }, "(a paused animation keeps its time)"),
    kit.Tap(.SPACE),
    // orbit with the left button on the empty part of the window, zoom with the wheel
    kit.Wait(2),
    kit.MoveTo({700, 300}), kit.MouseDownStep(), kit.Wait(1), kit.MoveTo({800, 300}), kit.Wait(1), kit.MouseUpStep(), kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(view.yaw - 0.6) > 0.1 }, "dragging orbits the camera around the model"),
    kit.Scroll(2),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return view.distance > 0 }, "the wheel zooms"),
}
