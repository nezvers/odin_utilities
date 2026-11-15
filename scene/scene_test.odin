#+build !js
// Tests of scene.odin. They are in their own file because the scene system is imported by games with a web build, and core:testing does not compile for js_wasm32.
package scene

import "core:testing"
import "base:runtime"
import hm "core:container/handle_map"

@(private="file", thread_local)
log: [64]string
@(private="file", thread_local)
log_count: int
@(private="file", thread_local)
fake_time: f64
@(private="file", thread_local)
unloaded: int
@(private="file", thread_local)
arena_pointer: rawptr

@(private="file")
write_log :: proc(text: string) {
    if log_count < len(log) {
        log[log_count] = text
        log_count += 1
    }
}

@(private="file")
log_has :: proc(text: string) -> bool {
    for i in 0 ..< log_count {
        if log[i] == text { return true }
    }
    return false
}

@(private="file")
log_index :: proc(text: string) -> int {
    for i in 0 ..< log_count {
        if log[i] == text { return i }
    }
    return -1
}

@(private="file")
fake_clock :: proc() -> f64 { return fake_time }

@(private="file")
fake_load :: proc(def: ^AssetDef, scratch: runtime.Allocator) -> (AssetValue, bool) {
    fake_time += 0.001
    if def.name == "bad" { return {}, false }
    return {handle = 1000 + u64(def.flags)}, true
}

@(private="file")
fake_unload :: proc(def: ^AssetDef, value: AssetValue) {
    unloaded += 1
}

// scene procs: every one writes a line to the log
@(private="file") title_init :: proc() { write_log("title init") }
@(private="file") title_finit :: proc() { write_log("title finit") }
@(private="file") menu_init :: proc() { write_log("menu init") }
@(private="file") menu_finit :: proc() { write_log("menu finit") }
@(private="file") game_init :: proc() {
    write_log("game init")
    // the memory of a scene comes from its arena
    scene_memory := make([]u8, 1024, test_system_allocator())
    arena_pointer = raw_data(scene_memory)
}
@(private="file") game_finit :: proc() { write_log("game finit") }
@(private="file") game_resume :: proc() { write_log("game resume") }
@(private="file") game_update :: proc() { write_log("game update") }

@(private="file", thread_local)
current_system: ^SceneSystem

@(private="file")
test_system_allocator :: proc() -> runtime.Allocator {
    return SceneAllocator(current_system)
}

// ids of the assets of the test: 1 font and 2 sound are small (the title), 3 level, 4 enemy, 5 music, 6 bad, 7 ui (persistent)
@(private="file")
TestWorld :: struct {
    scenes: [3]SceneDef,
    asset_defs: [8]AssetDef,
    loaders: [1]AssetLoader,
    storage: AssetStorage(8),
    scene_memory: [8192]u8,
    system: SceneSystem,
}

@(private="file") TITLE :: SceneId(0)
@(private="file") MENU :: SceneId(1)
@(private="file") GAME :: SceneId(2)

@(private="file")
test_world_init :: proc(world_pointer: rawptr, scenes: [3]SceneDef) {
    world: ^TestWorld = cast(^TestWorld)world_pointer       // the system keeps pointers into the world, it lives as long as the test
    fake_time = 0
    log_count = 0
    unloaded = 0
    arena_pointer = nil
    for name, i in ([8]string{"none", "font", "sound", "level", "enemy", "music", "bad", "ui"}) {
        world.asset_defs[i] = {name = name, flags = u32(i), placeholder = {handle = 7}}
    }
    world.asset_defs[7].persistent = true
    world.loaders[0] = {load = fake_load, unload = fake_unload}
    world.scenes = scenes
    SceneSystemInit(&world.system, {loader = {clock = fake_clock}, scene_memory = world.scene_memory[:]}, world.scenes[:], world.asset_defs[:], world.loaders[:], &world.storage)
    current_system = &world.system
}

// static data: the slices inside of it have to outlive every test
@(private="file")
base_scenes: [3]SceneDef = {
    TITLE = {name = "title", init = title_init, finit = title_finit, required = {1}, next = {MENU}},
    MENU = {name = "menu", init = menu_init, finit = menu_finit, required = {2}, optional = {5}, next = {GAME}},
    GAME = {name = "game", init = game_init, finit = game_finit, update = game_update, required = {3, 4}},
}

@(private="file")
test_scenes :: proc() -> [3]SceneDef {
    return base_scenes
}

