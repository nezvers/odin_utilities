// Runs only the tests that a change can break, and prints little: one line per package, the failures in full.
//
//     odin run tool/test                    the packages of the uncommitted changes (staged, unstaged, untracked) and the packages that import them
//     odin run tool/test -- --since main    the changes since a commit or branch (committed ones too)
//     odin run tool/test -- ui reports      these packages, whatever changed
//     odin run tool/test -- --all           every package that has tests
//     odin run tool/test -- --list          only say which packages would run
//     odin run tool/test -- --verbose       print the whole output of a failing package, not only its errors
//     odin run tool/test -- --cross         instead of the tests: `odin check` the selected packages (with or without tests) for linux_amd64 and darwin_arm64, which finds what only Windows
//                                           compiles (an import that is used only in a `when ODIN_OS == .Windows` branch, a Windows only call). A package that stops at a missing vendor library
//                                           ("Compile time panic") or builds only for the web is said to be unchecked, not failed
//     odin run tool/test -- --levels        also run the packages that use the `simd` library once per instruction set level (SIMD_LEVEL=scalar, sse2, sse4.2, avx, avx2, avx512;
//                                           a level above the CPU runs its best), so the kernels of the lower levels run on a machine that has more
//     odin run tool/test -- --browser       also run the checks that need a browser, when the package they belong to is selected: `simd` runs its SIMD128 text kernels in every installed browser
//                                           (simd/web_check), and the web demos load their page in it and report console errors (`--check` of file_browser/demo_web and web_build/demo_karl2d:
//                                           they build first, so it takes a while). A check runs when a package it depends on is selected. Without a browser on the machine it says so and does not fail
//
// Run it from odin_utilities. A package is a folder with .odin files; one is tested when it has an @(test) proc. A change in a folder
// counts for that package and, through the imports (`import x "../ui"`), for every package that uses it, so a change of `ui` also runs
// `ui/demo_common`. Exit code 0: all passed (or nothing to run), 1: a test failed or a package did not build, 2: wrong argument.
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// "templates/": the template of a library has the imports of the place a copy of it goes to, it does not build where it is
SKIP_PREFIXES :: [?]string{"karl2d/", "references/", "scratch/", "hot_reload_demo/", "templates/"}
// Packages whose tests read files by a path from their own folder: they are run there
OWN_DIRECTORY :: [?]string{"3d_models"}
MAX_ERROR_LINES :: 12

Package :: struct {
    dir: string,
    files: [dynamic]string,
    imports: [dynamic]string,            // directories (resolved) of the packages this one imports
    has_tests: bool,
}

