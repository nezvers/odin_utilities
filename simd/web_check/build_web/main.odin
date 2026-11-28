// Build the check that runs the text kernels of simd in a browser, and serve it. Run from odin_utilities:
//
//   odin run simd/web_check/build_web -- [--open] [--port N]
//   odin run simd/web_check/build_web -- --headless     build, serve, load the page in every installed browser (Chrome, Edge, Firefox) with browser_drive, print each verdict; exit code 0 passed, 1 failed, 3 no browser found
//
// The page shows "SIMD128 PASS: 0 of N checks failed". `--build-only` stops after the build (the folder is simd/web_check/game/bin/web: serve it and open it in a browser, or read it with
// a headless one: chrome --headless --dump-dom http://127.0.0.1:PORT/).
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import browser_drive "../../../browser_drive"
import web_build "../../../web_build"
import web_serve "../../../web_serve"

SOURCE :: "simd/web_check/game"

main :: proc() {
	open_browser, build_only, headless: bool
	port: int = 8000
	arguments: []string = os.args[1:]
	for i := 0; i < len(arguments); i += 1 {
		switch arguments[i] {
		case "--open": open_browser = true
		case "--build-only": build_only = true
		case "--headless": headless = true
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
			fmt.eprintln("Usage: odin run simd/web_check/build_web -- [--open] [--build-only] [--headless] [--port N]")
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
	if headless { os.exit(runHeadless()) }
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

ServeJob :: struct {
	server: ^web_serve.Server,
	stop: bool,
}

// Serve the build and let every installed browser (Chrome, Edge, Firefox) load it, print what the title of the page says: the page runs the check in the start of its wasm and reports there.
// Exit codes: 0 every browser passed, 1 one failed, 3 no browser is installed.
runHeadless :: proc() -> int {
	server: web_serve.Server
	if !web_serve.ServerInit(&server, {directory = SOURCE + "/bin/web", port = 0}) {
		fmt.eprintln("could not listen on a free port")
		return 1
	}
	defer web_serve.ServerShutdown(&server)
	job: ServeJob = {server = &server}
	runner: ^thread.Thread = thread.create_and_start_with_poly_data(&job, proc(job: ^ServeJob) {
		web_serve.ServerRun(job.server, &job.stop)
	})
	defer {
		sync.atomic_store(&job.stop, true)
		thread.join(runner)
		thread.destroy(runner)
	}

	driver: ^browser_drive.Driver = new(browser_drive.Driver)
	defer free(driver)
	tried, failed: int
	passed: strings.Builder
	strings.builder_init(&passed, context.temp_allocator)
	for browser in ([?]browser_drive.Browser{.CHROME, .EDGE, .FIREFOX}) {
		if len(browser_drive.BrowserFind(browser)) == 0 { continue }
		tried += 1
		name: string = browser_drive.BrowserName(browser)
		if error := browser_drive.DriverStart(driver, {browser = browser}); error != .NONE {
			fmt.printfln("%s did not start: %v %s", name, error, browser_drive.DriverLastError(driver))
			failed += 1
			continue
		}
		browser_drive.DriverNavigate(driver, fmt.tprintf("http://127.0.0.1:%d/", server.port))
		// the check runs while the wasm starts: its verdict is the title
		browser_drive.DriverWaitUntil(driver, "document.title.startsWith('SIMD128')", 60000)
		verdict, _ := browser_drive.DriverEvaluate(driver, "document.title")
		browser_drive.DriverStop(driver)
		fmt.printfln("%s (%s)", verdict, name)
		if strings.has_prefix(verdict, "SIMD128 PASS") {
			if strings.builder_len(passed) > 0 { strings.write_string(&passed, ", ") }
			strings.write_string(&passed, name)
		} else {
			failed += 1
		}
	}
	if tried == 0 {
		fmt.println("no Chrome, Edge or Firefox found: the browser check was not run")
		return 3
	}
	// the last line is what tool/test shows
	if failed > 0 {
		fmt.printfln("SIMD128 FAILED in %d of %d browsers (passed in: %s)", failed, tried, strings.to_string(passed))
		return 1
	}
	fmt.printfln("SIMD128 PASS in %s", strings.to_string(passed))
	return 0
}
