package demo_karl2d

import kit_karl2d "../../demo_kit/glue_karl2d"
import demo_common "../demo_common"

// `odin run reports/demo_karl2d`, the same demos as demo_raylib. `-define:DEMO_TEST=true` plays their scripts.
main :: proc() {
	kit_karl2d.Run("reports", demo_common.demos[:])
}