@(private="file")
run :: proc(system: ^SceneSystem, frames: int, dt: f32 = 1.0 / 60) {
    for _ in 0 ..< frames { SceneUpdate(system, dt) }
}

@(test)
test_first_scene_covers_until_ready_then_uncovers :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system

    SceneStart(system, TITLE)
    testing.expect_value(t, system.transition.phase, TransitionPhase.LOADING)
    testing.expect_value(t, system.transition.alpha, f32(1))                         // starts covered, nothing to see yet
    testing.expect(t, !log_has("title init"))

    run(system, 1)                                                                   // the blocking load happens in this frame
    testing.expect(t, AssetIsReady(&system.assets, 1))
    run(system, 12)                                                                  // the cover stays for the hold time (0.15 s)
    testing.expect(t, log_has("title init"))
    testing.expect_value(t, system.transition.phase, TransitionPhase.IN)
    run(system, 20)
    testing.expect_value(t, system.transition.phase, TransitionPhase.NONE)
    testing.expect_value(t, system.transition.alpha, f32(0))
}

@(test)
test_prefetch_makes_the_next_scene_instant :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    SceneStart(system, TITLE)
    run(system, 60)                                                                  // title is up, its `next` (menu) loads in the background
    testing.expect(t, SceneIsReady(system, MENU), "the likely next scene was loaded without being asked for")

    SceneGoto(system, MENU)
    testing.expect_value(t, system.transition.phase, TransitionPhase.NONE)           // no transition: nothing to wait for
    testing.expect(t, system.current == MENU && system.entered)
    testing.expect(t, log_index("title finit") < log_index("menu init"), "leaves the old scene before the new one starts")
}

@(test)
test_unpredictable_scene_waits_behind_a_transition :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    SceneStart(system, TITLE)
    run(system, 30)                                                                  // the title is up and the start transition is over
    system.loader.smoothed_dt = 0.1                                                  // a slow game, background loading is one item per frame
    testing.expect(t, !SceneIsReady(system, GAME), "the game scene was not predicted from the title")

    SceneGoto(system, GAME)                                                          // unpredictable
    testing.expect_value(t, system.transition.phase, TransitionPhase.OUT)
    testing.expect(t, AssetsHaveBlocking(&system.assets), "what is missing jumps the queue")
    testing.expect(t, system.current == TITLE, "the old scene still runs while the cover goes up")

    phases_seen: [TransitionPhase]bool
    max_alpha_before_switch: f32
    for _ in 0 ..< 200 {
        SceneUpdate(system, 1.0 / 60)
        phases_seen[system.transition.phase] = true
        if !log_has("game init") { max_alpha_before_switch = max(max_alpha_before_switch, system.transition.alpha) }
        if system.transition.phase == .NONE { break }
    }
    testing.expect(t, phases_seen[.OUT] && phases_seen[.LOADING] && phases_seen[.IN], "out, loading and in")
    testing.expect_value(t, max_alpha_before_switch, f32(1))                         // the switch happened behind a full cover
    testing.expect(t, log_has("game init") && system.current == GAME)
    testing.expect(t, AssetIsReady(&system.assets, 3) && AssetIsReady(&system.assets, 4), "the scene had what it required")
}

@(test)
test_goto_works_while_a_transition_is_running :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    SceneStart(system, TITLE)
    run(system, 40)
    system.loader.smoothed_dt = 0.1
    SceneGoto(system, GAME)
    run(system, 3)
    SceneGoto(system, MENU)                                                          // changed their mind
    testing.expect_value(t, system.target, MENU)
    run(system, 200)
    testing.expect(t, system.current == MENU && system.transition.phase == .NONE)
    testing.expect(t, !log_has("game init"))
}

@(test)
test_scene_update_and_arena :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    SceneStart(system, GAME)
    run(system, 40)
    testing.expect(t, system.current == GAME)
    testing.expect(t, log_has("game update"))
    stats: SceneStats = SceneGetStats(system)
    testing.expect(t, stats.arena_used >= 1024, "init allocated from the scene arena")
    testing.expect_value(t, stats.arena_capacity, 8192)
    testing.expect(t, arena_pointer != nil)

    SceneGoto(system, TITLE)                                                         // unpredictable too
    run(system, 100)
    testing.expect(t, system.current == TITLE)
    testing.expect_value(t, SceneGetStats(system).arena_used, 0)                     // freed in one step when the scene exited
    testing.expect(t, SceneGetStats(system).arena_peak >= 1024, "the peak is kept")
}

