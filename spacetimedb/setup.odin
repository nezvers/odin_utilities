package spacetimedb

// Setup: gets what working with SpacetimeDB from Odin needs and keeps all of it out of git. `SetupRun` is called by `odin run spacetimedb/tool/setup` and by the setup of a library that builds
// on this one (the Godot extension, a game template): it clones the sources the library follows into the `references` folder of odin_utilities (a clone that is there is left alone, `update`
// pulls it), and downloads the server of the release that matches them into `spacetimedb/bin`. Everything it makes is untracked (`references/` and `spacetimedb/bin/` are in .gitignore).
//
// What it clones (shallow, only the newest state; a tool that reads the history clones in full by hand):
//   SpacetimeDB             the server, the protocol (crates/client-api-messages), the module ABI (crates/bindings-sys), the SDKs and the docs: the reference of every part of this library.
//                           It is vendored into this library (`spacetimedb/SpacetimeDB`, ignored by `spacetimedb/.gitignore`) and not into references/: it is the source this library is written
//                           against and the one that a build of the server for a platform without a release would use, so it lives next to the code that follows it. The others are references/.
//   BitCraftPublic          the server code of a real MMO that runs on SpacetimeDB: what a big module looks like
//   spacetimedb-python-sdk  an SDK of a language that is not Rust, C# or TypeScript
//   spacetimedb-bindings-cpp  the module bindings for C++: the nearest thing to what an Odin module needs
//   spacetimedb-cookbook    examples of the account of clockworklabs
//   spacetime-studio        a desktop database manager (ElegonCode): the REST side of the server in use
//
// The commands it runs are `git` and the `tar` of the system (a zip is unpacked by the tar of Windows 10; on Linux and macOS the release is a .tar.gz).

import "core:fmt"
import "core:os"
import "core:strings"
import web_build "../web_build"

SPACETIMEDB_VERSION :: "v2.16.1"                  // the release that the library is tested with: the protocol and the module ABI are of this one

Reference :: struct {
    name: string,               // the folder in references/
    url: string,
    purpose: string,
    local: bool,                // vendored into spacetimedb/<name> (untracked by the .gitignore of the library) and not into references/
}

REFERENCES :: [?]Reference{
    {"SpacetimeDB", "https://github.com/clockworklabs/SpacetimeDB.git", "the server, the protocol, the module ABI, the SDKs, the docs", true},
    {"BitCraftPublic", "https://github.com/clockworklabs/BitCraftPublic.git", "the server of an MMO on SpacetimeDB", false},
    {"spacetimedb-python-sdk", "https://github.com/clockworklabs/spacetimedb-python-sdk.git", "a client SDK in another language", false},
    {"spacetimedb-bindings-cpp", "https://github.com/clockworklabs/spacetimedb-bindings-cpp.git", "module bindings in C++", false},
    {"spacetimedb-cookbook", "https://github.com/clockworklabs/spacetimedb-cookbook.git", "examples", false},
    {"spacetime-studio", "https://github.com/ElegonCode/spacetime-studio.git", "a desktop manager of a database: the REST side in use", false},
}

SetupOptions :: struct {
    root: string,               // odin_utilities: references/ and spacetimedb/bin are made in it ("" : the folder this library is in, found by #directory)
    update: bool,               // pull the clones that exist
    skip_server: bool,          // only the references
    skip_references: bool,      // only the server
    skip_fixtures: bool,        // do not build the test modules (they need Rust: rustup with the wasm32-unknown-unknown target; the toolchain of fixtures/*/rust-toolchain.toml is fetched by rustup)
    log: proc(text: string),    // told what is done (nil: printed)
}

SetupResult :: struct {
    cloned: int,
    present: int,
    failed: int,
    server: bool,               // the server is there (downloaded now or before)
    fixtures: int,              // the test modules that are built
}

// The folder of odin_utilities (this library is in it)
SetupRoot :: proc() -> string {
    return #directory + ".."
}

ServerBinFolder :: proc(root: string = "") -> string {
    return fmt.tprintf("%s/spacetimedb/bin", root if root != "" else SetupRoot())
}

// The executable of the CLI (it starts the standalone server): where setup puts it
ServerCliPath :: proc(root: string = "") -> string {
    when ODIN_OS == .Windows {
        return fmt.tprintf("%s/spacetimedb-cli.exe", ServerBinFolder(root))
    } else {
        return fmt.tprintf("%s/spacetimedb-cli", ServerBinFolder(root))
    }
}

// The executable of the standalone server (what ServerStart runs)
ServerBinaryPath :: proc(root: string = "") -> string {
    when ODIN_OS == .Windows {
        return fmt.tprintf("%s/spacetimedb-standalone.exe", ServerBinFolder(root))
    } else {
        return fmt.tprintf("%s/spacetimedb-standalone", ServerBinFolder(root))
    }
}

