package demo_karl2d

import "../../karl2d"
import kit_karl2d "../../demo_kit/glue_karl2d"
import demo_common "../demo_common"

// `odin run demo_karl2d`. This demo needs the CUSTOM Karl2D fork (odin_utilities/karl2d is a junction to odin_plug/karl2d, branch `render3d`):
// the 3D layer (karl2d.r3d_*) is not in upstream Karl2D. See the README of this library.
// `-define:DEMO_TEST=true` plays the scripts of the demos with simulated input and exits with 1 on a failure.
main :: proc() {
	demo_common.scene_drawer = draw_scene
	// depth_test: the 3D layer shares the depth buffer of Karl2D
	kit_karl2d.Run("fps_controller", demo_common.demos[:], options = karl2d.Init_Options{window_mode = .Windowed_Resizable, depth_test = true})
}
