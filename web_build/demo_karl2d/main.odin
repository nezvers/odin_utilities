package demo_karl2d

import kit_karl2d "../../demo_kit/karl2d"
import demo_common "../demo_common"

// `odin run demo_karl2d`: the resource demo on the desktop, from demo_common. The web build of the same idea is the package `game/` (init, step, shutdown)
// built by `odin run build_web`, see the README.
main :: proc() {
	kit_karl2d.Run("web_build", demo_common.demos[:])
}
