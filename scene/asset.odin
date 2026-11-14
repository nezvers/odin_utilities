package scene

// Assets that are loaded in the background while the game runs.
//
// Two kinds of requests share one queue:
//   background - prefetch for something that is likely to be needed (the next scene, an optional asset). Loads a little each frame.
//   blocking   - something that has to be ready before a scene can start. Served first, with a bigger budget, the scene system
//                covers the wait with a transition.
// A request for an asset that is already queued as background and is now needed makes it blocking (the guess was wrong or late).
//
// Whatever is not READY yet gives the placeholder of its definition, a null id gives a null value. Callers never have to check,
// and never wait: they draw the placeholder and the real value shows up when it is loaded.
//
// Threads: a loader can be split in two. `decode` is the CPU work (unpacking an image, parsing a file), it only touches the bytes it
// is given and the memory it is given, so it can run on a worker thread. `finish` makes the value from the decoded data (creates the
// GPU texture, the audio buffer) and always runs on the main thread, because frameworks are not thread safe. When the platform has
// threads (not the web) and memory for them is provided, decoding runs on a few worker threads next to the game and the main
// thread only does the cheap finish step. Without threads, or for a loader that only has `load`, the same loader runs on the main
// thread, a few items per frame, with the same results.
//
// Memory: the definitions are a constant table, the state lives in a user provided AssetStorage, each worker decodes into its own
// arena (a part of the memory the user provided) that is reset after every item, a scratch arena does the same for the main thread.
// Threads are created once at init, never while loading. Nothing allocates per frame.

import "base:runtime"
import "core:mem"
import "core:time"

// Index into the table of asset definitions. 0 is the null asset: the first definition is a dummy that is never loaded.
AssetId :: distinct u16
ASSET_NONE :: AssetId(0)

// Selects the loader of an asset, the meaning is up to the user (texture, sound, font ...)
AssetKind :: distinct u8

// What a loader produced. A texture handle, an audio clip, a font: anything that fits in two words
AssetValue :: struct {
    handle: u64,
    extra: u64,
}

AssetState :: enum u8 {
    UNLOADED,
    QUEUED,
    LOADING,    // decoding on a worker thread
    READY,
    FAILED,     // the loader said no. Counts as settled so nothing waits for it forever, reads give the placeholder
}

// One row of the asset table, data only
AssetDef :: struct {
    name: string,
    kind: AssetKind,
    source: []byte,             // bytes of the asset, usually #load. Has to stay alive while the asset is loading or in use
    flags: u32,                 // loader options
    placeholder: AssetValue,    // given while the asset is not ready
    persistent: bool,           // survives scene changes
}

// A loader needs `load`, or `decode` and `finish`. With `decode` and `finish` the decode step can run on a worker thread.
AssetLoader :: struct {
    // Everything on the main thread. `scratch` is for decoding, it is cleared right after the call
    load: proc(def: ^AssetDef, scratch: runtime.Allocator) -> (value: AssetValue, ok: bool),
    // The CPU part. May run on a worker thread: no framework calls, no globals that change, allocate only from `memory`
    // (an arena that is reset after finish). Returns what finish needs, usually a pointer into `memory`
    decode: proc(def: ^AssetDef, memory: runtime.Allocator) -> (decoded: rawptr, ok: bool),
    // The main thread part: make the value from the decoded data
    finish: proc(def: ^AssetDef, decoded: rawptr) -> (value: AssetValue, ok: bool),
    unload: proc(def: ^AssetDef, value: AssetValue),
}

// The state of N assets in one block the user owns, for example inside the game memory
AssetStorage :: struct($N: int) {
    values: [N]AssetValue,
    states: [N]AssetState,
    blocking: [N]bool,
    wanted: [N]bool,
    queue: [N]AssetId,
}

AssetStoreConfig :: struct {
    scratch: []byte,            // decode memory of the main thread, reused for every item. Empty - the temp allocator
    decode_memory: []byte,      // split between the workers. Empty - no threads. Has to fit the biggest decoded asset per worker
    workers: int,               // 0 - as many as the platform suggests (cores - 1, at most 4), negative - none, else that many
    allocator: runtime.Allocator,   // for the thread objects, only at init and shutdown. Empty - context.allocator
}

AssetStore :: struct {
    defs: []AssetDef,
    loaders: []AssetLoader,         // indexed by AssetKind
    values: []AssetValue,
    states: []AssetState,
    blocking: []bool,
    wanted: []bool,
    queue: []AssetId,               // FIFO ring
    queue_head: int,
    queue_count: int,
    scratch: mem.Arena,
    has_scratch: bool,
    workers: Workers,               // see asset_workers.odin. The store must not move: the workers point at it
}

