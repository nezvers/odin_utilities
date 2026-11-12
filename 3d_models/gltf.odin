// Engine and framework agnostic glTF 2.0 / GLB model loading and animation.
// Parsing is done by vendor:cgltf, data is copied into plain Odin structs (vertices, indices, nodes, skins, animations)
// that a glue package (raylib/) turns into drawing. Reference: third_party/gltf (gltf_example_odin).
//
// Memory: every slice and string of a Model is allocated with the allocator given to ModelLoadGltf.
// Use an arena (core:mem Arena over a buffer, or virtual arena) and free it with the scene, or call ModelDestroy.
// Animation and skinning work in place on the nodes and in buffers provided by the caller, nothing allocates per frame.
package models3d

import "base:runtime"
import "core:math/linalg"
import "core:strings"
import gltf2 "glTF2"

Vec3 :: [3]f32
Vec4 :: [4]f32
Quat :: quaternion128
Mat4 :: matrix[4, 4]f32

// Joint count that glue code can keep in fixed size buffers
MAX_JOINTS :: 128

NONE :: -1

Vertex :: struct {
    position: Vec3,
    normal: Vec3,
    uv: [2]f32,
    joints: [4]u16,     // indices into Skin.joints
    weights: Vec4,
}

Primitive :: struct {
    vertices: []Vertex,
    indices: []u32,     // triangle list
    material: int,      // NONE if the primitive has no material
}

Mesh :: struct {
    name: string,
    primitives: []Primitive,
}

Alpha_Mode :: enum {
    OPAQUE,
    MASK,
    BLEND,
}

Material :: struct {
    name: string,
    base_color: Vec4,           // factor
    base_color_image: int,      // index into Model.images or NONE
    metallic: f32,
    roughness: f32,
    emissive: Vec3,
    alpha_mode: Alpha_Mode,
    alpha_cutoff: f32,
    double_sided: bool,
}

// Image is stored as file bytes (PNG/JPEG) when it is embedded in the model, otherwise only the uri is known.
Image :: struct {
    name: string,
    uri: string,
    mime_type: string,
    data: []byte,
}

Node :: struct {
    name: string,
    parent: int,            // NONE for roots
    children: []int,
    mesh: int,              // NONE if the node has no mesh
    skin: int,              // NONE if the node has no skin
    // Local transform. Animation changes translation, rotation and scale.
    translation: Vec3,
    rotation: Quat,
    scale: Vec3,
    has_matrix: bool,       // local transform is `matrix_` instead of TRS
    matrix_: Mat4,
    world: Mat4,            // updated by ModelUpdateNodes
}

Skin :: struct {
    name: string,
    joints: []int,          // node indices
    inverse_bind: []Mat4,   // one per joint, identity if the file doesn't have them
}

Interpolation :: enum {
    LINEAR,
    STEP,
    CUBIC_SPLINE,
}

Animation_Path :: enum {
    TRANSLATION,
    ROTATION,
    SCALE,
    WEIGHTS,    // morph targets are not supported, the channel is ignored
}

// values hold 3 floats per key for translation and scale and 4 for rotation, cubic spline has 3 values per key
// (in tangent, value, out tangent)
Animation_Sampler :: struct {
    times: []f32,
    values: []f32,
    interpolation: Interpolation,
}

Animation_Channel :: struct {
    sampler: int,
    node: int,
    path: Animation_Path,
}

Animation :: struct {
    name: string,
    duration: f32,
    samplers: []Animation_Sampler,
    channels: []Animation_Channel,
}

Model :: struct {
    meshes: []Mesh,
    materials: []Material,
    images: []Image,
    nodes: []Node,
    skins: []Skin,
    animations: []Animation,
    roots: []int,           // nodes without parent
    bounds_min: Vec3,       // of the model in rest pose
    bounds_max: Vec3,
}

// ------------------------------------------------------------------------------------------------
// Loading
// ------------------------------------------------------------------------------------------------

// Load .gltf or .glb file. External buffers are read relative to the file.
// The parser (glTF2 package) allocates its temporary data with context.allocator and frees it before returning,
// only the Model is allocated with `allocator`.
ModelLoadGltf :: proc(path: string, allocator := context.allocator) -> (model: Model, ok: bool) {
    data, err: = gltf2.load_from_file(path)
    if err != nil {
        return
    }
    defer gltf2.unload(data)
    return ModelFromGltf(data, allocator)
}

