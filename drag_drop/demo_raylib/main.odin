package demo_raylib

import kit_raylib "../../demo_kit/glue_raylib"
import demo_common "../demo_common"

main :: proc() {
	kit_raylib.Run("drag_drop", demo_common.demos[:])
}
