#+build js
// The options page inside of the extension, drawn by Karl2D: a web_build package (init, step, shutdown) that runs the same page as the raylib
// host (options/options.odin). The bridge is the browser: messages go to the background, its replies come back to OptionsOnReply.
package host_karl2d

import "../../../karl2d"
import kit "../../../demo_kit"
import kit_karl2d "../../../demo_kit/glue_karl2d"
import "../options"
import extension "../../runtime"

runner: kit.Runner
backend: kit.Backend
state: kit_karl2d.State
demos: [1]kit.Demo

init :: proc() {
	karl2d.init(int(options.SCREEN_SIZE.x), int(options.SCREEN_SIZE.y), "YouTube Shorts", options = {window_mode = .Windowed_Resizable})
	extension.SetReplyHandler(options.OptionsOnReply)
	options.OptionsSetBridge({send = extension.SendMessage, open_url = extension.OpenUrl})
	demos[0] = options.demo
	kit_karl2d.Init(&backend, &state)
	kit.RunnerInit(&runner, demos[:], &backend)
	// a tab has no escape key that closes the page
	runner.escape_exits = false
}

step :: proc() -> bool {
	return kit.RunnerStep(&runner)
}

shutdown :: proc() {
	kit.RunnerShutdown(&runner)
}