// The store must stay where it is after this: worker threads keep a pointer to it
AssetStoreInit :: proc(store: ^AssetStore, defs: []AssetDef, loaders: []AssetLoader, storage: ^AssetStorage($N), config: AssetStoreConfig = {}) {
    count: int = len(defs)
    assert(count > 0 && count <= N, "the storage has to be as big as the table")
    store^ = {
        defs = defs,
        loaders = loaders,
        values = storage.values[:count],
        states = storage.states[:count],
        blocking = storage.blocking[:count],
        wanted = storage.wanted[:count],
        queue = storage.queue[:count],
    }
    if len(config.scratch) > 0 {
        mem.arena_init(&store.scratch, config.scratch)
        store.has_scratch = true
    }
    WorkersStart(store, config.workers, config.decode_memory, config.allocator)
}

// Stop the worker threads and wait for them. Loaded assets stay as they are, use AssetsReleaseAll to unload them
AssetStoreShutdown :: proc(store: ^AssetStore) {
    WorkersStop(store)
}

// The code that was reloaded has new tables, the state stays. Waits for the decodes that are running: they read the tables
AssetStoreRebind :: proc(store: ^AssetStore, defs: []AssetDef, loaders: []AssetLoader) {
    assert(len(defs) == len(store.states))
    WorkersWaitIdle(store)
    store.defs = defs
    store.loaders = loaders
}

AssetIsValid :: proc(store: ^AssetStore, id: AssetId) -> bool {
    return id != ASSET_NONE && int(id) < len(store.defs)
}

AssetGetState :: proc(store: ^AssetStore, id: AssetId) -> AssetState {
    if !AssetIsValid(store, id) { return .UNLOADED }
    return store.states[id]
}

AssetIsReady :: proc(store: ^AssetStore, id: AssetId) -> bool {
    return AssetGetState(store, id) == .READY
}

// Nothing more will happen to the asset until somebody asks again: ready, or failed. The null asset is always settled
AssetIsSettled :: proc(store: ^AssetStore, id: AssetId) -> bool {
    if id == ASSET_NONE { return true }
    state: AssetState = AssetGetState(store, id)
    return state == .READY || state == .FAILED
}

// The loaded value, or the placeholder while it is not ready, or a null value for the null asset
AssetGet :: proc(store: ^AssetStore, id: AssetId) -> AssetValue {
    if !AssetIsValid(store, id) { return {} }
    if store.states[id] == .READY {
        return store.values[id]
    }
    return store.defs[id].placeholder
}

@(private)
QueueFind :: proc(store: ^AssetStore, id: AssetId) -> int {
    for i in 0 ..< store.queue_count {
        if store.queue[(store.queue_head + i) % len(store.queue)] == id {
            return i
        }
    }
    return -1
}

// Take an item out of the middle of the queue, keeps the order of the others
@(private)
QueueRemoveAt :: proc(store: ^AssetStore, index: int) {
    capacity: int = len(store.queue)
    for i in index ..< store.queue_count - 1 {
        store.queue[(store.queue_head + i) % capacity] = store.queue[(store.queue_head + i + 1) % capacity]
    }
    store.queue_count -= 1
}

// Ask for an asset. Returns true when it is ready or on its way. Asking again is free; asking for blocking what was queued as
// background (or is being decoded) makes it blocking. A failed asset is tried again.
AssetRequest :: proc(store: ^AssetStore, id: AssetId, blocking: bool) -> bool {
    if !AssetIsValid(store, id) { return false }
    switch store.states[id] {
    case .READY:
        return true
    case .QUEUED, .LOADING:
        store.blocking[id] ||= blocking
        return true
    case .UNLOADED, .FAILED:
        if store.queue_count >= len(store.queue) { return false }
        store.states[id] = .QUEUED
        store.blocking[id] = blocking
        store.queue[(store.queue_head + store.queue_count) % len(store.queue)] = id
        store.queue_count += 1
        return true
    }
    return false
}

// --- Unloading: mark what is still needed, then release the rest ---

AssetsClearWanted :: proc(store: ^AssetStore) {
    for &wanted in store.wanted { wanted = false }
}

AssetWant :: proc(store: ^AssetStore, id: AssetId) {
    if AssetIsValid(store, id) {
        store.wanted[id] = true
    }
}

@(private)
AssetUnload :: proc(store: ^AssetStore, id: AssetId) {
    def: ^AssetDef = &store.defs[id]
    if store.states[id] == .READY && int(def.kind) < len(store.loaders) && store.loaders[def.kind].unload != nil {
        store.loaders[def.kind].unload(def, store.values[id])
    }
    store.states[id] = .UNLOADED
    store.values[id] = {}
    store.blocking[id] = false
}

