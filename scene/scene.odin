package scene

// Scenes as data, with loading that stays out of the way.
//
// A SceneDef is a row of a table: its procs, the assets it REQUIRES (it cannot start without them), the assets it would LIKE
// (loaded in the background after it started), the prefabs it uses and the scenes that are likely to come next.
//
// Fast loading:
//   - Predictable: when a scene starts, the assets of the scenes in `next` start loading in the background, a few per frame
//     (see LoaderUpdate), so a likely next scene is already there when it is asked for. Code that knows more can call SceneExpect
//     as soon as something is predictable: the player stands at the door, the mouse is over the Play button.
//   - Not predictable: SceneGoto to a scene that is not ready turns what is missing into blocking requests (they jump the queue
//     and get a bigger budget) and starts a transition. The transition covers the screen while the loader works, the scene starts
//     when everything it requires is settled and the cover has been up for a moment. A scene that is already ready starts at once.
//   - Non-blocking loads never stall: AssetGet gives a placeholder or a null value until the real thing is there.
//
// Memory:
//   - Everything is fixed size: the tables are yours, the asset state is an AssetStorage, listeners and scene instances live in
//     static handle maps of the system (a stale handle is refused, a slot is reused with a new generation), prefab records in arrays.
//     Assets, prefabs and scenes are ids that index constant tables, handles are for what is made and removed while running.
//     Nothing allocates per frame.
//   - Each scene has an arena (SceneAllocator): what the scene allocates in `init` goes there and the whole arena is freed in one
//     step when the scene exits. Decode scratch memory is reset after every loaded item.
//   - When a scene starts, the assets that it, its hints and the persistent set don't need are unloaded.
//   - The system must not move after SceneSystemInit, the asset store points into it.
//
// Hot reload: all state is plain data, scenes are ids. SceneRelease before the old code is left, SceneRebind with the tables of the
// new code, SceneResume to start the current scene again. Loaded assets stay loaded.

import "base:runtime"
import hm "core:container/handle_map"
import "core:mem"

SceneId :: distinct u16
SCENE_NONE :: SceneId(max(u16))

PrefabId :: distinct u16
PREFAB_NONE :: PrefabId(max(u16))

MAX_SCENES :: 32
MAX_PREFABS :: 32
MAX_PREFAB_ASSETS :: 8
MAX_LISTENERS :: 32
MAX_INSTANCES :: 4      // the running scene, the one that is loading, and some room for replaced ones
READY_BUFFER :: 16
ANY_ID :: max(u32)      // a listener on this id hears every event of its kind

TransitionDef :: struct {
    out_seconds: f32,       // the cover goes up
    in_seconds: f32,        // the cover goes away
    hold_seconds: f32,      // the least time the cover stays up while loading, so it never flashes
}

TransitionPhase :: enum u8 {
    NONE,
    OUT,        // covering, the old scene still runs
    LOADING,    // fully covered, waiting for the assets
    IN,         // uncovering, the new scene runs
}

Transition :: struct {
    phase: TransitionPhase,
    time: f32,              // seconds in the phase
    alpha: f32,             // how much the screen is covered, 0 - 1
    progress: f32,          // how much of what the target requires is settled, 0 - 1
}

SceneDef :: struct {
    name: string,
    init: proc(),
    finit: proc(),
    update: proc(),
    draw: proc(),
    gui: proc(),
    required: []AssetId,        // the scene cannot start before these are settled
    prefabs: []PrefabId,        // the assets of these prefabs are required too
    optional: []AssetId,        // loaded in the background after the scene started
    next: []SceneId,            // likely next scenes: their assets are prefetched when this scene starts
    transition: TransitionDef,  // all zero - the default of the system
    always_transition: bool,    // also when everything is ready already
}

EventKind :: enum u8 {
    ASSET_READY,
    PREFAB_READY,       // every asset of the prefab is settled
    SCENE_READY,        // every required asset of the scene is settled, it can start without waiting
    SCENE_ENTERED,      // the scene started (its init ran)
    SCENE_EXITED,
    SCENE_CANCELLED,    // a scene that was asked for was replaced by another one before it started
}

