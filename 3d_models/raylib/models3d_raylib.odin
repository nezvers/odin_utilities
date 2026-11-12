// Raylib glue for models3d. Draws Model with raylib immediate mode (rlgl), skinning is done on the CPU.
// Nothing is uploaded to the GPU except textures, so models can be posed every frame without buffer updates.
// For many characters on screen a GPU skinning path (shader + joint matrices) would be the next step.
package models3d_raylib

import "core:math/linalg"
import m3d ".."
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

Mat4 :: m3d.Mat4
Vec3 :: m3d.Vec3
Vec4 :: m3d.Vec4

// Directional light, direction the light travels
LIGHT_DIRECTION :Vec3: {-0.4, -1, -0.6}
AMBIENT :: 0.45
DIFFUSE :: 0.65

// Load a texture for every embedded image of the model. Images without data (uri only) stay empty,
// load them yourself relative to the model file. `textures` has one entry per Model.images
LoadTextures :: proc(model: ^m3d.Model, textures: []rl.Texture2D) {
    assert(len(textures) >= len(model.images))
    for image, i in model.images {
        textures[i] = {}
        if len(image.data) == 0 { continue }

        extension: cstring = ".jpg" if image.mime_type == "image/jpeg" else ".png"
        rl_image: rl.Image = rl.LoadImageFromMemory(extension, raw_data(image.data), i32(len(image.data)))
        if rl_image.data != nil {
            textures[i] = rl.LoadTextureFromImage(rl_image)
            rl.UnloadImage(rl_image)
        }
    }
}

UnloadTextures :: proc(textures: []rl.Texture2D) {
    for texture in textures {
        if texture.id != 0 { rl.UnloadTexture(texture) }
    }
}

// Draw all nodes in the current pose (ModelAnimate / ModelUpdateNodes) with transform applied on top.
// textures can be empty when the model doesn't use any.
DrawModel :: proc(model: ^m3d.Model, textures: []rl.Texture2D, transform: Mat4 = 1, tint: rl.Color = rl.WHITE) {
    joint_matrices: [m3d.MAX_JOINTS]Mat4
    light: Vec3 = linalg.normalize(LIGHT_DIRECTION)

    for &node in model.nodes {
        if node.mesh == m3d.NONE { continue }

        // Skinned vertices are placed by the joint matrices only, the mesh node transform is ignored (glTF spec)
        skinned: bool = node.skin != m3d.NONE
        joint_count: int
        node_matrix: Mat4 = transform * node.world
        if skinned {
            joint_count = m3d.ModelSkinMatrices(model, node.skin, joint_matrices[:])
            for i in 0..<joint_count {
                joint_matrices[i] = transform * joint_matrices[i]
            }
        }

        for &primitive in model.meshes[node.mesh].primitives {
            DrawPrimitive(model, textures, &primitive, node_matrix, joint_matrices[:joint_count], skinned, light, tint)
        }
    }
}

@(private="file")
DrawPrimitive :: proc(
    model: ^m3d.Model,
    textures: []rl.Texture2D,
    primitive: ^m3d.Primitive,
    node_matrix: Mat4,
    joint_matrices: []Mat4,
    skinned: bool,
    light: Vec3,
    tint: rl.Color,
) {
    base_color: Vec4 = {1, 1, 1, 1}
    texture_id: u32 = rlgl.GetTextureIdDefault()
    double_sided: bool
    if primitive.material != m3d.NONE {
        material: ^m3d.Material = &model.materials[primitive.material]
        base_color = material.base_color
        double_sided = material.double_sided
        image: int = material.base_color_image
        if image != m3d.NONE && image < len(textures) && textures[image].id != 0 {
            texture_id = textures[image].id
        }
    }
    base_color *= Vec4{f32(tint.r), f32(tint.g), f32(tint.b), f32(tint.a)} / 255

    if double_sided { rlgl.DisableBackfaceCulling() }
    rlgl.SetTexture(texture_id)

    for i := 0; i + 2 < len(primitive.indices); i += 3 {
        // Flush before the batch is full
        _ = rlgl.CheckRenderBatchLimit(3)
        rlgl.Begin(rlgl.TRIANGLES)
        for corner in 0..<3 {
            vertex: ^m3d.Vertex = &primitive.vertices[primitive.indices[i + corner]]
            position, normal: Vec3
            if skinned {
                position = m3d.VertexSkinPosition(vertex, joint_matrices)
                normal = m3d.VertexSkinNormal(vertex, joint_matrices)
            } else {
                position = (node_matrix * Vec4{vertex.position.x, vertex.position.y, vertex.position.z, 1}).xyz
                normal = (node_matrix * Vec4{vertex.normal.x, vertex.normal.y, vertex.normal.z, 0}).xyz
            }

            // Lambert shading on the CPU
            intensity: f32 = AMBIENT
            if linalg.length2(normal) > 0 {
                intensity += DIFFUSE * max(linalg.dot(linalg.normalize(normal), -light), 0)
            }
            intensity = min(intensity, 1)
            rlgl.Color4ub(u8(clamp(base_color.r * intensity, 0, 1) * 255), u8(clamp(base_color.g * intensity, 0, 1) * 255), u8(clamp(base_color.b * intensity, 0, 1) * 255), u8(clamp(base_color.a, 0, 1) * 255))
            rlgl.TexCoord2f(vertex.uv.x, vertex.uv.y)
            rlgl.Vertex3f(position.x, position.y, position.z)
        }
        rlgl.End()
    }

    rlgl.SetTexture(0)
    if double_sided { rlgl.EnableBackfaceCulling() }
}

// Bounding box of the rest pose bounds with transform applied to the corners
ModelBoundingBox :: proc(model: ^m3d.Model, transform: Mat4 = 1) -> rl.BoundingBox {
    low: Vec3 = {max(f32), max(f32), max(f32)}
    high: Vec3 = {min(f32), min(f32), min(f32)}
    for corner in 0..<8 {
        point: Vec4 = {
            model.bounds_max.x if corner & 1 != 0 else model.bounds_min.x,
            model.bounds_max.y if corner & 2 != 0 else model.bounds_min.y,
            model.bounds_max.z if corner & 4 != 0 else model.bounds_min.z,
            1,
        }
        world: Vec3 = (transform * point).xyz
        low = linalg.min(low, world)
        high = linalg.max(high, world)
    }
    return {min = low, max = high}
}
