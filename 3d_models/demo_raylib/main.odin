package demo_raylib

import kit_raylib "../../demo_kit/raylib"
import demo_common "../demo_common"

// `odin run demo_raylib`. The model is drawn by scene3d.odin (raylib, CPU skinning through 3d_models/raylib), the demo in demo_common only poses it.
// `-define:DEMO_TEST=true` plays the script of the demo with simulated input and exits with 1 on a failure.
main :: proc() {
	demo_common.model_drawer = draw_model
	kit_raylib.Run("3d_models", demo_common.demos[:])
}
