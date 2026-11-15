package demo_raylib

import kit_raylib "../../demo_kit/raylib"
import demo_common "../demo_common"

main :: proc() {
	kit_raylib.Run("viewport_rect", demo_common.demos[:])
}