// Unload everything that is not persistent and was not marked wanted. Drops queued requests of unwanted assets too.
// An asset that is being decoded right now is left alone, it is released by the next call if it is still unwanted.
AssetsReleaseUnwanted :: proc(store: ^AssetStore) -> (released: int) {
    for i in 1 ..< len(store.defs) {
        id: AssetId = AssetId(i)
        if store.wanted[id] || store.defs[id].persistent { continue }
        switch store.states[id] {
        case .READY:
            AssetUnload(store, id)
            released += 1
        case .QUEUED:
            QueueRemoveAt(store, QueueFind(store, id))
            store.states[id] = .UNLOADED
            store.blocking[id] = false
        case .FAILED:
            store.states[id] = .UNLOADED
        case .UNLOADED, .LOADING:
        }
    }
    return
}

// Unload everything, persistent too. Waits for the decodes that are running
AssetsReleaseAll :: proc(store: ^AssetStore) {
    WorkersDiscardAll(store)
    for i in 1 ..< len(store.defs) {
        id: AssetId = AssetId(i)
        if store.states[id] == .READY {
            AssetUnload(store, id)
        }
        store.states[id] = .UNLOADED
        store.blocking[id] = false
    }
    store.queue_head = 0
    store.queue_count = 0
}

// --- The loader: a few items per frame ---

LoaderConfig :: struct {
    target_frame_seconds: f32,          // default 1/60
    slack: f32,                         // the frame time may be this much over the target and still count as good. Default 0.15
    background_budget_seconds: f32,     // main thread time for background items in a good frame. Default 2 ms
    blocking_budget_seconds: f32,       // main thread time for blocking items, a transition hides it. Default 12 ms
    max_per_frame: int,                 // Default 8
    smoothing: f32,                     // weight of the newest frame in the smoothed frame time. Default 0.1
    clock: proc() -> f64,               // seconds, nil - the system clock. Tests give a fake one
}

LoaderConfigDefault :: proc() -> LoaderConfig {
    return {
        target_frame_seconds = 1.0 / 60,
        slack = 0.15,
        background_budget_seconds = 0.002,
        blocking_budget_seconds = 0.012,
        max_per_frame = 8,
        smoothing = 0.1,
    }
}

Loader :: struct {
    config: LoaderConfig,
    smoothed_dt: f32,
    loaded_last_frame: int,
    loaded_total: int,
    failed_total: int,
    decoded_on_workers: int,            // items whose decode step ran on a worker thread
}

LoaderInit :: proc(loader: ^Loader, config: LoaderConfig) {
    loader^ = {config = config}
    defaults: LoaderConfig = LoaderConfigDefault()
    if loader.config.target_frame_seconds <= 0 { loader.config.target_frame_seconds = defaults.target_frame_seconds }
    if loader.config.slack <= 0 { loader.config.slack = defaults.slack }
    if loader.config.background_budget_seconds <= 0 { loader.config.background_budget_seconds = defaults.background_budget_seconds }
    if loader.config.blocking_budget_seconds <= 0 { loader.config.blocking_budget_seconds = defaults.blocking_budget_seconds }
    if loader.config.max_per_frame <= 0 { loader.config.max_per_frame = defaults.max_per_frame }
    if loader.config.smoothing <= 0 { loader.config.smoothing = defaults.smoothing }
}

@(private)
LoaderNow :: proc(loader: ^Loader) -> f64 {
    if loader.config.clock != nil {
        return loader.config.clock()
    }
    return time.duration_seconds(time.since(time.Time{}))
}

// The next item to load: the oldest blocking one, else the oldest. Returns the position in the queue
@(private)
QueueNext :: proc(store: ^AssetStore) -> int {
    capacity: int = len(store.queue)
    for i in 0 ..< store.queue_count {
        if store.blocking[store.queue[(store.queue_head + i) % capacity]] {
            return i
        }
    }
    return 0
}

// A blocking item is waiting in the queue
AssetsHaveBlocking :: proc(store: ^AssetStore) -> bool {
    capacity: int = len(store.queue)
    for i in 0 ..< store.queue_count {
        if store.blocking[store.queue[(store.queue_head + i) % capacity]] {
            return true
        }
    }
    return false
}

// A blocking item is waiting or being decoded
@(private)
BlockingWork :: proc(store: ^AssetStore) -> bool {
    if AssetsHaveBlocking(store) { return true }
    for i in 1 ..< len(store.states) {
        if store.states[i] == .LOADING && store.blocking[i] { return true }
    }
    return false
}

// Whether the loader of the asset can decode on a worker thread
@(private)
Threadable :: proc(store: ^AssetStore, id: AssetId) -> bool {
    kind: int = int(store.defs[id].kind)
    return kind < len(store.loaders) && store.loaders[kind].decode != nil && store.loaders[kind].finish != nil
}

