#+build !js
package web_build

// An optional check of a built page: load it in a headless browser and report what the page wrote to its console as an error (a failed import, an exception, a missing file). It catches what only a
// browser sees: the page that compiles and links and still does not start ("function import requires a callable", a wrong name in the imports, a 404). The browser is driven with `browser_drive`
// (Chrome, Edge or Firefox, the first one that is installed unless one is asked for); without any the status is NO_BROWSER and it never fails for that.
//
//     if !WebBuild(config) { ... }
//     result: WebBuildCheckResult = WebBuildCheck(config)
//     if result.status == .FAILED { fmt.eprintln(result.message) }

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"
import "core:thread"
import browser_drive "../browser_drive"
import web_serve "../web_serve"

// The longest a page gets to start: the template sets `window.odinStarted` after the first frame, and the check stops waiting at the first console error. A grace time after the signal
// catches what the first frames write.
WEB_BUILD_CHECK_START_MS :: 20000
WEB_BUILD_CHECK_GRACE_MS :: 500
WEB_BUILD_CHECK_POLL_MS :: 100 // one wait of the loop: it ends at once when the page has started

WebBuildCheckStatus :: enum {
    PASSED,
    FAILED,                 // the page wrote errors to its console, `message` lists them
    NO_BROWSER,             // no browser found: nothing was checked
    NOT_RUN,                // the check itself could not run (no build to load, no port, the browser did not start): `message` says why
}

WebBuildCheckResult :: struct {
    status: WebBuildCheckStatus,
    message: string,        // temp allocator
    browser: string,        // the browser that loaded the page: "chrome", "edge" or "firefox"
}

@(private = "file")
ServeJob :: struct {
    server: ^web_serve.Server,
    stop: bool,
}

// The first installed browser of Chrome, Edge and Firefox
WebBuildBrowserPick :: proc() -> (browser: browser_drive.Browser, found: bool) {
    for candidate in ([?]browser_drive.Browser{.CHROME, .EDGE, .FIREFOX}) {
        if len(browser_drive.BrowserFind(candidate)) > 0 { return candidate, true }
    }
    return {}, false
}

// Load the page that `WebBuild(config)` made (`<source>/bin/web`) and collect its console errors; `browser` asks for one browser, by default the first installed. Allocates the message with the temp
// allocator, and the driver (about 17 MB) for the time of the check.
WebBuildCheck :: proc(config: WebBuildConfig, browser: Maybe(browser_drive.Browser) = nil) -> WebBuildCheckResult {
    chosen, found := browser.?
    if !found { chosen, found = WebBuildBrowserPick() }
    if !found || len(browser_drive.BrowserFind(chosen)) == 0 { return {status = .NO_BROWSER, message = "no Chrome, Edge or Firefox found: the page was not loaded"} }
    name: string = browser_drive.BrowserName(chosen)
    paths: WebBuildPaths = WebBuildGetPaths(config, context.temp_allocator)
    if !os.exists(fmt.tprintf("%s/index.html", paths.output_directory)) {
        return {status = .NOT_RUN, browser = name, message = fmt.tprintf("web_build: %s has no index.html, build first", paths.output_directory)}
    }

    server: web_serve.Server
    if !web_serve.ServerInit(&server, {directory = paths.output_directory, port = 0}) {
        return {status = .NOT_RUN, browser = name, message = "web_build: could not listen on a free port"}
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
    if error := browser_drive.DriverStart(driver, {browser = chosen}); error != .NONE {
        return {status = .NOT_RUN, browser = name, message = fmt.tprintf("web_build: %s did not start: %v %s", name, error, browser_drive.DriverLastError(driver))}
    }
    defer browser_drive.DriverStop(driver)

    // a page that fails to start may also fail to report it as loaded: only an error of the browser itself (no connection) stops the check
    if error := browser_drive.DriverNavigate(driver, fmt.tprintf("http://127.0.0.1:%d/", server.port)); error == .CONNECT_FAILED || error == .CLOSED {
        return {status = .NOT_RUN, browser = name, message = fmt.tprintf("web_build: %s could not load the page: %s", name, browser_drive.DriverLastError(driver))}
    }
    started: bool
    deadline: time.Time = time.time_add(time.now(), WEB_BUILD_CHECK_START_MS * time.Millisecond)
    for time.diff(time.now(), deadline) > 0 && len(browser_drive.DriverConsoleErrors(driver)) == 0 {
        if browser_drive.DriverWaitUntil(driver, "window.odinStarted === true", WEB_BUILD_CHECK_POLL_MS) == .NONE {
            started = true
            break
        }
    }
    if started { browser_drive.DriverWait(driver, WEB_BUILD_CHECK_GRACE_MS) }
    errors: string = browser_drive.DriverConsoleErrors(driver)
    if len(errors) == 0 && !started {
        return {status = .FAILED, browser = name, message = fmt.tprintf("the page did not start in %d ms (window.odinStarted was never set) and wrote no console error", WEB_BUILD_CHECK_START_MS)}
    }
    if len(errors) == 0 { return {status = .PASSED, browser = name} }
    return {status = .FAILED, browser = name, message = strings.clone(strings.trim_space(errors), context.temp_allocator)}
}

// --- Tests ---

@(private = "file")
checkTinyPage :: proc(t: ^testing.T, name: string, imports_js: string, browser: browser_drive.Browser) -> (result: WebBuildCheckResult, built: bool) {
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
    return WebBuildCheck(config, browser), true
}

@(test)
test_a_page_that_starts_passes_and_a_page_that_does_not_fails_with_the_error :: proc(t: ^testing.T) {
    // one browser is enough here: browser_drive tests each of them
    ran: int
    for browser in ([?]browser_drive.Browser{.CHROME, .EDGE, .FIREFOX}) {
        if len(browser_drive.BrowserFind(browser)) == 0 || ran > 0 { continue }
        ran += 1
        name: string = browser_drive.BrowserName(browser)
        temp, _ := os.temp_directory(context.temp_allocator)
        defer os.remove_all(fmt.tprintf("%s/odin_utilities_web_build_check_good_%s", temp, name))
        defer os.remove_all(fmt.tprintf("%s/odin_utilities_web_build_check_bad_%s", temp, name))

        good, good_built := checkTinyPage(t, fmt.tprintf("good_%s", name), "", browser)
        testing.expectf(t, good_built, "%s: the good page builds", name)
        testing.expectf(t, good.status == .PASSED && good.browser == name, "%s: a page that starts has no console errors: %v %s", name, good.status, good.message)

        // imports that name something the page does not have: the page builds, links and does not start
        bad, bad_built := checkTinyPage(t, fmt.tprintf("bad_%s", name), "missingImportsOfThePage", browser)
        testing.expectf(t, bad_built, "%s: the bad page builds", name)
        testing.expectf(t, bad.status == .FAILED, "%s: a page that does not start fails: %v", name, bad.status)
        testing.expectf(t, strings.contains(bad.message, "missingImportsOfThePage"), "%s: the message names what is missing: %s", name, bad.message)
    }
    if ran == 0 { fmt.println("no browser: the page check test is skipped") }
}
