#+build !js
// Make a web build (js_wasm32) of a program. Framework agnostic, the same flow as karl2d/build_web but configurable, so it also works
// for programs that need extra JavaScript (karl2d audio) or none at all.
//
// The source directory is an Odin package with three procs, the contract of the web entry:
//     init :: proc()            run once at start
//     step :: proc() -> bool    run every frame, false stops
//     shutdown :: proc()        run once when step returned false
// WebBuild writes a small entry package that calls them, an index.html, copies the Odin JavaScript runtime and builds main.wasm:
//     <source>/build/web/   generated entry, built with -target:js_wasm32
//     <source>/bin/web/     index.html, odin.js, main.wasm and the copied files. Serve this folder
// A browser refuses to load wasm from file://, serve the folder: `python -m http.server` inside of bin/web.
// There is no disk on the web, resources have to be embedded (see resource.odin).
package web_build

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

WEB_ENTRY_TEMPLATE :: #load("templates/web_entry_template.odin.txt")
WEB_INDEX_TEMPLATE :: #load("templates/index_template.html", string)

WebBuildConfig :: struct {
    source_directory: string,   // package with init, step and shutdown
    title: string,              // page title
    odin_arguments: []string,   // passed to `odin build`: "-o:size", "-define:RESOURCE_PATH=..."
    copy_files: []string,       // files copied next to index.html (paths on disk, the file name is kept)
    scripts: []string,          // names of copied files that index.html loads with <script> before odin.js
    imports_js: string,         // JavaScript expression of an object that is merged into the wasm imports. Empty - {}
    start_js: string,           // JavaScript statements that run once the wasm memory exists. `exports` is in scope
}

WebBuildPaths :: struct {
    build_directory: string,    // generated entry
    output_directory: string,   // what is served
}

WebBuildGetPaths :: proc(config: WebBuildConfig, allocator := context.allocator) -> WebBuildPaths {
    return {
        build_directory = fmt.aprintf("%s/build/web", config.source_directory, allocator = allocator),
        output_directory = fmt.aprintf("%s/bin/web", config.source_directory, allocator = allocator),
    }
}

// index.html for the config, the template with its placeholders filled in
WebBuildIndexHtml :: proc(config: WebBuildConfig, allocator := context.allocator) -> string {
    scripts: strings.Builder
    strings.builder_init(&scripts, context.temp_allocator)
    for script in config.scripts {
        fmt.sbprintfln(&scripts, "\t\t<script type=\"text/javascript\" src=\"%s\"></script>", script)
    }

    title: string = config.title if len(config.title) > 0 else "Web Build"
    imports: string = config.imports_js if len(config.imports_js) > 0 else "{}"
    html, _ := strings.replace_all(WEB_INDEX_TEMPLATE, "{{TITLE}}", title, context.temp_allocator)
    html, _ = strings.replace_all(html, "{{SCRIPTS}}", strings.to_string(scripts), context.temp_allocator)
    html, _ = strings.replace_all(html, "{{IMPORTS}}", imports, context.temp_allocator)
    html, _ = strings.replace_all(html, "{{START}}", config.start_js, allocator)
    return html
}

// The Odin JavaScript runtime that every js_wasm32 program needs next to its wasm
@(private)
WebBuildOdinJs :: proc() -> (path: string, ok: bool) {
    _, stdout, _, error := os.process_exec({command = {"odin", "root"}}, context.temp_allocator)
    if error != nil {
        return
    }
    root: string = strings.trim_space(string(stdout))
    path = fmt.tprintf("%s/core/sys/wasm/js/odin.js", strings.trim_right(root, "/\\"))
    return path, os.exists(path)
}

// What a build came to: `message` says what went wrong (the output of the compiler included, in the temp allocator) and is empty when it worked
WebBuildResult :: struct {
    ok: bool,
    message: string,
}

// Build the web version. Needs `odin` in PATH. A failure is printed to stderr, whole: nothing about it is hidden. Allocates temporary strings with the temp allocator, free it afterwards.
WebBuild :: proc(config: WebBuildConfig) -> bool {
    result: WebBuildResult = WebBuildTry(config)
    if !result.ok { fmt.eprintln(result.message) }
    return result.ok
}

