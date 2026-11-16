#+build !js
// Build a browser extension whose logic is Odin (compiled to wasm) for Firefox, Chrome, Opera and Edge. Build side, it runs in a tool
// (see demo/build); the code that ends up in the extension is runtime/runtime.odin and the source package.
//
// The source directory is an Odin package with two procs (contract in runtime/runtime.odin):
//     init :: proc()
//     on_message :: proc(message: string, reply: []u8) -> int
// ExtensionBuild writes a small entry package next to it, builds main.wasm with -target:js_wasm32 and fills one folder per target:
//     <source>/build/extension/        generated entry
//     <output>/chromium/               unpacked extension for Chrome, Opera and Edge (Manifest V3, background service worker)
//     <output>/firefox/                unpacked extension for Firefox (Manifest V3, background event page)
//     <output>/<name>-chromium.zip     what the Chrome Web Store, Opera add-ons and Edge add-ons take
//     <output>/<name>-firefox.zip      a plain zip too: what addons.mozilla.org takes, and what Firefox Developer Edition / Nightly / ESR install
//                                      with signature checking off. A release Firefox needs it signed (release.odin), unsigned it is refused.
// Chrome, Opera and Edge are all Chromium, one build serves them. Installing into a browser is install.odin.
package browser_extension

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import web_build "../web_build"

ENTRY_TEMPLATE :: #load("templates/extension_entry_template.odin.txt")
BACKGROUND_JS :: #load("templates/background.js", string)
EXTENSION_JS :: #load("templates/extension.js")
IMPORTS_JS :: #load("templates/imports.js")
OPTIONS_HTML :: #load("templates/options.html", string)
OPTIONS_RUN_JS :: #load("templates/options_run.js", string)
POPUP_HTML :: #load("templates/popup.html", string)
POPUP_JS :: #load("templates/popup.js")
CONTENT_JS :: #load("templates/content.js")

// wasm needs 'wasm-unsafe-eval', without it the browser refuses to compile main.wasm in an extension page
CONTENT_SECURITY_POLICY :: "script-src 'self' 'wasm-unsafe-eval'; object-src 'self'"
// data_collection_permissions is read from 140, older Firefox only warns about it
FIREFOX_MIN_VERSION :: "140.0"

Target :: enum {
    CHROMIUM,
    FIREFOX,
}

ExtensionConfig :: struct {
    source_directory: string,   // package with init and on_message
    output_directory: string,   // default "<source>/bin/extension"
    name: string,               // shown in the browser, also the file name of the packages (spaces become _)
    version: string,            // "1.0.0": up to four numbers
    description: string,
    id: string,                 // Firefox add-on id ("name@example.com"), required there to keep the storage between loads
    popup: bool,                // toolbar button that opens a popup (templates/popup.html, sends "ping")
    content_matches: []string,  // match patterns ("https://example.com/*"): a content script. Empty - none
    content_script_file: string,// JavaScript file of the content script, empty - templates/content.js (sends "page:<title>")
    content_run_at: string,     // "document_start", "document_end" or "document_idle" (the default of the browser)
    native_host: string,        // name of a native messaging host ("com.example.helper"): a program the background may talk to. Empty - none
    native_host_executable: string, // path of that program, ExtensionInstall registers it for the browser (native_host.odin)
    options: OptionsPage,       // a page in the extension settings, drawn by a web_build package. Empty source_directory - none
    permissions: []string,      // "storage", "tabs", ...
    odin_arguments: []string,   // passed to `odin build`: "-o:size", "-define:..."
}

// The options page is a web_build package (init, step, shutdown): Karl2D drawing into a canvas, see demo_kit for a ui that also runs on raylib.
// `web` is passed to web_build.WebBuild, its copy_files / scripts / imports_js / start_js are what Karl2D needs on the web (audio scripts).
// The page is opened in its own tab. It reaches the background with runtime.SendMessage.
OptionsPage :: struct {
    title: string,
    web: web_build.WebBuildConfig,
}

OPTIONS_DIRECTORY :: "options"

ExtensionOutputDirectory :: proc(config: ExtensionConfig, allocator := context.allocator) -> string {
    if len(config.output_directory) > 0 {
        return config.output_directory
    }
    return fmt.aprintf("%s/bin/extension", config.source_directory, allocator = allocator)
}

ExtensionTargetDirectory :: proc(config: ExtensionConfig, target: Target, allocator := context.allocator) -> string {
    name: string = "chromium" if target == .CHROMIUM else "firefox"
    return fmt.aprintf("%s/%s", ExtensionOutputDirectory(config, context.temp_allocator), name, allocator = allocator)
}

