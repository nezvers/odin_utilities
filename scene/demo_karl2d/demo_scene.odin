// Scene system demo: three scenes that need different textures.
//   - Hover a button for a moment: the scene is expected, its assets load in the background and the click is instant.
//   - Click Cave (no hint): not predicted, so the transition covers the wait while the blocking assets load.
//   - Before a texture is loaded it draws as a checker (the placeholder), then the real one replaces it.
// The tiles textures take 250 ms each to decode on purpose (see slow_texture_decode) so the waiting is easy to see.
// On a platform with threads that work happens on worker threads, the frame time on screen stays flat while the loading bar fills.
// Run from the scene directory: odin run demo_karl2d
#+private file
package demo_karl2d

import "core:fmt"
import kit "../../demo_kit"
import "core:time"
import "base:runtime"
import "../../karl2d"
import scene ".."
import glue "../glue_karl2d"

KIND_SLOW_TEXTURE :: scene.AssetKind(4)

// asset ids: the table is data, scenes list what they need
DUST :: scene.AssetId(1)
PLAYER :: scene.AssetId(2)
TILES :: scene.AssetId(3)
TILES_DUAL :: scene.AssetId(4)
PALETTE :: scene.AssetId(5)

HOME :: scene.SceneId(0)
FOREST :: scene.SceneId(1)
CAVE :: scene.SceneId(2)
SKY :: scene.SceneId(3)