// One run of a scene. SceneGoto and SceneStart make one and return its handle: it exists from the moment the scene is asked for
// until it exits, so listeners can follow one particular run. A handle of an instance that is gone is refused.
SceneInstanceId :: distinct hm.Handle32

Event :: struct {
    kind: EventKind,
    id: u32,                    // AssetId, PrefabId or SceneId, by kind
    instance: SceneInstanceId,  // the run it happened in or for, empty when there is none
}

ListenerProc :: proc(event: Event, user: rawptr)

ListenerId :: distinct hm.Handle32

@(private)
Listener :: struct {
    handle: ListenerId,         // required by the handle map
    once: bool,
    kind: EventKind,
    id: u32,
    scope: SceneInstanceId,     // only events of this instance, removed when it is gone. Empty - all events of the kind
    callback: ListenerProc,
    user: rawptr,
}

@(private)
SceneInstance :: struct {
    handle: SceneInstanceId,    // required by the handle map
    scene: SceneId,
    active: bool,               // its init ran and its finit did not
}

SceneSystemConfig :: struct {
    loader: LoaderConfig,
    transition: TransitionDef,      // default 0.25 s out, 0.25 s in, 0.15 s hold
    scene_memory: []byte,           // the arena of the running scene
    scratch_memory: []byte,         // decode scratch of the loader
}

SceneSystem :: struct {
    scenes: []SceneDef,
    assets: AssetStore,
    loader: Loader,
    default_transition: TransitionDef,

    current: SceneId,
    has_current: bool,
    entered: bool,                  // init of the current scene ran and finit did not
    instances_started: u32,         // counts the scenes that started, for the statistics
    current_instance: SceneInstanceId,
    target: SceneId,
    target_instance: SceneInstanceId,
    transition: Transition,

    arena: mem.Arena,
    has_arena: bool,

    prefab_count: int,
    prefab_assets: [MAX_PREFABS][MAX_PREFAB_ASSETS]AssetId,
    prefab_asset_count: [MAX_PREFABS]u8,
    prefab_ready: [MAX_PREFABS]bool,
    scene_ready: [MAX_SCENES]bool,
    expected: [MAX_SCENES]bool,     // scenes that code hinted with SceneExpect, their assets survive the next scene start

    listeners: hm.Static_Handle_Map(MAX_LISTENERS + 1, Listener, ListenerId),    // + 1: slot 0 is the empty handle
    instances: hm.Static_Handle_Map(MAX_INSTANCES + 1, SceneInstance, SceneInstanceId),
    ready_buffer: [READY_BUFFER]AssetId,
}

SceneSystemInit :: proc(
    system: ^SceneSystem,
    config: SceneSystemConfig,
    scenes: []SceneDef,
    asset_defs: []AssetDef,
    loaders: []AssetLoader,
    storage: ^AssetStorage($N),
) {
    assert(len(scenes) <= MAX_SCENES)
    system^ = {
        scenes = scenes,
        current = SCENE_NONE,
        target = SCENE_NONE,
        default_transition = config.transition,
    }
    if system.default_transition == {} {
        system.default_transition = {out_seconds = 0.25, in_seconds = 0.25, hold_seconds = 0.15}
    }
    AssetStoreInit(&system.assets, asset_defs, loaders, storage, config.scratch_memory)
    LoaderInit(&system.loader, config.loader)
    if len(config.scene_memory) > 0 {
        mem.arena_init(&system.arena, config.scene_memory)
        system.has_arena = true
    }
}

// Memory of the running scene. Freed in one step when the scene exits, nothing in it needs freeing one by one
SceneAllocator :: proc(system: ^SceneSystem) -> runtime.Allocator {
    if !system.has_arena {
        return runtime.nil_allocator()
    }
    return mem.arena_allocator(&system.arena)
}