// Load from memory, for example `#load("model.glb")`. Buffers that point to files are not supported.
ModelLoadGltfBytes :: proc(bytes: []byte, allocator := context.allocator) -> (model: Model, ok: bool) {
    options: gltf2.Options
    // GLB files start with "glTF"
    options.is_glb = len(bytes) >= 4 && bytes[0] == 'g' && bytes[1] == 'l' && bytes[2] == 'T' && bytes[3] == 'F'
    data, err: = gltf2.parse(bytes, options)
    if err != nil {
        return
    }
    defer gltf2.unload(data)
    return ModelFromGltf(data, allocator)
}

// Release memory when the model was not allocated from an arena
ModelDestroy :: proc(model: ^Model, allocator := context.allocator) {
    for mesh in model.meshes {
        for primitive in mesh.primitives {
            delete(primitive.vertices, allocator)
            delete(primitive.indices, allocator)
        }
        delete(mesh.primitives, allocator)
        delete(mesh.name, allocator)
    }
    for material in model.materials { delete(material.name, allocator) }
    for image in model.images {
        delete(image.name, allocator)
        delete(image.uri, allocator)
        delete(image.mime_type, allocator)
        delete(image.data, allocator)
    }
    for node in model.nodes {
        delete(node.name, allocator)
        delete(node.children, allocator)
    }
    for skin in model.skins {
        delete(skin.name, allocator)
        delete(skin.joints, allocator)
        delete(skin.inverse_bind, allocator)
    }
    for animation in model.animations {
        for sampler in animation.samplers {
            delete(sampler.times, allocator)
            delete(sampler.values, allocator)
        }
        delete(animation.samplers, allocator)
        delete(animation.channels, allocator)
        delete(animation.name, allocator)
    }
    delete(model.meshes, allocator)
    delete(model.materials, allocator)
    delete(model.images, allocator)
    delete(model.nodes, allocator)
    delete(model.skins, allocator)
    delete(model.animations, allocator)
    delete(model.roots, allocator)
    model^ = {}
}

@(private="file")
CloneName :: proc(name: Maybe(string), allocator: runtime.Allocator) -> string {
    text: string = name.? or_else ""
    return strings.clone(text, allocator)
}

