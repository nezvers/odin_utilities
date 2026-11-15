package demo_karl2d

import kit "../../demo_kit"
import kit_karl2d "../../demo_kit/glue_karl2d"
import demo_common "../demo_common"

// `odin run demo_karl2d`. The actions demo works through input/karl2d (real devices): Karl2D reads them itself, so no script plays into it.
main :: proc() {
	// a test run plays simulated input of the kit, Karl2D devices cannot get it: the adapter over the keys of the kit takes its place
	when kit.DEMO_TEST { demo_common.adapter = demo_common.KitAdapter() } else { demo_common.adapter = karl2d_adapter() }
	kit_karl2d.Run("input", demo_common.demos[:])
}