// --- Prefab records: which assets a prefab needs, so it can be waited for and listened to ---

// Register what a prefab needs. Use PrefabAssets of the prefab definition for the list
PrefabRegister :: proc(system: ^SceneSystem, assets: []AssetId) -> PrefabId {
    assert(system.prefab_count < MAX_PREFABS)
    assert(len(assets) <= MAX_PREFAB_ASSETS)
    index: int = system.prefab_count
    for id, i in assets {
        system.prefab_assets[index][i] = id
    }
    system.prefab_asset_count[index] = u8(len(assets))
    system.prefab_count += 1
    system.prefab_ready[index] = PrefabIsReady(system, PrefabId(index))
    return PrefabId(index)
}

@(private)
PrefabAssetsOf :: proc(system: ^SceneSystem, id: PrefabId) -> []AssetId {
    return system.prefab_assets[id][:system.prefab_asset_count[id]]
}

// Every asset of the prefab is settled
PrefabIsReady :: proc(system: ^SceneSystem, id: PrefabId) -> bool {
    if int(id) >= system.prefab_count { return false }
    for asset in PrefabAssetsOf(system, id) {
        if !AssetIsSettled(&system.assets, asset) { return false }
    }
    return true
}

PrefabRequest :: proc(system: ^SceneSystem, id: PrefabId, blocking: bool) {
    if int(id) >= system.prefab_count { return }
    for asset in PrefabAssetsOf(system, id) {
        AssetRequest(&system.assets, asset, blocking)
    }
}

// --- Scenes: what they need ---

@(private)
SceneValid :: proc(system: ^SceneSystem, id: SceneId) -> bool {
    return int(id) < len(system.scenes)
}

// How many of the required assets (own and of the prefabs) are settled
SceneRequiredCount :: proc(system: ^SceneSystem, id: SceneId) -> (settled: int, total: int) {
    if !SceneValid(system, id) { return }
    def: ^SceneDef = &system.scenes[id]
    for asset in def.required {
        if asset == ASSET_NONE { continue }
        total += 1
        if AssetIsSettled(&system.assets, asset) { settled += 1 }
    }
    for prefab in def.prefabs {
        if int(prefab) >= system.prefab_count { continue }
        for asset in PrefabAssetsOf(system, prefab) {
            if asset == ASSET_NONE { continue }
            total += 1
            if AssetIsSettled(&system.assets, asset) { settled += 1 }
        }
    }
    return
}

// The scene can start without waiting
SceneIsReady :: proc(system: ^SceneSystem, id: SceneId) -> bool {
    settled, total := SceneRequiredCount(system, id)
    return SceneValid(system, id) && settled == total
}

// 0 - 1, 1 when there is nothing to wait for
SceneProgress :: proc(system: ^SceneSystem, id: SceneId) -> f32 {
    settled, total := SceneRequiredCount(system, id)
    return 1 if total == 0 else f32(settled) / f32(total)
}

@(private)
SceneRequestAssets :: proc(system: ^SceneSystem, id: SceneId, blocking: bool, with_optional: bool) {
    if !SceneValid(system, id) { return }
    def: ^SceneDef = &system.scenes[id]
    for asset in def.required { AssetRequest(&system.assets, asset, blocking) }
    for prefab in def.prefabs { PrefabRequest(system, prefab, blocking) }
    if with_optional {
        for asset in def.optional { AssetRequest(&system.assets, asset, false) }
    }
}

@(private)
SceneWantAssets :: proc(system: ^SceneSystem, id: SceneId) {
    if !SceneValid(system, id) { return }
    def: ^SceneDef = &system.scenes[id]
    for asset in def.required { AssetWant(&system.assets, asset) }
    for asset in def.optional { AssetWant(&system.assets, asset) }
    for prefab in def.prefabs {
        if int(prefab) >= system.prefab_count { continue }
        for asset in PrefabAssetsOf(system, prefab) { AssetWant(&system.assets, asset) }
    }
}

