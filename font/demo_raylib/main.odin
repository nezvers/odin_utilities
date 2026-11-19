package demo_raylib

import kit_raylib "../../demo_kit/glue_raylib"
import demo_common "../demo_common"

// `odin run font/demo_raylib` (from odin_utilities). `-define:DEMO_TEST=true` plays the scripts of the demos with simulated input and exits with 1 on a failure.
// The text of the demos is drawn by the font library through text.odin; the demos in demo_common only fill a list of requests.
main :: proc() {
	demo_common.text_drawer = draw_text
	demo_common.rich_drawer = draw_rich
	kit_raylib.Run("font", demo_common.demos[:])
}