// Make the value of one asset on the calling thread
@(private)
LoadInline :: proc(store: ^AssetStore, id: AssetId) -> (value: AssetValue, ok: bool) {
    def: ^AssetDef = &store.defs[id]
    if int(def.kind) >= len(store.loaders) { return }
    loader: ^AssetLoader = &store.loaders[def.kind]
    scratch: runtime.Allocator = mem.arena_allocator(&store.scratch) if store.has_scratch else context.temp_allocator
    if loader.load != nil {
        value, ok = loader.load(def, scratch)
    } else if loader.decode != nil && loader.finish != nil {
        decoded: rawptr
        decoded, ok = loader.decode(def, scratch)
        if ok { value, ok = loader.finish(def, decoded) }
    }
    if store.has_scratch {
        free_all(scratch)
    }
    return
}

@(private)
LoaderSettle :: proc(loader: ^Loader, store: ^AssetStore, id: AssetId, value: AssetValue, ok: bool, ready: []AssetId, count: ^int) {
    store.blocking[id] = false
    if ok {
        store.states[id] = .READY
        store.values[id] = value
        ready[count^] = id
        count^ += 1
        loader.loaded_total += 1
    } else {
        store.states[id] = .FAILED
        loader.failed_total += 1
    }
    loader.loaded_last_frame += 1
}

// Load some of the queue. Call once per frame with the frame time.
// How much is loaded depends on how the game runs:
//   - blocking items are waiting: many, up to the blocking budget. The transition covers the cost
//   - the frames are good (smoothed frame time near the target): many background items, up to the background budget
//   - the frames are slow: one background item per frame, so loading never stops and never makes it worse
// With worker threads the decode of items runs next to the game: a good frame or blocking work keeps every worker busy, a slow frame
// one. The budget is for the main thread (finish steps and loaders without decode): that is what can make a frame slower.
// Ids of what became ready go into `ready`, the number is returned. Loading stops when `ready` is full.
LoaderUpdate :: proc(loader: ^Loader, store: ^AssetStore, dt: f32, ready: []AssetId) -> (count: int) {
    loader.smoothed_dt = dt if loader.smoothed_dt == 0 else loader.smoothed_dt + (dt - loader.smoothed_dt) * loader.config.smoothing
    loader.loaded_last_frame = 0
    if len(ready) == 0 { return }

    workers: int = WorkersCount(store)
    blocking: bool = BlockingWork(store)
    good: bool = loader.smoothed_dt <= loader.config.target_frame_seconds * (1 + loader.config.slack)
    max_items: int = loader.config.max_per_frame if blocking || good else 1
    budget: f64 = f64(loader.config.blocking_budget_seconds if blocking else loader.config.background_budget_seconds)
    frame_start: f64 = LoaderNow(loader)
    main_thread_items: int

    // 1. what the workers have decoded: finish it here
    for slot in 0 ..< workers {
        if count >= len(ready) { break }
        id, decoded, decode_ok, done := WorkersTake(store, slot)
        if !done { continue }
        value: AssetValue
        ok: bool = decode_ok
        if ok {
            def: ^AssetDef = &store.defs[id]
            value, ok = store.loaders[def.kind].finish(def, decoded)
        }
        WorkersRelease(store, slot)
        loader.decoded_on_workers += 1
        LoaderSettle(loader, store, id, value, ok, ready, &count)
        main_thread_items += 1
        if main_thread_items >= max_items || LoaderNow(loader) - frame_start >= budget { break }
    }

    // 2. start new work
    in_flight_limit: int = workers if blocking || good else 1
    for store.queue_count > 0 && count < len(ready) {
        index: int = QueueNext(store)
        id: AssetId = store.queue[(store.queue_head + index) % len(store.queue)]

        if workers > 0 && Threadable(store, id) {
            if WorkersBusy(store) >= in_flight_limit { break }
            QueueRemoveAt(store, index)
            store.states[id] = .LOADING
            if !WorkersSubmit(store, id) {
                store.states[id] = .QUEUED      // no free worker after all, it keeps its place at the back
                store.queue[(store.queue_head + store.queue_count) % len(store.queue)] = id
                store.queue_count += 1
                break
            }
            continue
        }

        // a loader without a decode step, or no workers: on this thread, within the budget
        if main_thread_items > 0 && (main_thread_items >= max_items || LoaderNow(loader) - frame_start >= budget) { break }
        QueueRemoveAt(store, index)
        value, ok := LoadInline(store, id)
        LoaderSettle(loader, store, id, value, ok, ready, &count)
        main_thread_items += 1
        if main_thread_items >= max_items || LoaderNow(loader) - frame_start >= budget { break }
        if blocking && !AssetsHaveBlocking(store) && workers == 0 { break }
    }
    return
}