// Something makes `id` likely to be the next scene: load what it needs in the background, now. Costs nothing when it is
// already loaded or queued. If it turns out to be needed right away, SceneGoto makes the rest blocking.
SceneExpect :: proc(system: ^SceneSystem, id: SceneId) {
    if !SceneValid(system, id) { return }
    system.expected[id] = true
    SceneRequestAssets(system, id, false, true)
}

// --- Scene instances ---

@(private)
InstanceCreate :: proc(system: ^SceneSystem, scene: SceneId) -> SceneInstanceId {
    instance, ok := hm.add(&system.instances, SceneInstance{scene = scene})
    if !ok {
        // all used: a replaced run that never started is the one to drop
        it := hm.iterator_make(&system.instances)
        for item, handle in hm.iterate(&it) {
            if !item.active && handle != system.target_instance {
                InstanceCancel(system, handle)
                break
            }
        }
        instance = hm.add(&system.instances, SceneInstance{scene = scene})
    }
    return instance
}

// The run is gone: the listeners that followed it are removed
@(private)
InstanceRemove :: proc(system: ^SceneSystem, instance: SceneInstanceId) {
    RemoveScoped(system, instance)
    hm.remove(&system.instances, instance)
}

// A scene that never started says so
@(private)
InstanceCancel :: proc(system: ^SceneSystem, instance: SceneInstanceId) {
    item, alive := hm.get(&system.instances, instance)
    if !alive || item.active { return }
    Dispatch(system, {kind = .SCENE_CANCELLED, id = u32(item.scene), instance = instance})
    InstanceRemove(system, instance)
}

// The instance exists
SceneInstanceIsAlive :: proc(system: ^SceneSystem, instance: SceneInstanceId) -> bool {
    return hm.is_valid(system.instances, instance)
}

// Which scene a run belongs to
SceneInstanceScene :: proc(system: ^SceneSystem, instance: SceneInstanceId) -> (scene: SceneId, ok: bool) {
    item := hm.get(&system.instances, instance) or_return
    return item.scene, true
}

// The run that is running now. Empty when no scene runs
SceneCurrentInstance :: proc(system: ^SceneSystem) -> SceneInstanceId {
    return system.current_instance if system.entered else {}
}

// The run the events of this moment belong to: the one that is loading, or else the running one
@(private)
EventInstance :: proc(system: ^SceneSystem) -> SceneInstanceId {
    if system.transition.phase != .NONE && hm.is_valid(system.instances, system.target_instance) {
        return system.target_instance
    }
    return system.current_instance
}

// --- Events and listeners ---

@(private)
Satisfied :: proc(system: ^SceneSystem, kind: EventKind, id: u32, scope: SceneInstanceId) -> bool {
    if scope != {} && !hm.is_valid(system.instances, scope) { return false }
    switch kind {
    case .ASSET_READY: return AssetIsReady(&system.assets, AssetId(id))
    case .PREFAB_READY: return PrefabIsReady(system, PrefabId(id))
    case .SCENE_READY: return SceneIsReady(system, SceneId(id))
    case .SCENE_ENTERED: return system.entered && system.current == SceneId(id) && (scope == {} || scope == system.current_instance)
    case .SCENE_EXITED, .SCENE_CANCELLED: return false
    }
    return false
}

// Call `callback` when the event happens, as many times as it happens (or once). If it is true already (the prefab is ready, the
// scene is the current one) the callback is called right away, so the order of listening and loading does not matter.
// `scope` is a scene instance (what SceneGoto returned): only events of that run are heard, and the listener is removed when the
// run is gone. `id` ANY_ID hears every id of the kind. Returns false when all slots are used.
Listen :: proc(
    system: ^SceneSystem,
    kind: EventKind,
    id: u32,
    callback: ListenerProc,
    user: rawptr = nil,
    once: bool = false,
    scope: SceneInstanceId = {},
) -> (listener: ListenerId, ok: bool) {
    if scope != {} && !hm.is_valid(system.instances, scope) {
        return {}, false        // the run is gone, nothing will ever happen to it
    }
    if id != ANY_ID && Satisfied(system, kind, id, scope) {
        callback({kind = kind, id = id, instance = scope if scope != {} else EventInstance(system)}, user)
        if once { return {}, true }
    }
    return hm.add(&system.listeners, Listener{once = once, kind = kind, id = id, scope = scope, callback = callback, user = user})
}