// The same build that gives the message back and prints nothing: for a caller that decides what to do with a failure (a test that expects one checks WHAT it says, so that a different failure
// is not mistaken for the expected one).
WebBuildTry :: proc(config: WebBuildConfig) -> WebBuildResult {
    assert(len(config.source_directory) > 0)
    paths: WebBuildPaths = WebBuildGetPaths(config, context.temp_allocator)

    if os.make_directory_all(paths.build_directory) != nil || os.make_directory_all(paths.output_directory) != nil {
        return {message = fmt.tprintf("web_build: could not create the folders in %s", config.source_directory)}
    }

    // the entry imports the source package, which is two folders up from build/web
    if os.write_entire_file(fmt.tprintf("%s/web_entry.odin", paths.build_directory), WEB_ENTRY_TEMPLATE) != nil {
        return {message = fmt.tprintf("web_build: could not write the entry")}
    }
    if os.write_entire_file(fmt.tprintf("%s/index.html", paths.output_directory), WebBuildIndexHtml(config, context.temp_allocator)) != nil {
        return {message = fmt.tprintf("web_build: could not write index.html")}
    }

    odin_js, odin_js_ok := WebBuildOdinJs()
    if !odin_js_ok {
        return {message = fmt.tprintf("web_build: odin.js of the Odin runtime was not found, is odin in PATH?")}
    }
    if os.copy_file(fmt.tprintf("%s/odin.js", paths.output_directory), odin_js) != nil {
        return {message = fmt.tprintf("web_build: could not copy odin.js")}
    }
    for file in config.copy_files {
        name: string = file[max(strings.last_index_byte(file, '/'), strings.last_index_byte(file, '\\')) + 1:]
        if os.copy_file(fmt.tprintf("%s/%s", paths.output_directory, name), file) != nil {
            return {message = fmt.tprintf("web_build: could not copy %s", file)}
        }
    }

    command: [dynamic]string
    command.allocator = context.temp_allocator
    append(&command, "odin", "build", paths.build_directory, fmt.tprintf("-out:%s/main.wasm", paths.output_directory), "-target:js_wasm32")
    // wasm SIMD is in every current browser: with it `simd` (font, demo_kit) runs its 16 byte text kernels, without it the build still links and uses the scalar ones
    append(&command, "-target-features:simd128")
    append(&command, ..config.odin_arguments)
    state, _, errors, error := os.process_exec({command = command[:]}, context.temp_allocator)
    if error != nil || state.exit_code != 0 {
        return {message = fmt.tprintf("web_build: building main.wasm failed\n%s", string(errors))}
    }
    return {ok = true}
}

// --- Tests ---
// The build test calls `odin build -target:js_wasm32`, so `odin` has to be in PATH. A browser is not needed.

@(test)
test_index_html_placeholders :: proc(t: ^testing.T) {
    plain: string = WebBuildIndexHtml({title = "My Game"}, context.temp_allocator)
    testing.expect(t, strings.contains(plain, "<title>My Game</title>"))
    testing.expect(t, !strings.contains(plain, "{{"), "every placeholder is filled")
    testing.expect(t, strings.contains(plain, "...({})"), "no extra imports: an empty object")
    testing.expect(t, strings.contains(plain, "src=\"odin.js\""))

    extra: string = WebBuildIndexHtml({
        scripts = []string{"audio.js", "other.js"},
        imports_js = "audioImports",
        start_js = "setAudioMemory(exports.memory);",
    }, context.temp_allocator)
    testing.expect(t, strings.contains(extra, "src=\"audio.js\""))
    testing.expect(t, strings.contains(extra, "src=\"other.js\""))
    testing.expect(t, strings.index(extra, "audio.js") < strings.index(extra, "odin.js"), "extra scripts load before the runtime")
    testing.expect(t, strings.contains(extra, "...(audioImports)"))
    testing.expect(t, strings.contains(extra, "setAudioMemory(exports.memory);"))
    testing.expect(t, strings.contains(extra, "Web Build"), "default title")
}

@(test)
test_paths :: proc(t: ^testing.T) {
    paths: WebBuildPaths = WebBuildGetPaths({source_directory = "game"}, context.temp_allocator)
    testing.expect_value(t, paths.build_directory, "game/build/web")
    testing.expect_value(t, paths.output_directory, "game/bin/web")
}