// Convert parsed glTF2 data into a Model
ModelFromGltf :: proc(data: ^gltf2.Data, allocator := context.allocator) -> (model: Model, ok: bool) {
    model.materials = make([]Material, len(data.materials), allocator)
    for material, i in data.materials {
        out: ^Material = &model.materials[i]
        out^ = {
            name = CloneName(material.name, allocator),
            base_color = {1, 1, 1, 1},
            base_color_image = NONE,
            metallic = 1,
            roughness = 1,
            alpha_cutoff = material.alpha_cutoff if material.alpha_cutoff > 0 else 0.5,
            double_sided = material.double_sided,
            emissive = material.emissive_factor,
        }
        if pbr, has_pbr := material.metallic_roughness.?; has_pbr {
            out.base_color = pbr.base_color_factor
            out.metallic = pbr.metallic_factor
            out.roughness = pbr.roughness_factor
            if info, has_texture := pbr.base_color_texture.?; has_texture && int(info.index) < len(data.textures) {
                if source, has_source := data.textures[info.index].source.?; has_source {
                    out.base_color_image = int(source)
                }
            }
        }
        #partial switch material.alpha_mode {
        case .Mask, .Alpha_Cutoff: out.alpha_mode = .MASK
        case .Blend: out.alpha_mode = .BLEND
        case: out.alpha_mode = .OPAQUE
        }
    }

    model.images = make([]Image, len(data.images), allocator)
    for image, i in data.images {
        out: ^Image = &model.images[i]
        out.name = CloneName(image.name, allocator)
        if type, has_type := image.type.?; has_type {
            out.mime_type = strings.clone("image/jpeg" if type == .JPEG else "image/png", allocator)
        }
        if view_index, has_view := image.buffer_view.?; has_view {
            bytes, found: = BufferViewBytes(data, int(view_index))
            if found {
                out.data = make([]byte, len(bytes), allocator)
                copy(out.data, bytes)
            }
        } else if uri_bytes, is_bytes := image.uri.([]byte); is_bytes {
            out.data = make([]byte, len(uri_bytes), allocator)
            copy(out.data, uri_bytes)
        } else if uri, is_string := image.uri.(string); is_string {
            out.uri = strings.clone(uri, allocator)
        }
    }

    model.meshes = make([]Mesh, len(data.meshes), allocator)
    for mesh, mesh_index in data.meshes {
        out_mesh: ^Mesh = &model.meshes[mesh_index]
        out_mesh.name = CloneName(mesh.name, allocator)

        count: int
        for primitive in mesh.primitives {
            if primitive.mode == .Triangles { count += 1 }
        }
        out_mesh.primitives = make([]Primitive, count, allocator)

        index: int
        for primitive in mesh.primitives {
            if primitive.mode != .Triangles { continue }
            out_mesh.primitives[index] = PrimitiveFromGltf(data, primitive, allocator) or_return
            index += 1
        }
    }

    model.nodes = make([]Node, len(data.nodes), allocator)
    for node, i in data.nodes {
        out: ^Node = &model.nodes[i]
        out^ = {
            name = CloneName(node.name, allocator),
            parent = NONE,
            mesh = NONE,
            skin = NONE,
            translation = node.translation,
            rotation = node.rotation,
            scale = node.scale,
            matrix_ = node.mat,
            world = 1,
        }
        // The parser fills the matrix with identity when the file has none
        out.has_matrix = node.mat != Mat4(1)
        if mesh, has_mesh := node.mesh.?; has_mesh { out.mesh = int(mesh) }
        if skin, has_skin := node.skin.?; has_skin { out.skin = int(skin) }
        out.children = make([]int, len(node.children), allocator)
        for child, child_index in node.children {
            out.children[child_index] = int(child)
        }
    }
    // glTF nodes only know their children
    for node, i in model.nodes {
        for child in node.children {
            model.nodes[child].parent = i
        }
    }
    root_count: int
    for node in model.nodes {
        if node.parent == NONE { root_count += 1 }
    }
    model.roots = make([]int, root_count, allocator)
    root_index: int
    for node, i in model.nodes {
        if node.parent == NONE {
            model.roots[root_index] = i
            root_index += 1
        }
    }

    model.skins = make([]Skin, len(data.skins), allocator)
    for skin, i in data.skins {
        out: ^Skin = &model.skins[i]
        out.name = CloneName(skin.name, allocator)
        out.joints = make([]int, len(skin.joints), allocator)
        out.inverse_bind = make([]Mat4, len(skin.joints), allocator)
        for joint, joint_index in skin.joints {
            out.joints[joint_index] = int(joint)
            out.inverse_bind[joint_index] = 1
        }
        if accessor_index, has_matrices := skin.inverse_bind_matrices.?; has_matrices {
            view, view_ok: = AccessorViewMake(data, int(accessor_index))
            if view_ok && view.components == 16 {
                for joint_index in 0..<min(len(skin.joints), view.count) {
                    // Column-major like Odin matrices
                    values: [16]f32
                    AccessorViewReadFloats(&view, joint_index, values[:])
                    out.inverse_bind[joint_index] = transmute(Mat4)values
                }
            }
        }
    }

    model.animations = make([]Animation, len(data.animations), allocator)
    for animation, i in data.animations {
        out: ^Animation = &model.animations[i]
        out.name = CloneName(animation.name, allocator)
        out.samplers = make([]Animation_Sampler, len(animation.samplers), allocator)
        for sampler, sampler_index in animation.samplers {
            out_sampler: ^Animation_Sampler = &out.samplers[sampler_index]
            out_sampler.interpolation = Interpolation(int(sampler.interpolation))

            times, times_ok: = AccessorViewMake(data, int(sampler.input))
            values, values_ok: = AccessorViewMake(data, int(sampler.output))
            if !times_ok || !values_ok {
                return
            }
            out_sampler.times = make([]f32, times.count, allocator)
            for key in 0..<times.count {
                AccessorViewReadFloats(&times, key, out_sampler.times[key:key + 1])
            }
            if len(out_sampler.times) > 0 {
                out.duration = max(out.duration, out_sampler.times[len(out_sampler.times) - 1])
            }
            out_sampler.values = make([]f32, values.count * values.components, allocator)
            for key in 0..<values.count {
                AccessorViewReadFloats(&values, key, out_sampler.values[key * values.components:(key + 1) * values.components])
            }
        }

        out.channels = make([]Animation_Channel, len(animation.channels), allocator)
        for channel, channel_index in animation.channels {
            node: int = NONE
            if target_node, has_node := channel.target.node.?; has_node { node = int(target_node) }
            out.channels[channel_index] = {
                sampler = int(channel.sampler),
                node = node,
                path = Animation_Path(int(channel.target.path)),
            }
        }
    }

    ModelUpdateNodes(&model)
    model.bounds_min, model.bounds_max = ModelComputeBounds(&model)
    ok = true
    return
}

