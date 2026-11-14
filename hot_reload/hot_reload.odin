// Hot reload of a game DLL while the host executable keeps running.
// Framework agnostic: the host owns the window and the loop, the DLL owns the game. They share one block of game memory
// that is kept across reloads when its layout did not change, and rebuilt when it did.
//
// The DLL exports the procs of `Api` with the prefix `game_` (game_init, game_update ...).
// The host passes one pointer to the DLL at init and after each reload. A pointer to a table of host procs
// (drawing, input) works well, because then the DLL never has to share the state of a framework.
//
// A reload is started by `HotReloadRequest` (for example from a button) or, with `config.poll`, when the DLL file is rewritten.
// No hidden allocations: the user provides the buffer of loaded DLLs, paths live in fixed buffers.
package hot_reload

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"
import "core:mem"
import "core:testing"
import api_demo "demo_game/api"   // only for the tests at the bottom

PATH_CAPACITY :: 260
FNV_OFFSET :: u64(14695981039346656037)
FNV_PRIME :: u64(1099511628211)

// What the DLL exports. Every proc is required, a DLL that misses one is refused.
Api :: struct {
    lib: dynlib.Library,

    // Create the game state with `allocator` and keep `host` for calling back into the executable
    init: proc(host: rawptr, allocator: runtime.Allocator),
    // Free the game state
    destroy: proc(),
    // One frame. Returns false when the game wants to quit
    update: proc() -> bool,
    // The game memory that is kept across reloads, its size and its layout (see LayoutHash)
    memory: proc() -> rawptr,
    memory_size: proc() -> int,
    memory_layout: proc() -> u64,
    // The code is about to be left behind: free what lives in the globals of this DLL (resources of the running screen)
    release: proc(),
    // The new code takes over the old memory
    reloaded: proc(memory: rawptr, host: rawptr),

    // Bookkeeping of the library
    version: int,
    modified: time.Time,
    copy_path: [PATH_CAPACITY]u8,
    copy_length: int,
}

ReloadResult :: enum {
    NONE,
    KEPT,       // the memory has the same layout, the new code runs on the same memory
    REBUILT,    // the layout changed, the game memory was destroyed and created again
    FAILED,     // the DLL could not be used, the old one keeps running
}

HotReloadConfig :: struct {
    dll_path: string,           // the built DLL, it is never loaded itself so the build can overwrite it
    copy_directory: string,     // where the loaded copies go, created if missing. Empty - current directory
    host: rawptr,               // handed to the DLL
    allocator: runtime.Allocator,   // given to the DLL for its game memory
    poll: bool,                 // also reload when the modified time of the DLL changes
    retry_seconds: f32,         // wait before trying a DLL that failed to load again (poll only), a build may still be writing it
}

HotReload :: struct {
    config: HotReloadConfig,
    api: Api,                   // the running one
    loaded: []Api,              // user buffer, the DLLs that were left behind stay loaded because the new state can point into them
    loaded_count: int,
    next_version: int,
    requested: bool,
    retry_after: time.Time,
    last_result: ReloadResult,
    reload_count: int,          // successful reloads
}

// Hash of the layout of a type: field names, offsets and types, through nested structs and arrays.
// Use it for `memory_layout` in the DLL. Same size is not enough to reuse memory, and typeid only hashes the name of a named type.
LayoutHash :: proc($T: typeid) -> u64 {
    hash: u64 = FNV_OFFSET
    LayoutHashType(&hash, type_info_of(T))
    return hash
}

@(private)
LayoutHashBytes :: proc(hash: ^u64, text: string) {
    for b in transmute([]u8)text {
        hash^ = (hash^ ~ u64(b)) * FNV_PRIME
    }
}

@(private)
LayoutHashType :: proc(hash: ^u64, info: ^runtime.Type_Info) {
    buffer: [128]u8
    base: ^runtime.Type_Info = runtime.type_info_base(info)
    LayoutHashBytes(hash, fmt.bprintf(buffer[:], "%v|%d|", info.id, info.size))
    #partial switch variant in base.variant {
    case ^runtime.Type_Info_Struct:
        for i in 0 ..< int(variant.field_count) {
            LayoutHashBytes(hash, variant.names[i])
            LayoutHashBytes(hash, fmt.bprintf(buffer[:], "@%d:", variant.offsets[i]))
            LayoutHashType(hash, variant.types[i])
        }
    case ^runtime.Type_Info_Array:
        LayoutHashBytes(hash, fmt.bprintf(buffer[:], "[%d]", variant.count))
        LayoutHashType(hash, variant.elem)
    }
}