@(test)
test_assets_of_left_scenes_are_unloaded_but_hinted_ones_stay :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    AssetRequest(&system.assets, 7, false)                                           // persistent
    SceneStart(system, TITLE)
    run(system, 80)
    SceneGoto(system, MENU)
    run(system, 80)                                                                  // menu is up, game (its next) loaded in the background
    testing.expect(t, AssetIsReady(&system.assets, 3) && AssetIsReady(&system.assets, 4), "the next scene is prefetched")
    testing.expect(t, AssetIsReady(&system.assets, 5), "optional assets arrive after the scene started")
    testing.expect(t, !AssetIsReady(&system.assets, 1), "the title font is not needed any more")
    testing.expect(t, AssetIsReady(&system.assets, 7), "persistent stays")
    testing.expect(t, unloaded >= 1)
    testing.expect_value(t, AssetGet(&system.assets, 1).handle, u64(7))              // anything still holding the id gets the placeholder
}

@(private="file", thread_local)
heard: [16]u32
@(private="file", thread_local)
heard_count: int

@(private="file")
hear :: proc(event: Event, user: rawptr) {
    if heard_count < len(heard) {
        heard[heard_count] = u32(event.kind) * 1000 + event.id
        heard_count += 1
    }
    if user != nil {
        (cast(^int)user)^ += 1
    }
}

@(test)
test_listeners_hear_assets_prefabs_and_scenes :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    heard_count = 0

    prefab: PrefabId = PrefabRegister(system, {3, 4})
    testing.expect(t, !PrefabIsReady(system, prefab))
    count: int
    Listen(system, .PREFAB_READY, u32(prefab), hear, &count, true)
    Listen(system, .ASSET_READY, u32(3), hear, &count)
    Listen(system, .SCENE_READY, u32(GAME), hear, &count, true)
    Listen(system, .SCENE_ENTERED, u32(TITLE), hear, &count)
    testing.expect_value(t, heard_count, 0)

    PrefabRequest(system, prefab, true)
    run(system, 4)
    testing.expect(t, PrefabIsReady(system, prefab))
    testing.expect_value(t, count, 3)                                                // asset 3, the prefab, the scene (game requires 3 and 4)
    testing.expect_value(t, heard[0], u32(EventKind.ASSET_READY) * 1000 + 3)

    // listening late: it is true already, so the callback comes at once
    late: int
    Listen(system, .PREFAB_READY, u32(prefab), hear, &late, true)
    Listen(system, .ASSET_READY, u32(4), hear, &late, true)
    testing.expect_value(t, late, 2)

    SceneStart(system, TITLE)
    run(system, 20)
    testing.expect_value(t, count, 4)                                                // the title was entered

    // once listeners are gone after they fired
    run(system, 5)
    before: int = count
    AssetsReleaseAll(&system.assets)
    AssetRequest(&system.assets, 3, false)
    run(system, 3)
    testing.expect_value(t, count, before + 1)                                       // only the repeating asset listener hears it again
}

@(test)
test_listeners_of_a_scene_go_with_it :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    title_run: SceneInstanceId = SceneStart(system, TITLE)
    run(system, 40)

    heard_count = 0
    in_title: int
    anywhere: int
    Listen(system, .SCENE_EXITED, ANY_ID, hear, &anywhere)
    mine, ok := Listen(system, .SCENE_EXITED, u32(TITLE), hear, &in_title, false, title_run)   // follows this run of the title
    testing.expect(t, ok)
    Listen(system, .ASSET_READY, u32(5), hear, &in_title, false, title_run)
    in_title = 0                                                                     // asset 5 may be ready already and called at once

    SceneGoto(system, MENU)                                                          // exits the title
    testing.expect_value(t, in_title, 1)                                             // heard the exit
    testing.expect_value(t, anywhere, 1)
    run(system, 60)                                                                  // asset 5 loads with the menu, but the run it followed is gone
    testing.expect_value(t, in_title, 1)

    SceneGoto(system, TITLE)
    run(system, 100)
    testing.expect_value(t, anywhere, 2)                                             // the wildcard listener stays

    Unlisten(system, mine)                                                           // an id that is gone already is harmless
    Unlisten(system, {idx = 99})
    testing.expect(t, !SceneInstanceIsAlive(system, title_run), "the first run of the title is over")
}