@(private="file")
PrimitiveFromGltf :: proc(data: ^gltf2.Data, primitive: gltf2.Mesh_Primitive, allocator: runtime.Allocator) -> (result: Primitive, ok: bool) {
    position_index, has_position: = primitive.attributes["POSITION"]
    if !has_position {
        return
    }
    position, position_ok: = AccessorViewMake(data, int(position_index))
    if !position_ok || position.components != 3 {
        return
    }

    normal, has_normal: = AccessorViewFind(data, primitive, "NORMAL")
    uv, has_uv: = AccessorViewFind(data, primitive, "TEXCOORD_0")
    joints, has_joints: = AccessorViewFind(data, primitive, "JOINTS_0")
    weights, has_weights: = AccessorViewFind(data, primitive, "WEIGHTS_0")

    result.material = NONE
    if material, has_material: = primitive.material.?; has_material {
        result.material = int(material)
    }

    result.vertices = make([]Vertex, position.count, allocator)
    for i in 0..<position.count {
        vertex: ^Vertex = &result.vertices[i]
        AccessorViewReadFloats(&position, i, vertex.position[:])
        if has_normal && normal.components == 3 { AccessorViewReadFloats(&normal, i, vertex.normal[:]) }
        if has_uv && uv.components == 2 { AccessorViewReadFloats(&uv, i, vertex.uv[:]) }
        if has_joints && joints.components == 4 {
            raw: [4]u32
            AccessorViewReadUints(&joints, i, raw[:])
            vertex.joints = {u16(raw[0]), u16(raw[1]), u16(raw[2]), u16(raw[3])}
        }
        if has_weights && weights.components == 4 { AccessorViewReadFloats(&weights, i, vertex.weights[:]) }
    }

    if indices_index, has_indices: = primitive.indices.?; has_indices {
        indices, indices_ok: = AccessorViewMake(data, int(indices_index))
        if !indices_ok || indices.components != 1 {
            return
        }
        result.indices = make([]u32, indices.count, allocator)
        for i in 0..<indices.count {
            index: [1]u32
            AccessorViewReadUints(&indices, i, index[:])
            result.indices[i] = index[0]
        }
    } else {
        result.indices = make([]u32, position.count, allocator)
        for i in 0..<position.count {
            result.indices[i] = u32(i)
        }
    }

    if !has_normal {
        PrimitiveComputeNormals(&result)
    }
    ok = true
    return
}

// ------------------------------------------------------------------------------------------------
// Accessors, with byte stride and normalized integer support
// ------------------------------------------------------------------------------------------------

AccessorView :: struct {
    base: [^]byte,
    stride: int,
    count: int,
    components: int,
    component_type: gltf2.Component_Type,
    normalized: bool,
}

@(private="file")
BufferViewBytes :: proc(data: ^gltf2.Data, view_index: int) -> (bytes: []byte, ok: bool) {
    if view_index < 0 || view_index >= len(data.buffer_views) { return }
    view: gltf2.Buffer_View = data.buffer_views[view_index]
    if int(view.buffer) >= len(data.buffers) { return }
    buffer: []byte = data.buffers[view.buffer].uri.([]byte) or_return
    start: int = int(view.byte_offset)
    end: int = start + int(view.byte_length)
    if end > len(buffer) { return }
    return buffer[start:end], true
}

