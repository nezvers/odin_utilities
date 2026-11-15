package demo_karl2d

import "../../karl2d"
import kit_karl2d "../../demo_kit/karl2d"
import demo_common "../demo_common"

// `odin run demo_karl2d`. This demo needs the CUSTOM Karl2D fork (odin_utilities/karl2d is a junction to odin_plug/karl2d, branch `render3d`): the model
// is drawn with its 3D layer (karl2d.r3d_*), see 3d_models/karl2d. `-define:DEMO_TEST=true` plays the script of the demo.
main :: proc() {
	demo_common.model_drawer = draw_model
	// depth_test: the 3D layer shares the depth buffer of Karl2D
	kit_karl2d.Run("3d_models", demo_common.demos[:], options = karl2d.Init_Options{window_mode = .Windowed_Resizable, depth_test = true})
}
