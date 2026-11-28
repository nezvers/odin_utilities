// Build the check that runs the text kernels of simd in a browser, and serve it. Run from odin_utilities:
//
//   odin run simd/web_check/build_web -- [--open] [--port N]
//   odin run simd/web_check/build_web -- --headless     build, serve, read the page with a headless Chrome or Edge, print the verdict; exit code 0 passed, 1 failed, 3 no browser found
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

// Serve the build, let the browser load it, print what its title says. The page runs the check in the start of its wasm; --virtual-time-budget lets the browser wait for it.
runHeadless :: proc() -> int {
	browser: string = web_build.WebBuildBrowserFind()
	if len(browser) == 0 {
		fmt.println("no Chrome or Edge found: the browser check was not run")
		return 3
	}
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

	// a profile of its own: a browser that is already open would take the request and exit
	temp, _ := os.temp_directory(context.temp_allocator)
	profile: string = fmt.tprintf("%s/odin_utilities_simd_web_check_profile", temp)
	defer os.remove_all(profile)
	url: string = fmt.tprintf("http://127.0.0.1:%d/", server.port)
	state, stdout, stderr, error := os.process_exec({command = {browser, "--headless=new", "--disable-gpu", fmt.tprintf("--user-data-dir=%s", profile), "--virtual-time-budget=60000", "--dump-dom", url}}, context.temp_allocator)
	if error != nil || state.exit_code != 0 {
		fmt.printfln("the browser did not run: %v, exit code %d: %s", error, state.exit_code, string(stderr))
		return 1
	}
	page: string = string(stdout)
	start: int = strings.index(page, "<title>")
	end: int = strings.index(page, "</title>")
	if start < 0 || end < start {
		fmt.println("the page has no title: the check did not report (is the page broken?)")
		return 1
	}
	verdict: string = page[start + len("<title>"):end]
	fmt.printfln("%s (%s)", verdict, browser[strings.last_index_byte(browser, '/') + 1:])
	return 0 if strings.has_prefix(verdict, "SIMD128 PASS") else 1
}
