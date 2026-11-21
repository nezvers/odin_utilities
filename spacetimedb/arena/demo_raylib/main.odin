package demo_raylib

import kit_raylib "../../../demo_kit/glue_raylib"
import demo_common "../demo_common"

// `odin run spacetimedb/arena/demo_raylib` (solo), `-- host`, `-- host --derp`, `-- join <code>`: see demo_common/demo_arena.odin
main :: proc() {
	kit_raylib.Run("arena", demo_common.demos[:])
}