main :: proc() {
    explicit: [dynamic]string
    since: string
    all, list, verbose, levels, cross, browser: bool
    arguments: []string = os.args[1:]
    for i := 0; i < len(arguments); i += 1 {
        switch arguments[i] {
        case "--all": all = true
        case "--list": list = true
        case "--verbose": verbose = true
        case "--levels": levels = true
        case "--cross": cross = true
        case "--browser": browser = true
        case "--since":
            i += 1
            if i >= len(arguments) { fail("--since needs a commit or branch") }
            since = arguments[i]
        case:
            if strings.has_prefix(arguments[i], "--") { fail(fmt.tprintf("unknown option %s", arguments[i])) }
            append(&explicit, strings.trim_right(arguments[i], "/\\"))
        }
    }

    tracked: [dynamic]string = gitLines({"git", "ls-files", "--", "*.odin"})
    packages: map[string]^Package
    for path in tracked {
        if skipped(path) { continue }
        dir: string = directoryOf(path)
        package_found: ^Package = packages[dir]
        if package_found == nil {
            package_found = new(Package)
            package_found.dir = dir
            packages[dir] = package_found
        }
        append(&package_found.files, path)
        scanFile(package_found, path)
    }

    selected: map[string]bool
    switch {
    case all:
        for dir, package_found in packages { if package_found.has_tests || cross { selected[dir] = true } }
    case len(explicit) > 0:
        for dir in explicit {
            if dir not_in packages { fail(fmt.tprintf("no package %s", dir)) }
            selected[dir] = true
        }
    case:
        changed: map[string]bool = changedPackages(since, packages)
        // the packages that import a changed one, again and again, until nothing is added
        grew: bool = true
        for grew {
            grew = false
            for dir, package_found in packages {
                if dir in changed { continue }
                for imported in package_found.imports {
                    if imported in changed { changed[dir] = true; grew = true; break }
                }
            }
        }
        for dir in changed {
            if package_found, found := packages[dir]; found && (package_found.has_tests || cross) { selected[dir] = true }
        }
    }

    order: [dynamic]string
    for dir in selected { append(&order, dir) }
    slice.sort(order[:])
    if len(order) == 0 {
        fmt.println("nothing to test: no changed package has tests")
        return
    }
    if list {
        for dir in order { fmt.println(dir) }
        return
    }

    failures: int
    start: time.Tick = time.tick_now()
    if cross {
        unchecked: int
        for dir in order {
            switch crossCheck(dir, packages[dir]) {
            case .OK:
            case .FAILED: failures += 1
            case .UNCHECKED: unchecked += 1
            }
        }
        seconds: f64 = time.duration_seconds(time.tick_since(start))
        if failures > 0 {
            fmt.printfln("FAILED: %d of %d packages do not build for Linux or macOS (%d unchecked, %.1f s)", failures, len(order), unchecked, seconds)
            os.exit(1)
        }
        fmt.printfln("%d packages check for Linux and macOS, %d are unchecked (%.1f s)", len(order) - unchecked, unchecked, seconds)
        return
    }
    for dir in order {
        if !runPackage(dir, verbose) { failures += 1 }
    }
    if levels {
        for dir in order {
            uses: bool = dir == "simd" || dir == "simd/example"
            for imported in packages[dir].imports {
                if imported == "simd" { uses = true }
            }
            if uses && !runLevels(dir, verbose) { failures += 1 }
        }
    }
    if browser {
        for check in BROWSER_CHECKS {
            run: bool = all
            for dir in order {
                for trigger in check.triggers {
                    if dir == trigger { run = true }
                }
            }
            if run && !runBrowserCheck(check.name, check.command, check.working_dir) { failures += 1 }
        }
    }
    seconds: f64 = time.duration_seconds(time.tick_since(start))
    if failures > 0 {
        fmt.printfln("FAILED: %d failures in %d packages and browser checks (%.1f s)", failures, len(order), seconds)
        os.exit(1)
    }
    fmt.printfln("all %d packages passed (%.1f s)", len(order), seconds)
}

fail :: proc(message: string) {
    fmt.eprintln(message)
    os.exit(2)
}

skipped :: proc(path: string) -> bool {
    for prefix in SKIP_PREFIXES {
        if strings.has_prefix(path, prefix) { return true }
    }
    return false
}

directoryOf :: proc(path: string) -> string {
    slash: int = strings.last_index_byte(path, '/')
    if slash < 0 { return "." }
    return path[:slash]
}

// The test marker and the relative imports of one file
scanFile :: proc(package_found: ^Package, path: string) {
    bytes, err := os.read_entire_file(path, context.allocator)
    if err != nil { return }
    text: string = string(bytes)
    for line in strings.split_lines_iterator(&text) {
        trimmed: string = strings.trim_space(line)
        if strings.has_prefix(line, "@(test)") { package_found.has_tests = true }     // at the start of a line: a mention in a string or a comment is not a test
        if !strings.has_prefix(trimmed, "import ") { continue }
        open: int = strings.index_byte(trimmed, '"')
        close: int = strings.last_index_byte(trimmed, '"')
        if open < 0 || close <= open { continue }
        target: string = trimmed[open + 1:close]
        if !strings.has_prefix(target, ".") { continue }
        append(&package_found.imports, resolve(package_found.dir, target))
    }
}

