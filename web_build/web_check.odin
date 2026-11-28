#+build !js
package web_build

// An optional check of a built page: load it in a headless Chrome or Edge and report what the page wrote to its console as an error (a failed import, an exception, a missing file). It catches what
// only a browser sees: the page that compiles and links and still does not start ("function import requires a callable", a wrong name in the imports, a 404). It needs a browser on the machine
// (`WebBuildBrowserFind`), says NO_BROWSER when there is none and never fails for that.
//
//     if !WebBuild(config) { ... }
//     result: WebBuildCheckResult = WebBuildCheck(config)
//     if result.status == .FAILED { fmt.eprintln(result.message) }

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import web_serve "../web_serve"

// The browsers that can load a page without a window, in the order they are tried
WEB_BUILD_BROWSERS :: [?]string{
    "C:/Program Files/Google/Chrome/Application/chrome.exe",
    "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
    "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
    "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
}

// How long the page gets to start (virtual time of the browser: a page that waits for a timer is not waited for in real time)
WEB_BUILD_CHECK_WAIT_MS :: 8000

WebBuildCheckStatus :: enum {
    PASSED,
    FAILED,                 // the page wrote errors to its console, `message` lists them
    NO_BROWSER,             // no Chrome or Edge found: nothing was checked
    NOT_RUN,                // the check itself could not run (no build to load, no port, the browser did not start): `message` says why
}

WebBuildCheckResult :: struct {
    status: WebBuildCheckStatus,
    message: string,        // temp allocator
    browser: string,
}

// The first browser of WEB_BUILD_BROWSERS that is installed, or "" for none
WebBuildBrowserFind :: proc() -> string {
    for candidate in WEB_BUILD_BROWSERS {
        if os.exists(candidate) { return candidate }
    }
    return ""
}

@(private = "file")
ServeJob :: struct {
    server: ^web_serve.Server,
    stop: bool,
}

// Load the page that `WebBuild(config)` made (`<source>/bin/web`) and collect its console errors. Allocates the message with the temp allocator.
WebBuildCheck :: proc(config: WebBuildConfig) -> WebBuildCheckResult {
    browser: string = WebBuildBrowserFind()
    if len(browser) == 0 { return {status = .NO_BROWSER, message = "no Chrome or Edge found: the page was not loaded"} }
    paths: WebBuildPaths = WebBuildGetPaths(config, context.temp_allocator)
    if !os.exists(fmt.tprintf("%s/index.html", paths.output_directory)) {
        return {status = .NOT_RUN, browser = browser, message = fmt.tprintf("web_build: %s has no index.html, build first", paths.output_directory)}
    }

    server: web_serve.Server
    if !web_serve.ServerInit(&server, {directory = paths.output_directory, port = 0}) {
        return {status = .NOT_RUN, browser = browser, message = "web_build: could not listen on a free port"}
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

    // a profile of its own: a browser that is already open would take the request and exit. The console of the page is in the log of the browser (stderr).
    temp, _ := os.temp_directory(context.temp_allocator)
    profile: string = fmt.tprintf("%s/odin_utilities_web_build_check_profile", temp)
    defer os.remove_all(profile)
    command: []string = {
        browser, "--headless=new", "--disable-gpu", fmt.tprintf("--user-data-dir=%s", profile), "--enable-logging=stderr", "--v=0",
        fmt.tprintf("--virtual-time-budget=%d", WEB_BUILD_CHECK_WAIT_MS), "--dump-dom", fmt.tprintf("http://127.0.0.1:%d/", server.port),
    }
    state, _, stderr, error := os.process_exec({command = command}, context.temp_allocator)
    if error != nil || state.exit_code != 0 {
        return {status = .NOT_RUN, browser = browser, message = fmt.tprintf("web_build: the browser did not run: %v, exit code %d", error, state.exit_code)}
    }

    errors: [dynamic]string
    errors.allocator = context.temp_allocator
    for line in strings.split_lines(string(stderr), context.temp_allocator) {
        if !strings.contains(line, ":CONSOLE:") { continue }
        if webBuildConsoleError(line) { append(&errors, strings.trim_space(line[strings.index(line, ":CONSOLE:") + len(":CONSOLE:"):])) }
    }
    if len(errors) == 0 { return {status = .PASSED, browser = browser} }
    return {status = .FAILED, browser = browser, message = strings.join(errors[:], "\n", context.temp_allocator)}
}

// The log of the browser has a line for every console message, whatever its level: an error is told by its text (an uncaught exception, a failed load of a file, an error that the program printed)
@(private)
webBuildConsoleError :: proc(line: string) -> bool {
    markers := [?]string{"Uncaught", "Error:", "error:", "Failed to load resource", "Failed to fetch", "is not defined", "is not a function"}
    for marker in markers {
        if strings.contains(line, marker) { return true }
    }
    return false
}

// --- Tests ---

@(private = "file")
checkTinyPage :: proc(t: ^testing.T, name: string, imports_js: string) -> (result: WebBuildCheckResult, built: bool) {
    temp, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil { return {}, false }
    directory: string = fmt.tprintf("%s/odin_utilities_web_build_check_%s", temp, name)
    os.remove_all(directory)
    os.make_directory_all(directory)
    source :: `package tiny

init :: proc() {}

step :: proc() -> bool {
	return true
}

shutdown :: proc() {}
`
    if os.write_entire_file(fmt.tprintf("%s/tiny.odin", directory), source) != nil { return {}, false }
    config: WebBuildConfig = {source_directory = directory, title = "Tiny", imports_js = imports_js}
    if !WebBuild(config) { return {}, false }
    return WebBuildCheck(config), true
}

@(test)
test_a_page_that_starts_passes_and_a_page_that_does_not_fails_with_the_error :: proc(t: ^testing.T) {
    if WebBuildBrowserFind() == "" {
        fmt.println("no browser: the page check test is skipped")
        return
    }
    temp, _ := os.temp_directory(context.temp_allocator)
    defer os.remove_all(fmt.tprintf("%s/odin_utilities_web_build_check_good", temp))
    defer os.remove_all(fmt.tprintf("%s/odin_utilities_web_build_check_bad", temp))

    good, good_built := checkTinyPage(t, "good", "")
    testing.expect(t, good_built, "the good page builds")
    testing.expectf(t, good.status == .PASSED, "a page that starts has no console errors: %v %s", good.status, good.message)

    // imports that name something the page does not have: the page builds, links and does not start
    bad, bad_built := checkTinyPage(t, "bad", "missingImportsOfThePage")
    testing.expect(t, bad_built, "the bad page builds")
    testing.expectf(t, bad.status == .FAILED, "a page that does not start fails: %v", bad.status)
    testing.expectf(t, strings.contains(bad.message, "missingImportsOfThePage"), "the message names what is missing: %s", bad.message)
}
