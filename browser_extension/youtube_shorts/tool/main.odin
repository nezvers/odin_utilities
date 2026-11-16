// Build the YouTube Shorts extension and optionally start a browser with it loaded. Run from the browser_extension directory:
//   odin run youtube_shorts/tool -- [browser ...] [--install | --release [--no-open]] [--headless] [--browser-path PATH] [--firefox-port N] [-- odin arguments]
// Same arguments as demo/tool, see there. The output is in youtube_shorts/bin/extension.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import extension "../.."

HELPER_EXECUTABLE :: "youtube_shorts/bin/native/shorts_helper_host.exe" when ODIN_OS == .Windows else "youtube_shorts/bin/native/shorts_helper_host"

main :: proc() {
	config: extension.ExtensionConfig = {
		source_directory = "youtube_shorts/background",
		output_directory = "youtube_shorts/bin/extension",
		name = "Shorts Helper",
		version = "0.1.0",
		description = "Open YouTube Shorts as full videos, save Shorts from the desktop player. Written in Odin.",
		id = "shorts-helper@odin-utilities",
		permissions = {"storage"},
		// the toolbar button opens a small popup with the settings (the full options page is behind a button in it)
		popup = true,
		popup_file = "youtube_shorts/popup.html",
		popup_script_file = "youtube_shorts/popup.js",
		// the Download button runs yt-dlp / youtube-dl through this program, ExtensionInstall registers it for the browser
		native_host = "com.odin_utilities.shorts_helper",
		native_host_executable = HELPER_EXECUTABLE,
		// the content script asks the background what to do on every page of YouTube, at the start so a redirect is early
		content_matches = {"https://www.youtube.com/*", "https://m.youtube.com/*", "https://youtube.com/*"},
		content_script_file = "youtube_shorts/youtube_content.js",
		content_run_at = "document_start",
		options = {
			title = "Shorts Helper options",
			web = {
				source_directory = "youtube_shorts/host_karl2d",
				title = "Shorts Helper options",
				// Karl2D plays audio through JavaScript on the web
				copy_files = {"../karl2d/audio_backend_web_audio.js", "../karl2d/audio_backend_web_audio_processor.js"},
				scripts = {"audio_backend_web_audio.js"},
				imports_js = "karl2dAudioJsImports",
				start_js = "setKarl2dAudioWasmMemory(exports.memory);",
			},
		},
	}
	browsers: bit_set[extension.Browser]
	options: extension.InstallOptions
	install: bool
	release: bool
	no_open: bool

	arguments: []string = os.args[1:]
	for i := 0; i < len(arguments); i += 1 {
		switch arguments[i] {
		case "chrome": browsers += {.CHROME}
		case "opera": browsers += {.OPERA}
		case "edge": browsers += {.EDGE}
		case "firefox": browsers += {.FIREFOX}
		case "all": browsers += {.CHROME, .OPERA, .EDGE, .FIREFOX}
		case "--install": install = true
		case "--headless": options.headless = true
		case "--release": release = true
		case "--no-open": no_open = true
		case "--browser-path":
			i += 1
			if i >= len(arguments) { usage(); return }
			options.executable = arguments[i]
		case "--firefox-port":
			i += 1
			if i >= len(arguments) { usage(); return }
			port, ok := strconv.parse_int(arguments[i])
			if !ok { usage(); return }
			options.debugger_port = port
		case "--":
			// the options page and the background are both built with these
			config.odin_arguments = arguments[i + 1:]
			config.options.web.odin_arguments = arguments[i + 1:]
			i = len(arguments)
		case:
			usage()
			return
		}
	}
	if browsers == {} {
		browsers = {.CHROME, .OPERA, .EDGE, .FIREFOX}
	}

	targets: bit_set[extension.Target]
	for browser in browsers {
		targets += {extension.BrowserTarget(browser)}
	}
	if !buildHelper() {
		os.exit(1)
	}
	if !extension.ExtensionBuild(config, targets) {
		os.exit(1)
	}
	fmt.printfln("Built %s", extension.ExtensionOutputDirectory(config, context.temp_allocator))

	if release {
		// the browser of your main profile, the way a release is installed (see release.odin for what each browser allows)
		signing_key, signing_secret := SigningCredentials()
		for browser in browsers {
			if !extension.ExtensionRelease(config, browser, {executable = options.executable, no_open = no_open, signing_key = signing_key, signing_secret = signing_secret}) {
				os.exit(1)
			}
		}
		return
	}
	if install {
		for browser in browsers {
			if !extension.ExtensionInstall(config, browser, options) {
				os.exit(1)
			}
			fmt.printfln("Started %s with the extension", extension.BrowserName(browser))
		}
	}
}

usage :: proc() {
	fmt.eprintln("usage: odin run youtube_shorts/tool -- [chrome|opera|edge|firefox|all] [--install] [--headless] [--browser-path PATH] [--firefox-port N] [-- odin arguments]")
	os.exit(2)
}

// The native messaging program of the Download button
buildHelper :: proc() -> bool {
	os.make_directory_all("youtube_shorts/bin/native")
	command: [dynamic]string
	command.allocator = context.temp_allocator
	append(&command, "odin", "build", "youtube_shorts/native_host", fmt.tprintf("-out:%s", HELPER_EXECUTABLE), "-o:speed")
	state, _, errors, error := os.process_exec({command = command[:]}, context.temp_allocator)
	if error != nil || state.exit_code != 0 {
		fmt.eprintfln("building the download helper failed\n%s", string(errors))
		return false
	}
	return true
}