// Every proc has to be found: dynlib reports success when only some of the symbols exist
@(private)
ApiIsComplete :: proc(api: ^Api) -> bool {
    return api.init != nil && api.destroy != nil && api.update != nil && api.memory != nil && api.memory_size != nil &&
        api.memory_layout != nil && api.release != nil && api.reloaded != nil
}

// Copy the DLL to a versioned name and load the copy. A DLL that is still being written, or that doesn't match, is not fatal
@(private)
LoadApi :: proc(hot_reload: ^HotReload, version: int) -> (api: Api, ok: bool) {
    modified, modified_error := os.last_write_time_by_name(hot_reload.config.dll_path)
    if modified_error != nil {
        return
    }

    directory: string = hot_reload.config.copy_directory if len(hot_reload.config.copy_directory) > 0 else "."
    copy_path: string = fmt.bprintf(api.copy_path[:PATH_CAPACITY - 1], "%s/game_%d.%s", directory, version, dynlib.LIBRARY_FILE_EXTENSION)
    api.copy_length = len(copy_path)

    if os.copy_file(copy_path, hot_reload.config.dll_path) != nil {
        return
    }

    _, symbols_ok := dynlib.initialize_symbols(&api, copy_path, "game_", "lib")
    if !symbols_ok || !ApiIsComplete(&api) {
        api.version = version
        UnloadApi(&api)
        api = {}
        return
    }

    api.version = version
    api.modified = modified
    ok = true
    return
}

@(private)
UnloadApi :: proc(api: ^Api) {
    if api.lib != nil {
        dynlib.unload_library(api.lib)
        api.lib = nil
    }
    if api.copy_length > 0 {
        os.remove(string(api.copy_path[:api.copy_length]))
    }
}

// Load the first version and create the game state.
// `loaded` is the buffer for the DLLs that were left behind, its length limits how many reloads one run can take.
HotReloadInit :: proc(hot_reload: ^HotReload, config: HotReloadConfig, loaded: []Api) -> bool {
    assert(len(config.dll_path) > 0)
    assert(len(loaded) > 0)
    hot_reload^ = {
        config = config,
        loaded = loaded,
    }
    if hot_reload.config.retry_seconds <= 0 {
        hot_reload.config.retry_seconds = 0.5
    }
    if len(config.copy_directory) > 0 {
        os.make_directory_all(config.copy_directory)
    }

    api, ok := LoadApi(hot_reload, 0)
    if !ok {
        return false
    }
    hot_reload.api = api
    hot_reload.next_version = 1
    hot_reload.api.init(config.host, config.allocator)
    return true
}

// Run one frame of the game, then take a pending reload. Returns false when the game wants to quit.
HotReloadUpdate :: proc(hot_reload: ^HotReload) -> bool {
    running: bool = hot_reload.api.update()

    if hot_reload.requested {
        hot_reload.requested = false
        HotReloadNow(hot_reload)
    } else if hot_reload.config.poll && time.diff(hot_reload.retry_after, time.now()) > 0 {
        modified, modified_error := os.last_write_time_by_name(hot_reload.config.dll_path)
        if modified_error == nil && modified != hot_reload.api.modified {
            HotReloadNow(hot_reload)
        }
    }
    return running
}

// Reload at the end of the next HotReloadUpdate. Call it from a button or a key, after the DLL was rebuilt.
HotReloadRequest :: proc(hot_reload: ^HotReload) {
    hot_reload.requested = true
}

// Load the DLL that is at `dll_path` now and hand the game over to it. The old DLL stays loaded and the game keeps
// running on it when the new one can't be used.
HotReloadNow :: proc(hot_reload: ^HotReload) -> ReloadResult {
    hot_reload.last_result = .FAILED
    if hot_reload.loaded_count >= len(hot_reload.loaded) {
        return .FAILED
    }

    new_api, ok := LoadApi(hot_reload, hot_reload.next_version)
    if !ok {
        // most likely a build that is still writing the DLL
        hot_reload.retry_after = time.time_add(time.now(), time.Duration(f64(hot_reload.config.retry_seconds) * f64(time.Second)))
        return .FAILED
    }
    hot_reload.next_version += 1

    old_api: Api = hot_reload.api
    hot_reload.loaded[hot_reload.loaded_count] = old_api
    hot_reload.loaded_count += 1

    // Reuse the memory only when the new DLL describes it exactly like the old one
    if old_api.memory_size() == new_api.memory_size() && old_api.memory_layout() == new_api.memory_layout() {
        // What the running screen holds (globals, audio, textures) lives in the old DLL, so the old DLL releases it
        memory: rawptr = old_api.memory()
        old_api.release()
        new_api.reloaded(memory, hot_reload.config.host)
        hot_reload.last_result = .KEPT
    } else {
        old_api.destroy()
        new_api.init(hot_reload.config.host, hot_reload.config.allocator)
        hot_reload.last_result = .REBUILT
    }

    hot_reload.api = new_api
    hot_reload.reload_count += 1
    return hot_reload.last_result
}

