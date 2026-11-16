// Build the demo extension and optionally start a browser with it loaded. Run from the browser_extension directory:
//   odin run demo/tool -- [browser ...] [--install | --release [--no-open]] [--headless] [--browser-path PATH] [--firefox-port N] [-- odin arguments]
//
//   browser     chrome, opera, edge, firefox, all. Default all. chrome, opera and edge share the chromium build
//   --install   start the browser (a profile of its own in bin/extension/profile) with the extension loaded; with several browsers each one starts
//   --headless  without a window
//   --browser-path PATH   executable to start, when it is not in the usual install folder (one browser)
//   --firefox-port N      port of the Firefox remote debugging server, default 6000
//   --           everything after is passed to `odin build`, for example -o:size
// A real extension copies this file, changes the config and points source_directory at its own package.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import extension "../.."

main :: proc() {
	config: extension.ExtensionConfig = {
		source_directory = "demo",
		name = "Odin Extension Demo",
		version = "0.1.0",
		description = "A browser extension written in Odin (wasm)",
		id = "odin-extension-demo@odin-utilities",
		popup = true,
		// pages the content script runs in, empty for none
		content_matches = {"https://example.com/*"},
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
			config.odin_arguments = arguments[i + 1:]
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
	if !extension.ExtensionBuild(config, targets) {
		os.exit(1)
	}
	fmt.printfln("Built %s", extension.ExtensionOutputDirectory(config, context.temp_allocator))

	if release {
		// the browser of your main profile, the way a release is installed (see release.odin for what each browser allows)
		for browser in browsers {
			if !extension.ExtensionRelease(config, browser, {executable = options.executable, no_open = no_open}) {
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
	fmt.eprintln("usage: odin run demo/tool -- [chrome|opera|edge|firefox|all] [--install] [--headless] [--browser-path PATH] [--firefox-port N] [-- odin arguments]")
	os.exit(2)
}
