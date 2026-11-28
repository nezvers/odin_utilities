package demo_raylib

import kit_raylib "../../demo_kit/glue_raylib"
import demo_common "../demo_common"

// `odin run file_browser/demo_raylib`: open and save pictures and sounds on the disk. `-define:DEMO_TEST=true` plays the script (files in memory) and exits with 1 on a failure.
main :: proc() {
	kit_raylib.Run("file_browser", demo_common.demos[:])
}