AccessorViewMake :: proc(data: ^gltf2.Data, accessor_index: int) -> (view: AccessorView, ok: bool) {
    if accessor_index < 0 || accessor_index >= len(data.accessors) { return }
    accessor: gltf2.Accessor = data.accessors[accessor_index]

    switch accessor.type {
    case .Scalar: view.components = 1
    case .Vector2: view.components = 2
    case .Vector3: view.components = 3
    case .Vector4: view.components = 4
    case .Matrix2: view.components = 4
    case .Matrix3: view.components = 9
    case .Matrix4: view.components = 16
    }
    component_size: int
    switch accessor.component_type {
    case .Byte, .Unsigned_Byte: component_size = 1
    case .Short, .Unsigned_Short: component_size = 2
    case .Unsigned_Int, .Float: component_size = 4
    }
    view.count = int(accessor.count)
    view.component_type = accessor.component_type
    view.normalized = accessor.normalized

    // Accessors without buffer view and sparse accessors are not supported
    view_index, has_view: = accessor.buffer_view.?
    if !has_view || int(view_index) >= len(data.buffer_views) { return }
    buffer_view: gltf2.Buffer_View = data.buffer_views[view_index]
    if int(buffer_view.buffer) >= len(data.buffers) { return }
    buffer: []byte = data.buffers[buffer_view.buffer].uri.([]byte) or_return

    element_size: int = view.components * component_size
    view.stride = int(buffer_view.byte_stride.? or_else gltf2.Integer(element_size))
    offset: int = int(buffer_view.byte_offset) + int(accessor.byte_offset)
    if view.count > 0 && offset + (view.count - 1) * view.stride + element_size > len(buffer) { return }
    view.base = raw_data(buffer[offset:]) if view.count > 0 else nil
    ok = true
    return
}

@(private="file")
AccessorViewFind :: proc(data: ^gltf2.Data, primitive: gltf2.Mesh_Primitive, name: string) -> (view: AccessorView, ok: bool) {
    index: gltf2.Integer = primitive.attributes[name] or_return
    return AccessorViewMake(data, int(index))
}

// Read an element as floats (integer components are converted, normalized ones to 0..1 or -1..1)
AccessorViewReadFloats :: proc(view: ^AccessorView, index: int, out: []f32) {
    element: [^]byte = view.base[index * view.stride:]
    for i in 0..<min(view.components, len(out)) {
        switch view.component_type {
        case .Float:
            out[i] = (cast(^f32)&element[i * 4])^
        case .Unsigned_Byte:
            value: f32 = f32(element[i])
            out[i] = value / 255 if view.normalized else value
        case .Byte:
            value: f32 = f32((cast(^i8)&element[i])^)
            out[i] = max(value / 127, -1) if view.normalized else value
        case .Unsigned_Short:
            value: f32 = f32((cast(^u16le)&element[i * 2])^)
            out[i] = value / 65535 if view.normalized else value
        case .Short:
            value: f32 = f32((cast(^i16le)&element[i * 2])^)
            out[i] = max(value / 32767, -1) if view.normalized else value
        case .Unsigned_Int:
            out[i] = f32((cast(^u32le)&element[i * 4])^)
        }
    }
}

// Read an element of unsigned integers, for indices and joints
AccessorViewReadUints :: proc(view: ^AccessorView, index: int, out: []u32) {
    element: [^]byte = view.base[index * view.stride:]
    for i in 0..<min(view.components, len(out)) {
        switch view.component_type {
        case .Unsigned_Byte, .Byte: out[i] = u32(element[i])
        case .Unsigned_Short, .Short: out[i] = u32((cast(^u16le)&element[i * 2])^)
        case .Unsigned_Int: out[i] = u32((cast(^u32le)&element[i * 4])^)
        case .Float: out[i] = u32((cast(^f32)&element[i * 4])^)
        }
    }
}
// Smooth normals from triangle faces, used when the file doesn't have normals
PrimitiveComputeNormals :: proc(primitive: ^Primitive) {
    for &vertex in primitive.vertices {
        vertex.normal = {}
    }
    for i := 0; i + 2 < len(primitive.indices); i += 3 {
        a: ^Vertex = &primitive.vertices[primitive.indices[i]]
        b: ^Vertex = &primitive.vertices[primitive.indices[i + 1]]
        c: ^Vertex = &primitive.vertices[primitive.indices[i + 2]]
        face: Vec3 = linalg.cross(b.position - a.position, c.position - a.position)
        a.normal += face
        b.normal += face
        c.normal += face
    }
    for &vertex in primitive.vertices {
        if linalg.length2(vertex.normal) > 0 {
            vertex.normal = linalg.normalize(vertex.normal)
        }
    }
}