// --- Manifest ---

@(private)
ManifestAction :: struct {
    default_popup: string `json:"default_popup,omitempty"`,
}

@(private)
ManifestBackground :: struct {
    service_worker: string `json:"service_worker,omitempty"`,
    scripts: []string `json:"scripts,omitempty"`,
}

@(private)
ManifestOptions :: struct {
    page: string `json:"page"`,
    open_in_tab: bool `json:"open_in_tab"`,
}

@(private)
ManifestContentSecurityPolicy :: struct {
    extension_pages: string `json:"extension_pages"`,
}

@(private)
ManifestContentScript :: struct {
    matches: []string `json:"matches"`,
    js: []string `json:"js"`,
    run_at: string `json:"run_at,omitempty"`,
}

@(private)
ManifestDataCollection :: struct {
    required: []string `json:"required"`,
}

@(private)
ManifestGecko :: struct {
    id: string `json:"id,omitempty"`,
    strict_min_version: string `json:"strict_min_version"`,
    data_collection_permissions: ManifestDataCollection `json:"data_collection_permissions"`,
}

@(private)
ManifestSpecificSettings :: struct {
    gecko: ManifestGecko `json:"gecko"`,
}

@(private)
Manifest :: struct {
    manifest_version: int `json:"manifest_version"`,
    name: string `json:"name"`,
    version: string `json:"version"`,
    description: string `json:"description,omitempty"`,
    action: ManifestAction `json:"action"`,
    background: ManifestBackground `json:"background"`,
    content_security_policy: ManifestContentSecurityPolicy `json:"content_security_policy"`,
    content_scripts: []ManifestContentScript `json:"content_scripts,omitempty"`,
    permissions: []string `json:"permissions,omitempty"`,
    options_ui: ManifestOptions `json:"options_ui,omitempty"`,
    host_permissions: []string `json:"host_permissions,omitempty"`,
}

// Manifest plus what only Firefox reads (add-on id, minimum version). A copy of the fields: json.marshal writes an embedded struct as a nested object.
@(private)
ManifestFirefox :: struct {
    manifest_version: int `json:"manifest_version"`,
    name: string `json:"name"`,
    version: string `json:"version"`,
    description: string `json:"description,omitempty"`,
    action: ManifestAction `json:"action"`,
    background: ManifestBackground `json:"background"`,
    content_security_policy: ManifestContentSecurityPolicy `json:"content_security_policy"`,
    content_scripts: []ManifestContentScript `json:"content_scripts,omitempty"`,
    permissions: []string `json:"permissions,omitempty"`,
    options_ui: ManifestOptions `json:"options_ui,omitempty"`,
    host_permissions: []string `json:"host_permissions,omitempty"`,
    browser_specific_settings: ManifestSpecificSettings `json:"browser_specific_settings"`,
}

// manifest.json of a target. Chromium wants a service worker, Firefox does not run one (it takes background scripts), so each
// target lists only what it understands.
ExtensionManifest :: proc(config: ExtensionConfig, target: Target, allocator := context.allocator) -> string {
    assert(len(config.name) > 0 && len(config.version) > 0)
    permissions: [dynamic]string
    permissions.allocator = context.temp_allocator
    append(&permissions, ..config.permissions)
    if len(config.native_host) > 0 {
        append(&permissions, "nativeMessaging")
    }
    manifest: Manifest = {
        manifest_version = 3,
        name = config.name,
        version = config.version,
        description = config.description,
        content_security_policy = {extension_pages = CONTENT_SECURITY_POLICY},
        permissions = permissions[:],
        // Firefox runs a content script only on pages it has host access to, Chromium does not mind
        host_permissions = config.content_matches,
    }
    if len(config.options.web.source_directory) > 0 {
        manifest.options_ui = {page = "options/options.html", open_in_tab = true}
    }
    if config.popup {
        manifest.action.default_popup = "popup.html"
    }
    content_script: [1]ManifestContentScript = {{matches = config.content_matches, js = {"content.js"}, run_at = config.content_run_at}}
    if len(config.content_matches) > 0 {
        manifest.content_scripts = content_script[:]
    }

    options: json.Marshal_Options = {pretty = true, use_spaces = true, spaces = 4}
    data: []byte
    error: json.Marshal_Error
    switch target {
    case .CHROMIUM:
        manifest.background.service_worker = "background.js"
        data, error = json.marshal(manifest, options, allocator)
    case .FIREFOX:
        manifest.background.scripts = {"odin.js", "imports.js", "extension.js", "background.js"}
        firefox: ManifestFirefox = {
            manifest_version = manifest.manifest_version, name = manifest.name, version = manifest.version, description = manifest.description,
            action = manifest.action, background = manifest.background, content_security_policy = manifest.content_security_policy,
            content_scripts = manifest.content_scripts, permissions = manifest.permissions, options_ui = manifest.options_ui, host_permissions = manifest.host_permissions,
            browser_specific_settings = {gecko = {id = config.id, strict_min_version = FIREFOX_MIN_VERSION, data_collection_permissions = {required = {"none"}}}},
        }
        data, error = json.marshal(firefox, options, allocator)
    }
    assert(error == nil)
    return string(data)
}

