#+build !js
// Install the extension for good in the browser you use every day (your main profile), the way a release is installed: it stays after the
// browser restarts, it does not depend on the debugging flags of ExtensionInstall, and updating is running the same command again.
//
// What a browser allows is different, so the steps differ:
//   Chrome, Opera, Edge   A release browser takes no packaged extension that is not from its store, and it ignores --load-extension for a profile that is
//                         already running. What stays is an unpacked extension that you load once in developer mode. So the build is copied to a
//                         folder that does not move (`<local app data>/<name>/chromium`), the native helper next to it, the helper is registered
//                         for the id that folder gives, and the browser is opened on its extensions page with the folder in the clipboard.
//                         You press Load unpacked once and paste. An update is this command again and the reload button of the extension.
//   Firefox               A release Firefox only keeps an extension that Mozilla signed. The build is signed with `web-ext sign` (channel
//                         unlisted: no review, no listing, the file is yours) and the signed .xpi is opened in Firefox. That needs a free
//                         key from addons.mozilla.org/developers/addon/api/key, in the environment as WEB_EXT_API_KEY and
//                         WEB_EXT_API_SECRET, and Node.js (npx). Every release needs a new `version` in the config, Mozilla refuses a version twice.
package browser_extension

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

ReleaseOptions :: struct {
    executable: string,     // the browser, empty - looked up in the usual install folders
    no_open: bool,          // copy and register, but do not touch the browser (tests)
}

// The folder of the release copy of everything: <local app data>/<name> (Windows), <home>/.local/share/<name> elsewhere
ReleaseRoot :: proc(config: ExtensionConfig, allocator := context.temp_allocator) -> string {
    safe_name, _ := strings.replace_all(config.name, " ", "_", context.temp_allocator)
    when ODIN_OS == .Windows {
        base, _ := os.lookup_env("LOCALAPPDATA", context.temp_allocator)
        return fmt.aprintf("%s/%s", base, safe_name, allocator = allocator)
    } else {
        home, _ := os.lookup_env("HOME", context.temp_allocator)
        return fmt.aprintf("%s/.local/share/%s", home, safe_name, allocator = allocator)
    }
}

// Where the release copy of a target is. The folder is the identity of a Chromium extension (its id comes from the path), so it never changes.
ReleaseTargetDirectory :: proc(config: ExtensionConfig, target: Target, allocator := context.temp_allocator) -> string {
    return fmt.aprintf("%s/%s", ReleaseRoot(config, context.temp_allocator), "chromium" if target == .CHROMIUM else "firefox", allocator = allocator)
}

// What an address of this system looks like to the programs that take paths from the command line
@(private)
nativePath :: proc(path: string) -> string {
    when ODIN_OS == .Windows {
        return strings.replace_all(path, "/", "\\", context.temp_allocator) or_else path
    } else {
        return path
    }
}

// A folder with the contents of another. robocopy /MIR on Windows (exit codes below 8 are fine), cp elsewhere.
@(private)
copyFolder :: proc(from, to: string) -> bool {
    absolute_from, from_error := os.get_absolute_path(from, context.temp_allocator)
    if from_error != nil {
        return false
    }
    os.make_directory_all(to)
    absolute_to, to_error := os.get_absolute_path(to, context.temp_allocator)
    if to_error != nil {
        return false
    }
    when ODIN_OS == .Windows {
        state, _, _, error := os.process_exec({command = {"robocopy", nativePath(absolute_from), nativePath(absolute_to), "/MIR", "/NFL", "/NDL", "/NJH", "/NJS", "/NP"}}, context.temp_allocator)
        return error == nil && state.exit_code < 8
    } else {
        os.remove_all(absolute_to)
        state, _, _, error := os.process_exec({command = {"cp", "-R", absolute_from, absolute_to}}, context.temp_allocator)
        return error == nil && state.exit_code == 0
    }
}

@(private)
copyToClipboard :: proc(text: string) -> bool {
    when ODIN_OS == .Windows {
        state, _, _, error := os.process_exec({command = {"powershell", "-NoProfile", "-Command", fmt.tprintf("Set-Clipboard -Value '%s'", text)}}, context.temp_allocator)
        return error == nil && state.exit_code == 0
    } else {
        return false
    }
}

@(private)
EXTENSIONS_PAGE :: [Browser]string {
    .CHROME = "chrome://extensions",
    .OPERA = "opera://extensions",
    .EDGE = "edge://extensions",
    .FIREFOX = "about:addons",
}

