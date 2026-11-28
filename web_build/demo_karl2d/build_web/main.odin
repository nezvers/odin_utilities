// Web build of the karl2d demo. Run from the web_build directory:
//   odin run demo_karl2d/build_web -- [--check] -o:size
// `--check` (exit code 3 when no browser is installed) then loads the page in a headless Chrome or Edge and reports what it writes to its console as an error. Everything else after `--` goes to `odin build`. The result is in demo_karl2d/game/bin/web, serve that folder.
package main

import "core:fmt"
import "core:os"
import web_build "../.."

main :: proc() {
	check: bool
	odin_arguments: [dynamic]string
	for argument in os.args[1:] {
		if argument == "--check" { check = true } else { append(&odin_arguments, argument) }
	}
	config: web_build.WebBuildConfig = {
		source_directory = "demo_karl2d/game",
		title = "web_build demo",
		// karl2d plays audio through JavaScript on the web
		copy_files = {"../karl2d/audio_backend_web_audio.js", "../karl2d/audio_backend_web_audio_processor.js"},
		scripts = {"audio_backend_web_audio.js"},
		imports_js = "karl2dAudioJsImports",
		start_js = "setKarl2dAudioWasmMemory(exports.memory);",
		odin_arguments = odin_arguments[:],
	}
	if !web_build.WebBuild(config) {
		os.exit(1)
	}
	fmt.println("Done: demo_karl2d/game/bin/web. Serve that folder, for example `python -m http.server` inside of it.")
	if check {
		result: web_build.WebBuildCheckResult = web_build.WebBuildCheck(config)
		fmt.printfln("page check: %v %s", result.status, result.message)
		if result.status == .NO_BROWSER { os.exit(3) }
		if result.status == .FAILED || result.status == .NOT_RUN { os.exit(1) }
	}
}