// --- Build ---

// The Odin JavaScript runtime that every js_wasm32 program needs next to its wasm
@(private)
ExtensionOdinJs :: proc() -> (path: string, ok: bool) {
    _, stdout, _, error := os.process_exec({command = {"odin", "root"}}, context.temp_allocator)
    if error != nil {
        return
    }
    root: string = strings.trim_space(string(stdout))
    path = fmt.tprintf("%s/core/sys/wasm/js/odin.js", strings.trim_right(root, "/\\"))
    return path, os.exists(path)
}

@(private)
ExtensionWriteFile :: proc(directory, name: string, data: []byte) -> bool {
    if os.write_entire_file(fmt.tprintf("%s/%s", directory, name), data) != nil {
        fmt.eprintfln("browser_extension: could not write %s/%s", directory, name)
        return false
    }
    return true
}

// Names of the files in an unpacked target, in the order they go into the package
@(private)
ExtensionFiles :: proc(config: ExtensionConfig, allocator := context.temp_allocator) -> []string {
    files: [dynamic]string
    files.allocator = allocator
    append(&files, "manifest.json", "main.wasm", "odin.js", "imports.js", "extension.js", "background.js")
    if config.popup {
        append(&files, "popup.html", "popup.js")
    }
    if len(config.content_matches) > 0 {
        append(&files, "content.js")
    }
    if len(config.options.web.source_directory) > 0 {
        append(&files, "options/options.html", "options/options_run.js", "options/main.wasm")
        for file in config.options.web.copy_files {
            append(&files, fmt.tprintf("options/%s", FileName(file)))
        }
    }
    return files[:]
}

@(private)
FileName :: proc(path: string) -> string {
    return path[max(strings.last_index_byte(path, '/'), strings.last_index_byte(path, '\\')) + 1:]
}

// One file of the options page, read once and written into every target
@(private)
OptionsFile :: struct {
    name: string,
    data: []byte,
}

// Builds the web package of the options page and returns its files (names relative to the options folder)
@(private)
ExtensionBuildOptions :: proc(config: ExtensionConfig) -> (files: []OptionsFile, ok: bool) {
    web: web_build.WebBuildConfig = config.options.web
    if !web_build.WebBuild(web) {
        return
    }
    paths: web_build.WebBuildPaths = web_build.WebBuildGetPaths(web, context.temp_allocator)
    list: [dynamic]OptionsFile
    list.allocator = context.temp_allocator

    wasm, wasm_error := os.read_entire_file(fmt.tprintf("%s/main.wasm", paths.output_directory), context.temp_allocator)
    if wasm_error != nil {
        fmt.eprintln("browser_extension: could not read the main.wasm of the options page")
        return
    }
    append(&list, OptionsFile{"main.wasm", wasm})
    for file in web.copy_files {
        data, error := os.read_entire_file(file, context.temp_allocator)
        if error != nil {
            fmt.eprintfln("browser_extension: could not read %s", file)
            return
        }
        append(&list, OptionsFile{FileName(file), data})
    }

    // external script tags: an extension page may not run inline scripts
    scripts: strings.Builder
    strings.builder_init(&scripts, context.temp_allocator)
    for script in web.scripts {
        fmt.sbprintfln(&scripts, "		<script src=\"%s\"></script>", script)
    }
    title: string = config.options.title if len(config.options.title) > 0 else config.name
    html, _ := strings.replace_all(OPTIONS_HTML, "{{TITLE}}", title, context.temp_allocator)
    html, _ = strings.replace_all(html, "{{SCRIPTS}}", strings.to_string(scripts), context.temp_allocator)
    imports: string = web.imports_js if len(web.imports_js) > 0 else "{}"
    run, _ := strings.replace_all(OPTIONS_RUN_JS, "{{IMPORTS}}", imports, context.temp_allocator)
    run, _ = strings.replace_all(run, "{{START}}", web.start_js, context.temp_allocator)
    append(&list, OptionsFile{"options.html", transmute([]byte)html})
    append(&list, OptionsFile{"options_run.js", transmute([]byte)run})
    return list[:], true
}

