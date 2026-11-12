package models3d

import "core:encoding/base64"
import "core:strings"
import "core:math"
import "core:mem"
import "core:testing"

// A triangle with an animation that moves the node from x = 0 to x = 2 in one second, as .gltf text with embedded buffer
@(private="file")
TriangleGltf :: proc(allocator := context.allocator) -> []byte {
    buffer: [76]byte
    positions: [9]f32 = {0, 0, 0, 1, 0, 0, 0, 1, 0}
    indices: [3]u16 = {0, 1, 2}
    times: [2]f32 = {0, 1}
    translations: [6]f32 = {0, 0, 0, 2, 0, 0}
    mem.copy(&buffer[0], &positions, 36)
    mem.copy(&buffer[36], &indices, 6)
    mem.copy(&buffer[44], &times, 8)
    mem.copy(&buffer[52], &translations, 24)

    encoded: string = base64.encode(buffer[:], allocator = allocator)
    // Not fmt: braces are placeholders there
    head: string = `{
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "triangle", "mesh": 0}],
        "meshes": [{"name": "mesh", "primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
        "buffers": [{"byteLength": 76, "uri": "data:application/octet-stream;base64,`
    tail: string = `"}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 6},
            {"buffer": 0, "byteOffset": 44, "byteLength": 8},
            {"buffer": 0, "byteOffset": 52, "byteLength": 24}
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"},
            {"bufferView": 2, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
            {"bufferView": 3, "componentType": 5126, "count": 2, "type": "VEC3"}
        ],
        "animations": [{
            "name": "move",
            "samplers": [{"input": 2, "output": 3, "interpolation": "LINEAR"}],
            "channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}]
        }]
    }`
    json: string = strings.concatenate({head, encoded, tail}, allocator)
    return transmute([]byte)json
}

@(test)
test_load_triangle :: proc(t: ^testing.T) {
    source: []byte = TriangleGltf(context.temp_allocator)

    buffer: [64 * mem.Kilobyte]byte
    arena: mem.Arena
    mem.arena_init(&arena, buffer[:])
    model, ok: = ModelLoadGltfBytes(source, mem.arena_allocator(&arena))
    testing.expect(t, ok)
    if !ok { return }

    testing.expect(t, len(model.meshes) == 1 && len(model.meshes[0].primitives) == 1)
    primitive: Primitive = model.meshes[0].primitives[0]
    testing.expect(t, len(primitive.vertices) == 3)
    testing.expect(t, len(primitive.indices) == 3 && primitive.indices[1] == 1 && primitive.indices[2] == 2)
    testing.expect(t, primitive.material == NONE)
    // No normals in the file, counter clockwise triangle gets computed normals along +z
    testing.expect(t, primitive.vertices[0].normal == Vec3{0, 0, 1})
    testing.expect(t, primitive.vertices[1].position == Vec3{1, 0, 0})

    testing.expect(t, len(model.nodes) == 1 && len(model.roots) == 1 && model.roots[0] == 0)
    testing.expect(t, model.nodes[0].name == "triangle" && model.nodes[0].mesh == 0 && model.nodes[0].skin == NONE)
    testing.expect(t, model.bounds_min == Vec3{0, 0, 0} && model.bounds_max == Vec3{1, 1, 0})

    testing.expect(t, len(model.animations) == 1)
    testing.expect(t, model.animations[0].name == "move" && model.animations[0].duration == 1)
    testing.expect(t, ModelFindAnimation(&model, "move") == 0 && ModelFindAnimation(&model, "none") == NONE)

    ModelAnimate(&model, 0, 0.5)
    testing.expect(t, abs(model.nodes[0].translation.x - 1) < 0.0001)
    testing.expect(t, abs(model.nodes[0].world[3][0] - 1) < 0.0001)
    // Looping
    ModelAnimate(&model, 0, 1.25)
    testing.expect(t, abs(model.nodes[0].translation.x - 0.5) < 0.0001)
    // Not looping stays at the end
    ModelAnimate(&model, 0, 5, false)
    testing.expect(t, abs(model.nodes[0].translation.x - 2) < 0.0001)
}

