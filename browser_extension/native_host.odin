#+build !js
// Registers a native messaging host for a browser, so an extension can talk to a program on the computer (ExtensionConfig.native_host).
// A browser finds a host by name: a manifest file (name, path of the program, which extension may use it) and, on Windows, a registry value
// that points at the file. Chromium browsers name the extension by its address (chrome-extension://<id>/), Firefox by the add-on id.
//
// The id of an unpacked Chromium extension is made from the folder it is loaded from (the first 16 bytes of the SHA-256 of the path, a-p),
// so registering for the folder that ExtensionInstall loads is enough: no key in the manifest needed.
package browser_extension

import "core:crypto/sha2"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:unicode/utf16"

// The id Chromium gives an unpacked extension loaded from `directory` (an absolute path). On Windows the path is hashed as UTF-16.
ChromiumExtensionId :: proc(directory: string, allocator := context.temp_allocator) -> string {
    bytes: [dynamic]u8
    bytes.allocator = context.temp_allocator
    when ODIN_OS == .Windows {
        units: []u16 = make([]u16, len(directory) + 1, context.temp_allocator)
        count: int = utf16.encode_string(units, directory)
        for unit in units[:count] {
            append(&bytes, u8(unit), u8(unit >> 8))
        }
    } else {
        append(&bytes, ..transmute([]u8)directory)
    }
    context_hash: sha2.Context_256
    sha2.init_256(&context_hash)
    sha2.update(&context_hash, bytes[:])
    hash: [32]u8
    sha2.final(&context_hash, hash[:])

    id: [32]u8
    for byte, i in hash[:16] {
        id[i * 2] = 'a' + (byte >> 4)
        id[i * 2 + 1] = 'a' + (byte & 15)
    }
    return strings.clone(string(id[:]), allocator)
}

@(private)
NativeManifestChromium :: struct {
    name: string `json:"name"`,
    description: string `json:"description"`,
    path: string `json:"path"`,
    type: string `json:"type"`,
    allowed_origins: []string `json:"allowed_origins"`,
}

@(private)
NativeManifestFirefox :: struct {
    name: string `json:"name"`,
    description: string `json:"description"`,
    path: string `json:"path"`,
    type: string `json:"type"`,
    allowed_extensions: []string `json:"allowed_extensions"`,
}

// The manifest of the host: who may talk to it. `extension` is the extension id of Chromium or the add-on id of Firefox.
NativeHostManifest :: proc(target: Target, name, description, executable, extension: string, allocator := context.temp_allocator) -> string {
    data: []byte
    options: json.Marshal_Options = {pretty = true, use_spaces = true, spaces = 4}
    switch target {
    case .CHROMIUM:
        origins: [1]string = {fmt.tprintf("chrome-extension://%s/", extension)}
        data, _ = json.marshal(NativeManifestChromium{name, description, executable, "stdio", origins[:]}, options, allocator)
    case .FIREFOX:
        ids: [1]string = {extension}
        data, _ = json.marshal(NativeManifestFirefox{name, description, executable, "stdio", ids[:]}, options, allocator)
    }
    return string(data)
}

// Where the browser looks for host manifests on Windows: the default value of this key (the key is per user, no administrator needed)
@(private)
NATIVE_REGISTRY_KEYS :: [Browser]string {
    .CHROME = "HKCU\\Software\\Google\\Chrome\\NativeMessagingHosts",
    // Opera reads the key of Chrome
    .OPERA = "HKCU\\Software\\Google\\Chrome\\NativeMessagingHosts",
    .EDGE = "HKCU\\Software\\Microsoft\\Edge\\NativeMessagingHosts",
    .FIREFOX = "HKCU\\Software\\Mozilla\\NativeMessagingHosts",
}

// Folders of the manifests on Linux and macOS, under the home folder (no registry there)
@(private)
NATIVE_HOME_FOLDERS :: [Browser]string {
    .CHROME = ".config/google-chrome/NativeMessagingHosts",
    .OPERA = ".config/google-chrome/NativeMessagingHosts",
    .EDGE = ".config/microsoft-edge/NativeMessagingHosts",
    .FIREFOX = ".mozilla/native-messaging-hosts",
}

@(private)
NATIVE_HOME_FOLDERS_MAC :: [Browser]string {
    .CHROME = "Library/Application Support/Google/Chrome/NativeMessagingHosts",
    .OPERA = "Library/Application Support/Google/Chrome/NativeMessagingHosts",
    .EDGE = "Library/Application Support/Microsoft Edge/NativeMessagingHosts",
    .FIREFOX = "Library/Application Support/Mozilla/NativeMessagingHosts",
}

