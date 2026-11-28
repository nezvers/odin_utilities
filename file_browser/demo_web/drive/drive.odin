// The click-through of the file browser web demo in a real browser, driven with browser_drive: open a picture and a sound through the file chooser of the browser, play, save both back (the page
// downloads them), invert the picture and save it again. What the page does is read from the downloads (a save only works when the file was opened) and from the console (no errors).
// The coordinates are the ones of the window pictures of the demo (1280 x 720).
package drive

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import browser_drive "../../../browser_drive"
import web_serve "../../../web_serve"

PICTURE :: "assets/textures/player_sheet.png"
SOUND :: "assets/sounds/damage_sound.wav"

ServeJob :: struct {
	server: ^web_serve.Server,
	stop: bool,
}

// Exit codes: 0 passed, 1 failed, 3 the browser is not installed
ClickThrough :: proc(directory: string, browser: browser_drive.Browser, screenshots: string) -> int {
	name: string = browser_drive.BrowserName(browser)
	picture, picture_error := filepath.abs(PICTURE, context.temp_allocator)
	sound, sound_error := filepath.abs(SOUND, context.temp_allocator)
	if picture_error != nil || sound_error != nil || !os.exists(picture) || !os.exists(sound) {
		fmt.eprintln("run it from odin_utilities: the assets are not found")
		return 1
	}

	server: web_serve.Server
	if !web_serve.ServerInit(&server, {directory = directory, port = 0}) {
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
	#partial switch error := browser_drive.DriverStart(driver, {browser = browser}); error {
	case .NONE:
	case .NO_BROWSER:
		fmt.printfln("%s is not installed: the click-through was not run", name)
		return 3
	case:
		fmt.printfln("%s did not start: %v %s", name, error, browser_drive.DriverLastError(driver))
		return 1
	}
	defer browser_drive.DriverStop(driver)

	failures: int
	check :: proc(failures: ^int, ok: bool, what: string, detail: string = "") {
		if ok { return }
		failures^ += 1
		fmt.printfln("  FAIL %s %s", what, detail)
	}
	shot :: proc(driver: ^browser_drive.Driver, directory: string, name: string, step: string) {
		if len(directory) == 0 { return }
		os.make_directory_all(directory)
		browser_drive.DriverScreenshot(driver, fmt.tprintf("%s/%s_%s.png", directory, name, step))
	}

	check(&failures, browser_drive.DriverNavigate(driver, fmt.tprintf("http://127.0.0.1:%d/", server.port)) == .NONE, "the page loads", browser_drive.DriverLastError(driver))
	// the wasm starts after the page: the demo draws into the canvas a moment later
	browser_drive.DriverWaitUntil(driver, "!!document.getElementById('webgl-canvas')")
	browser_drive.DriverWait(driver, 2500)
	check(&failures, browser_drive.DriverTrackDownloads(driver) == .NONE, "downloads are tracked")
	check(&failures, len(browser_drive.DriverConsoleErrors(driver)) == 0, "the page starts without console errors", browser_drive.DriverConsoleErrors(driver))
	shot(driver, screenshots, name, "1_start")

	// open a picture
	browser_drive.DriverAnswerFileChooser(driver, picture)
	browser_drive.DriverClick(driver, 84, 58)
	browser_drive.DriverWait(driver, 2500)
	check(&failures, browser_drive.DriverFileDialogs(driver) == 1, "Open picture opens the file chooser of the browser")
	shot(driver, screenshots, name, "2_picture")

	// open a sound, play it
	browser_drive.DriverAnswerFileChooser(driver, sound)
	browser_drive.DriverClick(driver, 224, 58)
	browser_drive.DriverWait(driver, 2500)
	check(&failures, browser_drive.DriverFileDialogs(driver) == 2, "Open sound opens the file chooser of the browser")
	browser_drive.DriverClick(driver, 274, 96)
	browser_drive.DriverWait(driver, 600)
	shot(driver, screenshots, name, "3_sound")

	// save both back: the buttons only work when the files were opened
	browser_drive.DriverClick(driver, 312, 58)
	browser_drive.DriverWait(driver, 1200)
	browser_drive.DriverClick(driver, 446, 58)
	browser_drive.DriverWait(driver, 1200)
	downloads: string = browser_drive.DriverDownloads(driver)
	check(&failures, strings.contains(downloads, "player_sheet.png:747"), "the picture is saved with its 747 bytes", downloads)
	check(&failures, strings.contains(downloads, "damage_sound.wav:27328"), "the sound is saved with its 27328 bytes", downloads)

	// change the picture, save it under its new name
	browser_drive.DriverClick(driver, 65, 96)
	browser_drive.DriverWait(driver, 800)
	browser_drive.DriverClick(driver, 312, 58)
	browser_drive.DriverWait(driver, 1200)
	downloads = browser_drive.DriverDownloads(driver)
	check(&failures, strings.contains(downloads, "player_sheet_inverted.png:"), "the inverted picture is saved under its new name", downloads)
	shot(driver, screenshots, name, "4_inverted")

	check(&failures, len(browser_drive.DriverConsoleErrors(driver)) == 0, "the page ends without console errors", browser_drive.DriverConsoleErrors(driver))
	if failures > 0 {
		fmt.printfln("%s click-through: FAILED, %d checks", name, failures)
		return 1
	}
	fmt.printfln("%s click-through: PASSED (%s)", name, downloads)
	return 0
}