// An id that is gone, or was reused by another listener, is refused and does nothing
Unlisten :: proc(system: ^SceneSystem, listener: ListenerId) {
    hm.remove(&system.listeners, listener)
}

@(private)
Dispatch :: proc(system: ^SceneSystem, event: Event) {
    // callbacks may add and remove listeners: look at the slots that existed when the event started
    end: int = int(system.listeners.used_len)
    for i in 1 ..< end {
        listener: Listener = system.listeners.items[i]
        if listener.handle.idx == 0 || listener.kind != event.kind { continue }
        if listener.id != ANY_ID && listener.id != event.id { continue }
        if listener.scope != {} && listener.scope != event.instance { continue }
        if listener.once {
            hm.remove(&system.listeners, listener.handle)
        }
        listener.callback(event, listener.user)
    }
}

@(private)
RemoveScoped :: proc(system: ^SceneSystem, instance: SceneInstanceId) {
    for i in 1 ..< int(system.listeners.used_len) {
        listener: ^Listener = &system.listeners.items[i]
        if listener.handle.idx != 0 && listener.scope == instance {
            hm.remove(&system.listeners, listener.handle)
        }
    }
}

@(private)
RemoveAllListeners :: proc(system: ^SceneSystem) {
    for i in 1 ..< int(system.listeners.used_len) {
        listener: ^Listener = &system.listeners.items[i]
        if listener.handle.idx != 0 {
            hm.remove(&system.listeners, listener.handle)
        }
    }
}

// What became ready this frame, and the prefabs and scenes that became ready because of it
@(private)
NotifyReady :: proc(system: ^SceneSystem, ready: []AssetId) {
    instance: SceneInstanceId = EventInstance(system)
    for asset in ready {
        Dispatch(system, {kind = .ASSET_READY, id = u32(asset), instance = instance})
    }
    for i in 0 ..< system.prefab_count {
        if !system.prefab_ready[i] && PrefabIsReady(system, PrefabId(i)) {
            system.prefab_ready[i] = true
            Dispatch(system, {kind = .PREFAB_READY, id = u32(i), instance = instance})
        }
    }
    for i in 0 ..< len(system.scenes) {
        if !system.scene_ready[i] && SceneIsReady(system, SceneId(i)) {
            system.scene_ready[i] = true
            // the scene that is being loaded tells its own run, others have none
            scene_instance: SceneInstanceId = system.target_instance if SceneId(i) == system.target else {}
            Dispatch(system, {kind = .SCENE_READY, id = u32(i), instance = scene_instance})
        }
    }
}

// After assets were released: what is ready now is not news, only the next change is
@(private)
ResyncReady :: proc(system: ^SceneSystem) {
    for i in 0 ..< system.prefab_count {
        system.prefab_ready[i] = PrefabIsReady(system, PrefabId(i))
    }
    for i in 0 ..< len(system.scenes) {
        system.scene_ready[i] = SceneIsReady(system, SceneId(i))
    }
}

// --- Starting and leaving scenes ---

@(private)
TransitionOf :: proc(system: ^SceneSystem, id: SceneId) -> TransitionDef {
    def: TransitionDef = system.scenes[id].transition
    return system.default_transition if def == {} else def
}