// `dir` + a relative import path, without . and .. parts
resolve :: proc(dir: string, relative: string) -> string {
    parts: [dynamic]string
    if dir != "." {
        for part in strings.split(dir, "/", context.temp_allocator) { append(&parts, part) }
    }
    for part in strings.split(relative, "/", context.temp_allocator) {
        switch part {
        case ".", "": continue
        case "..": if len(parts) > 0 { pop(&parts) }
        case: append(&parts, part)
        }
    }
    if len(parts) == 0 { return "." }
    return strings.join(parts[:], "/")
}

// The folders of the changed files that are packages (a changed file that is not Odin, a test asset or a golden picture, counts for the nearest package above it)
changedPackages :: proc(since: string, packages: map[string]^Package) -> map[string]bool {
    files: [dynamic]string
    if since != "" {
        for line in gitLines({"git", "diff", "--name-only", since}) { append(&files, line) }
    }
    for line in gitLines({"git", "status", "--porcelain", "-uall"}) {
        if len(line) < 4 { continue }
        path: string = line[3:]
        if arrow := strings.index(path, " -> "); arrow >= 0 { path = path[arrow + 4:] }       // a rename: the new name
        append(&files, strings.trim(path, "\""))
    }
    changed: map[string]bool
    for path in files {
        if skipped(path) { continue }
        dir: string = directoryOf(path)
        for {
            if dir in packages { changed[dir] = true; break }
            if dir == "." { break }
            dir = directoryOf(dir)
        }
    }
    return changed
}

gitLines :: proc(command: []string) -> [dynamic]string {
    lines: [dynamic]string
    state, stdout, _, err := os.process_exec({command = command}, context.allocator)
    if err != nil || state.exit_code != 0 { return lines }
    for line in strings.split_lines(string(stdout), context.allocator) {
        text: string = strings.trim_right(line, "\r")
        if text != "" { append(&lines, text) }
    }
    return lines
}

// One line when the package passes. When it does not: the failed tests and the errors, never the progress lines.
CROSS_TARGETS :: [?]string{"linux_amd64", "darwin_arm64"}
// Packages that are built only for the web (they declare `foreign` procedures of the browser): not checked for the desktop
CROSS_WEB_ONLY :: [?]string{"browser_extension/runtime", "browser_extension/demo", "spacetimedb/module/example/basic"}

CrossResult :: enum { OK, FAILED, UNCHECKED }

// `odin check` of a package for the other systems. Errors that are not the program's: a vendor library that is not compiled here ("Compile time panic"), a package that builds only for the web (every
// file says `#+build js`) are reported as unchecked.
crossCheck :: proc(dir: string, package_found: ^Package) -> CrossResult {
    listed: bool = len(package_found.files) > 0
    web_only: bool
    for web in CROSS_WEB_ONLY {
        if web == dir { web_only = true }
        for imported in package_found.imports {
            if imported == web { web_only = true }          // what imports a web only package is one too
        }
    }
    for path in package_found.files {
        bytes, err := os.read_entire_file(path, context.temp_allocator)
        if err != nil || !strings.has_prefix(string(bytes), "#+build js") { listed = false; break }
    }
    web_only = web_only || listed
    if web_only {
        fmt.printfln("skip %-28s builds only for the web", dir)
        return .UNCHECKED
    }
    result: CrossResult = .OK
    for target in CROSS_TARGETS {
        state, stdout, stderr, err := os.process_exec({command = {"odin", "check", dir, "-no-entry-point", fmt.tprintf("-target:%s", target), "-strict-style", "-vet"}}, context.temp_allocator)
        if err != nil {
            fmt.printfln("FAIL %s: cannot start odin: %v", dir, err)
            return .FAILED
        }
        if state.exit_code == 0 { continue }
        output: string = strings.concatenate({string(stdout), "\n", string(stderr)}, context.temp_allocator)
        if strings.contains(output, "Compile time panic") {
            fmt.printfln("skip %-28s %s: a vendor library is not compiled here", dir, target)
            if result == .OK { result = .UNCHECKED }
            continue
        }
        fmt.printfln("FAIL %-28s %s", dir, target)
        printed: int
        for line in strings.split_lines(output, context.temp_allocator) {
            if !strings.contains(line, "Error") { continue }
            fmt.printfln("     %s", strings.trim_right(line, " "))
            printed += 1
            if printed >= MAX_ERROR_LINES { break }
        }
        return .FAILED
    }
    if result == .OK { fmt.printfln("ok   %-28s %s", dir, "linux_amd64, darwin_arm64") }
    return result
}

