#+private file
package demo_common

// Hot reload of a game DLL (demo_game, no framework in it: it draws and reads the time through api.Host). The Reload button rebuilds the
// DLL and asks the library to load it: the game keeps its memory, the frame counter keeps counting. Edit demo_game/game.odin and press Reload.

import "core:fmt"
import "core:os"
import hot_reload ".."
import api "../demo_game/api"
import kit "../../demo_kit"

@(private="package")
demo_reload: kit.Demo = {
    name = "reload",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

DLL_DIRECTORY :: "hot_reload_demo"
DLL_PATH :: DLL_DIRECTORY + "/game.dll"
BUTTON_RECT :: kit.Rect{10, 40, 150, 30}

ctx_now: ^kit.Context
reported_counter: int       // the frame counter the game keeps in its memory, reported every frame

// Procs the game DLL draws with: the DLL never touches the framework itself
host: api.Host = {
    draw_rect = proc(rect: api.Rect, color: api.Color) { kit.DrawRect(ctx_now, rect, color) },
    draw_text = proc(text: string, position: api.Vec2, size: f32, color: api.Color) { kit.DrawText(ctx_now, text, position, size, color) },
    frame_time = proc() -> f32 { return ctx_now.delta_time },
    screen_size = proc() -> api.Vec2 { return ctx_now.screen },
    report = proc(counter: int) { reported_counter = counter },
}

reload_state: hot_reload.HotReload
loaded_buffer: [64]hot_reload.Api
started: bool
build_ok: bool

init :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    reported_counter = 0
    started = false
    os.make_directory_all(DLL_DIRECTORY)
    if !os.exists(DLL_PATH) && !api.BuildGameDll(DLL_PATH) { return }
    config: hot_reload.HotReloadConfig = {
        dll_path = DLL_PATH,
        copy_directory = DLL_DIRECTORY + "/copies",
        host = &host,
        allocator = context.allocator,
    }
    started = hot_reload.HotReloadInit(&reload_state, config, loaded_buffer[:])
}

finit :: proc(ctx: ^kit.Context) {
    if started { hot_reload.HotReloadShutdown(&reload_state) }
    started = false
}

update :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
}

draw :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    if !started {
        kit.DrawText(ctx, "the demo game could not be built", {10, 10}, 20, kit.RED)
        return
    }
    // the game updates and draws itself through the host
    hot_reload.HotReloadUpdate(&reload_state)

    // The button is the trigger: rebuild the DLL, then ask for the reload
    if kit.Button(ctx, BUTTON_RECT, "Reload") {
        build_ok = api.BuildGameDll(DLL_PATH)
        if build_ok { hot_reload.HotReloadRequest(&reload_state) }
    }
    kit.DrawText(ctx, fmt.tprintf("reloads: %d  last: %s", reload_state.reload_count, reload_name()), {10, 80}, 20, kit.DARK_GRAY)
    kit.DrawText(ctx, "edit demo_game/game.odin, then press Reload", {10, 110}, 20, kit.GRAY)
}

reload_name :: proc() -> string {
    switch reload_state.last_result {
    case .NONE: return "-"
    case .KEPT: return "memory kept"
    case .REBUILT: return "memory rebuilt"
    case .FAILED: return "failed, old code still runs"
    }
    return ""
}

counter_before: int

script: []kit.Step = {
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return started && reported_counter >= 5 }, "the DLL was built and loaded: its frame counter counts"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        counter_before = reported_counter
        return reload_state.reload_count == 0
    }, "no reload yet"),
    // the Reload button: rebuilds the DLL (the compiler runs, a few seconds), then the library loads the new one
    kit.MoveTo({60, 55}), kit.Wait(2), kit.Click({60, 55}),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return build_ok && reload_state.reload_count == 1 }, "the button rebuilt the DLL and it was reloaded"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return reload_state.last_result == .KEPT }, "same layout of the game memory: it was kept"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return reported_counter > counter_before }, "the frame counter of the game kept counting over the reload"),
}