@(private)
setupSay :: proc(options: SetupOptions, text: string) {
    if options.log != nil {
        options.log(text)
    } else {
        fmt.println(text)
    }
}

@(private)
runCommand :: proc(command: []string, working_dir: string = "") -> bool {
    state, _, _, err := os.process_exec({command = command, working_dir = working_dir}, context.temp_allocator)
    return err == nil && state.success
}

// Clones what is missing, downloads the server when it is missing. Idempotent: run it as often as you like.
SetupRun :: proc(options: SetupOptions = {}) -> (result: SetupResult) {
    root: string = options.root if options.root != "" else SetupRoot()
    if !options.skip_references {
        folder: string = fmt.tprintf("%s/references", root)
        os.make_directory_all(folder)
        // everything in references/ stays out of git: one rule in the folder itself, so no .gitignore of the repository has to know it
        ignore: string = fmt.tprintf("%s/.gitignore", folder)
        if !os.exists(ignore) { _ = os.write_entire_file(ignore, transmute([]u8)string("*\n")) }
        table := REFERENCES
        for reference in table {
            path: string = fmt.tprintf("%s/spacetimedb/%s", root, reference.name) if reference.local else fmt.tprintf("%s/%s", folder, reference.name)
            if os.exists(path) {
                result.present += 1
                if options.update && runCommand({"git", "pull", "--ff-only"}, path) { setupSay(options, fmt.tprintf("updated %s", reference.name)) }
                continue
            }
            setupSay(options, fmt.tprintf("cloning %s (%s)", reference.name, reference.purpose))
            if runCommand({"git", "clone", "--depth", "1", reference.url, path}) {
                result.cloned += 1
            } else {
                result.failed += 1
                setupSay(options, fmt.tprintf("could not clone %s", reference.url))
            }
        }
    }
    if !options.skip_server {
        result.server = SetupServer(options, root)
        if !result.server { result.failed += 1 }
    }
    if !options.skip_fixtures {
        if SetupFixture(options, "basic-rs", root) { result.fixtures += 1 }
        if SetupOdinModule(options, "basic", root) { result.fixtures += 1 }
        if SetupOdinModule(options, "rich", root) { result.fixtures += 1 }
        if SetupOdinModule(options, "arena", root) { result.fixtures += 1 }
        if SetupOdinModule(options, "auth", root) { result.fixtures += 1 }
    }
    return
}

// The built module of a fixture (fixtures/<name>/ is a Rust module, the module of the server's own template): `bin/<name>.wasm`. "" when it is not built.
FixturePath :: proc(name: string, root: string = "") -> string {
    path: string = fmt.tprintf("%s/%s.wasm", ServerBinFolder(root), name)
    return path if os.exists(path) else ""
}

// Builds a fixture module with cargo (when cargo is there and the module is not built yet): a table and a reducer that the tests of a session publish and call.
SetupFixture :: proc(options: SetupOptions, name: string, root: string = "") -> bool {
    base: string = root if root != "" else SetupRoot()
    if FixturePath(name, base) != "" { return true }
    source: string = fmt.tprintf("%s/spacetimedb/fixtures/%s", base, name)
    if !os.exists(source) { return false }
    // Rust is only for this test module and for building the server from source: nothing else of the library needs it (the server is a release binary, a module can be written in Odin)
    if !runCommand({"cargo", "--version"}) {
        setupSay(options, fmt.tprintf("no Rust here: the module %s is skipped (the session test runs with the module in Odin, which needs only the Odin compiler)", name))
        return false
    }
    bin: string = ServerBinFolder(base)
    os.make_directory_all(bin)
    target: string = fmt.tprintf("%s/cargo_target", bin)
    setupSay(options, fmt.tprintf("building the module %s with cargo", name))
    if !runCommand({"cargo", "build", "--release", "--target", "wasm32-unknown-unknown", "--target-dir", target}, source) {
        setupSay(options, "the build failed (is Rust installed, with the wasm32-unknown-unknown target?)")
        return false
    }
    crate, _ := strings.replace_all(name, "-", "_", context.temp_allocator)
    built: string = fmt.tprintf("%s/wasm32-unknown-unknown/release/%s_fixture.wasm", target, crate)
    data, err := os.read_entire_file(built, context.temp_allocator)
    if err != nil { return false }
    return os.write_entire_file(fmt.tprintf("%s/%s.wasm", bin, name), data) == nil
}

// The release of the server for this machine: the name of the archive, and the executables inside of it
@(private)
releaseArchive :: proc() -> (name: string, zipped: bool, ok: bool) {
    when ODIN_OS == .Windows && ODIN_ARCH == .amd64 {
        return "spacetime-x86_64-pc-windows-msvc.zip", true, true
    } else when ODIN_OS == .Linux && ODIN_ARCH == .amd64 {
        return "spacetime-x86_64-unknown-linux-gnu.tar.gz", false, true
    } else when ODIN_OS == .Linux && ODIN_ARCH == .arm64 {
        return "spacetime-aarch64-unknown-linux-gnu.tar.gz", false, true
    } else when ODIN_OS == .Darwin && ODIN_ARCH == .arm64 {
        return "spacetime-aarch64-apple-darwin.tar.gz", false, true
    } else when ODIN_OS == .Darwin && ODIN_ARCH == .amd64 {
        return "spacetime-x86_64-apple-darwin.tar.gz", false, true
    }
    return "", false, false
}