// The package of a target: a plain zip (zip.odin) with the files listed by name, no folder entries and no "./" in front of them (Firefox
// refuses those). The same file serves the Chrome Web Store, the Opera and Edge add-ons, and, signed, addons.mozilla.org.
@(private)
ExtensionPack :: proc(directory, package_path: string, files: []string) -> bool {
    os.remove(package_path)
    return ZipWriteFolder(package_path, directory, files)
}

// Build the extension for the targets. Needs `odin` in PATH. Temp allocator strings, free it afterwards.
ExtensionBuild :: proc(config: ExtensionConfig, targets: bit_set[Target] = {.CHROMIUM, .FIREFOX}) -> bool {
    assert(len(config.source_directory) > 0)
    entry_directory: string = fmt.tprintf("%s/build/extension", config.source_directory)
    output: string = ExtensionOutputDirectory(config, context.temp_allocator)
    if os.make_directory_all(entry_directory) != nil || os.make_directory_all(output) != nil {
        fmt.eprintfln("browser_extension: could not create the folders in %s", config.source_directory)
        return false
    }
    // the entry imports the source package, which is two folders up from build/extension
    if !ExtensionWriteFile(entry_directory, "entry.odin", ENTRY_TEMPLATE) {
        return false
    }

    odin_js, odin_js_ok := ExtensionOdinJs()
    if !odin_js_ok {
        fmt.eprintln("browser_extension: odin.js of the Odin runtime was not found, is odin in PATH?")
        return false
    }
    odin_js_data, odin_js_error := os.read_entire_file(odin_js, context.temp_allocator)
    if odin_js_error != nil {
        fmt.eprintln("browser_extension: could not read odin.js")
        return false
    }

    // one wasm for every target, built once next to the generated entry
    wasm_path: string = fmt.tprintf("%s/main.wasm", entry_directory)
    command: [dynamic]string
    command.allocator = context.temp_allocator
    append(&command, "odin", "build", entry_directory, fmt.tprintf("-out:%s", wasm_path), "-target:js_wasm32")
    append(&command, ..config.odin_arguments)
    state, _, errors, error := os.process_exec({command = command[:]}, context.temp_allocator)
    if error != nil || state.exit_code != 0 {
        fmt.eprintfln("browser_extension: building main.wasm failed\n%s", string(errors))
        return false
    }
    wasm, wasm_error := os.read_entire_file(wasm_path, context.temp_allocator)
    if wasm_error != nil {
        fmt.eprintln("browser_extension: could not read main.wasm")
        return false
    }

    content_script: []byte = CONTENT_JS
    if len(config.content_script_file) > 0 {
        read_error: os.Error
        content_script, read_error = os.read_entire_file(config.content_script_file, context.temp_allocator)
        if read_error != nil {
            fmt.eprintfln("browser_extension: could not read %s", config.content_script_file)
            return false
        }
    }
    options_files: []OptionsFile
    if len(config.options.web.source_directory) > 0 {
        options_ok: bool
        options_files, options_ok = ExtensionBuildOptions(config)
        if !options_ok {
            return false
        }
    }

    background_js, _ := strings.replace_all(BACKGROUND_JS, "{{NATIVE_HOST}}", config.native_host, context.temp_allocator)
    popup_html, _ := strings.replace_all(POPUP_HTML, "{{TITLE}}", config.name, context.temp_allocator)
    safe_name, _ := strings.replace_all(config.name, " ", "_", context.temp_allocator)
    for target in targets {
        directory: string = ExtensionTargetDirectory(config, target, context.temp_allocator)
        os.remove_all(directory)
        if os.make_directory_all(directory) != nil {
            fmt.eprintfln("browser_extension: could not create %s", directory)
            return false
        }
        ok: bool = ExtensionWriteFile(directory, "manifest.json", transmute([]byte)ExtensionManifest(config, target, context.temp_allocator))
        ok &&= ExtensionWriteFile(directory, "main.wasm", wasm)
        ok &&= ExtensionWriteFile(directory, "odin.js", odin_js_data)
        ok &&= ExtensionWriteFile(directory, "imports.js", IMPORTS_JS)
        ok &&= ExtensionWriteFile(directory, "extension.js", EXTENSION_JS)
        ok &&= ExtensionWriteFile(directory, "background.js", transmute([]byte)background_js)
        if config.popup {
            ok &&= ExtensionWriteFile(directory, "popup.html", transmute([]byte)popup_html)
            ok &&= ExtensionWriteFile(directory, "popup.js", POPUP_JS)
        }
        if len(config.content_matches) > 0 {
            ok &&= ExtensionWriteFile(directory, "content.js", content_script)
        }
        if len(options_files) > 0 {
            options_directory: string = fmt.tprintf("%s/%s", directory, OPTIONS_DIRECTORY)
            ok &&= os.make_directory_all(options_directory) == nil
            for file in options_files {
                ok &&= ExtensionWriteFile(options_directory, file.name, file.data)
            }
        }
        if !ok {
            return false
        }

        suffix: string = "chromium" if target == .CHROMIUM else "firefox"
        package_path: string = fmt.tprintf("%s/%s-%s.zip", output, safe_name, suffix)
        // an earlier version of this tool wrote a .xpi
        os.remove(fmt.tprintf("%s/%s-%s.xpi", output, safe_name, suffix))
        if !ExtensionPack(directory, package_path, ExtensionFiles(config)) {
            return false
        }
    }
    return true
}

