#+build !js
// Start a browser with the built extension loaded, in a profile of its own (`<output>/profile/<browser>`) so the real profile is not
// touched and the extension is not remembered after the profile is deleted.
//
// Chromium browsers (Chrome, Opera, Edge): `--load-extension=<folder>`. Chrome 137+ ignores that switch unless the feature
// DisableLoadExtensionCommandLineSwitch is off, it is switched off here. If a browser still ignores it, load the folder by hand (README).
// Firefox: release builds only take unsigned extensions as temporary add-ons, the tool does what `web-ext run` does: starts Firefox with
// the remote debugging server and sends it `installTemporaryAddon` (firefox_remote.odin). Running the tool again reloads the add-on in the
// Firefox that is already open.
package browser_extension

import "core:fmt"
import "core:os"

Browser :: enum {
    CHROME,
    OPERA,
    EDGE,
    FIREFOX,
}

InstallOptions :: struct {
    executable: string,         // path of the browser, empty - looked up in the usual install folders
    profile_directory: string,  // empty - "<output>/profile/<browser>"
    debugger_port: int,         // Firefox remote debugging port, default 6000
    headless: bool,             // no window, for scripts and tests
}

DEFAULT_DEBUGGER_PORT :: 6000

BrowserTarget :: proc(browser: Browser) -> Target {
    return .FIREFOX if browser == .FIREFOX else .CHROMIUM
}

BrowserName :: proc(browser: Browser) -> string {
    switch browser {
    case .CHROME: return "chrome"
    case .OPERA: return "opera"
    case .EDGE: return "edge"
    case .FIREFOX: return "firefox"
    }
    return ""
}

// Folders a browser is installed in on Windows, `%NAME%` parts are environment variables. Other systems start the name from PATH.
@(private)
BROWSER_WINDOWS_PATHS :: [Browser][]string {
    .CHROME = {"%ProgramFiles%/Google/Chrome/Application/chrome.exe", "%ProgramFiles(x86)%/Google/Chrome/Application/chrome.exe", "%LOCALAPPDATA%/Google/Chrome/Application/chrome.exe"},
    .OPERA = {"%LOCALAPPDATA%/Programs/Opera/opera.exe", "%LOCALAPPDATA%/Programs/Opera GX/opera.exe", "%ProgramFiles%/Opera/opera.exe"},
    .EDGE = {"%ProgramFiles(x86)%/Microsoft/Edge/Application/msedge.exe", "%ProgramFiles%/Microsoft/Edge/Application/msedge.exe"},
    .FIREFOX = {"%ProgramFiles%/Mozilla Firefox/firefox.exe", "%ProgramFiles(x86)%/Mozilla Firefox/firefox.exe"},
}

@(private)
BROWSER_COMMANDS :: [Browser]string {
    .CHROME = "google-chrome",
    .OPERA = "opera",
    .EDGE = "microsoft-edge",
    .FIREFOX = "firefox",
}

// Where the browser is installed. Not found - ok is false, pass InstallOptions.executable then.
BrowserFind :: proc(browser: Browser, allocator := context.temp_allocator) -> (path: string, ok: bool) {
    when ODIN_OS == .Windows {
        paths := BROWSER_WINDOWS_PATHS
        for candidate in paths[browser] {
            // "%NAME%/rest" -> value of NAME + "/rest"
            end: int
            for character, index in candidate[1:] {
                if character == '%' {
                    end = index + 1
                    break
                }
            }
            value, found := os.lookup_env(candidate[1:end], context.temp_allocator)
            if !found {
                continue
            }
            full: string = fmt.aprintf("%s%s", value, candidate[end + 1:], allocator = allocator)
            if os.exists(full) {
                return full, true
            }
        }
        return
    } else {
        commands := BROWSER_COMMANDS
        return commands[browser], true
    }
}

// Starts the browser with the extension of the config loaded and returns. The browser keeps running after the tool exits.
// The extension has to be built first (ExtensionBuild).
ExtensionInstall :: proc(config: ExtensionConfig, browser: Browser, options: InstallOptions = {}) -> bool {
    executable: string = options.executable
    if len(executable) == 0 {
        found: bool
        executable, found = BrowserFind(browser)
        if !found {
            fmt.eprintfln("browser_extension: %s was not found, pass its path (-browser-path)", BrowserName(browser))
            return false
        }
    }

    directory, directory_error := os.get_absolute_path(ExtensionTargetDirectory(config, BrowserTarget(browser), context.temp_allocator), context.temp_allocator)
    if directory_error != nil || !os.exists(fmt.tprintf("%s/manifest.json", directory)) {
        fmt.eprintfln("browser_extension: nothing built in %s, build first", directory)
        return false
    }
    profile: string = options.profile_directory
    if len(profile) == 0 {
        profile = fmt.tprintf("%s/profile/%s", ExtensionOutputDirectory(config, context.temp_allocator), BrowserName(browser))
    }
    profile, _ = os.get_absolute_path(profile, context.temp_allocator)
    if os.make_directory_all(profile) != nil {
        fmt.eprintfln("browser_extension: could not create the profile folder %s", profile)
        return false
    }

    if browser == .FIREFOX {
        return FirefoxInstall(executable, profile, directory, options)
    }

    command: [dynamic]string
    command.allocator = context.temp_allocator
    append(&command, executable)
    append(&command, fmt.tprintf("--user-data-dir=%s", profile), fmt.tprintf("--load-extension=%s", directory))
    append(&command, "--disable-features=DisableLoadExtensionCommandLineSwitch", "--no-first-run", "--no-default-browser-check")
    if options.headless {
        append(&command, "--headless=new")
    }
    _, error := os.process_start({command = command[:]})
    if error != nil {
        fmt.eprintfln("browser_extension: could not start %s", executable)
        return false
    }
    return true
}
