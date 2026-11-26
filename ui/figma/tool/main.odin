package main

// Design in, Odin out:
//
//     odin run ui/figma/tool -- --in design.json [--out design.odin] [--package name] [--ui ../ui] [--frame "Login Card"]... [--text-colors]
//
// `design.json` is a Figma file as the REST API gives it. Get one with a personal access token (the token stays in your shell, never in a file of the repository):
//
//     curl -H "X-Figma-Token: $FIGMA_TOKEN" https://api.figma.com/v1/files/<file key> -o design.json
//     curl -H "X-Figma-Token: $FIGMA_TOKEN" "https://api.figma.com/v1/files/<file key>/nodes?ids=1:2" -o design.json     (one frame)
//
// `--ui` is the import path of the ui package AS SEEN FROM THE OUTPUT FILE (default `../ui`). Without `--out` the source is printed. What could not be carried over is printed to stderr. The work is in
// `run` (returns the exit code), so that figma_test.odin can drive it.

import "core:fmt"
import "core:os"
import "core:strings"
import figma ".."

main :: proc() {
    os.exit(run(os.args[1:]))
}

failed :: proc(text: string) -> int {
    fmt.eprintln("error:", text)
    return 1
}

run :: proc(arguments: []string) -> int {
    input, output: string
    options: figma.Options
    frames: [dynamic]string = make([dynamic]string, 0, 4, context.temp_allocator)
    index: int
    for index < len(arguments) {
        argument: string = arguments[index]
        index += 1
        value :: proc(arguments: []string, index: ^int) -> (text: string, ok: bool) {
            if index^ >= len(arguments) { return "", false }
            text = arguments[index^]
            index^ += 1
            return text, true
        }
        ok: bool = true
        switch argument {
        case "--in": input, ok = value(arguments, &index)
        case "--out": output, ok = value(arguments, &index)
        case "--package": options.package_name, ok = value(arguments, &index)
        case "--ui": options.ui_import, ok = value(arguments, &index)
        case "--frame":
            name: string
            name, ok = value(arguments, &index)
            append(&frames, name)
        case "--text-colors": options.text_colors = true
        case: return failed(fmt.tprintf("unknown argument %q (usage in the header of ui/figma/tool/main.odin)", argument))
        }
        if !ok { return failed(fmt.tprintf("%s needs a value", argument)) }
    }
    if input == "" { return failed("--in <design.json> is needed") }
    bytes, read_error := os.read_entire_file(input, context.allocator)
    if read_error != nil { return failed(fmt.tprintf("cannot read %s", input)) }
    defer delete(bytes)
    document, parsed := figma.Parse(bytes, context.temp_allocator)
    if !parsed { return failed(fmt.tprintf("%s is not a Figma file (no \"document\" or \"nodes\")", input)) }
    options.frames = frames[:]
    options.source_label = input
    if slash := strings.last_index_any(input, "/\\"); slash >= 0 { options.source_label = input[slash + 1:] }
    source, warnings := figma.Generate(document, options, context.temp_allocator)
    for warning in warnings { fmt.eprintln("warning:", warning) }
    if len(warnings) > 0 && strings.contains(warnings[0], "no frame found") { return 1 }
    if output == "" {
        fmt.print(source)
        return 0
    }
    if write_error := os.write_entire_file(output, transmute([]u8)source); write_error != nil { return failed(fmt.tprintf("cannot write %s", output)) }
    fmt.println("wrote", output)
    return 0
}
