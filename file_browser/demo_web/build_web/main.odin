// Build the web version of the file browser demo with web_build and, with --serve, serve it with web_serve. Run from odin_utilities:
//
//   odin run file_browser/demo_web/build_web -- [--serve] [--open] [--check] [--port N] [odin arguments such as -o:size]
//
// --check loads the page in a headless Chrome or Edge after the build and fails when it writes errors to its console.
// --drive chrome|edge|firefox clicks through the page in that browser (open a picture and a sound, play, save both, invert, save again; exit code 3 when the browser is not installed),
// --screenshots <folder> keeps pictures of the steps, --no-build uses the last build.
//
// The result is in file_browser/demo_web/game/bin/web (index.html, main.wasm, odin.js and the two JavaScript files of the audio of Karl2D and of file_browser).
// --serve then serves that folder (Ctrl+C stops), --open opens the page in the default browser.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import browser_drive "../../../browser_drive"
import web_build "../../../web_build"
import web_serve "../../../web_serve"
import "../drive"

SOURCE :: "file_browser/demo_web/game"

main :: proc() {
	serve, open_browser, check, no_build: bool
	drive_browser: Maybe(browser_drive.Browser)
	screenshots: string
	port: int = 8000
	odin_arguments: [dynamic]string
	arguments: []string = os.args[1:]
	for i := 0; i < len(arguments); i += 1 {
		switch arguments[i] {
		case "--serve": serve = true
		case "--check": check = true
		case "--no-build": no_build = true
		case "--screenshots":
			i += 1
			if i >= len(arguments) {
				fmt.eprintln("--screenshots needs a folder")
				os.exit(1)
			}
			screenshots = arguments[i]
		case "--drive":
			i += 1
			if i >= len(arguments) {
				fmt.eprintln("--drive needs chrome, edge or firefox")
				os.exit(1)
			}
			switch arguments[i] {
			case "chrome": drive_browser = .CHROME
			case "edge": drive_browser = .EDGE
			case "firefox": drive_browser = .FIREFOX
			case:
				fmt.eprintln("--drive needs chrome, edge or firefox")
				os.exit(1)
			}
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
	if !no_build && !web_build.WebBuild(config) { os.exit(1) }
	fmt.printfln("Done: %s/bin/web", SOURCE)
	if browser, drive_it := drive_browser.?; drive_it {
		// the click-through in a real browser (exit code 3 when it is not installed)
		os.exit(drive.ClickThrough(SOURCE + "/bin/web", browser, screenshots))
	}
	if check {
		// the page is loaded in a headless Chrome or Edge: what only a browser sees (a wrong import name, a 404) is reported
		result: web_build.WebBuildCheckResult = web_build.WebBuildCheck(config)
		fmt.printfln("page check: %v %s", result.status, result.message)
		if result.status == .NO_BROWSER { os.exit(3) }
		if result.status == .FAILED || result.status == .NOT_RUN { os.exit(1) }
	}
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
