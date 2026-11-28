#+build js
// The demo of the library in a web page (a web_build package: init, step, shutdown). The same demo as demo_raylib and demo_karl2d: in a page it opens files with the file chooser of the browser
// and "saves" by downloading. Build and serve it with `odin run file_browser/demo_web/build_web -- --serve --open` (from odin_utilities).
package game

import "../../../karl2d"
import kit "../../../demo_kit"
import kit_karl2d "../../../demo_kit/glue_karl2d"
import demo_common "../../demo_common"

WINDOW_SIZE :: [2]int{1280, 720}

runner: kit.Runner
backend: kit.Backend
state: kit_karl2d.State

init :: proc() {
	karl2d.init(WINDOW_SIZE.x, WINDOW_SIZE.y, "file_browser", options = {window_mode = .Windowed_Resizable})
	kit_karl2d.Init(&backend, &state)
	kit.RunnerInit(&runner, demo_common.demos[:], &backend)
	// a tab has no escape key that closes the page
	runner.escape_exits = false
}

step :: proc() -> bool {
	return kit.RunnerStep(&runner)
}

shutdown :: proc() {
	kit.RunnerShutdown(&runner)
}