@(test)
test_build_a_web_version :: proc(t: ^testing.T) {
    temp, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil {
        testing.fail_now(t, "no temp directory")
    }
    directory: string = fmt.tprintf("%s/odin_utilities_web_build_test", temp)
    os.remove_all(directory)
    os.make_directory_all(directory)
    defer os.remove_all(directory)

    // the smallest program of the entry contract
    source :: `package tiny

init :: proc() {}

step :: proc() -> bool {
	return true
}

shutdown :: proc() {}
`
    testing.expect_value(t, os.write_entire_file(fmt.tprintf("%s/tiny.odin", directory), source), nil)
    testing.expect_value(t, os.write_entire_file(fmt.tprintf("%s/extra.js", directory), "// extra"), nil)

    config: WebBuildConfig = {
        source_directory = directory,
        title = "Tiny",
        copy_files = []string{fmt.tprintf("%s/extra.js", directory)},
        scripts = []string{"extra.js"},
    }
    if !WebBuild(config) {
        testing.fail_now(t, "the web build failed")
    }

    output: string = fmt.tprintf("%s/bin/web", directory)
    wasm, wasm_error := os.read_entire_file(fmt.tprintf("%s/main.wasm", output), context.temp_allocator)
    testing.expect_value(t, wasm_error, nil)
    testing.expect(t, len(wasm) > 8 && wasm[0] == 0 && wasm[1] == 'a' && wasm[2] == 's' && wasm[3] == 'm', "a wasm binary")
    testing.expect(t, os.exists(fmt.tprintf("%s/odin.js", output)))
    testing.expect(t, os.exists(fmt.tprintf("%s/extra.js", output)), "extra files are copied")
    html, _ := os.read_entire_file(fmt.tprintf("%s/index.html", output), context.temp_allocator)
    testing.expect(t, strings.contains(string(html), "<title>Tiny</title>"))
    testing.expect(t, strings.contains(string(html), "src=\"extra.js\""))

    // a program that does not follow the contract fails and says so, instead of leaving an old wasm behind
    testing.expect_value(t, os.write_entire_file(fmt.tprintf("%s/tiny.odin", directory), "package tiny\n"), nil)
    os.remove(fmt.tprintf("%s/main.wasm", output))
    // the compiler's complaint is expected, and it is checked: it has to be about the missing functions of the entry contract, so another failure would not pass for it
    failed: WebBuildResult = WebBuildTry(config)
    testing.expect(t, !failed.ok)
    testing.expect(t, strings.contains(failed.message, "'init' is not declared") && strings.contains(failed.message, "'step' is not declared") && strings.contains(failed.message, "'shutdown' is not declared"), "the failure names the missing procedures")
    testing.expect(t, !os.exists(fmt.tprintf("%s/main.wasm", output)))
}

// `simd` (and `font`, `demo_kit`, which use it) has 16 byte vector kernels that LLVM cannot lower for wasm without the simd128 feature: it stopped with "Do not know how to split the result of this
// operator!" and only a build with -target-features:simd128 linked. simd now leaves the kernels out without the feature; this builds programs that use it WITHOUT the flag (not through WebBuild,
// which passes it) so that the error cannot come back unnoticed.
@(test)
test_a_program_that_uses_simd_or_font_links_without_the_simd128_flag :: proc(t: ^testing.T) {
    temp, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil { testing.fail_now(t, "no temp directory") }
    // an absolute path is not an import path: the library folder is a collection of the build
    root: string = strings.trim_right(fmt.tprintf("%s/..", #directory), "/")
    Probe :: struct { name: string, imports: string, body: string }
    probes := [?]Probe{
        {"simd", `import simd "odin_utilities:simd"`, `x := simd.AsciiRun(transmute([]u8)string("hello"))` + "\n\t_ = x"},
        {"font", `import font "odin_utilities:font"`, "atlas: font.Atlas\n\t_ = font.SlugCoverage(&atlas, 0, {}, {1, 1})"},
    }
    for probe in probes {
        directory: string = fmt.tprintf("%s/odin_utilities_web_build_probe_%s", temp, probe.name)
        os.remove_all(directory)
        os.make_directory_all(directory)
        defer os.remove_all(directory)
        source: string = fmt.tprintf("package probe\n\n%s\n\nmain :: proc() {{\n\t%s\n}}\n", probe.imports, probe.body)
        testing.expect_value(t, os.write_entire_file(fmt.tprintf("%s/probe.odin", directory), source), nil)
        command: []string = {"odin", "build", directory, fmt.tprintf("-out:%s/probe.wasm", directory), "-target:js_wasm32", fmt.tprintf("-collection:odin_utilities=%s", root)}
        state, _, errors, error := os.process_exec({command = command}, context.temp_allocator)
        testing.expectf(t, error == nil && state.exit_code == 0, "%s does not link for js_wasm32 without -target-features:simd128: %s", probe.name, string(errors))
        testing.expectf(t, os.exists(fmt.tprintf("%s/probe.wasm", directory)), "%s: no wasm", probe.name)
    }
}