// Copies the build and the helper to the release folder and finishes the install the way the browser allows. False when a step failed.
// The extension has to be built first (ExtensionBuild).
ExtensionRelease :: proc(config: ExtensionConfig, browser: Browser, options: ReleaseOptions = {}) -> bool {
    target: Target = BrowserTarget(browser)
    built: string = ExtensionTargetDirectory(config, target, context.temp_allocator)
    if !os.exists(fmt.tprintf("%s/manifest.json", built)) {
        fmt.eprintfln("browser_extension: nothing built in %s, build first", built)
        return false
    }
    executable: string = options.executable
    if len(executable) == 0 && !options.no_open {
        found: bool
        executable, found = BrowserFind(browser)
        if !found {
            fmt.eprintfln("browser_extension: %s was not found, pass its path (-browser-path)", BrowserName(browser))
            return false
        }
    }

    stage: string = ReleaseTargetDirectory(config, target, context.temp_allocator)
    if !copyFolder(built, stage) {
        fmt.eprintfln("browser_extension: could not copy the build to %s", stage)
        return false
    }
    fmt.printfln("Copied the build to %s", stage)

    // the helper is copied too, so a rebuild in the project does not change what the browser runs
    if len(config.native_host) > 0 && len(config.native_host_executable) > 0 {
        native_folder: string = fmt.tprintf("%s/native", ReleaseRoot(config, context.temp_allocator))
        os.make_directory_all(native_folder)
        helper: string = fmt.tprintf("%s/%s", native_folder, FileName(config.native_host_executable))
        if os.copy_file(helper, config.native_host_executable) != nil {
            fmt.eprintfln("browser_extension: could not copy the native host to %s (is it running? close the browser and try again)", helper)
            return false
        }
        if !NativeHostRegister(config, browser, helper, native_folder) {
            return false
        }
        fmt.printfln("Registered the native host %s for %s", config.native_host, BrowserName(browser))
    }

    if target == .FIREFOX {
        return releaseFirefox(config, stage, executable, options)
    }

    absolute_stage, _ := os.get_absolute_path(stage, context.temp_allocator)
    pages := EXTENSIONS_PAGE
    clipboard_ok: bool = !options.no_open && copyToClipboard(nativePath(absolute_stage))
    fmt.printfln("")
    fmt.printfln("Last step, once, in %s (an update later is: run this again, press the reload button of the extension):", BrowserName(browser))
    fmt.printfln("  1. %s: switch Developer mode on", pages[browser])
    fmt.printfln("  2. Load unpacked, choose this folder%s:", " (it is in the clipboard)" if clipboard_ok else "")
    fmt.printfln("     %s", nativePath(absolute_stage))
    if options.no_open {
        return true
    }
    // the main profile: no --user-data-dir. A running browser opens the page in a new tab.
    _, error := os.process_start({command = {executable, pages[browser]}})
    if error != nil {
        fmt.eprintfln("browser_extension: could not start %s", executable)
        return false
    }
    when ODIN_OS == .Windows {
        _, _ = os.process_start({command = {"explorer", nativePath(absolute_stage)}})
    }
    return true
}

// Signs the Firefox build with Mozilla (unlisted) and opens the signed file in Firefox, which asks to add it
@(private)
releaseFirefox :: proc(config: ExtensionConfig, stage, executable: string, options: ReleaseOptions) -> bool {
    key, has_key := os.lookup_env("WEB_EXT_API_KEY", context.temp_allocator)
    _, has_secret := os.lookup_env("WEB_EXT_API_SECRET", context.temp_allocator)
    if !has_key || len(key) == 0 || !has_secret {
        fmt.eprintln("")
        fmt.eprintln("A release Firefox keeps only extensions that Mozilla signed. Get a free API key (JWT issuer and secret) at")
        fmt.eprintln("  https://addons.mozilla.org/developers/addon/api/key/")
        fmt.eprintln("and set the environment variables WEB_EXT_API_KEY (the issuer) and WEB_EXT_API_SECRET, then run this again.")
        fmt.eprintln("The signing is `unlisted`: no review of the code, no page on the add-ons site, the signed file is yours.")
        return false
    }

    artifacts: string = fmt.tprintf("%s/signed", ReleaseRoot(config, context.temp_allocator))
    os.make_directory_all(artifacts)
    absolute_stage, _ := os.get_absolute_path(stage, context.temp_allocator)
    fmt.printfln("Signing with Mozilla (this waits for the result, up to a few minutes)...")
    command: [dynamic]string
    command.allocator = context.temp_allocator
    when ODIN_OS == .Windows {
        append(&command, "cmd", "/c")
    }
    append(&command, "npx", "--yes", "web-ext", "sign", "--source-dir", nativePath(absolute_stage), "--artifacts-dir", nativePath(artifacts), "--channel", "unlisted")
    state, stdout, errors, error := os.process_exec({command = command[:]}, context.temp_allocator)
    if error != nil || state.exit_code != 0 {
        fmt.eprintfln("browser_extension: signing failed\n%s\n%s", string(stdout), string(errors))
        fmt.eprintln("(the version in the config has to be new for every signing: Mozilla refuses one version twice)")
        return false
    }

    // the newest .xpi of the folder is the one just made
    files, files_error := os.read_all_directory_by_path(artifacts, context.temp_allocator)
    if files_error != nil {
        return false
    }
    newest: os.File_Info
    for file in files {
        if strings.has_suffix(file.name, ".xpi") && (len(newest.name) == 0 || file.modification_time._nsec > newest.modification_time._nsec) {
            newest = file
        }
    }
    if len(newest.name) == 0 {
        fmt.eprintfln("browser_extension: signing finished but there is no .xpi in %s", artifacts)
        return false
    }
    fmt.printfln("Signed: %s", newest.fullpath)
    if options.no_open {
        return true
    }
    // Firefox shows the "add this extension" prompt for a file it is given, in the profile you use
    _, start_error := os.process_start({command = {executable, newest.fullpath}})
    if start_error != nil {
        fmt.eprintfln("browser_extension: could not start %s", executable)
        return false
    }
    fmt.printfln("Firefox asks to add the extension: accept it.")
    return true
}

// --- Tests ---

@(test)
test_release_folders :: proc(t: ^testing.T) {
    config: ExtensionConfig = {name = "My Ext"}
    root: string = ReleaseRoot(config)
    testing.expect(t, strings.has_suffix(root, "/My_Ext"), "the name makes the folder, spaces become _")
    testing.expect_value(t, ReleaseTargetDirectory(config, .CHROMIUM), fmt.tprintf("%s/chromium", root))
    testing.expect_value(t, ReleaseTargetDirectory(config, .FIREFOX), fmt.tprintf("%s/firefox", root))
}
