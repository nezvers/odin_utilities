package demo_karl2d

import kit "../../demo_kit"
import kit_karl2d "../../demo_kit/karl2d"

// `odin run demo_karl2d`. The scene system loads Karl2D textures (scene/karl2d), so this demo is Karl2D only and has no demo_common:
// there is no raylib glue for the asset loaders. `-define:DEMO_TEST=true` plays the script (clicks, hovers, waits for the loading).
main :: proc() {
	demos: []kit.Demo = {demo_scene}
	kit_karl2d.Run("scene", demos)
}
