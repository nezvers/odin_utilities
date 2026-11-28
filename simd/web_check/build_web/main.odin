// Build the check that runs the text kernels of simd in a browser, and serve it. Run from odin_utilities:
//
//   odin run simd/web_check/build_web -- [--open] [--port N]
//
// The page shows "SIMD128 PASS: 0 of N checks failed". `--build-only` stops after the build (the folder is simd/web_check/game/bin/web: serve it and open it in a browser, or read it with
// a headless one: chrome --headless --dump-dom http://127.0.0.1:PORT/).
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import web_build "../../../web_build"
import web_serve "../../../web_serve"

SOURCE :: "simd/web_check/game"

main :: proc() {
	open_browser, build_only: bool
	port: int = 8000
	arguments: []string = os.args[1:]
	for i := 0; i < len(arguments); i += 1 {
		switch arguments[i] {
		case "--open": open_browser = true
		case "--build-only": build_only = true
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
		case:
			fmt.eprintln("Usage: odin run simd/web_check/build_web -- [--open] [--build-only] [--port N]")
			os.exit(1)
		}
	}
	config: web_build.WebBuildConfig = {
		source_directory = SOURCE,
		title = "simd web check",
		copy_files = {"simd/web_check/simd_web_check.js"},
		scripts = {"simd_web_check.js"},
		imports_js = "simdWebCheckImports",
	}
	if !web_build.WebBuild(config) { os.exit(1) }
	fmt.printfln("Done: %s/bin/web", SOURCE)
	if build_only { return }
	server: web_serve.Server
	if !web_serve.ServerInit(&server, {directory = SOURCE + "/bin/web", port = port, log = true}) {
		fmt.eprintfln("Could not listen on port %d, is something else using it?", port)
		os.exit(1)
	}
	defer web_serve.ServerShutdown(&server)
	buffer: [64]u8
	url: string = web_serve.ServerUrl(&server, buffer[:])
	fmt.printfln("Serving at %s (Ctrl+C to stop)", url)
	if open_browser { web_serve.ServerOpenBrowser(url) }
	web_serve.ServerRun(&server)
}