// ------------------------------------------------------------------------------------------------
// Nodes
// ------------------------------------------------------------------------------------------------

NodeLocalMatrix :: proc(node: ^Node) -> Mat4 {
    if node.has_matrix {
        return node.matrix_
    }
    return linalg.matrix4_translate(node.translation) * linalg.matrix4_from_quaternion(node.rotation) * linalg.matrix4_scale(node.scale)
}

// Recalculate world matrices of all nodes from their local transforms. Parents are always before children
// in glTF files written by exporters, but not required, so this walks from the roots.
ModelUpdateNodes :: proc(model: ^Model) {
    for root in model.roots {
        NodeUpdateWorld(model, root, 1)
    }
}

@(private="file")
NodeUpdateWorld :: proc(model: ^Model, index: int, parent_world: Mat4) {
    node: ^Node = &model.nodes[index]
    node.world = parent_world * NodeLocalMatrix(node)
    for child in node.children {
        NodeUpdateWorld(model, child, node.world)
    }
}

// Bounds of all mesh vertices in the current pose, skinned meshes are measured without skinning
ModelComputeBounds :: proc(model: ^Model) -> (low: Vec3, high: Vec3) {
    low = {max(f32), max(f32), max(f32)}
    high = {min(f32), min(f32), min(f32)}
    found: bool
    for node in model.nodes {
        if node.mesh == NONE { continue }
        world: Mat4 = node.world if node.skin == NONE else 1
        for primitive in model.meshes[node.mesh].primitives {
            for vertex in primitive.vertices {
                point: Vec3 = (world * Vec4{vertex.position.x, vertex.position.y, vertex.position.z, 1}).xyz
                low = linalg.min(low, point)
                high = linalg.max(high, point)
                found = true
            }
        }
    }
    if !found { low, high = {}, {} }
    return
}

// ------------------------------------------------------------------------------------------------
// Animation and skinning
// ------------------------------------------------------------------------------------------------

// Pose nodes at time (seconds) of the animation and update world matrices. Time loops when `looped`.
ModelAnimate :: proc(model: ^Model, animation_index: int, time: f32, looped: bool = true) {
    if animation_index < 0 || animation_index >= len(model.animations) { return }
    animation: ^Animation = &model.animations[animation_index]

    t: f32 = time
    if animation.duration > 0 {
        t = linalg.mod(time, animation.duration) if looped else clamp(time, 0, animation.duration)
    }

    for channel in animation.channels {
        if channel.node == NONE || channel.sampler < 0 { continue }
        sampler: ^Animation_Sampler = &animation.samplers[channel.sampler]
        node: ^Node = &model.nodes[channel.node]
        switch channel.path {
        case .TRANSLATION:
            node.translation = SamplerEvaluate(sampler, t, 3).xyz
            node.has_matrix = false
        case .ROTATION:
            q: Vec4 = SamplerEvaluate(sampler, t, 4)
            node.rotation = linalg.normalize(quaternion(x = q.x, y = q.y, z = q.z, w = q.w))
            node.has_matrix = false
        case .SCALE:
            node.scale = SamplerEvaluate(sampler, t, 3).xyz
            node.has_matrix = false
        case .WEIGHTS:
        }
    }
    ModelUpdateNodes(model)
}

