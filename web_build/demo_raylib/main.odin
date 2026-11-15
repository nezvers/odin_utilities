package demo_raylib

import kit_raylib "../../demo_kit/glue_raylib"
import demo_common "../demo_common"

// `odin run demo_raylib`: the same resource demo as Karl2D, desktop only (raylib in a browser needs emscripten, outside of what web_build does).
// `-define:DEMO_TEST=true` plays its script.
main :: proc() {
	kit_raylib.Run("web_build", demo_common.demos[:])
}
