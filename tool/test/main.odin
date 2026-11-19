// Runs only the tests that a change can break, and prints little: one line per package, the failures in full.
//
//     odin run tool/test                    the packages of the uncommitted changes (staged, unstaged, untracked) and the packages that import them
//     odin run tool/test -- --since main    the changes since a commit or branch (committed ones too)
//     odin run tool/test -- ui reports      these packages, whatever changed
//     odin run tool/test -- --all           every package that has tests
//     odin run tool/test -- --list          only say which packages would run
//     odin run tool/test -- --verbose       print the whole output of a failing package, not only its errors
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

SKIP_PREFIXES :: [?]string{"karl2d/", "references/", "scratch/", "hot_reload_demo/"}
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
    all, list, verbose: bool
    arguments: []string = os.args[1:]
    for i := 0; i < len(arguments); i += 1 {
        switch arguments[i] {
        case "--all": all = true
        case "--list": list = true
        case "--verbose": verbose = true
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
        for dir, package_found in packages { if package_found.has_tests { selected[dir] = true } }
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
            if package_found, found := packages[dir]; found && package_found.has_tests { selected[dir] = true }
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
    for dir in order {
        if !runPackage(dir, verbose) { failures += 1 }
    }
    seconds: f64 = time.duration_seconds(time.tick_since(start))
    if failures > 0 {
        fmt.printfln("FAILED: %d of %d packages (%.1f s)", failures, len(order), seconds)
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
    if strings.contains(text, "@(test)") { package_found.has_tests = true }
    for line in strings.split_lines_iterator(&text) {
        trimmed: string = strings.trim_space(line)
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
    if err != nil || !state.success { return lines }
    for line in strings.split_lines(string(stdout), context.allocator) {
        text: string = strings.trim_right(line, "\r")
        if text != "" { append(&lines, text) }
    }
    return lines
}

// One line when the package passes. When it does not: the failed tests and the errors, never the progress lines.
runPackage :: proc(dir: string, verbose: bool) -> bool {
    start: time.Tick = time.tick_now()
    state, stdout, stderr, err := os.process_exec({command = {"odin", "test", dir, "-strict-style", "-vet"}}, context.allocator)
    seconds: f64 = time.duration_seconds(time.tick_since(start))
    os.remove(fmt.tprintf("%s.exe", baseName(dir)))                    // `odin test <pkg>` leaves it in the working directory
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
    if state.success && !strings.contains(summary, "failed") {
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

// Errors of the tests and of the compiler, and the names of the failed tests
interesting :: proc(line: string) -> bool {
    return strings.contains(line, "[ERROR]") || strings.contains(line, "Error:") || strings.contains(line, "Syntax Error") ||
        strings.has_prefix(line, " - ") || strings.contains(line, "failed") || strings.contains(line, "-define:ODIN_TEST_NAMES")
}

baseName :: proc(dir: string) -> string {
    slash: int = strings.last_index_byte(dir, '/')
    return dir[slash + 1:]
}