// The scene starts: release what the new set of scenes does not need, run init, prefetch what is likely to come next
@(private)
SceneEnter :: proc(system: ^SceneSystem, id: SceneId, instance: SceneInstanceId, release_unused: bool) {
    def: ^SceneDef = &system.scenes[id]

    if release_unused {
        AssetsClearWanted(&system.assets)
        SceneWantAssets(system, id)
        for next in def.next { SceneWantAssets(system, next) }
        for scene in 0 ..< len(system.scenes) {
            if system.expected[scene] { SceneWantAssets(system, SceneId(scene)) }
        }
        AssetsReleaseUnwanted(&system.assets)
        ResyncReady(system)
        system.expected = {}    // a hint is good for one scene start, the next one has its own
    }

    system.current = id
    system.has_current = true
    system.current_instance = instance
    system.instances_started += 1
    system.entered = true
    if item, alive := hm.get(&system.instances, instance); alive { item.active = true }
    if def.init != nil { def.init() }
    Dispatch(system, {kind = .SCENE_ENTERED, id = u32(id), instance = instance})

    // after init: what the scene likes, then what is likely next, both in the background. The required assets are settled already,
    // asking for a failed one again here would retry it at every start
    for asset in def.optional { AssetRequest(&system.assets, asset, false) }
    for next in def.next { SceneExpect(system, next) }
}

// Leave the running scene: exit event, finit, its listeners go, its arena is freed. `keep_instance` for a hot reload,
// the same run starts again afterwards
@(private)
SceneLeave :: proc(system: ^SceneSystem, keep_instance: bool = false) {
    if !system.entered { return }
    id: SceneId = system.current
    Dispatch(system, {kind = .SCENE_EXITED, id = u32(id), instance = system.current_instance})
    if system.scenes[id].finit != nil { system.scenes[id].finit() }
    if system.has_arena { free_all(SceneAllocator(system)) }
    system.entered = false
    if !keep_instance {
        InstanceRemove(system, system.current_instance)
        system.current_instance = {}
    }
}

// Start the first scene. Not ready: the screen starts covered and the transition uncovers it when the scene starts.
// Returns the run of the scene.
SceneStart :: proc(system: ^SceneSystem, id: SceneId) -> SceneInstanceId {
    assert(SceneValid(system, id))
    system.has_current = false
    system.entered = false
    instance: SceneInstanceId = InstanceCreate(system, id)
    SceneRequestAssets(system, id, true, false)
    if SceneIsReady(system, id) && !system.scenes[id].always_transition {
        SceneEnter(system, id, instance, true)
        return instance
    }
    system.target = id
    system.target_instance = instance
    system.transition = {phase = .LOADING, alpha = 1}
    return instance
}

// Go to a scene. Ready (prefetched): at once. Not ready: what is missing becomes blocking, the transition covers the wait.
// Returns the run of the scene: listen to it to know when it is ready, started, left or replaced.
SceneGoto :: proc(system: ^SceneSystem, id: SceneId) -> SceneInstanceId {
    assert(SceneValid(system, id))
    if system.transition.phase != .NONE {
        // already on the way somewhere: the run that was asked for is replaced, the cover stays as it is
        if system.target == id { return system.target_instance }
        InstanceCancel(system, system.target_instance)
        system.target = id
        system.target_instance = InstanceCreate(system, id)
        SceneRequestAssets(system, id, true, false)
        return system.target_instance
    }
    if system.has_current && system.current == id && system.entered { return system.current_instance }

    instance: SceneInstanceId = InstanceCreate(system, id)
    SceneRequestAssets(system, id, true, false)
    if SceneIsReady(system, id) && !system.scenes[id].always_transition {
        SceneLeave(system)
        SceneEnter(system, id, instance, true)
        return instance
    }
    system.target = id
    system.target_instance = instance
    system.transition = {phase = .OUT}
    return instance
}

