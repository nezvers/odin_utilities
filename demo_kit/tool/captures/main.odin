// captures: runs the screenshot tests of the libraries in a window and says which pictures changed. A demo script can hold `kit.Capture("name")` steps (see
// demo_kit/README.md): the frame is compared with a stored picture, but only in a window with -define:DEMO_CAPTURE=true, so `odin test` never runs them. This
// program does: it finds the libraries whose demos have Capture steps, runs their demo programs with the right defines, and prints one line per library.
//
//   odin run demo_kit/tool/captures                      every library with Capture steps, on raylib
//   odin run demo_kit/tool/captures -- ui reports        only these libraries
//   odin run demo_kit/tool/captures -- --karl2d          also the Karl2D demos (their pictures are separate: raylib and Karl2D draw text differently)
//   odin run demo_kit/tool/captures -- --update ui       replace the stored pictures of a library with the current frames (look at them, commit what changed)
//   odin run demo_kit/tool/captures -- --allow-new       a picture that did not exist is written as the new stored picture: that is fine
//   odin run demo_kit/tool/captures -- --monitor dell    the windows open on the display whose name holds "dell" (without regard to case)
//
// The display: --monitor, else the environment variable DEMO_MONITOR, else the first line of the file demo_kit/monitor.txt (a local file, git ignored: write the name of the
// display your pictures are tested on once). The window is moved there and its drawing area is made exactly the size the demo asked for, whatever the scaling of that display
// is, so the pictures always have the size of the stored ones; the report says which display and scale a run had. See demo_kit/display.odin.
//
// Run it from the odin_utilities folder. A window opens for every demo program. Exit codes: 0 every picture is as stored, 1 a picture changed or a program
// failed (the current frame is saved as <name>.actual.png next to the stored one, the line says where), 2 new pictures were written (a picture that was
// never stored passes by itself, so it is reported until someone has looked at it and says --allow-new).
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "../../../karl2d"

Result :: struct {
    library: string,
    backend: string,
    compared: int,
    new_images: int,
    skipped: int,
    failures: [dynamic]string,          // "capture imgui_modal: 8715 of 921600 pixels differ ..."
    error: string,                      // the program did not run, or ended without a report
    display: string,                    // where the window was: "BenQ DL2215, scale 1.00, window 1280 x 720"
}

main :: proc() {
    libraries: [dynamic]string
    karl2d: bool
    update: bool
    allow_new: bool
    monitor: string
    arguments: []string = os.args[1:]
    for index := 0; index < len(arguments); index += 1 {
        argument: string = arguments[index]
        switch argument {
        case "--monitor":
            index += 1
            if index >= len(arguments) {
                fmt.eprintln("captures: --monitor wants the name (or a part of the name) of a display")
                os.exit(2)
            }
            monitor = arguments[index]
        case "--karl2d":
            karl2d = true
        case "--update":
            update = true
        case "--allow-new":
            allow_new = true
        case "--help", "-h":
            fmt.println("captures [--karl2d] [--update] [--allow-new] [--monitor name] [library...]   (see the top of demo_kit/tool/captures/main.odin)")
            return
        case:
            if strings.has_prefix(argument, "--") {
                fmt.eprintfln("captures: unknown option %s", argument)
                os.exit(2)
            }
            append(&libraries, argument)
        }
    }
    choose_display(monitor)
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
            fmt.printfln("%-14s %-7s %d compared, %d new, %d failed%s%s", library, backend, result.compared, result.new_images, len(result.failures), fmt.tprintf("  on %s", result.display) if result.display != "" else "", fmt.tprintf("  ERROR: %s", result.error) if result.error != "" else "")
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
        case strings.has_prefix(body, "display: "):
            if result.display == "" { result.display = strings.clone(body[len("display: "):]) }
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
        // the program ended with an error that is not a picture: what the demos say went wrong ("[DEMO TEST]" lines about the display or a script that did not end), else the last lines of the output
        reasons: [dynamic]string
        reasons.allocator = context.temp_allocator
        for line in strings.split_lines(string(stdout), context.temp_allocator) {
            text: string = strings.trim_space(line)
            if strings.has_prefix(text, "[DEMO TEST]") && (strings.contains(text, "cannot") || strings.contains(text, "no display") || strings.contains(text, "NOT finish") || strings.contains(text, "the window on")) {
                append(&reasons, text)
            }
        }
        if len(reasons) > 0 {
            result.error = fmt.aprintf("exit code %d: %s", state.exit_code, strings.join(reasons[:], " | ", context.temp_allocator))
        } else {
            lines: []string = strings.split_lines(strings.trim_space(string(stderr)) if len(stderr) > 0 else strings.trim_space(string(stdout)), context.temp_allocator)
            tail: []string = lines[max(len(lines) - 3, 0):]
            result.error = fmt.aprintf("exit code %d: %s", state.exit_code, strings.join(tail, " | ", context.temp_allocator))
        }
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

// The display of the test windows: the option, else what the environment already says, else the local file; the demo programs read it from DEMO_MONITOR.
choose_display :: proc(option: string) {
    name: string = strings.trim_space(option)
    if name == "" { name = strings.trim_space(os.get_env("DEMO_MONITOR", context.temp_allocator)) }
    if name == "" {
        data, err := os.read_entire_file("demo_kit/monitor.txt", context.temp_allocator)
        if err == nil {
            lines: []string = strings.split_lines(string(data), context.temp_allocator)
            if len(lines) > 0 { name = strings.trim_space(lines[0]) }
        }
    }
    if name == "" { return }
    // the name is looked up here (Karl2D reads the real names of the displays): the demo programs get the name and where the display is on the desktop
    monitors: []karl2d.Monitor_Info = karl2d.get_monitors(context.temp_allocator)
    for monitor in monitors {
        if !strings.contains(strings.to_lower(monitor.name, context.temp_allocator), strings.to_lower(name, context.temp_allocator)) { continue }
        os.set_env("DEMO_MONITOR", monitor.name)
        os.set_env("DEMO_MONITOR_RECT", fmt.tprintf("%d,%d,%d,%d", monitor.position[0], monitor.position[1], monitor.size[0], monitor.size[1]))
        fmt.printfln("captures: windows on the display \"%s\" (%d x %d at %d, %d, scale %.2f)", monitor.name, monitor.size[0], monitor.size[1], monitor.position[0], monitor.position[1], monitor.scale)
        return
    }
    listed: [dynamic]string
    listed.allocator = context.temp_allocator
    for monitor in monitors { append(&listed, fmt.tprintf("\"%s\"", monitor.name)) }
    fmt.eprintfln("captures: no connected display has \"%s\" in its name. Connected: %s", name, strings.join(listed[:], ", ", context.temp_allocator))
    os.exit(2)
}