@(test)
test_load_fails_on_garbage :: proc(t: ^testing.T) {
    garbage: []byte = {1, 2, 3, 4, 5, 6, 7, 8}
    _, ok: = ModelLoadGltfBytes(garbage, context.temp_allocator)
    testing.expect(t, !ok)
    _, ok = ModelLoadGltf("does_not_exist.glb", context.temp_allocator)
    testing.expect(t, !ok)
}

@(test)
test_sampler_interpolation :: proc(t: ^testing.T) {
    times: [3]f32 = {0, 1, 2}
    values: [9]f32 = {0, 0, 0, 1, 0, 0, 1, 4, 0}
    sampler: Animation_Sampler = {times = times[:], values = values[:], interpolation = .LINEAR}
    testing.expect(t, SamplerEvaluate(&sampler, 0.5, 3).xyz == Vec3{0.5, 0, 0})
    testing.expect(t, SamplerEvaluate(&sampler, 1.5, 3).xyz == Vec3{1, 2, 0})
    testing.expect(t, SamplerEvaluate(&sampler, -1, 3).xyz == Vec3{0, 0, 0})
    testing.expect(t, SamplerEvaluate(&sampler, 9, 3).xyz == Vec3{1, 4, 0})

    sampler.interpolation = .STEP
    testing.expect(t, SamplerEvaluate(&sampler, 1.5, 3).xyz == Vec3{1, 0, 0})

    // Rotation about z by 90 degrees halfway is 45 degrees
    half: f32 = math.sqrt_f32(0.5)
    rotation_values: [8]f32 = {0, 0, 0, 1, 0, 0, half, half}
    rotation_times: [2]f32 = {0, 1}
    rotation: Animation_Sampler = {times = rotation_times[:], values = rotation_values[:], interpolation = .LINEAR}
    q: Vec4 = SamplerEvaluate(&rotation, 0.5, 4)
    testing.expect(t, abs(q.z - math.sin(f32(math.PI) / 8)) < 0.001 && abs(q.w - math.cos(f32(math.PI) / 8)) < 0.001)
}

// Real model: Adventurer.glb is a skinned character with many animations
@(test)
test_load_adventurer :: proc(t: ^testing.T) {
    @(static) buffer: [16 * mem.Megabyte]byte
    arena: mem.Arena
    mem.arena_init(&arena, buffer[:])
    model, ok: = ModelLoadGltf("../assets/gltf/Adventurer.glb", mem.arena_allocator(&arena))
    testing.expect(t, ok)
    if !ok { return }

    testing.expect(t, len(model.meshes) > 0 && len(model.nodes) > 0 && len(model.roots) > 0)
    testing.expect(t, len(model.skins) > 0 && len(model.animations) > 0)
    for skin in model.skins {
        testing.expect(t, len(skin.joints) > 0 && len(skin.joints) <= MAX_JOINTS)
        testing.expect(t, len(skin.inverse_bind) == len(skin.joints))
    }
    size: Vec3 = model.bounds_max - model.bounds_min
    testing.expect(t, size.x > 0 && size.y > 0 && size.z > 0)

    // Every animation poses the skeleton without producing invalid numbers
    joints: [MAX_JOINTS]Mat4
    for animation, index in model.animations {
        testing.expectf(t, animation.duration > 0, "animation %s has no duration", animation.name)
        for time in ([3]f32{0, animation.duration * 0.5, animation.duration * 2.3}) {
            ModelAnimate(&model, index, time)
            for node in model.nodes {
                testing.expect(t, !math.is_nan(node.world[3][0]) && !math.is_nan(node.world[3][1]) && !math.is_nan(node.world[3][2]))
            }
            for node in model.nodes {
                if node.skin == NONE { continue }
                count: int = ModelSkinMatrices(&model, node.skin, joints[:])
                testing.expect(t, count == len(model.skins[node.skin].joints))
                // A skinned vertex stays near the model
                primitive: Primitive = model.meshes[node.mesh].primitives[0]
                point: Vec3 = VertexSkinPosition(&primitive.vertices[0], joints[:count])
                testing.expect(t, !math.is_nan(point.x) && abs(point.x) < 100 && abs(point.y) < 100 && abs(point.z) < 100)
            }
        }
    }
}