runPackage :: proc(dir: string, verbose: bool) -> bool {
    start: time.Tick = time.tick_now()
    inside: bool
    for own in OWN_DIRECTORY {
        if own == dir { inside = true }
    }
    description: os.Process_Desc = {command = {"odin", "test", "." if inside else dir, "-strict-style", "-vet"}, working_dir = dir if inside else ""}
    state, stdout, stderr, err := os.process_exec(description, context.allocator)
    seconds: f64 = time.duration_seconds(time.tick_since(start))
    // `odin test <pkg>` leaves its program in the working directory
    os.remove(fmt.tprintf("%s/%s.exe", dir, baseName(dir)) if inside else fmt.tprintf("%s.exe", baseName(dir)))
    if err != nil {
        fmt.printfln("FAIL %s: cannot start odin: %v", dir, err)
        return false
    }
    output: string = strings.concatenate({string(stdout), "\n", string(stderr)})
    summary: string
    for line in strings.split_lines(output, context.temp_allocator) {
        if strings.has_prefix(line, "Finished ") { summary = strings.trim_space(line) }
    }
    // the runner can exit with 0 when a test failed: its summary line is the truth
    if state.exit_code == 0 && summary != "" && !strings.contains(summary, "failed") {
        fmt.printfln("ok   %-28s %s (%.1f s)", dir, summary if summary != "" else "no summary", seconds)
        return true
    }
    fmt.printfln("FAIL %-28s %s (%.1f s)", dir, summary if summary != "" else "did not build or run", seconds)
    printed: int
    for line in strings.split_lines(output, context.temp_allocator) {
        text: string = strings.trim_right(line, "\r ")
        if text == "" || strings.contains(text, "[INFO ]") { continue }
        if !verbose && !interesting(text) { continue }
        fmt.printfln("     %s", text)
        printed += 1
        if !verbose && printed >= MAX_ERROR_LINES * 2 { fmt.println("     ... (--verbose for everything)"); break }
    }
    return false
}

// The levels of the instruction set that a package that uses the `simd` library is run at: the test program is built once and run once for each, with SIMD_LEVEL in its environment
LEVELS :: [?]string{"scalar", "sse2", "sse4.2", "avx", "avx2", "avx512"}

runLevels :: proc(dir: string, verbose: bool) -> bool {
    start: time.Tick = time.tick_now()
    program: string = fmt.tprintf("%s_levels.exe", baseName(dir))
    build, _, build_stderr, build_err := os.process_exec({command = {"odin", "build", dir, "-build-mode:test", "-strict-style", "-vet", fmt.tprintf("-out:%s", program)}}, context.allocator)
    if build_err != nil || build.exit_code != 0 {
        fmt.printfln("FAIL %-28s levels: did not build", dir)
        if verbose { fmt.println(string(build_stderr)) }
        return false
    }
    defer os.remove(program)
    environment: [dynamic]string
    current, environ_error := os.environ(context.allocator)
    if environ_error == nil {
        for entry in current { if !strings.has_prefix(entry, "SIMD_LEVEL=") { append(&environment, entry) } }
    }
    base: int = len(environment)
    names: [dynamic]string
    failed: [dynamic]string
    for level in LEVELS {
        resize(&environment, base)
        append(&environment, fmt.tprintf("SIMD_LEVEL=%s", level))
        state, stdout, stderr, err := os.process_exec({command = {fmt.tprintf("./%s", program)}, env = environment[:]}, context.allocator)
        output: string = strings.concatenate({string(stdout), "\n", string(stderr)})
        summary: string
        for line in strings.split_lines(output, context.temp_allocator) {
            if strings.has_prefix(line, "Finished ") { summary = strings.trim_space(line) }
        }
        append(&names, level)
        if err != nil || state.exit_code != 0 || summary == "" || strings.contains(summary, "failed") { append(&failed, level) }
    }
    seconds: f64 = time.duration_seconds(time.tick_since(start))
    if len(failed) == 0 {
        fmt.printfln("ok   %-28s at the levels %s (%.1f s)", dir, strings.join(names[:], ", ", context.temp_allocator), seconds)
        return true
    }
    fmt.printfln("FAIL %-28s at the levels %s (%.1f s)", dir, strings.join(failed[:], ", ", context.temp_allocator), seconds)
    return false
}

