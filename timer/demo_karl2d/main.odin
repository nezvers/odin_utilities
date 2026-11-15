package demo_karl2d

import kit_karl2d "../../demo_kit/glue_karl2d"
import demo_common "../demo_common"

main :: proc() {
	kit_karl2d.Run("timer", demo_common.demos[:])
}