// Writes the manifest of the host for the browser and tells the browser where it is. Called by ExtensionInstall when the config has a
// native_host. Windows is the tested platform, Linux and macOS write the manifest to the folder the browser documents.
NativeHostRegister :: proc(config: ExtensionConfig, browser: Browser) -> bool {
    assert(len(config.native_host) > 0)
    executable, executable_error := os.get_absolute_path(config.native_host_executable, context.temp_allocator)
    if executable_error != nil || !os.exists(executable) {
        fmt.eprintfln("browser_extension: the native host program %s was not built", config.native_host_executable)
        return false
    }
    target: Target = BrowserTarget(browser)
    extension: string = config.id
    if target == .CHROMIUM {
        directory, directory_error := os.get_absolute_path(ExtensionTargetDirectory(config, target, context.temp_allocator), context.temp_allocator)
        if directory_error != nil {
            return false
        }
        extension = ChromiumExtensionId(directory)
    }

    manifest: string = NativeHostManifest(target, config.native_host, config.name, executable, extension)
    when ODIN_OS == .Windows {
        folder: string = fmt.tprintf("%s/native", ExtensionOutputDirectory(config, context.temp_allocator))
    } else {
        home, _ := os.lookup_env("HOME", context.temp_allocator)
        folders := NATIVE_HOME_FOLDERS_MAC if ODIN_OS == .Darwin else NATIVE_HOME_FOLDERS
        folder: string = fmt.tprintf("%s/%s", home, folders[browser])
    }
    if os.make_directory_all(folder) != nil {
        fmt.eprintfln("browser_extension: could not create %s", folder)
        return false
    }
    manifest_path, _ := os.get_absolute_path(fmt.tprintf("%s/%s.%s.json", folder, config.native_host, "firefox" if target == .FIREFOX else "chromium"), context.temp_allocator)
    if os.write_entire_file(manifest_path, manifest) != nil {
        fmt.eprintfln("browser_extension: could not write %s", manifest_path)
        return false
    }

    when ODIN_OS == .Windows {
        keys := NATIVE_REGISTRY_KEYS
        key: string = fmt.tprintf("%s\\%s", keys[browser], config.native_host)
        state, _, errors, error := os.process_exec({command = {"reg", "add", key, "/ve", "/t", "REG_SZ", "/d", manifest_path, "/f"}}, context.temp_allocator)
        if error != nil || state.exit_code != 0 {
            fmt.eprintfln("browser_extension: could not register the native host in %s\n%s", key, string(errors))
            return false
        }
    }
    return true
}

// --- Tests ---

@(test)
test_native_manifest :: proc(t: ^testing.T) {
    chromium, _ := json.parse(transmute([]byte)NativeHostManifest(.CHROMIUM, "com.test.host", "Test", "C:\\host.exe", "abcdefghijklmnopabcdefghijklmnop"), allocator = context.temp_allocator)
    object: json.Object = chromium.(json.Object)
    testing.expect_value(t, string(object["type"].(json.String)), "stdio")
    testing.expect_value(t, string(object["allowed_origins"].(json.Array)[0].(json.String)), "chrome-extension://abcdefghijklmnopabcdefghijklmnop/")
    testing.expect(t, "allowed_extensions" not_in object)
    testing.expect_value(t, string(object["path"].(json.String)), "C:\\host.exe")

    firefox, _ := json.parse(transmute([]byte)NativeHostManifest(.FIREFOX, "com.test.host", "Test", "/bin/host", "me@example.com"), allocator = context.temp_allocator)
    object = firefox.(json.Object)
    testing.expect_value(t, string(object["allowed_extensions"].(json.Array)[0].(json.String)), "me@example.com")
    testing.expect(t, "allowed_origins" not_in object)
}

// The id of a folder was read from a browser that loaded it (Edge, see README): the same folder gives the same id
@(test)
test_chromium_id :: proc(t: ^testing.T) {
    when ODIN_OS == .Windows {
        testing.expect_value(t, ChromiumExtensionId("O:\\Projects\\Odin\\odin_utilities\\browser_extension\\youtube_shorts\\bin\\extension\\chromium"), "ooffmkdddooegoddbbonhiemfkckgbdl")
    }
    id: string = ChromiumExtensionId("/some/path")
    testing.expect_value(t, len(id), 32)
    for character in id {
        testing.expect(t, character >= 'a' && character <= 'p')
    }
}