// Errors of the tests and of the compiler, and the names of the failed tests
interesting :: proc(line: string) -> bool {
    return strings.contains(line, "[ERROR]") || strings.contains(line, "Error:") || strings.contains(line, "Syntax Error") ||
        strings.has_prefix(line, " - ") || strings.contains(line, "failed") || strings.contains(line, "-define:ODIN_TEST_NAMES")
}

baseName :: proc(dir: string) -> string {
    slash: int = strings.last_index_byte(dir, '/')
    return dir[slash + 1:]
}

// The checks that need a browser: a program that prints its verdict (see runBrowserCheck) and the packages whose change makes it worth running (the ones it is made of)
BrowserCheck :: struct {
    name: string,
    command: []string,
    working_dir: string,
    triggers: []string,
}

BROWSER_CHECKS := [?]BrowserCheck{
    {"simd kernels", {"odin", "run", "simd/web_check/build_web", "--", "--headless"}, "", {"simd"}},
    {"file_browser page", {"odin", "run", "file_browser/demo_web/build_web", "--", "--check"}, "", {"file_browser", "ui", "web_build", "web_serve", "browser_drive", "simd", "font", "demo_kit"}},
    // the click-through of the page (open, play, save, invert) in a real browser; they use the build of the check above
    {"file_browser chrome", {"odin", "run", "file_browser/demo_web/build_web", "--", "--no-build", "--drive", "chrome"}, "", {"file_browser", "ui", "web_build", "web_serve", "browser_drive", "simd", "font", "demo_kit"}},
    {"file_browser firefox", {"odin", "run", "file_browser/demo_web/build_web", "--", "--no-build", "--drive", "firefox"}, "", {"file_browser", "ui", "web_build", "web_serve", "browser_drive", "simd", "font", "demo_kit"}},
    {"web_build page", {"odin", "run", "demo_karl2d/build_web", "--", "--check"}, "web_build", {"web_build", "web_serve", "simd", "font", "demo_kit"}},
    // the options page of the youtube_shorts extension, loaded as an extension page of Edge (the branded Chrome ignores --load-extension: skipped); builds the extension first, so it takes a while
    {"youtube_shorts options", {"odin", "run", "youtube_shorts/tool", "--", "edge", "--drive", "edge"}, "browser_extension", {"browser_extension", "browser_drive", "web_build", "web_serve", "demo_kit", "simd", "font"}},
}

// A check that runs in a browser: the program prints its verdict and exits 0 (passed), 1 (failed) or 3 (no browser on this machine: not a failure)
runBrowserCheck :: proc(name: string, command: []string, working_dir: string) -> bool {
    start: time.Tick = time.tick_now()
    state, stdout, stderr, err := os.process_exec({command = command, working_dir = working_dir}, context.allocator)
    seconds: f64 = time.duration_seconds(time.tick_since(start))
    if err != nil {
        fmt.printfln("FAIL browser %s: cannot start odin: %v", name, err)
        return false
    }
    verdict: string
    for line in strings.split_lines(strings.concatenate({string(stdout), "\n", string(stderr)}, context.temp_allocator), context.temp_allocator) {
        text: string = strings.trim_space(line)
        if text != "" && !strings.has_prefix(text, "Done:") { verdict = text }
    }
    switch state.exit_code {
    case 0: fmt.printfln("ok   browser %-21s %s (%.1f s)", name, verdict, seconds)
    case 3: fmt.printfln("skip browser %-21s %s", name, verdict)
    case:
        fmt.printfln("FAIL browser %-21s %s (%.1f s)", name, verdict if verdict != "" else "did not build or run", seconds)
        return false
    }
    return true
}
