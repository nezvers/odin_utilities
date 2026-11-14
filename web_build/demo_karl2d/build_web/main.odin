// Web build of the karl2d demo. Run from the web_build directory:
//   odin run demo_karl2d/build_web -- -o:size
// Everything after `--` goes to `odin build`. The result is in demo_karl2d/game/bin/web, serve that folder.
package main

import "core:fmt"
import "core:os"
import web_build "../.."

main :: proc() {
	config: web_build.WebBuildConfig = {
		source_directory = "demo_karl2d/game",
		title = "web_build demo",
		// karl2d plays audio through JavaScript on the web
		copy_files = {"../karl2d/audio_backend_web_audio.js", "../karl2d/audio_backend_web_audio_processor.js"},
		scripts = {"audio_backend_web_audio.js"},
		imports_js = "karl2dAudioJsImports",
		start_js = "setKarl2dAudioWasmMemory(exports.memory);",
		odin_arguments = os.args[1:],
	}
	if !web_build.WebBuild(config) {
		os.exit(1)
	}
	fmt.println("Done: demo_karl2d/game/bin/web. Serve that folder, for example `python -m http.server` inside of it.")
}
