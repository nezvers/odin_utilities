package demo_raylib

// The 3D drawing of the demos with raylib: the list of shapes of demo_common.Scene on the camera of the player.

import rl "vendor:raylib"
import "vendor:raylib/rlgl"
import kit "../../demo_kit"
import demo_common "../demo_common"
import fps "../"

draw_scene :: proc(ctx: ^kit.Context, view: ^fps.View, scene: ^demo_common.Scene) {
    camera: rl.Camera3D = {
        position = view.position,
        target = view.target,
        up = view.up,
        fovy = view.fov_y,
        projection = .PERSPECTIVE,
    }
    rl.BeginMode3D(camera)
    if scene.floor {
        demo_common.SceneFloorTiles(draw_tile, nil)
    }
    for i in 0 ..< scene.box_count {
        box: demo_common.SceneBox = scene.boxes[i]
        draw_at(box.center, box.rotation)
        rl.DrawCubeV({}, box.half * 2, rl.Color(box.color))
        if box.wire.a > 0 { rl.DrawCubeWiresV({}, box.half * 2, rl.Color(box.wire)) }
        rlgl.PopMatrix()
    }
    for i in 0 ..< scene.sphere_count {
        sphere: demo_common.SceneSphere = scene.spheres[i]
        rl.DrawSphere(sphere.center, sphere.radius, rl.Color(sphere.color))
    }
    rl.EndMode3D()
}

draw_tile :: proc(center: fps.Vec3, size: f32, color: kit.Color, user: rawptr) {
    rl.DrawPlane(center, {size, size}, rl.Color(color))
}

// Move to the transform of a shape: what is drawn until PopMatrix is around the origin
draw_at :: proc(position: fps.Vec3, rotation: quaternion128) {
    axis, angle := rl.QuaternionToAxisAngle(rotation)
    rlgl.PushMatrix()
    rlgl.Translatef(position.x, position.y, position.z)
    rlgl.Rotatef(angle * rl.RAD2DEG, axis.x, axis.y, axis.z)
}
