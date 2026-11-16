// The options page on the desktop, drawn by raylib, talking to a loopback background (with a few saved shorts): the quick way to work on the page.
//   odin run youtube_shorts/host_raylib                       from the browser_extension folder
//   odin run youtube_shorts/host_raylib -define:DEMO_TEST=true    plays the script of the page in the window
package host_raylib

import kit_raylib "../../../demo_kit/glue_raylib"
import "../options"
import kit "../../../demo_kit"

main :: proc() {
	options.OptionsLoopbackInit(true)
	demos: []kit.Demo = {options.demo}
	kit_raylib.Run("YouTube Shorts options", demos, i32(options.SCREEN_SIZE.x), i32(options.SCREEN_SIZE.y))
}
