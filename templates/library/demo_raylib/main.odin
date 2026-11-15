package demo_raylib

import kit_raylib "../../demo_kit/glue_raylib"
import demo_common "../demo_common"

// `odin run demo_raylib`. `-define:DEMO_TEST=true` plays the scripts of the demos with simulated input and exits with 1 on a failure.
main :: proc() {
	kit_raylib.Run("example", demo_common.demos[:])
}