// Downloads the release into spacetimedb/bin and unpacks it (`curl` and `tar` are the ones of the system). True when the CLI is there afterwards.
SetupServer :: proc(options: SetupOptions = {}, root: string = "") -> bool {
    base: string = root if root != "" else SetupRoot()
    cli: string = ServerCliPath(base)
    if os.exists(cli) { return true }
    archive, zipped, supported := releaseArchive()
    if !supported {
        setupSay(options, "no release of the server for this system: build it from spacetimedb/SpacetimeDB (cargo build -p spacetimedb-cli -p spacetimedb-standalone --release)")
        return false
    }
    folder: string = ServerBinFolder(base)
    os.make_directory_all(folder)
    file: string = fmt.tprintf("%s/%s", folder, archive)
    url: string = fmt.tprintf("https://github.com/clockworklabs/SpacetimeDB/releases/download/%s/%s", SPACETIMEDB_VERSION, archive)
    setupSay(options, fmt.tprintf("downloading %s", url))
    if !runCommand({"curl", "-sL", "-f", "-o", file, url}) {
        setupSay(options, "the download failed")
        return false
    }
    // the tar of Windows reads a zip, the tar of git bash does not: ask for the system one by its path
    tar: string = "tar"
    when ODIN_OS == .Windows { tar = "C:/Windows/System32/tar.exe" }
    _ = zipped
    if !runCommand({tar, "-xf", file}, folder) {
        setupSay(options, "could not unpack the archive")
        return false
    }
    os.remove(file)
    return os.exists(cli)
}

// The module written in Odin of `module/example/<name>`, built into bin/<name>-odin.wasm when it is not there (the compiler is the one that runs setup: `odin` in the PATH)
SetupOdinModule :: proc(options: SetupOptions, name: string, root: string = "") -> bool {
    base: string = root if root != "" else SetupRoot()
    out: string = fmt.tprintf("%s/%s-odin.wasm", ServerBinFolder(base), name)
    if os.exists(out) { return true }
    setupSay(options, fmt.tprintf("building the module %s in Odin", name))
    os.make_directory_all(ServerBinFolder(base))
    package_path: string = fmt.tprintf("%s/spacetimedb/module/example/%s", base, name)
    if !os.exists(package_path) { package_path = fmt.tprintf("%s/spacetimedb/%s/module", base, name) }       // a game: spacetimedb/arena/module
    return BuildModule(package_path, out)
}

// The namespaces of host functions that a SpacetimeDB module may import (the ABI versions of the server of SPACETIMEDB_VERSION): a module that imports another one does not load
MODULE_IMPORT_MODULES :: [?]string{"spacetime_10.0", "spacetime_10.1", "spacetime_10.2", "spacetime_10.3", "spacetime_10.4", "spacetime_10.5", "spacetime_10.6"}

// Builds a module written in Odin (a package that uses spacetimedb/module) to WebAssembly with `web_build.WasmBuild` (`-target:freestanding_wasm32 -no-entry-point`) and checks the result: it
// exports `__describe_module__`, `__call_reducer__` and its memory, and imports only from the namespaces of the ABI. The module has no heap and no entry point; the host calls its exports.
// `extra` are more flags (`-o:size`, `-debug`). The message of a failed build goes to stderr.
BuildModule :: proc(package_path: string, out: string, extra: []string = nil) -> bool {
    imports := MODULE_IMPORT_MODULES
    result: web_build.WasmBuildResult = web_build.WasmBuild({
        source_directory = package_path,
        output = out,
        strict = true,
        odin_arguments = extra,
        require_exports = {"__describe_module__", "__call_reducer__"},
        require_memory = true,
        allowed_import_modules = imports[:],
    })
    if !result.ok { fmt.eprintln(result.message) }
    return result.ok
}

// The path of the cloned reference, "" when it is not there (run setup). SpacetimeDB itself is in this library's folder, the others in references/.
ReferencePath :: proc(name: string, root: string = "") -> string {
    base: string = root if root != "" else SetupRoot()
    path: string = fmt.tprintf("%s/spacetimedb/%s", base, name) if name == "SpacetimeDB" else fmt.tprintf("%s/references/%s", base, name)
    return path if os.exists(path) else ""
}

// Whether a name is one of the references (for a tool that takes a name)
ReferenceKnown :: proc(name: string) -> bool {
    table := REFERENCES
    for reference in table {
        if strings.equal_fold(reference.name, name) { return true }
    }
    return false
}
