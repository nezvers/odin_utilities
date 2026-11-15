package demo_raylib

import kit "../../demo_kit"
import kit_raylib "../../demo_kit/raylib"
import demo_common "../demo_common"

// `odin run demo_raylib`. The actions demo works through input/raylib (real devices), the gamepad demo is raylib only.
main :: proc() {
	// a test run plays simulated input of the kit, raylib devices cannot get it: the adapter over the keys of the kit takes its place
	when kit.DEMO_TEST { demo_common.adapter = demo_common.KitAdapter() } else { demo_common.adapter = raylib_adapter() }
	demos: []kit.Demo = {demo_common.ActionDemo(), demo_gamepad}
	kit_raylib.Run("input", demos)
}
