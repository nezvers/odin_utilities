// Build the web version of the file browser demo with web_build and, with --serve, serve it with web_serve. Run from odin_utilities:
//
//   odin run file_browser/demo_web/build_web -- [--serve] [--open] [--port N] [odin arguments such as -o:size]
//
// The result is in file_browser/demo_web/game/bin/web (index.html, main.wasm, odin.js and the two JavaScript files of the audio of Karl2D and of file_browser).
// --serve then serves that folder (Ctrl+C stops), --open opens the page in the default browser.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import web_build "../../../web_build"
import web_serve "../../../web_serve"

SOURCE :: "file_browser/demo_web/game"

main :: proc() {
	serve, open_browser: bool
	port: int = 8000
	odin_arguments: [dynamic]string
	// the 16 byte text kernels of the simd package need wasm SIMD: without the feature LLVM stops with "Do not know how to split the result of this operator!"
	append(&odin_arguments, "-target-features:simd128")
	arguments: []string = os.args[1:]
	for i := 0; i < len(arguments); i += 1 {
		switch arguments[i] {
		case "--serve": serve = true
		case "--open": open_browser, serve = true, true
		case "--port":
			i += 1
			value: int
			ok: bool
			if i < len(arguments) { value, ok = strconv.parse_int(arguments[i]) }
			if !ok {
				fmt.eprintln("--port needs a number")
				os.exit(1)
			}
			port = value
		case: append(&odin_arguments, arguments[i])
		}
	}

	config: web_build.WebBuildConfig = {
		source_directory = SOURCE,
		title = "file_browser demo",
		// Karl2D plays audio through JavaScript on the web, file_browser opens files and downloads through its own JavaScript
		copy_files = {"karl2d/audio_backend_web_audio.js", "karl2d/audio_backend_web_audio_processor.js", "file_browser/file_browser.js"},
		scripts = {"audio_backend_web_audio.js", "file_browser.js"},
		imports_js = "{ ...karl2dAudioJsImports, ...fileBrowserJsImports }",
		start_js = "setKarl2dAudioWasmMemory(exports.memory); setFileBrowserWasmMemory(exports.memory);",
		odin_arguments = odin_arguments[:],
	}
	if !web_build.WebBuild(config) { os.exit(1) }
	fmt.printfln("Done: %s/bin/web", SOURCE)
	if !serve { return }

	server: web_serve.Server
	if !web_serve.ServerInit(&server, {directory = SOURCE + "/bin/web", port = port, log = true}) {
		fmt.eprintfln("Could not listen on port %d, is something else using it?", port)
		os.exit(1)
	}
	defer web_serve.ServerShutdown(&server)
	buffer: [64]u8
	url: string = web_serve.ServerUrl(&server, buffer[:])
	fmt.printfln("Serving %s at %s (Ctrl+C to stop)", SOURCE + "/bin/web", url)
	if open_browser { web_serve.ServerOpenBrowser(url) }
	web_serve.ServerRun(&server)
}
