package demo_raylib

import rl "vendor:raylib"
import m3d "../"
import glue "../raylib"
import kit "../../demo_kit"
import demo_common "../demo_common"

// Textures of the model images, made when the model is first drawn (the model lives in an arena of the demo, the textures belong to raylib)
textures: [dynamic]rl.Texture2D
textures_for: ^m3d.Model

draw_model :: proc(ctx: ^kit.Context, model: ^m3d.Model, view: demo_common.OrbitView) {
    if textures_for != model {
        glue.UnloadTextures(textures[:])
        resize(&textures, len(model.images))
        glue.LoadTextures(model, textures[:])
        textures_for = model
    }
    camera: rl.Camera3D = {
        position = demo_common.OrbitPosition(view),
        target = view.target,
        up = {0, 1, 0},
        fovy = 45,
        projection = .PERSPECTIVE,
    }
    rl.BeginMode3D(camera)
    rl.DrawGrid(20, 1)
    glue.DrawModel(model, textures[:])
    rl.EndMode3D()
}