// Value of a sampler at time. components is 3 (translation, scale) or 4 (rotation).
SamplerEvaluate :: proc(sampler: ^Animation_Sampler, time: f32, components: int) -> (result: Vec4) {
    count: int = len(sampler.times)
    if count == 0 { return }

    stride: int = components * 3 if sampler.interpolation == .CUBIC_SPLINE else components
    // Value of key `key`, cubic spline has tangents around the value
    value_offset :: proc(key: int, components: int, stride: int, cubic: bool) -> int {
        return key * stride + (components if cubic else 0)
    }
    cubic: bool = sampler.interpolation == .CUBIC_SPLINE

    read :: proc(values: []f32, offset: int, components: int) -> (v: Vec4) {
        for i in 0..<components { v[i] = values[offset + i] }
        return
    }

    if count == 1 || time <= sampler.times[0] {
        return read(sampler.values, value_offset(0, components, stride, cubic), components)
    }
    if time >= sampler.times[count - 1] {
        return read(sampler.values, value_offset(count - 1, components, stride, cubic), components)
    }

    // Find key with times[key] <= time < times[key + 1]
    key: int
    for key + 2 < count && time >= sampler.times[key + 1] {
        key += 1
    }
    delta: f32 = sampler.times[key + 1] - sampler.times[key]
    s: f32 = (time - sampler.times[key]) / delta if delta > 0 else 0

    v0: Vec4 = read(sampler.values, value_offset(key, components, stride, cubic), components)
    v1: Vec4 = read(sampler.values, value_offset(key + 1, components, stride, cubic), components)

    switch sampler.interpolation {
    case .STEP:
        return v0
    case .LINEAR:
        if components == 4 {
            q0: Quat = quaternion(x = v0.x, y = v0.y, z = v0.z, w = v0.w)
            q1: Quat = quaternion(x = v1.x, y = v1.y, z = v1.z, w = v1.w)
            q: Quat = linalg.quaternion_slerp(q0, q1, s)
            return {q.x, q.y, q.z, q.w}
        }
        return v0 + (v1 - v0) * s
    case .CUBIC_SPLINE:
        out_tangent0: Vec4 = read(sampler.values, key * stride + 2 * components, components)
        in_tangent1: Vec4 = read(sampler.values, (key + 1) * stride, components)
        s2: f32 = s * s
        s3: f32 = s2 * s
        result = (2 * s3 - 3 * s2 + 1) * v0 + (s3 - 2 * s2 + s) * delta * out_tangent0 + (-2 * s3 + 3 * s2) * v1 + (s3 - s2) * delta * in_tangent1
        if components == 4 {
            result = linalg.normalize(result)
        }
        return
    }
    return
}

// Joint matrices (world matrix of joint * inverse bind matrix) of a skin for the current pose.
// out has to be at least len(skin.joints) long, returns the count written. Use MAX_JOINTS for fixed buffers.
ModelSkinMatrices :: proc(model: ^Model, skin_index: int, out: []Mat4) -> int {
    skin: ^Skin = &model.skins[skin_index]
    count: int = min(len(skin.joints), len(out))
    for i in 0..<count {
        out[i] = model.nodes[skin.joints[i]].world * skin.inverse_bind[i]
    }
    return count
}

// Skin a vertex with joint matrices from ModelSkinMatrices
VertexSkinPosition :: proc(vertex: ^Vertex, joint_matrices: []Mat4) -> Vec3 {
    skin_matrix: Mat4 = VertexSkinMatrix(vertex, joint_matrices)
    return (skin_matrix * Vec4{vertex.position.x, vertex.position.y, vertex.position.z, 1}).xyz
}

VertexSkinNormal :: proc(vertex: ^Vertex, joint_matrices: []Mat4) -> Vec3 {
    skin_matrix: Mat4 = VertexSkinMatrix(vertex, joint_matrices)
    return (skin_matrix * Vec4{vertex.normal.x, vertex.normal.y, vertex.normal.z, 0}).xyz
}

VertexSkinMatrix :: proc(vertex: ^Vertex, joint_matrices: []Mat4) -> (result: Mat4) {
    for i in 0..<4 {
        weight: f32 = vertex.weights[i]
        if weight > 0 {
            result += weight * joint_matrices[vertex.joints[i]]
        }
    }
    return
}

ModelFindAnimation :: proc(model: ^Model, name: string) -> int {
    for animation, i in model.animations {
        if animation.name == name { return i }
    }
    return NONE
}
