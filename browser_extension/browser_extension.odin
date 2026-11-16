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
//     <output>/<name>-firefox.xpi      what addons.mozilla.org takes (a zip, unsigned: release Firefox only loads it temporarily)
// Chrome, Opera and Edge are all Chromium, one build serves them. Installing into a browser is install.odin.
package browser_extension

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

ENTRY_TEMPLATE :: #load("templates/extension_entry_template.odin.txt")
BACKGROUND_JS :: #load("templates/background.js")
EXTENSION_JS :: #load("templates/extension.js")
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
    content_matches: []string,  // match patterns ("https://example.com/*"): a content script that sends "page:<title>". Empty - none
    permissions: []string,      // "storage", "tabs", ...
    odin_arguments: []string,   // passed to `odin build`: "-o:size", "-define:..."
}

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
ManifestContentSecurityPolicy :: struct {
    extension_pages: string `json:"extension_pages"`,
}

@(private)
ManifestContentScript :: struct {
    matches: []string `json:"matches"`,
    js: []string `json:"js"`,
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
    browser_specific_settings: ManifestSpecificSettings `json:"browser_specific_settings"`,
}

// manifest.json of a target. Chromium wants a service worker, Firefox does not run one (it takes background scripts), so each
// target lists only what it understands.
ExtensionManifest :: proc(config: ExtensionConfig, target: Target, allocator := context.allocator) -> string {
    assert(len(config.name) > 0 && len(config.version) > 0)
    manifest: Manifest = {
        manifest_version = 3,
        name = config.name,
        version = config.version,
        description = config.description,
        content_security_policy = {extension_pages = CONTENT_SECURITY_POLICY},
        permissions = config.permissions,
    }
    if config.popup {
        manifest.action.default_popup = "popup.html"
    }
    content_script: [1]ManifestContentScript = {{matches = config.content_matches, js = {"content.js"}}}
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
        manifest.background.scripts = {"odin.js", "extension.js", "background.js"}
        firefox: ManifestFirefox = {
            manifest_version = manifest.manifest_version, name = manifest.name, version = manifest.version, description = manifest.description,
            action = manifest.action, background = manifest.background, content_security_policy = manifest.content_security_policy,
            content_scripts = manifest.content_scripts, permissions = manifest.permissions,
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
    append(&files, "manifest.json", "main.wasm", "odin.js", "extension.js", "background.js")
    if config.popup {
        append(&files, "popup.html", "popup.js")
    }
    if len(config.content_matches) > 0 {
        append(&files, "content.js")
    }
    return files[:]
}

// A zip with the files of a directory, `tar` of Windows (bsdtar) writes zip with -a. The files are listed by name, a "." would put
// "./" in front of every entry, which Firefox refuses.
@(private)
ExtensionPack :: proc(directory, package_path: string, files: []string) -> bool {
    os.remove(package_path)
    command: [dynamic]string
    command.allocator = context.temp_allocator
    working_directory: string
    when ODIN_OS == .Windows {
        append(&command, "tar", "-a", "-c", "-f", package_path, "-C", directory)
    } else {
        // GNU tar cannot write zip, `zip` runs inside of the folder so the package path has to be absolute
        absolute, _ := os.get_absolute_path(package_path, context.temp_allocator)
        append(&command, "zip", "-q", absolute)
        working_directory = directory
    }
    append(&command, ..files)
    state, _, errors, error := os.process_exec({working_dir = working_directory, command = command[:]}, context.temp_allocator)
    if error != nil || state.exit_code != 0 {
        fmt.eprintfln("browser_extension: packing %s failed\n%s", package_path, string(errors))
        return false
    }
    return true
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
        ok &&= ExtensionWriteFile(directory, "extension.js", EXTENSION_JS)
        ok &&= ExtensionWriteFile(directory, "background.js", BACKGROUND_JS)
        if config.popup {
            ok &&= ExtensionWriteFile(directory, "popup.html", transmute([]byte)popup_html)
            ok &&= ExtensionWriteFile(directory, "popup.js", POPUP_JS)
        }
        if len(config.content_matches) > 0 {
            ok &&= ExtensionWriteFile(directory, "content.js", CONTENT_JS)
        }
        if !ok {
            return false
        }

        extension: string = "zip" if target == .CHROMIUM else "xpi"
        suffix: string = "chromium" if target == .CHROMIUM else "firefox"
        package_path: string = fmt.tprintf("%s/%s-%s.%s", output, safe_name, suffix, extension)
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
    testing.expect_value(t, len(scripts), 3)
    testing.expect_value(t, string(scripts[0].(json.String)), "odin.js")
    gecko: json.Object = firefox_object["browser_specific_settings"].(json.Object)["gecko"].(json.Object)
    testing.expect_value(t, string(gecko["id"].(json.String)), "test@example.com")

    testing.expect(t, strings.contains(string(json_string(chromium_object["content_security_policy"].(json.Object)["extension_pages"])), "wasm-unsafe-eval"))
    testing.expect_value(t, len(chromium_object["content_scripts"].(json.Array)), 1)
    testing.expect_value(t, string(chromium_object["action"].(json.Object)["default_popup"].(json.String)), "popup.html")

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
