package demo_raylib

import kit_raylib "../../demo_kit/glue_raylib"
import demo_common "../demo_common"

// `odin run demo_raylib`. `-define:DEMO_TEST=true` plays the scripts of the demos with simulated input and exits with 1 on a failure.
// The 3D part of a frame is drawn by scene3d.odin (raylib), the demos in demo_common only fill a list of shapes.
main :: proc() {
	demo_common.scene_drawer = draw_scene
	kit_raylib.Run("fps_controller", demo_common.demos[:])
}