// One frame: load some assets, advance the transition, run the update of the scene
SceneUpdate :: proc(system: ^SceneSystem, dt: f32) {
    count: int = LoaderUpdate(&system.loader, &system.assets, dt, system.ready_buffer[:])
    if count > 0 {
        NotifyReady(system, system.ready_buffer[:count])
    }

    transition: ^Transition = &system.transition
    if transition.phase != .NONE {
        def: TransitionDef = TransitionOf(system, system.target)
        transition.time += dt
        switch transition.phase {
        case .OUT:
            transition.alpha = 1 if def.out_seconds <= 0 else min(transition.time / def.out_seconds, 1)
            if transition.time >= def.out_seconds {
                transition.phase = .LOADING
                transition.time = 0
            }
        case .LOADING:
            transition.alpha = 1
            transition.progress = SceneProgress(system, system.target)
            if SceneIsReady(system, system.target) && transition.time >= def.hold_seconds {
                SceneLeave(system)
                SceneEnter(system, system.target, system.target_instance, true)
                system.target_instance = {}
                transition.phase = .IN
                transition.time = 0
                transition.progress = 1
            }
        case .IN:
            transition.alpha = 0 if def.in_seconds <= 0 else max(1 - transition.time / def.in_seconds, 0)
            if transition.time >= def.in_seconds {
                transition.phase = .NONE
                transition.alpha = 0
            }
        case .NONE:
        }
    }

    if system.entered && transition.phase != .LOADING && system.scenes[system.current].update != nil {
        system.scenes[system.current].update()
    }
}

SceneDraw :: proc(system: ^SceneSystem) {
    if system.entered && system.scenes[system.current].draw != nil { system.scenes[system.current].draw() }
}

SceneGui :: proc(system: ^SceneSystem) {
    if system.entered && system.scenes[system.current].gui != nil { system.scenes[system.current].gui() }
}

// For the glue that draws the cover
SceneTransition :: proc(system: ^SceneSystem) -> Transition {
    return system.transition
}

// --- Hot reload and shutdown ---

// The code is about to be replaced: finish the running scene and forget the listeners (their procs belong to the old code).
// Loaded assets and the ids stay.
SceneRelease :: proc(system: ^SceneSystem) {
    SceneLeave(system, true)
    RemoveAllListeners(system)
}

// The new code has new tables
SceneRebind :: proc(system: ^SceneSystem, scenes: []SceneDef, asset_defs: []AssetDef, loaders: []AssetLoader) {
    assert(len(scenes) <= MAX_SCENES)
    system.scenes = scenes
    AssetStoreRebind(&system.assets, asset_defs, loaders)
}

// Start the scene that was running again, on what is loaded
SceneResume :: proc(system: ^SceneSystem) {
    if !system.has_current { return }
    id: SceneId = system.current
    if system.entered { return }
    SceneRequestAssets(system, id, true, false)
    if SceneIsReady(system, id) {
        SceneEnter(system, id, system.current_instance, false)
    } else {
        InstanceRemove(system, system.current_instance)
        SceneStart(system, id)
    }
}

// Finish the scene and unload everything
SceneShutdown :: proc(system: ^SceneSystem) {
    SceneRelease(system)
    AssetsReleaseAll(&system.assets)
    for i in 1 ..< int(system.instances.used_len) {
        if system.instances.items[i].handle.idx != 0 {
            hm.remove(&system.instances, system.instances.items[i].handle)
        }
    }
    system.current_instance = {}
    system.target_instance = {}
    system.has_current = false
    system.transition = {}
}

SceneStats :: struct {
    arena_used: int,
    arena_peak: int,
    arena_capacity: int,
    assets_ready: int,
    assets_queued: int,
    loaded_total: int,
    failed_total: int,
    smoothed_dt: f32,
    instances_started: u32,
}

SceneGetStats :: proc(system: ^SceneSystem) -> (stats: SceneStats) {
    for state in system.assets.states {
        if state == .READY { stats.assets_ready += 1 }
    }
    stats.assets_queued = system.assets.queue_count
    stats.loaded_total = system.loader.loaded_total
    stats.failed_total = system.loader.failed_total
    stats.smoothed_dt = system.loader.smoothed_dt
    stats.instances_started = system.instances_started
    if system.has_arena {
        stats.arena_used = system.arena.offset
        stats.arena_peak = system.arena.peak_used
        stats.arena_capacity = len(system.arena.data)
    }
    return
}
