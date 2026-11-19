package demo_karl2d

import kit_karl2d "../../demo_kit/glue_karl2d"
import demo_common "../demo_common"

// `odin run font/demo_karl2d` (from odin_utilities), the same demos as demo_raylib. `-define:DEMO_TEST=true` plays their scripts.
// The text of the demos is drawn by the font library through text.odin; the demos in demo_common only fill a list of requests.
main :: proc() {
	demo_common.text_drawer = draw_text
	demo_common.rich_drawer = draw_rich
	kit_karl2d.Run("font", demo_common.demos[:])
}
