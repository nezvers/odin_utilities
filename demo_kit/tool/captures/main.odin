// captures: runs the screenshot tests of the libraries in a window and says which pictures changed. A demo script can hold `kit.Capture("name")` steps (see
// demo_kit/README.md): the frame is compared with a stored picture, but only in a window with -define:DEMO_CAPTURE=true, so `odin test` never runs them. This
// program does: it finds the libraries whose demos have Capture steps, runs their demo programs with the right defines, and prints one line per library.
//
//   odin run demo_kit/tool/captures                      every library with Capture steps, on raylib
//   odin run demo_kit/tool/captures -- ui reports        only these libraries
//   odin run demo_kit/tool/captures -- --karl2d          also the Karl2D demos (their pictures are separate: raylib and Karl2D draw text differently)
//   odin run demo_kit/tool/captures -- --update ui       replace the stored pictures of a library with the current frames (look at them, commit what changed)
//   odin run demo_kit/tool/captures -- --allow-new       a picture that did not exist is written as the new stored picture: that is fine
//
// Run it from the odin_utilities folder. A window opens for every demo program. Exit codes: 0 every picture is as stored, 1 a picture changed or a program
// failed (the current frame is saved as <name>.actual.png next to the stored one, the line says where), 2 new pictures were written (a picture that was
// never stored passes by itself, so it is reported until someone has looked at it and says --allow-new).
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Result :: struct {
    library: string,
    backend: string,
    compared: int,
    new_images: int,
    skipped: int,
    failures: [dynamic]string,          // "capture imgui_modal: 8715 of 921600 pixels differ ..."
    error: string,                      // the program did not run, or ended without a report
}

main :: proc() {
    libraries: [dynamic]string
    karl2d: bool
    update: bool
    allow_new: bool
    for argument in os.args[1:] {
        switch argument {
        case "--karl2d":
            karl2d = true
        case "--update":
            update = true
        case "--allow-new":
            allow_new = true
        case "--help", "-h":
            fmt.println("captures [--karl2d] [--update] [--allow-new] [library...]   (see the top of demo_kit/tool/captures/main.odin)")
            return
        case:
            if strings.has_prefix(argument, "--") {
                fmt.eprintfln("captures: unknown option %s", argument)
                os.exit(2)
            }
            append(&libraries, argument)
        }
    }
    if update && len(libraries) == 0 {
        fmt.eprintln("captures: --update replaces stored pictures: name the libraries (captures --update ui)")
        os.exit(2)
    }
    if len(libraries) == 0 {
        libraries = find_libraries()
    }
    if len(libraries) == 0 {
        fmt.eprintln("captures: no library with Capture steps found (run it from the odin_utilities folder)")
        os.exit(2)
    }
    failed, created: bool
    for library in libraries {
        backends: [2]string = {"raylib", "karl2d"}
        for backend in backends {
            if backend == "karl2d" && !karl2d { continue }
            program: string = fmt.tprintf("%s/demo_%s", library, backend)
            if !os.is_directory(program) { continue }
            result: Result = run(library, backend, program, update)
            fmt.printfln("%-14s %-7s %d compared, %d new, %d failed%s", library, backend, result.compared, result.new_images, len(result.failures), fmt.tprintf("  ERROR: %s", result.error) if result.error != "" else "")
            for failure in result.failures {
                fmt.printfln("    %s", failure)
            }
            if len(result.failures) > 0 || result.error != "" { failed = true }
            if result.new_images > 0 && !update { created = true }
        }
    }
    switch {
    case failed:
        fmt.println("\nsome pictures changed (or a demo failed): look at the .actual.png files, fix the code or update the stored pictures (--update)")
        os.exit(1)
    case created && !allow_new:
        fmt.println("\nnew pictures were stored: look at them before committing them (--allow-new when that is fine)")
        os.exit(2)
    }
    fmt.println("\nevery picture is as stored")
}

// The libraries whose demo scripts hold Capture steps: a folder with demo_common/ that has a `Capture("` in one of its files.
find_libraries :: proc() -> (libraries: [dynamic]string) {
    handle, open_error := os.open(".")
    if open_error != nil { return }
    entries, _ := os.read_dir(handle, 512, context.allocator)
    for entry in entries {
        if entry.type != .Directory { continue }
        folder: string = fmt.tprintf("%s/demo_common", entry.name)
        files, read_error := os.read_all_directory_by_path(folder, context.temp_allocator)
        if read_error != nil { continue }
        found: bool
        for file in files {
            if !strings.has_suffix(file.name, ".odin") { continue }
            data, err := os.read_entire_file(fmt.tprintf("%s/%s", folder, file.name), context.temp_allocator)
            if err == nil && strings.contains(string(data), "Capture(\"") { found = true }
        }
        if found { append(&libraries, strings.clone(entry.name)) }
    }
    return
}

// One demo program of one library: its output says how many pictures were compared and which failed.
run :: proc(library: string, backend: string, program: string, update: bool) -> (result: Result) {
    result = {library = library, backend = backend}
    command: [dynamic]string
    append(&command, "odin", "run", program, "-define:DEMO_TEST=true", "-define:DEMO_CAPTURE=true")
    if update { append(&command, "-define:DEMO_CAPTURE_UPDATE=true") }
    state, stdout, stderr, err := os.process_exec({command = command[:]}, context.allocator)
    if err != nil {
        result.error = fmt.aprintf("cannot start odin: %v", err)
        return
    }
    saw_report: bool
    for line in strings.split_lines(string(stdout), context.temp_allocator) {
        text: string = strings.trim_space(line)
        if !strings.has_prefix(text, "[DEMO TEST]") { continue }
        body: string = strings.trim_space(text[len("[DEMO TEST]"):])
        switch {
        case strings.has_prefix(body, "captures: "):
            // "captures: 2 compared (0 new golden images), 0 skipped"
            saw_report = true
            result.compared += number_after(body, "captures: ")
            result.new_images += number_after(body, "(")
            result.skipped += number_after(body, "), ")
        case strings.has_prefix(body, "failed on frame") && strings.contains(body, "capture "):
            append(&result.failures, strings.clone(body[strings.index(body, "capture "):]))
        }
    }
    if state.exit_code != 0 && len(result.failures) == 0 {
        // the program ended with an error that is not a picture: the last lines of what it printed
        lines: []string = strings.split_lines(strings.trim_space(string(stderr)) if len(stderr) > 0 else strings.trim_space(string(stdout)), context.temp_allocator)
        tail: []string = lines[max(len(lines) - 3, 0):]
        result.error = fmt.aprintf("exit code %d: %s", state.exit_code, strings.join(tail, " | ", context.temp_allocator))
    } else if !saw_report && result.error == "" {
        result.error = "the demos printed no capture report (is there a window? are there Capture steps in the scripts?)"
    }
    return
}

// The number that follows `marker` in `text`, 0 when there is none.
number_after :: proc(text: string, marker: string) -> int {
    at: int = strings.index(text, marker)
    if at < 0 { return 0 }
    rest: string = text[at + len(marker):]
    end: int
    for end < len(rest) && rest[end] >= '0' && rest[end] <= '9' { end += 1 }
    value, _ := strconv.parse_int(rest[:end])
    return value
}
