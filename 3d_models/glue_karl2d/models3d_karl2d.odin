// Karl2D glue for models3d. Needs the CUSTOM Karl2D fork (odin_utilities/karl2d is a junction to odin_plug/karl2d, branch render3d): it draws with the
// 3D layer (karl2d.r3d_*), which is not in upstream Karl2D. Skinning is done on the CPU like in the raylib glue, the posed triangles of a primitive
// become a mesh of the 3D layer for the draw call of that frame, so a model can be posed every frame without any bookkeeping.
// Karl2D has to be started with depth_test = true and karl2d.r3d_init() called once.
package models3d_karl2d

import m3d ".."
import "../../karl2d"

Mat4 :: m3d.Mat4
Vec3 :: m3d.Vec3

// Load a texture for every embedded image of the model. Images without data (uri only) stay empty.
// `textures` has one entry per Model.images
LoadTextures :: proc(model: ^m3d.Model, textures: []karl2d.Texture) {
    assert(len(textures) >= len(model.images))
    for image, i in model.images {
        textures[i] = karl2d.TEXTURE_NONE
        if len(image.data) == 0 { continue }
        texture, ok := karl2d.load_texture_from_bytes(image.data)
        if ok { textures[i] = texture }
    }
}

UnloadTextures :: proc(textures: []karl2d.Texture) {
    for texture in textures {
        if texture != karl2d.TEXTURE_NONE { karl2d.destroy_texture(texture) }
    }
}

// Draw all nodes in the current pose (ModelAnimate / ModelUpdateNodes) with `transform` applied on top. Call between r3d_begin_scene and
// r3d_end_scene. `material` (karl2d.r3d_material_default()) decides the look: toon bands, outline, rim; the color and the texture come from the model.
DrawModel :: proc(model: ^m3d.Model, textures: []karl2d.Texture, material: karl2d.R3d_Material, transform: Mat4 = 1) {
    joint_matrices: [m3d.MAX_JOINTS]Mat4
    vertices: [dynamic]karl2d.R3d_Vertex
    indices: [dynamic]u32
    defer delete(vertices)
    defer delete(indices)

    for &node in model.nodes {
        if node.mesh == m3d.NONE { continue }
        // Skinned vertices are placed by the joint matrices only, the mesh node transform is ignored (glTF spec)
        skinned: bool = node.skin != m3d.NONE
        joint_count: int
        node_matrix: Mat4 = transform * node.world
        if skinned {
            joint_count = m3d.ModelSkinMatrices(model, node.skin, joint_matrices[:])
            for i in 0 ..< joint_count {
                joint_matrices[i] = transform * joint_matrices[i]
            }
        }
        for &primitive in model.meshes[node.mesh].primitives {
            clear(&vertices)
            clear(&indices)
            for &vertex in primitive.vertices {
                position, normal: Vec3
                if skinned {
                    position = m3d.VertexSkinPosition(&vertex, joint_matrices[:joint_count])
                    normal = m3d.VertexSkinNormal(&vertex, joint_matrices[:joint_count])
                } else {
                    position = (node_matrix * [4]f32{vertex.position.x, vertex.position.y, vertex.position.z, 1}).xyz
                    normal = (node_matrix * [4]f32{vertex.normal.x, vertex.normal.y, vertex.normal.z, 0}).xyz
                }
                append(&vertices, karl2d.R3d_Vertex{position = position, normal = normal, uv = vertex.uv, color = {255, 255, 255, 255}})
            }
            append(&indices, ..primitive.indices)

            primitive_material: karl2d.R3d_Material = material
            primitive_material.albedo = karl2d.TEXTURE_NONE
            if primitive.material != m3d.NONE {
                source: ^m3d.Material = &model.materials[primitive.material]
                primitive_material.tint = source.base_color
                image: int = source.base_color_image
                if image != m3d.NONE && image < len(textures) && textures[image] != karl2d.TEXTURE_NONE {
                    primitive_material.albedo = textures[image]
                }
            }
            mesh, ok := karl2d.r3d_mesh_create(vertices[:], indices[:])
            if !ok { continue }
            karl2d.r3d_draw_one(mesh, primitive_material, 1)
            karl2d.r3d_mesh_destroy(mesh)
        }
    }
}
