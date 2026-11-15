package demo_karl2d

import "../../karl2d"
import m3d "../"
import glue "../glue_karl2d"
import kit "../../demo_kit"
import demo_common "../demo_common"

ready: bool
textures: [dynamic]karl2d.Texture
textures_for: ^m3d.Model
material: karl2d.R3d_Material

draw_model :: proc(ctx: ^kit.Context, model: ^m3d.Model, view: demo_common.OrbitView) {
    if !ready {
        ensure(karl2d.r3d_init())
        material = karl2d.r3d_material_default()
        material.outline_width = 1.5
        material.rim_color = {}
        ready = true
    }
    if textures_for != model {
        glue.UnloadTextures(textures[:])
        resize(&textures, len(model.images))
        glue.LoadTextures(model, textures[:])
        textures_for = model
    }
    camera: karl2d.R3d_Camera = {
        position = demo_common.OrbitPosition(view),
        target = view.target,
        up = {0, 1, 0},
        fov_y_degrees = 45,
        near = 0.05,
        far = 200,
    }
    karl2d.r3d_begin_scene(camera, karl2d.r3d_environment_default())
    glue.DrawModel(model, textures[:], material)
    karl2d.r3d_end_scene()
    // the 2D that follows (the HUD and the menu of the kit) is in front of the 3D depth values
    karl2d.set_z(1)
}