// --- Tests ---

@(test)
test_manifest_per_target :: proc(t: ^testing.T) {
    config: ExtensionConfig = {
        name = "Test", version = "1.2.3", id = "test@example.com", popup = true,
        content_matches = {"https://example.com/*"}, permissions = {"storage"},
    }
    chromium, firefox: json.Value
    chromium_error: json.Error
    firefox_error: json.Error
    chromium, chromium_error = json.parse(transmute([]byte)ExtensionManifest(config, .CHROMIUM, context.temp_allocator), allocator = context.temp_allocator)
    firefox, firefox_error = json.parse(transmute([]byte)ExtensionManifest(config, .FIREFOX, context.temp_allocator), allocator = context.temp_allocator)
    testing.expect_value(t, chromium_error, nil)
    testing.expect_value(t, firefox_error, nil)

    chromium_object: json.Object = chromium.(json.Object)
    firefox_object: json.Object = firefox.(json.Object)
    testing.expect_value(t, chromium_object["manifest_version"].(json.Float), 3)
    testing.expect_value(t, string(chromium_object["name"].(json.String)), "Test")

    chromium_background: json.Object = chromium_object["background"].(json.Object)
    testing.expect_value(t, string(chromium_background["service_worker"].(json.String)), "background.js")
    testing.expect(t, "scripts" not_in chromium_background, "a service worker, no scripts")
    testing.expect(t, "browser_specific_settings" not_in chromium_object, "no add-on id outside Firefox")

    firefox_background: json.Object = firefox_object["background"].(json.Object)
    testing.expect(t, "service_worker" not_in firefox_background, "Firefox does not run service workers")
    scripts: json.Array = firefox_background["scripts"].(json.Array)
    testing.expect_value(t, len(scripts), 4)
    testing.expect_value(t, string(scripts[0].(json.String)), "odin.js")
    testing.expect_value(t, string(scripts[1].(json.String)), "imports.js")
    testing.expect_value(t, len(firefox_object["host_permissions"].(json.Array)), 1)
    gecko: json.Object = firefox_object["browser_specific_settings"].(json.Object)["gecko"].(json.Object)
    testing.expect_value(t, string(gecko["id"].(json.String)), "test@example.com")

    testing.expect(t, strings.contains(string(json_string(chromium_object["content_security_policy"].(json.Object)["extension_pages"])), "wasm-unsafe-eval"))
    testing.expect_value(t, len(chromium_object["content_scripts"].(json.Array)), 1)
    testing.expect_value(t, string(chromium_object["action"].(json.Object)["default_popup"].(json.String)), "popup.html")

    // an options page is a manifest key in both
    with_options: ExtensionConfig = config
    with_options.options.web.source_directory = "options_source"
    for target in Target {
        parsed, _ := json.parse(transmute([]byte)ExtensionManifest(with_options, target, context.temp_allocator), allocator = context.temp_allocator)
        page: json.Object = parsed.(json.Object)["options_ui"].(json.Object)
        testing.expect_value(t, string(page["page"].(json.String)), "options/options.html")
    }

    // optional parts stay out when not asked for
    plain: json.Value
    plain, _ = json.parse(transmute([]byte)ExtensionManifest({name = "P", version = "1"}, .CHROMIUM, context.temp_allocator), allocator = context.temp_allocator)
    plain_object: json.Object = plain.(json.Object)
    testing.expect(t, "content_scripts" not_in plain_object)
    testing.expect(t, "permissions" not_in plain_object)
    testing.expect(t, "default_popup" not_in plain_object["action"].(json.Object))
}

@(private = "file")
json_string :: proc(value: json.Value) -> json.String {
    text, _ := value.(json.String)
    return text
}