// Throw the game memory away and create it again with the running code, for a restart key
HotReloadRestart :: proc(hot_reload: ^HotReload) {
    hot_reload.api.destroy()
    hot_reload.api.init(hot_reload.config.host, hot_reload.config.allocator)
}

// Destroy the game state, unload every DLL and remove the copies
HotReloadShutdown :: proc(hot_reload: ^HotReload) {
    hot_reload.api.destroy()
    for i in 0 ..< hot_reload.loaded_count {
        UnloadApi(&hot_reload.loaded[i])
    }
    UnloadApi(&hot_reload.api)
    hot_reload^ = {}
}

// --- Tests ---
// The reload tests build the demo game (demo_game/) as a DLL with `odin build`, so `odin` has to be in PATH.

@(test)
test_layout_hash_tells_layouts_apart :: proc(t: ^testing.T) {
    Base :: struct { a: int, b: [4]u8, c: struct { x, y: f32 } }
    Renamed :: struct { a: int, b: [4]u8, d: struct { x, y: f32 } }
    Retyped :: struct { a: f64, b: [4]u8, c: struct { x, y: f32 } }
    Longer :: struct { a: int, b: [8]u8, c: struct { x, y: f32 } }
    Inner :: struct { a: int, b: [4]u8, c: struct { x, y: f64 } }

    testing.expect_value(t, LayoutHash(Base), LayoutHash(Base))
    testing.expect(t, LayoutHash(Base) != LayoutHash(Renamed), "another field name")
    testing.expect(t, LayoutHash(Base) != LayoutHash(Retyped), "same size, another type")
    testing.expect(t, LayoutHash(Base) != LayoutHash(Longer), "another array length")
    testing.expect(t, LayoutHash(Base) != LayoutHash(Inner), "a change inside of a nested struct")
    testing.expect_value(t, size_of(int), size_of(f64))
}

@(test)
test_init_fails_without_a_dll :: proc(t: ^testing.T) {
    hot_reload: HotReload
    loaded: [2]Api
    ok: bool = HotReloadInit(&hot_reload, {dll_path = "this/does/not/exist.dll"}, loaded[:])
    testing.expect(t, !ok)
}

@(test)
test_api_must_be_complete :: proc(t: ^testing.T) {
    api: Api
    testing.expect(t, !ApiIsComplete(&api))
    api = {
        init = proc(host: rawptr, allocator: runtime.Allocator) {},
        destroy = proc() {},
        update = proc() -> bool { return true },
        memory = proc() -> rawptr { return nil },
        memory_size = proc() -> int { return 0 },
        memory_layout = proc() -> u64 { return 0 },
        release = proc() {},
        reloaded = proc(memory: rawptr, host: rawptr) {},
    }
    testing.expect(t, ApiIsComplete(&api))
    api.release = nil
    testing.expect(t, !ApiIsComplete(&api), "a single missing export refuses the DLL")
}

// --- Integration test: the real demo game DLL, three builds of it ---
//   base    the game as it is
//   pad     the memory has a different size
//   layout  the memory has the same size, but a different type

@(private="file", thread_local)
reported_counter: int
@(private="file", thread_local)
reported_frames: int

@(private="file")
test_host :: proc() -> api_demo.Host {
    return {
        draw_rect = proc(rect: api_demo.Rect, color: api_demo.Color) {},
        draw_text = proc(text: string, position: api_demo.Vec2, size: f32, color: api_demo.Color) {},
        frame_time = proc() -> f32 { return 1.0 / 60 },
        screen_size = proc() -> api_demo.Vec2 { return {800, 600} },
        report = proc(counter: int) {
            reported_counter = counter
            reported_frames += 1
        },
    }
}

// New file in place at once so the next copy never sees a half written DLL
@(private="file")
install_dll :: proc(directory: string, variant: string) -> bool {
    source: string = fmt.tprintf("%s/variants/%s.dll", directory, variant)
    data, read_error := os.read_entire_file(source, context.temp_allocator)
    if read_error != nil { return false }
    incoming: string = fmt.tprintf("%s/incoming.dll", directory)
    if os.write_entire_file(incoming, data) != nil { return false }
    target: string = fmt.tprintf("%s/game.dll", directory)
    os.remove(target)
    return os.rename(incoming, target) == nil
}

