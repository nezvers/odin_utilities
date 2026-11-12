#+private file
package demo_raylib

import "core:math"
import "core:mem"
import "core:strings"
import m3d ".."
import glue "../raylib"
import rl "vendor:raylib"

@(private="package")
state_model:State = {
    enter,
    exit,
    update,
    draw,
}

MODEL_PATH :: "../assets/gltf/Adventurer.glb"

// Everything the model needs lives in this arena (vertices, nodes, animations, button names), exit frees it at once
ARENA_SIZE :: 32 * mem.Megabyte
arena_buffer: [ARENA_SIZE]byte
arena: mem.Arena

model: m3d.Model
is_loaded: bool
textures: []rl.Texture2D
animation_names: []cstring

animation_index: int
animation_time: f32
animation_speed: f32 = 1
is_hovering_ui: bool
is_paused: bool

// Orbit camera
camera: rl.Camera3D = {up = {0, 1, 0}, fovy = 45, projection = .PERSPECTIVE}
yaw: f32 = 0.6
pitch: f32 = 0.35
distance: f32 = 4
target: rl.Vector3

enter :: proc() {
    mem.arena_init(&arena, arena_buffer[:])
    scene: mem.Allocator = mem.arena_allocator(&arena)

    ok: bool
    model, ok = m3d.ModelLoadGltf(MODEL_PATH, scene)
    is_loaded = ok
    if !ok { return }

    textures = make([]rl.Texture2D, len(model.images), scene)
    glue.LoadTextures(&model, textures)

    animation_names = make([]cstring, len(model.animations), scene)
    for animation, i in model.animations {
        animation_names[i] = strings.clone_to_cstring(animation.name, scene)
    }

    // Frame the model
    box: rl.BoundingBox = glue.ModelBoundingBox(&model)
    target = (box.min + box.max) * 0.5
    size: rl.Vector3 = box.max - box.min
    distance = max(size.x, size.y, size.z) * 1.8

    animation_index = 0
    animation_time = 0
    is_paused = false
}

exit :: proc() {
    if is_loaded {
        glue.UnloadTextures(textures)
    }
    mem.arena_free_all(&arena)
    is_loaded = false
    model = {}
}

update :: proc() {
    if !is_loaded { return }

    if !is_hovering_ui {
        if rl.IsMouseButtonDown(.LEFT) {
            delta: rl.Vector2 = rl.GetMouseDelta()
            yaw -= delta.x * 0.005
            pitch = clamp(pitch + delta.y * 0.005, -1.4, 1.4)
        }
        distance = max(distance * (1 - rl.GetMouseWheelMove() * 0.1), 0.2)
    }
    if rl.IsKeyPressed(.SPACE) { is_paused = !is_paused }
    if rl.IsKeyPressed(.RIGHT) && len(model.animations) > 0 { select_animation((animation_index + 1) % len(model.animations)) }
    if rl.IsKeyPressed(.LEFT) && len(model.animations) > 0 { select_animation((animation_index + len(model.animations) - 1) % len(model.animations)) }

    if !is_paused {
        animation_time += rl.GetFrameTime() * animation_speed
    }
    if len(model.animations) > 0 {
        m3d.ModelAnimate(&model, animation_index, animation_time)
    }

    camera.target = target
    camera.position = target + rl.Vector3{
        distance * math.cos(pitch) * math.sin(yaw),
        distance * math.sin(pitch),
        distance * math.cos(pitch) * math.cos(yaw),
    }
}

select_animation :: proc(index: int) {
    animation_index = index
    animation_time = 0
}

draw :: proc() {
    if !is_loaded {
        rl.DrawText("Could not load " + MODEL_PATH, 10, 10, 20, rl.RED)
        return
    }

    rl.BeginMode3D(camera)
    rl.DrawGrid(20, 1)
    glue.DrawModel(&model, textures)
    rl.EndMode3D()

    // Animation list
    is_hovering_ui = false
    mouse: rl.Vector2 = rl.GetMousePosition()
    button: rl.Rectangle = {10, 40, 220, 22}
    for name, i in animation_names {
        if button.y > screen_size.y - 120 { break }
        if rl.GuiButton(button, name) {
            select_animation(i)
        }
        if i == animation_index {
            rl.DrawRectangleLinesEx(button, 2, rl.DARKBLUE)
        }
        if rl.CheckCollisionPointRec(mouse, button) { is_hovering_ui = true }
        button.y += button.height + 2
    }

    rl.DrawText("models3d: glTF with skinning, drag to orbit, wheel zoom, SPACE pause, LEFT/RIGHT animation", 10, 10, 20, rl.BLACK)

    speed_rect: rl.Rectangle = {120, screen_size.y - 100, 200, 20}
    rl.GuiSlider(speed_rect, "speed", rl.TextFormat("%.2f", animation_speed), &animation_speed, 0, 3)
    if rl.CheckCollisionPointRec(mouse, speed_rect) { is_hovering_ui = true }

    triangles: int
    for mesh in model.meshes {
        for primitive in mesh.primitives { triangles += len(primitive.indices) / 3 }
    }
    name: cstring = animation_names[animation_index] if len(animation_names) > 0 else "none"
    rl.DrawText(rl.TextFormat("animation %d/%d: %s  time %.2f / %.2f", i32(animation_index + 1), i32(len(model.animations)), name, animation_time, model.animations[animation_index].duration if len(model.animations) > 0 else 0), 10, i32(screen_size.y) - 70, 20, rl.DARKGRAY)
    rl.DrawText(rl.TextFormat("meshes %d, triangles %d, nodes %d, skins %d", i32(len(model.meshes)), i32(triangles), i32(len(model.nodes)), i32(len(model.skins))), 10, i32(screen_size.y) - 44, 20, rl.DARKGRAY)
}