@(test)
test_listener_slots_are_limited_and_reusable :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    ids: [MAX_LISTENERS]ListenerId
    for i in 0 ..< MAX_LISTENERS {
        ok: bool
        ids[i], ok = Listen(system, .ASSET_READY, u32(1), hear)
        testing.expect(t, ok)
    }
    _, full := Listen(system, .ASSET_READY, u32(1), hear)
    testing.expect(t, !full, "all slots are used")
    Unlisten(system, ids[3])
    reused, reused_ok := Listen(system, .ASSET_READY, u32(1), hear)
    testing.expect(t, reused_ok)
    testing.expect_value(t, reused.idx, ids[3].idx)
    testing.expect(t, reused.gen != ids[3].gen, "a reused slot has a new generation")
    Unlisten(system, ids[3])                                                         // the old id must not remove the new listener
    testing.expect(t, hm.is_valid(system.listeners, reused))
}

@(test)
test_failed_required_asset_does_not_hang_the_transition :: proc(t: ^testing.T) {
    world: TestWorld
    scenes: [3]SceneDef = test_scenes()
    scenes[TITLE].required = {1, 6}                                                  // asset 6 always fails
    test_world_init(rawptr(&world), scenes)
    system: ^SceneSystem = &world.system
    SceneStart(system, TITLE)
    run(system, 60)
    testing.expect(t, system.current == TITLE && system.entered, "the scene starts, the asset gives its placeholder")
    testing.expect_value(t, AssetGet(&system.assets, 6).handle, u64(7))
    testing.expect_value(t, system.loader.failed_total, 1)
}

@(test)
test_progress_and_always_transition :: proc(t: ^testing.T) {
    world: TestWorld
    scenes: [3]SceneDef = test_scenes()
    scenes[MENU].always_transition = true
    test_world_init(rawptr(&world), scenes)
    system: ^SceneSystem = &world.system
    testing.expect_value(t, SceneProgress(system, GAME), f32(0))
    AssetRequest(&system.assets, 3, true)
    run(system, 1)
    testing.expect_value(t, SceneProgress(system, GAME), f32(0.5))                   // one of two required assets
    AssetRequest(&system.assets, 4, true)
    run(system, 1)
    testing.expect_value(t, SceneProgress(system, GAME), f32(1))

    SceneStart(system, TITLE)
    run(system, 60)
    SceneGoto(system, MENU)                                                          // ready, but this scene always shows its transition
    testing.expect_value(t, system.transition.phase, TransitionPhase.OUT)
    run(system, 60)
    testing.expect(t, system.current == MENU)
}

@(test)
test_expect_prefetches_on_a_hint_from_code :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    SceneStart(system, TITLE)
    run(system, 30)
    testing.expect(t, !SceneIsReady(system, GAME))

    SceneExpect(system, GAME)                                                        // the player is at the door
    testing.expect(t, !AssetsHaveBlocking(&system.assets), "a hint is background work")
    run(system, 90)
    testing.expect(t, SceneIsReady(system, GAME))
    SceneGoto(system, GAME)
    testing.expect_value(t, system.transition.phase, TransitionPhase.NONE)          // so the switch is instant
    testing.expect(t, system.current == GAME)
}

@(test)
test_hot_reload_release_rebind_resume :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    SceneStart(system, GAME)
    run(system, 40)
    ready_before: int = SceneGetStats(system).assets_ready
    Listen(system, .ASSET_READY, ANY_ID, hear)

    SceneRelease(system)                                                             // the old code is about to go
    testing.expect(t, log_has("game finit"))
    testing.expect(t, !system.entered)
    testing.expect_value(t, hm.len(system.listeners), 0)                             // the procs of the old code are forgotten
    testing.expect_value(t, SceneGetStats(system).assets_ready, ready_before)        // loaded assets are kept

    other: [3]SceneDef = test_scenes()                                               // the tables of the new code
    other[GAME].resume = game_resume
    SceneRebind(system, other[:], world.asset_defs[:], world.loaders[:])
    log_count = 0
    SceneResume(system)
    testing.expect(t, log_has("game resume"), "the scene continues on its data: resume, not init")
    testing.expect(t, !log_has("game init"))
    testing.expect_value(t, system.transition.phase, TransitionPhase.NONE)
    testing.expect(t, system.entered && system.current == GAME)
}

@(test)
test_shutdown_unloads_everything :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    AssetRequest(&system.assets, 7, false)
    SceneStart(system, TITLE)
    run(system, 60)
    SceneShutdown(system)
    stats: SceneStats = SceneGetStats(system)
    testing.expect_value(t, stats.assets_ready, 0)
    testing.expect_value(t, stats.assets_queued, 0)
    testing.expect(t, log_has("title finit"))
}

