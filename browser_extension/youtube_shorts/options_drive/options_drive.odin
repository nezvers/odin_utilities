// The options page of the YouTube Shorts extension in a real browser, driven with browser_drive: the browser loads the built extension, the page is opened as an extension page
// (chrome-extension://<id>/options/options.html) and clicked. What the buttons did is read from the background itself (the same "get" message the page sends), so the whole way is
// tested: the Karl2D page, the wasm of the page, the browser messages, the wasm of the background and its storage. Chrome and Edge only: a Firefox extension page has a random
// moz-extension address that BiDi does not tell.
package options_drive

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import browser_drive "../../../browser_drive"

// Where the toggles of the page are (the page is 960 x 600 drawn in a 1280 x 720 tab, see options.odin: ROW_HEIGHT, rows from the top)
REDIRECT_BUTTON :: [2]f64{260, 98}
SAVE_BUTTON :: [2]f64{260, 144}

SETTINGS_DEFAULT :: "redirect=0 save=1 download=1"

// `folder` is the unpacked Chromium build (youtube_shorts/bin/extension/chromium), `name` the manifest name. Exit codes: 0 passed, 1 failed, 3 the browser is not installed or does not load
// extensions from the command line (the branded Chrome since 137 does not, Edge does).
OptionsCheck :: proc(folder: string, name: string, browser: browser_drive.Browser, screenshots: string) -> int {
	browser_name: string = browser_drive.BrowserName(browser)
	absolute, path_error := filepath.abs(folder, context.temp_allocator)
	if path_error != nil {
		fmt.eprintfln("%s: no such folder", folder)
		return 1
	}
	driver: ^browser_drive.Driver = new(browser_drive.Driver)
	defer free(driver)
	#partial switch error := browser_drive.DriverStart(driver, {browser = browser, extension = absolute}); error {
	case .NONE:
	case .NO_BROWSER:
		fmt.printfln("%s is not installed: the options page was not checked", browser_name)
		return 3
	case:
		fmt.printfln("%s did not start: %v %s", browser_name, error, browser_drive.DriverLastError(driver))
		return 1
	}
	defer browser_drive.DriverStop(driver)

	id: string = strings.clone(browser_drive.DriverExtensionId(driver, name), context.temp_allocator)
	if len(id) == 0 {
		fmt.printfln("%s did not load the extension (it ignores --load-extension): the options page was not checked", browser_name)
		return 3
	}
	url: string = fmt.tprintf("chrome-extension://%s/options/options.html", id)

	failures: int
	check :: proc(failures: ^int, ok: bool, what: string, detail: string = "") {
		if ok { return }
		failures^ += 1
		fmt.printfln("  FAIL %s %s", what, detail)
	}
	shot :: proc(driver: ^browser_drive.Driver, folder, browser_name, step: string) {
		if len(folder) == 0 { return }
		browser_drive.DriverScreenshot(driver, fmt.tprintf("%s/options_%s_%s.png", folder, browser_name, step))
	}
	// what the background keeps, asked the way the page asks
	settings :: proc(driver: ^browser_drive.Driver) -> string {
		text, _ := browser_drive.DriverEvaluate(driver, `chrome.runtime.sendMessage("get")`)
		return strings.clone(text, context.temp_allocator)
	}

	check(&failures, browser_drive.DriverNavigate(driver, url) == .NONE, "the options page loads", browser_drive.DriverLastError(driver))
	// the page starts its wasm and asks the background for the settings
	browser_drive.DriverWait(driver, 1500)
	shot(driver, screenshots, browser_name, "1_start")
	check(&failures, settings(driver) == SETTINGS_DEFAULT, "a new profile has the defaults", settings(driver))

	click :: proc(driver: ^browser_drive.Driver, at: [2]f64) {
		browser_drive.DriverClick(driver, at.x, at.y)
		browser_drive.DriverWait(driver, 500)
	}
	click(driver, REDIRECT_BUTTON)
	check(&failures, settings(driver) == "redirect=1 save=1 download=1", "the first button switches the redirect on", settings(driver))
	click(driver, SAVE_BUTTON)
	check(&failures, settings(driver) == "redirect=1 save=0 download=1", "the second button switches the save button off", settings(driver))
	shot(driver, screenshots, browser_name, "2_changed")

	// a page that is opened again shows what the background kept
	check(&failures, browser_drive.DriverNavigate(driver, url) == .NONE, "the options page loads again")
	browser_drive.DriverWait(driver, 1500)
	check(&failures, settings(driver) == "redirect=1 save=0 download=1", "the settings stay after the page is opened again", settings(driver))
	click(driver, REDIRECT_BUTTON)
	check(&failures, settings(driver) == "redirect=0 save=0 download=1", "the first button switches it off again", settings(driver))
	shot(driver, screenshots, browser_name, "3_again")

	errors: string = browser_drive.DriverConsoleErrors(driver)
	check(&failures, len(errors) == 0, "the page writes no console errors", errors)
	if failures > 0 {
		fmt.printfln("%s options page: FAILED, %d checks", browser_name, failures)
		return 1
	}
	fmt.printfln("%s options page: PASSED", browser_name)
	return 0
}
