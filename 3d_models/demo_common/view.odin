package demo_common

// What the drawer of a framework needs: the model in its pose and where the orbit camera is. Plain data.

import "core:math"
import m3d ".."
import kit "../../demo_kit"

OrbitView :: struct {
    target: m3d.Vec3,
    yaw: f32,
    pitch: f32,
    distance: f32,
}

ModelDrawer :: proc(ctx: ^kit.Context, model: ^m3d.Model, view: OrbitView)

// Set by the demo of a framework before it runs the demos
model_drawer: ModelDrawer

model: m3d.Model
view: OrbitView

// The camera position of the orbit view
OrbitPosition :: proc(view: OrbitView) -> m3d.Vec3 {
    return view.target + m3d.Vec3{
        view.distance * math.cos(view.pitch) * math.sin(view.yaw),
        view.distance * math.sin(view.pitch),
        view.distance * math.cos(view.pitch) * math.cos(view.yaw),
    }
}