defs: [6]scene.AssetDef = {
    DUST = {name = "dust", kind = glue.KIND_TEXTURE, source = #load("../../assets/textures/dust_4_strip.png"), flags = glue.FLAG_PREMULTIPLY_ALPHA},
    PLAYER = {name = "player", kind = glue.KIND_TEXTURE, source = #load("../../assets/textures/player_sheet.png"), flags = glue.FLAG_PREMULTIPLY_ALPHA},
    TILES = {name = "tiles", kind = KIND_SLOW_TEXTURE, source = #load("../../assets/textures/tileset_template.png")},
    TILES_DUAL = {name = "tiles dual", kind = KIND_SLOW_TEXTURE, source = #load("../../assets/textures/tileset_template_dualgrid.png")},
    PALETTE = {name = "palette", kind = glue.KIND_TEXTURE, source = #load("../../assets/textures/palette_journey.png")},
}

// the table of the library plus a kind that is slow, like a big file would be
loaders: [5]scene.AssetLoader

// The slow part is in the decode: it runs on a worker thread when the platform has them, so the frames do not stall
slow_texture_decode :: proc(def: ^scene.AssetDef, memory: runtime.Allocator) -> (rawptr, bool) {
    time.sleep(250 * time.Millisecond)
    return glue.TextureDecode(def, memory)
}

scenes: [4]scene.SceneDef = {
    HOME = {name = "home", draw = draw_home},
    FOREST = {name = "forest", draw = draw_forest, required = {PLAYER}, optional = {DUST}, next = {HOME}},
    CAVE = {name = "cave", draw = draw_cave, required = {TILES, TILES_DUAL}, next = {HOME}},
    SKY = {name = "sky", draw = draw_sky, required = {PALETTE}, next = {HOME}, transition = {out_seconds = 0.4, in_seconds = 0.4, hold_seconds = 0.3}},
}

LOG_LINES :: 8
SceneDemo :: struct {
    system: scene.SceneSystem,
    storage: scene.AssetStorage(6),
    scene_memory: [16 * 1024]byte,
    decode_memory: [1024 * 1024]byte,   // split between the worker threads
    placeholder: scene.AssetValue,
    log: [LOG_LINES][96]u8,
    log_lengths: [LOG_LINES]int,
    log_count: int,
    hover_time: f32,
    hover_scene: scene.SceneId,
}

demo: SceneDemo

@(private="package")
demo_scene: kit.Demo = {
    name = "scenes",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

ctx_now: ^kit.Context       // the widgets read the mouse of the kit, so a script can click them

init :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    ctx.background = {28, 32, 44, 255}
    demo = {}
    for i in 0 ..< 4 { loaders[i] = glue.loaders[i] }
    loaders[KIND_SLOW_TEXTURE] = {decode = slow_texture_decode, finish = glue.TextureFinish, unload = glue.TextureUnload}

    demo.placeholder = glue.PlaceholderTexture()
    glue.SetPlaceholders(defs[:], glue.KIND_TEXTURE, demo.placeholder)
    glue.SetPlaceholders(defs[:], KIND_SLOW_TEXTURE, demo.placeholder)
    scene.SceneSystemInit(&demo.system, {scene_memory = demo.scene_memory[:], decode_memory = demo.decode_memory[:]}, scenes[:], defs[:], loaders[:], &demo.storage)

    // listen to everything that is loaded, any asset
    scene.Listen(&demo.system, .ASSET_READY, scene.ANY_ID, on_event)
    scene.Listen(&demo.system, .SCENE_ENTERED, scene.ANY_ID, on_event)
    scene.Listen(&demo.system, .SCENE_READY, scene.ANY_ID, on_event)
    scene.Listen(&demo.system, .SCENE_CANCELLED, scene.ANY_ID, on_event)
    scene.SceneStart(&demo.system, HOME)
}

finit :: proc(ctx: ^kit.Context) {
    scene.SceneShutdown(&demo.system)
    glue.DestroyPlaceholderTexture(demo.placeholder)
}

update :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    scene.SceneUpdate(&demo.system, ctx.delta_time)
}

draw :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    scene.SceneDraw(&demo.system)
    draw_status()
    glue.DrawTransition(&demo.system, ctx.screen)
}

on_event :: proc(event: scene.Event, user: rawptr) {
    text: string
    switch event.kind {
    case .ASSET_READY: text = fmt.bprintf(demo.log[demo.log_count % LOG_LINES][:], "asset ready: %s", defs[event.id].name)
    case .SCENE_ENTERED: text = fmt.bprintf(demo.log[demo.log_count % LOG_LINES][:], "scene entered: %s", scenes[event.id].name)
    case .SCENE_READY: text = fmt.bprintf(demo.log[demo.log_count % LOG_LINES][:], "scene ready: %s", scenes[event.id].name)
    case .SCENE_CANCELLED: text = fmt.bprintf(demo.log[demo.log_count % LOG_LINES][:], "scene cancelled: %s", scenes[event.id].name)
    case .PREFAB_READY, .SCENE_EXITED: return
    }
    demo.log_lengths[demo.log_count % LOG_LINES] = len(text)
    demo.log_count += 1
}

// A button: a click goes to the scene, hovering it for 0.3 s only HINTS the scene so its assets load in the background
button :: proc(rect: karl2d.Rect, label: string, target: scene.SceneId, hint: bool) {
    mouse: karl2d.Vec2 = ctx_now.input.mouse_position
    hovering: bool = mouse.x >= rect.x && mouse.x <= rect.x + rect.w && mouse.y >= rect.y && mouse.y <= rect.y + rect.h
    karl2d.draw_rect(rect, karl2d.Color{90, 96, 120, 255} if hovering else karl2d.Color{60, 66, 88, 255})
    karl2d.draw_text(label, {rect.x + 12, rect.y + 10}, 22, karl2d.WHITE)
    if hovering && hint {
        if demo.hover_scene != target { demo.hover_scene = target; demo.hover_time = 0 }
        demo.hover_time += ctx_now.delta_time
        if demo.hover_time > 0.3 { scene.SceneExpect(&demo.system, target) }
    }
    if hovering && kit.MousePressed(&ctx_now.input) {
        scene.SceneGoto(&demo.system, target)
    }
}

draw_home :: proc() {
    karl2d.draw_text("scenes: hover for a moment to prefetch, click to go", {40, 30}, 26, karl2d.WHITE)
    button({40, 90, 420, 44}, "Forest (hint on hover)", FOREST, true)
    button({40, 150, 420, 44}, "Cave (no hint, slow textures)", CAVE, false)
    button({40, 210, 420, 44}, "Sky (hint on hover)", SKY, true)
}

back_button :: proc() {
    button({40, 660, 160, 40}, "Back", HOME, false)
}

draw_texture :: proc(id: scene.AssetId, rect: karl2d.Rect) {
    texture: karl2d.Texture = glue.TextureOf(&demo.system.assets, id)
    size: karl2d.Vec2 = {f32(karl2d.get_texture_width(texture)), f32(karl2d.get_texture_height(texture))}
    karl2d.draw_texture_fit(texture, {0, 0, size.x, size.y}, rect)
    state: scene.AssetState = scene.AssetGetState(&demo.system.assets, id)
    karl2d.draw_text(fmt.tprintf("%s: %v", defs[id].name, state), {rect.x, rect.y + rect.h + 6}, 18, karl2d.LIGHT_GRAY)
}

draw_forest :: proc() {
    draw_texture(PLAYER, {40, 90, 560, 70})
    draw_texture(DUST, {40, 220, 560, 70})                 // optional: the checker shows until it has loaded
    back_button()
}

draw_cave :: proc() {
    draw_texture(TILES, {40, 90, 400, 300})
    draw_texture(TILES_DUAL, {480, 90, 400, 300})
    back_button()
}

draw_sky :: proc() {
    draw_texture(PALETTE, {40, 90, 560, 200})
    back_button()
}

draw_status :: proc() {
    stats: scene.SceneStats = scene.SceneGetStats(&demo.system)
    x: f32 = 900
    karl2d.draw_text("loader", {x, 30}, 22, karl2d.WHITE)
    karl2d.draw_text(fmt.tprintf("ready %d  queued %d  loaded %d", stats.assets_ready, stats.assets_queued, stats.loaded_total), {x, 60}, 18, karl2d.LIGHT_GRAY)
    karl2d.draw_text(fmt.tprintf("frame %.1f ms (smoothed)  workers %d  decoded on them %d", stats.smoothed_dt * 1000, stats.workers, stats.decoded_on_workers), {x, 84}, 18, karl2d.LIGHT_GRAY)
    karl2d.draw_text(fmt.tprintf("scene memory %d / %d bytes", stats.arena_used, stats.arena_capacity), {x, 108}, 18, karl2d.LIGHT_GRAY)
    karl2d.draw_text("events", {x, 150}, 22, karl2d.WHITE)
    first: int = max(0, demo.log_count - LOG_LINES)
    for i in first ..< demo.log_count {
        line: int = i % LOG_LINES
        karl2d.draw_text(string(demo.log[line][:demo.log_lengths[line]]), {x, 182 + f32(i - first) * 22}, 17, karl2d.LIGHT_GRAY)
    }
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return demo.system.has_current && demo.system.current == HOME }, "starts on the home scene"),
    // hover over Forest: after a moment its assets are expected (prefetched in the background)
    kit.MoveTo({100, 110}),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return demo.hover_scene == FOREST && demo.hover_time > 0.3 }, "hovering hints the forest scene"),
    // the assets are decoded on worker threads, on a clock of their own: waited for, not slept (a fixed number of frames is too few when the frames are fast and the computer is busy)
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool { return scene.SceneIsReady(&demo.system, FOREST) }, "the hinted forest assets were prefetched in the background", 30),
    kit.Click({100, 110}),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return demo.system.current == FOREST && demo.system.entered }, "the hinted scene starts at once when it is clicked"),
    kit.Click({100, 680}),                      // Back
    kit.Wait(20),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return demo.system.current == HOME }, "back to home"),
    // the cave was not hinted and needs two slow textures: the transition covers the wait
    kit.Click({100, 170}),
    kit.Wait(1),                                // the transition is there from the click on; the slow textures take 250 ms of real time each, so this is looked at right away, not after a few frames
    kit.Check(proc(ctx: ^kit.Context) -> bool { return demo.system.transition.phase != .NONE }, "an unpredicted scene starts a transition while its assets load"),
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool { return demo.system.current == CAVE && demo.system.entered && demo.system.transition.phase == .NONE }, "the cave starts when its assets are ready", 30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return demo.log_count >= 4 }, "the listeners heard about the assets and the scenes"),
    // the two textures of the cave are on the screen, no longer the checker of the placeholder (the rest of the picture has times and counters and is not looked at)
    kit.Wait(15),
    kit.CaptureIn("cave", {{40, 90, 840, 300}}),
    kit.Wait(1),
}
