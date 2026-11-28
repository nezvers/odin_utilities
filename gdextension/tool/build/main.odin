package main

// `odin run gdextension/tool/build -- <package> <godot project> [--name N] [--entry symbol] [--release] [--force] [--import]`
//
// Builds a GDExtension package as a dynamic library for this computer into `<project>/bin` and writes `<project>/<name>.gdextension` with the entries for Windows, Linux and macOS, so a project
// needs nothing by hand. The name is the folder name of the package unless `--name` says otherwise; the entry symbol is found in the sources (the `@(export)` proc that takes a
// `GetProcAddress`) unless `--entry` says otherwise. An existing .gdextension file is kept (it may be edited) unless `--force`; `--release` builds with `-o:speed`; `--import` runs
// `godot --headless --import` in the project, which Godot needs once before it loads a new extension.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

main :: proc() {
    package_path, project: string
    name, entry: string
    release, force, import_project: bool
    positional: int
    arguments: []string = os.args[1:]
    for i := 0; i < len(arguments); i += 1 {
        switch arguments[i] {
        case "--name":
            i += 1
            if i < len(arguments) { name = arguments[i] }
        case "--entry":
            i += 1
            if i < len(arguments) { entry = arguments[i] }
        case "--release": release = true
        case "--force": force = true
        case "--import": import_project = true
        case:
            if strings.has_prefix(arguments[i], "--") { fail(fmt.tprintf("unknown option %s", arguments[i])) }
            switch positional {
            case 0: package_path = arguments[i]
            case 1: project = arguments[i]
            case: fail("too many arguments")
            }
            positional += 1
        }
    }
    if package_path == "" || project == "" { fail("usage: odin run gdextension/tool/build -- <package> <godot project> [--name N] [--entry symbol] [--release] [--force] [--import]") }
    if !os.is_directory(package_path) { fail(fmt.tprintf("%s is not a folder", package_path)) }
    if !os.exists(fmt.tprintf("%s/project.godot", project)) { fail(fmt.tprintf("%s has no project.godot", project)) }

    if name == "" { name = folderName(package_path) }
    if entry == "" {
        found: bool
        entry, found = findEntry(package_path)
        if !found { fail("no entry symbol found: an @(export) proc that takes a GetProcAddress (or pass --entry)") }
    }

    when ODIN_OS == .Windows {
        file: string = fmt.tprintf("%s.dll", name)
    } else when ODIN_OS == .Darwin {
        file: string = fmt.tprintf("lib%s.dylib", name)
    } else {
        file: string = fmt.tprintf("lib%s.so", name)
    }
    bin: string = fmt.tprintf("%s/bin", project)
    os.make_directory_all(bin)
    output: string = fmt.tprintf("%s/%s", bin, file)
    command: [dynamic]string
    append(&command, "odin", "build", package_path, "-build-mode:dll", "-strict-style", "-vet", fmt.tprintf("-out:%s", output))
    if release { append(&command, "-o:speed") }
    state, _, errors, run_error := os.process_exec({command = command[:]}, context.temp_allocator)
    if run_error != nil || !state.success { fail(fmt.tprintf("the build failed:\n%s", string(errors))) }
    fmt.printfln("built %s", output)

    descriptor: string = fmt.tprintf("%s/%s.gdextension", project, name)
    if os.exists(descriptor) && !force {
        fmt.printfln("kept %s (--force replaces it)", descriptor)
    } else {
        text: string = descriptorText(name, entry)
        if os.write_entire_file(descriptor, transmute([]u8)text) != nil { fail("cannot write the .gdextension file") }
        fmt.printfln("wrote %s (entry %s)", descriptor, entry)
    }
    if import_project {
        // Godot lists the extensions it loads when it imports the project
        _, _, _, _ = os.process_exec({command = {"godot", "--headless", "--path", project, "--import"}}, context.temp_allocator)
        fmt.println("imported the project")
    }
}

fail :: proc(message: string) {
    fmt.eprintln(message)
    os.exit(1)
}

descriptorText :: proc(name, entry: string) -> string {
    return fmt.tprintf(`[configuration]
entry_symbol = "%s"
compatibility_minimum = "4.4"
reloadable = true

[libraries]
windows.debug.x86_64 = "res://bin/%s.dll"
windows.release.x86_64 = "res://bin/%s.dll"
linux.debug.x86_64 = "res://bin/lib%s.so"
linux.release.x86_64 = "res://bin/lib%s.so"
macos.debug = "res://bin/lib%s.dylib"
macos.release = "res://bin/lib%s.dylib"
`, entry, name, name, name, name, name, name)
}

// The last folder of a path ("a/b/", "a\b" and "." give "b", "b" and the folder's own name is not known for ".": say --name then)
folderName :: proc(path: string) -> string {
    trimmed: string = strings.trim_right(path, "/\\")
    cut: int = max(strings.last_index(trimmed, "/"), strings.last_index(trimmed, "\\"))
    return trimmed[cut + 1:]
}

// The name of the exported proc that takes a GetProcAddress, read from the .odin files of the package folder
findEntry :: proc(package_path: string) -> (entry: string, found: bool) {
    files, error := os.read_all_directory_by_path(package_path, context.temp_allocator)
    if error != nil { return }
    for info in files {
        if !strings.has_suffix(info.name, ".odin") { continue }
        data, read_error := os.read_entire_file(fmt.tprintf("%s/%s", package_path, info.name), context.temp_allocator)
        if read_error != nil { continue }
        text: string = string(data)
        for line in strings.split_lines_iterator(&text) {
            marker: int = strings.index(line, " :: proc \"c\"")
            if marker > 0 && strings.contains(line, "GetProcAddress") {
                return strings.trim_space(line[:marker]), true
            }
        }
    }
    return
}

@(test)
test_the_folder_name_and_the_entry_symbol_are_found :: proc(t: ^testing.T) {
    testing.expect_value(t, folderName("gdextension/template"), "template")
    testing.expect_value(t, folderName(`a\b\`), "b")
    entry, found := findEntry(#directory + "../../template")
    testing.expect(t, found, "the template has an entry")
    testing.expect_value(t, entry, "template_entry")
    _, none := findEntry(#directory + "../../godot_api")
    testing.expect(t, !none, "a folder without an entry gives none")
}

@(test)
test_the_descriptor_names_every_platform :: proc(t: ^testing.T) {
    text: string = descriptorText("my_ext", "my_entry")
    testing.expect(t, strings.contains(text, `entry_symbol = "my_entry"`))
    testing.expect(t, strings.contains(text, `windows.release.x86_64 = "res://bin/my_ext.dll"`))
    testing.expect(t, strings.contains(text, `linux.debug.x86_64 = "res://bin/libmy_ext.so"`))
    testing.expect(t, strings.contains(text, `macos.release = "res://bin/libmy_ext.dylib"`))
}
