package demo_karl2d

import kit_karl2d "../../demo_kit/glue_karl2d"
import demo_common "../demo_common"

// `odin run file_browser/demo_karl2d`, the same demo as demo_raylib. The web version is `demo_web`.
main :: proc() {
	kit_karl2d.Run("file_browser", demo_common.demos[:])
}