@(private="file")
run_frames :: proc(hot_reload: ^HotReload, count: int) {
    for _ in 0 ..< count {
        HotReloadUpdate(hot_reload)
    }
}

@(test)
test_reload_keeps_or_rebuilds_the_memory :: proc(t: ^testing.T) {
    temp_directory, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil {
        testing.fail_now(t, "no temp directory")
    }
    directory: string = fmt.tprintf("%s/odin_utilities_hot_reload_test", temp_directory)
    os.make_directory_all(fmt.tprintf("%s/variants", directory))
    defer os.remove_all(directory)

    built: bool = api_demo.BuildGameDll(fmt.tprintf("%s/variants/base.dll", directory))
    built &&= api_demo.BuildGameDll(fmt.tprintf("%s/variants/pad.dll", directory), "-define:DEMO_PAD=64")
    built &&= api_demo.BuildGameDll(fmt.tprintf("%s/variants/layout.dll", directory), "-define:DEMO_FLOAT_COUNTER=true")
    if !built {
        testing.fail_now(t, "could not build the demo game, is odin in PATH?")
    }
    testing.expect(t, install_dll(directory, "base"))

    // every allocation of the game goes through the tracker, nothing may be left at the end
    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)

    host: api_demo.Host = test_host()
    hot_reload: HotReload
    loaded: [16]Api
    config: HotReloadConfig = {
        dll_path = fmt.tprintf("%s/game.dll", directory),
        copy_directory = fmt.tprintf("%s/copies", directory),
        host = &host,
        allocator = mem.tracking_allocator(&tracker),
        retry_seconds = 0.01,
    }
    testing.expect(t, HotReloadInit(&hot_reload, config, loaded[:]))
    run_frames(&hot_reload, 30)
    testing.expect_value(t, reported_counter, 30)

    // the same layout: the memory stays and counting goes on
    testing.expect(t, install_dll(directory, "base"))
    HotReloadRequest(&hot_reload)
    run_frames(&hot_reload, 1)
    testing.expect_value(t, hot_reload.last_result, ReloadResult.KEPT)
    run_frames(&hot_reload, 5)
    testing.expect_value(t, reported_counter, 36)

    // another size: the memory is new
    testing.expect(t, install_dll(directory, "pad"))
    testing.expect_value(t, HotReloadNow(&hot_reload), ReloadResult.REBUILT)
    run_frames(&hot_reload, 3)
    testing.expect_value(t, reported_counter, 3)

    // the same size and another layout, the old bytes must not be read as the new type
    testing.expect(t, install_dll(directory, "base"))
    testing.expect_value(t, HotReloadNow(&hot_reload), ReloadResult.REBUILT)
    run_frames(&hot_reload, 20)
    testing.expect(t, install_dll(directory, "layout"))
    testing.expect_value(t, HotReloadNow(&hot_reload), ReloadResult.REBUILT)
    run_frames(&hot_reload, 3)
    testing.expect_value(t, reported_counter, 3)

    // polling picks the file up without a request
    hot_reload.config.poll = true
    testing.expect(t, install_dll(directory, "layout"))
    reloads: int = hot_reload.reload_count
    run_frames(&hot_reload, 2)
    testing.expect_value(t, hot_reload.reload_count, reloads + 1)
    hot_reload.config.poll = false

    // a half written DLL and a file that is no DLL: refused, the game keeps running
    frames_before: int = reported_frames
    data, _ := os.read_entire_file(fmt.tprintf("%s/variants/base.dll", directory), context.temp_allocator)
    os.remove(config.dll_path)
    testing.expect_value(t, os.write_entire_file(config.dll_path, data[:len(data) / 3]), nil)
    testing.expect_value(t, HotReloadNow(&hot_reload), ReloadResult.FAILED)
    os.remove(config.dll_path)
    testing.expect_value(t, os.write_entire_file(config.dll_path, "not a dll"), nil)
    testing.expect_value(t, HotReloadNow(&hot_reload), ReloadResult.FAILED)
    run_frames(&hot_reload, 4)
    testing.expect_value(t, reported_frames, frames_before + 4)
    testing.expect(t, install_dll(directory, "base"))
    testing.expect_value(t, HotReloadNow(&hot_reload), ReloadResult.REBUILT)           // base after layout: the layout is not the same

    // restart
    run_frames(&hot_reload, 10)
    HotReloadRestart(&hot_reload)
    run_frames(&hot_reload, 2)
    testing.expect_value(t, reported_counter, 2)

    HotReloadShutdown(&hot_reload)
    testing.expect_value(t, len(tracker.allocation_map), 0)
    testing.expect_value(t, len(tracker.bad_free_array), 0)
}