@(private="file", thread_local)
heard_kinds: [16]EventKind
@(private="file", thread_local)
heard_kind_count: int

@(private="file")
hear_kind :: proc(event: Event, user: rawptr) {
    if heard_kind_count < len(heard_kinds) {
        heard_kinds[heard_kind_count] = event.kind
        heard_kind_count += 1
    }
}

@(private="file")
heard_kind_of :: proc(kind: EventKind) -> int {
    count: int
    for i in 0 ..< heard_kind_count {
        if heard_kinds[i] == kind { count += 1 }
    }
    return count
}

@(test)
test_a_run_of_a_scene_has_a_handle_that_listeners_can_follow :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    heard_kind_count = 0
    SceneStart(system, TITLE)
    run(system, 40)
    system.loader.smoothed_dt = 0.1                                                  // slow: the game scene is not prefetched

    game_run: SceneInstanceId = SceneGoto(system, GAME)                              // not ready: a transition, the run exists already
    testing.expect(t, SceneInstanceIsAlive(system, game_run))
    scene, known := SceneInstanceScene(system, game_run)
    testing.expect(t, known && scene == GAME)
    testing.expect(t, SceneCurrentInstance(system) != game_run, "the title still runs while the cover goes up")

    Listen(system, .SCENE_READY, u32(GAME), hear_kind, nil, true, game_run)
    Listen(system, .SCENE_ENTERED, u32(GAME), hear_kind, nil, true, game_run)
    Listen(system, .SCENE_EXITED, u32(GAME), hear_kind, nil, true, game_run)
    run(system, 200)
    testing.expect_value(t, heard_kind_of(.SCENE_READY), 1)
    testing.expect_value(t, heard_kind_of(.SCENE_ENTERED), 1)
    testing.expect_value(t, heard_kind_of(.SCENE_EXITED), 0)
    testing.expect_value(t, SceneCurrentInstance(system), game_run)

    SceneGoto(system, TITLE)
    run(system, 200)
    testing.expect_value(t, heard_kind_of(.SCENE_EXITED), 1)                         // the run was left
    testing.expect(t, !SceneInstanceIsAlive(system, game_run), "and its handle is stale now")
    _, can_listen := Listen(system, .SCENE_ENTERED, u32(GAME), hear_kind, nil, false, game_run)
    testing.expect(t, !can_listen, "nothing can happen to a run that is over")
    _, still_known := SceneInstanceScene(system, game_run)
    testing.expect(t, !still_known)
}

@(test)
test_a_replaced_scene_request_is_cancelled :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    heard_kind_count = 0
    SceneStart(system, TITLE)
    run(system, 40)
    system.loader.smoothed_dt = 0.1

    first: SceneInstanceId = SceneGoto(system, GAME)
    Listen(system, .SCENE_CANCELLED, ANY_ID, hear_kind)
    Listen(system, .SCENE_ENTERED, ANY_ID, hear_kind, nil, false, first)
    second: SceneInstanceId = SceneGoto(system, MENU)                                // the player changed their mind
    testing.expect(t, first != second)
    testing.expect_value(t, heard_kind_of(.SCENE_CANCELLED), 1)
    testing.expect(t, !SceneInstanceIsAlive(system, first))
    testing.expect_value(t, SceneGoto(system, MENU), second)                         // asking for the same scene again is the same run

    run(system, 200)
    testing.expect_value(t, SceneCurrentInstance(system), second)
    testing.expect_value(t, heard_kind_of(.SCENE_ENTERED), 0)                        // the listener of the cancelled run heard nothing
}

@(test)
test_instance_slots_do_not_run_out_when_scenes_are_replaced_often :: proc(t: ^testing.T) {
    world: TestWorld
    test_world_init(rawptr(&world), test_scenes())
    system: ^SceneSystem = &world.system
    SceneStart(system, TITLE)
    run(system, 40)
    system.loader.smoothed_dt = 0.1
    SceneGoto(system, GAME)
    for i in 0 ..< 20 {
        SceneGoto(system, MENU if i % 2 == 0 else GAME)                              // 20 replaced runs, only 4 slots
    }
    run(system, 300)
    testing.expect(t, system.entered && SceneInstanceIsAlive(system, system.current_instance))
    testing.expect(t, hm.len(system.instances) <= MAX_INSTANCES)
}
