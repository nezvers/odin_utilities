#+build !js
// Tests of asset.odin. They are in their own file because the scene system is imported by games with a web build, and core:testing does not compile for js_wasm32.
package scene

import "core:testing"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"
import "../wait_for"

@(private="file", thread_local)
fake_time: f64
@(private="file", thread_local)
load_log: [32]AssetId
@(private="file", thread_local)
load_log_count: int
@(private="file", thread_local)
unload_count: int

@(private="file")
fake_clock :: proc() -> f64 {
    return fake_time
}

// Every load takes 2 ms of the fake clock and is logged, an asset named "bad" fails
@(private="file")
fake_load :: proc(def: ^AssetDef, scratch: runtime.Allocator) -> (AssetValue, bool) {
    fake_time += 0.002
    if def.name == "bad" { return {}, false }
    // the scratch memory is usable
    bytes, error := make([]u8, 16, scratch)
    if error != nil { return {}, false }
    bytes[0] = 1
    return {handle = u64(def.flags) + 100}, true
}

@(private="file")
fake_unload :: proc(def: ^AssetDef, value: AssetValue) {
    unload_count += 1
}

@(private="file")
TestAssets :: struct {
    defs: [8]AssetDef,
    loaders: [1]AssetLoader,
    storage: AssetStorage(8),
    scratch: [256]u8,
    store: AssetStore,
    loader: Loader,
}

@(private="file")
test_assets_init :: proc(assets: ^TestAssets) {
    fake_time = 0
    load_log_count = 0
    unload_count = 0
    names: [8]string = {"none", "a", "b", "c", "d", "bad", "persist", "e"}
    for name, i in names {
        assets.defs[i] = {name = name, flags = u32(i), placeholder = {handle = 7}}
    }
    assets.defs[6].persistent = true
    assets.loaders[0] = {load = fake_load, unload = fake_unload}
    AssetStoreInit(&assets.store, assets.defs[:], assets.loaders[:], &assets.storage, {scratch = assets.scratch[:]})
    config: LoaderConfig = {clock = fake_clock}
    LoaderInit(&assets.loader, config)
}

@(test)
test_placeholder_until_ready_and_null_handle :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    ready: [8]AssetId

    testing.expect_value(t, AssetGet(&assets.store, 1).handle, u64(7))               // placeholder before anything happened
    testing.expect_value(t, AssetGet(&assets.store, ASSET_NONE), AssetValue{})         // the null asset: null value
    testing.expect_value(t, AssetGet(&assets.store, 99), AssetValue{})                 // so is an id outside of the table
    testing.expect(t, !AssetRequest(&assets.store, ASSET_NONE, true))
    testing.expect(t, AssetIsSettled(&assets.store, ASSET_NONE), "nothing to wait for")

    testing.expect(t, AssetRequest(&assets.store, 1, false))
    testing.expect_value(t, AssetGetState(&assets.store, 1), AssetState.QUEUED)
    testing.expect_value(t, AssetGet(&assets.store, 1).handle, u64(7))               // still the placeholder while queued

    count: int = LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect_value(t, count, 1)
    testing.expect_value(t, ready[0], AssetId(1))
    testing.expect_value(t, AssetGet(&assets.store, 1).handle, u64(101))             // the real value now
    testing.expect(t, AssetIsReady(&assets.store, 1))
}

@(test)
test_failed_asset_settles_and_keeps_the_placeholder :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    ready: [8]AssetId
    AssetRequest(&assets.store, 5, true)
    count: int = LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect_value(t, count, 0)                                                // nothing became ready
    testing.expect_value(t, AssetGetState(&assets.store, 5), AssetState.FAILED)
    testing.expect(t, AssetIsSettled(&assets.store, 5), "a scene does not wait for it forever")
    testing.expect(t, !AssetIsReady(&assets.store, 5))
    testing.expect_value(t, AssetGet(&assets.store, 5).handle, u64(7))
    testing.expect_value(t, assets.loader.failed_total, 1)
    testing.expect(t, AssetRequest(&assets.store, 5, false), "asking again tries again")
    testing.expect_value(t, AssetGetState(&assets.store, 5), AssetState.QUEUED)
}

@(test)
test_requests_do_not_duplicate_and_blocking_goes_first :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    ready: [8]AssetId
    assets.loader.config.max_per_frame = 1                                           // one item per pass to see the order

    AssetRequest(&assets.store, 1, false)
    AssetRequest(&assets.store, 2, false)
    AssetRequest(&assets.store, 3, false)
    AssetRequest(&assets.store, 1, false)                                            // asked twice
    testing.expect_value(t, assets.store.queue_count, 3)

    AssetRequest(&assets.store, 3, true)                                             // a guess that turned out too late: now it is needed
    testing.expect(t, AssetsHaveBlocking(&assets.store))
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect(t, AssetIsReady(&assets.store, 3), "the promoted one jumps the queue")
    testing.expect(t, !AssetIsReady(&assets.store, 1))

    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect(t, AssetIsReady(&assets.store, 1), "the others keep their order")
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect(t, AssetIsReady(&assets.store, 2))
    testing.expect_value(t, assets.store.queue_count, 0)
}

@(test)
test_load_amount_follows_performance :: proc(t: ^testing.T) {
    ready: [8]AssetId

    // good frames: as many as the 5 ms background budget allows, each item costs 2 ms: 3 items
    good: TestAssets
    test_assets_init(&good)
    good.loader.config.background_budget_seconds = 0.005
    for id in 1 ..= 4 { AssetRequest(&good.store, AssetId(id), false) }
    count: int = LoaderUpdate(&good.loader, &good.store, 1.0 / 60, ready[:])
    testing.expect_value(t, count, 3)

    // slow frames: one per frame, however much budget there is
    slow: TestAssets
    test_assets_init(&slow)
    slow.loader.config.background_budget_seconds = 1
    for id in 1 ..= 4 { AssetRequest(&slow.store, AssetId(id), false) }
    count = LoaderUpdate(&slow.loader, &slow.store, 1.0 / 20, ready[:])
    testing.expect_value(t, count, 1)
    count = LoaderUpdate(&slow.loader, &slow.store, 1.0 / 20, ready[:])
    testing.expect_value(t, count, 1)                                                // still slow, still one: loading goes on

    // a blocking item is hidden by the transition, so even slow frames load many (up to the blocking budget of 12 ms: 6 items,
    // only 4 are queued)
    blocking: TestAssets
    test_assets_init(&blocking)
    for id in 1 ..= 4 { AssetRequest(&blocking.store, AssetId(id), true) }
    count = LoaderUpdate(&blocking.loader, &blocking.store, 1.0 / 20, ready[:])
    testing.expect_value(t, count, 4)

    // when the frames recover the amount goes back up
    recovering: TestAssets
    test_assets_init(&recovering)
    recovering.loader.config.background_budget_seconds = 1
    for id in 1 ..= 4 { AssetRequest(&recovering.store, AssetId(id), false) }
    recovering.loader.smoothed_dt = 1.0 / 20
    for _ in 0 ..< 60 { recovering.loader.smoothed_dt += (1.0 / 60 - recovering.loader.smoothed_dt) * 0.1 }
    count = LoaderUpdate(&recovering.loader, &recovering.store, 1.0 / 60, ready[:])
    testing.expect_value(t, count, 4)
}

@(test)
test_loader_stops_when_the_ready_list_is_full :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    for id in 1 ..= 4 { AssetRequest(&assets.store, AssetId(id), true) }
    small: [2]AssetId
    count: int = LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, small[:])
    testing.expect_value(t, count, 2)
    testing.expect_value(t, assets.store.queue_count, 2)                             // the rest waits for the next call
}

@(test)
test_release_unwanted_keeps_wanted_and_persistent :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    ready: [8]AssetId
    for id in ([]AssetId{1, 2, 3, 6}) { AssetRequest(&assets.store, id, true) }
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    AssetRequest(&assets.store, 4, false)                                            // still queued
    AssetRequest(&assets.store, 7, false)

    AssetsClearWanted(&assets.store)
    AssetWant(&assets.store, 2)
    AssetWant(&assets.store, 7)
    released: int = AssetsReleaseUnwanted(&assets.store)

    testing.expect_value(t, released, 2)                                             // 1 and 3, the persistent 6 stays
    testing.expect_value(t, unload_count, 2)
    testing.expect(t, AssetIsReady(&assets.store, 2) && AssetIsReady(&assets.store, 6))
    testing.expect_value(t, AssetGetState(&assets.store, 1), AssetState.UNLOADED)
    testing.expect_value(t, AssetGet(&assets.store, 1).handle, u64(7))               // back to the placeholder
    testing.expect_value(t, AssetGetState(&assets.store, 4), AssetState.UNLOADED)    // a queued request nobody wants is dropped
    testing.expect_value(t, AssetGetState(&assets.store, 7), AssetState.QUEUED)
    testing.expect_value(t, assets.store.queue_count, 1)

    AssetsReleaseAll(&assets.store)
    testing.expect(t, !AssetIsReady(&assets.store, 6), "release all takes the persistent ones too")
    testing.expect_value(t, assets.store.queue_count, 0)
}

@(test)
test_queue_wraps_around :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    ready: [8]AssetId
    // fill and drain more often than the capacity so the ring wraps
    for round in 0 ..< 5 {
        for id in 1 ..= 5 { AssetRequest(&assets.store, AssetId(id), false) }
        for assets.store.queue_count > 0 { LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:]) }
        for id in 1 ..= 5 {
            testing.expectf(t, AssetIsSettled(&assets.store, AssetId(id)), "round %d id %d", round, id)
        }
        AssetsReleaseAll(&assets.store)
        assets.store.queue_head = (assets.store.queue_head + 3) % 7
    }
}

// --- Worker threads ---
// Real threads. Each asset has a record that its decode and finish write to, so tests do not share state.

@(private="file")
FakeRecord :: struct {
    delay_ms: int,          // how long the decode takes
    bytes: int,             // what the decode allocates from its memory
    decode_thread: int,
    finish_thread: int,
    decode_calls: int,
}

@(private="file")
fake_decode :: proc(def: ^AssetDef, memory: runtime.Allocator) -> (rawptr, bool) {
    record: ^FakeRecord = cast(^FakeRecord)raw_data(def.source)
    record.decode_thread = sync.current_thread_id()
    record.decode_calls += 1
    if record.delay_ms > 0 { time.sleep(time.Duration(record.delay_ms) * time.Millisecond) }
    block, error := make([]u8, max(record.bytes, 1), memory)
    if error != nil { return nil, false }
    block[0] = 42
    return raw_data(block), true
}

@(private="file")
fake_finish :: proc(def: ^AssetDef, decoded: rawptr) -> (AssetValue, bool) {
    record: ^FakeRecord = cast(^FakeRecord)raw_data(def.source)
    record.finish_thread = sync.current_thread_id()
    if (cast(^u8)decoded)^ != 42 { return {}, false }       // the decoded memory must still be intact here
    return {handle = 500 + u64(def.flags)}, true
}

@(private="file")
inline_load :: proc(def: ^AssetDef, scratch: runtime.Allocator) -> (AssetValue, bool) {
    return {handle = 900 + u64(def.flags)}, true
}

@(private="file")
ThreadedAssets :: struct {
    defs: [8]AssetDef,
    loaders: [2]AssetLoader,    // kind 0: decode and finish, kind 1: load only
    storage: AssetStorage(8),
    scratch: [4096]u8,
    decode_memory: [64 * 1024]u8,
    records: [8]FakeRecord,
    store: AssetStore,
    loader: Loader,
}

@(private="file")
threaded_init :: proc(assets_pointer: rawptr, workers: int, decode_memory: int = 64 * 1024) {
    assets: ^ThreadedAssets = cast(^ThreadedAssets)assets_pointer
    for i in 1 ..< 8 {
        assets.defs[i] = {name = "item", flags = u32(i), source = mem.byte_slice(&assets.records[i], size_of(FakeRecord)), placeholder = {handle = 7}}
    }
    assets.loaders[0] = {decode = fake_decode, finish = fake_finish}
    assets.loaders[1] = {load = inline_load}
    AssetStoreInit(&assets.store, assets.defs[:], assets.loaders[:], &assets.storage, {
        scratch = assets.scratch[:],
        decode_memory = assets.decode_memory[:decode_memory],
        workers = workers,
    })
    LoaderInit(&assets.loader, {})
}

// Call the loader like frames do until everything requested is settled, a thread may need a few frames
@(private="file")
pump :: proc(assets: ^ThreadedAssets, ids: []AssetId, dt: f32 = 1.0 / 60) -> (settled: bool) {
    ready: [8]AssetId
    for deadline := wait_for.DeadlineStart(10); !wait_for.DeadlineExpired(&deadline); {
        LoaderUpdate(&assets.loader, &assets.store, dt, ready[:])
        all: bool = true
        for id in ids { all &&= AssetIsSettled(&assets.store, id) }
        if all { return true }
        time.sleep(time.Millisecond)
    }
    return false
}

@(test)
test_decode_runs_on_a_worker_and_finish_on_the_calling_thread :: proc(t: ^testing.T) {
    assets: ThreadedAssets
    threaded_init(rawptr(&assets), 2)
    testing.expect_value(t, WorkersCount(&assets.store), 2)
    defer AssetStoreShutdown(&assets.store)
    for i in 1 ..= 3 { assets.records[i].delay_ms = 40 }
    for i in 1 ..= 3 { AssetRequest(&assets.store, AssetId(i), true) }

    ready: [8]AssetId
    start: time.Tick = time.tick_now()
    count: int = LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    waited: time.Duration = time.tick_since(start)
    testing.expect_value(t, count, 0)                                                // nothing is ready yet and the call did not wait for it
    testing.expect(t, waited < 30 * time.Millisecond, "the frame is not held up by the decodes")
    testing.expect_value(t, AssetGetState(&assets.store, 1), AssetState.LOADING)
    testing.expect_value(t, AssetGetState(&assets.store, 3), AssetState.QUEUED)     // two workers, the third waits for one
    testing.expect_value(t, AssetGet(&assets.store, 1).handle, u64(7))               // still the placeholder

    testing.expect(t, pump(&assets, {1, 2, 3}))
    main_thread: int = sync.current_thread_id()
    for i in 1 ..= 3 {
        testing.expect(t, AssetIsReady(&assets.store, AssetId(i)))
        testing.expect_value(t, AssetGet(&assets.store, AssetId(i)).handle, u64(500 + i))
        testing.expect(t, assets.records[i].decode_thread != main_thread, "decoded on a worker")
        testing.expect_value(t, assets.records[i].finish_thread, main_thread)        // the framework part stays on the main thread
    }
    testing.expect_value(t, assets.loader.decoded_on_workers, 3)
}

@(test)
test_in_flight_work_follows_performance :: proc(t: ^testing.T) {
    ready: [8]AssetId

    good: ThreadedAssets
    threaded_init(rawptr(&good), 2)
    defer AssetStoreShutdown(&good.store)
    for i in 1 ..= 4 { good.records[i].delay_ms = 50 }
    for i in 1 ..= 4 { AssetRequest(&good.store, AssetId(i), false) }                // background
    LoaderUpdate(&good.loader, &good.store, 1.0 / 60, ready[:])
    testing.expect_value(t, WorkersBusy(&good.store), 2)                             // good frames: every worker works

    slow: ThreadedAssets
    threaded_init(rawptr(&slow), 2)
    defer AssetStoreShutdown(&slow.store)
    for i in 1 ..= 4 { slow.records[i].delay_ms = 50 }
    for i in 1 ..= 4 { AssetRequest(&slow.store, AssetId(i), false) }
    LoaderUpdate(&slow.loader, &slow.store, 1.0 / 15, ready[:])
    testing.expect_value(t, WorkersBusy(&slow.store), 1)                             // slow frames: one at a time, the game comes first

    blocking: ThreadedAssets
    threaded_init(rawptr(&blocking), 2)
    defer AssetStoreShutdown(&blocking.store)
    for i in 1 ..= 4 { blocking.records[i].delay_ms = 50 }
    for i in 1 ..= 4 { AssetRequest(&blocking.store, AssetId(i), true) }
    LoaderUpdate(&blocking.loader, &blocking.store, 1.0 / 15, ready[:])
    testing.expect_value(t, WorkersBusy(&blocking.store), 2)                         // blocking work uses every worker even when slow

    testing.expect(t, pump(&slow, {1, 2, 3, 4}, 1.0 / 15), "slow frames still finish everything, one at a time")
}

@(test)
test_workers_reuse_their_memory_and_a_too_small_arena_fails_cleanly :: proc(t: ^testing.T) {
    assets: ThreadedAssets
    threaded_init(rawptr(&assets), 1, 8192)                                          // one worker with 8 KB
    defer AssetStoreShutdown(&assets.store)
    for i in 1 ..= 5 { assets.records[i].bytes = 6000 }
    assets.records[6].bytes = 100_000                                                // more than the whole arena
    assets.records[7].bytes = 6000

    // each item takes 6000 of 8192 bytes: only works when the arena is reset after every item
    for i in 1 ..= 5 { AssetRequest(&assets.store, AssetId(i), true) }
    testing.expect(t, pump(&assets, {1, 2, 3, 4, 5}))
    for i in 1 ..= 5 { testing.expectf(t, AssetIsReady(&assets.store, AssetId(i)), "item %d", i) }

    AssetRequest(&assets.store, 6, true)
    testing.expect(t, pump(&assets, {6}))
    testing.expect_value(t, AssetGetState(&assets.store, 6), AssetState.FAILED)      // no crash, a failed asset
    AssetRequest(&assets.store, 7, true)
    testing.expect(t, pump(&assets, {7}))
    testing.expect(t, AssetIsReady(&assets.store, 7), "the worker is usable after a failure")
}

@(test)
test_without_workers_the_same_loader_runs_on_the_main_thread :: proc(t: ^testing.T) {
    assets: ThreadedAssets
    threaded_init(rawptr(&assets), -1)                                               // threads switched off
    defer AssetStoreShutdown(&assets.store)
    testing.expect_value(t, WorkersCount(&assets.store), 0)
    AssetRequest(&assets.store, 1, true)
    AssetRequest(&assets.store, 2, true)

    ready: [8]AssetId
    count: int = LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect_value(t, count, 2)                                                // done in this call, like before
    main_thread: int = sync.current_thread_id()
    testing.expect_value(t, assets.records[1].decode_thread, main_thread)
    testing.expect_value(t, assets.records[1].finish_thread, main_thread)
    testing.expect_value(t, AssetGet(&assets.store, 1).handle, u64(501))             // the same value the threaded path makes
    testing.expect_value(t, assets.loader.decoded_on_workers, 0)

    // no memory for workers: no workers
    nowhere: ThreadedAssets
    threaded_init(rawptr(&nowhere), 2, 100)
    testing.expect_value(t, WorkersCount(&nowhere.store), 0)
}

@(test)
test_loaders_without_decode_load_next_to_the_threads :: proc(t: ^testing.T) {
    assets: ThreadedAssets
    threaded_init(rawptr(&assets), 2)
    defer AssetStoreShutdown(&assets.store)
    assets.defs[2].kind = 1                                                          // a loader that only has `load`
    assets.records[1].delay_ms = 30
    AssetRequest(&assets.store, 1, true)
    AssetRequest(&assets.store, 2, true)

    ready: [8]AssetId
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect(t, AssetIsReady(&assets.store, 2), "the main thread loader is done at once")
    testing.expect_value(t, AssetGet(&assets.store, 2).handle, u64(902))
    testing.expect(t, !AssetIsReady(&assets.store, 1), "while the decode is still running")
    testing.expect(t, pump(&assets, {1}))
    testing.expect_value(t, assets.loader.decoded_on_workers, 1)
}

@(test)
test_release_all_waits_for_decodes_and_shutdown_stops_the_threads :: proc(t: ^testing.T) {
    assets: ThreadedAssets
    threaded_init(rawptr(&assets), 2)
    for i in 1 ..= 4 { assets.records[i].delay_ms = 40 }
    for i in 1 ..= 4 { AssetRequest(&assets.store, AssetId(i), true) }
    ready: [8]AssetId
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect_value(t, WorkersBusy(&assets.store), 2)

    AssetsReleaseAll(&assets.store)                                                  // waits for the running decodes, drops their results
    testing.expect_value(t, WorkersBusy(&assets.store), 0)
    for i in 1 ..= 4 { testing.expect_value(t, AssetGetState(&assets.store, AssetId(i)), AssetState.UNLOADED) }
    testing.expect_value(t, assets.store.queue_count, 0)

    AssetRequest(&assets.store, 1, true)                                             // still usable after that
    testing.expect(t, pump(&assets, {1}))
    testing.expect(t, AssetIsReady(&assets.store, 1))

    AssetStoreShutdown(&assets.store)
    testing.expect_value(t, WorkersCount(&assets.store), 0)
    AssetStoreShutdown(&assets.store)                                                // twice is harmless
}

@(test)
test_rebind_waits_for_the_decodes_that_read_the_tables :: proc(t: ^testing.T) {
    assets: ThreadedAssets
    threaded_init(rawptr(&assets), 1)
    defer AssetStoreShutdown(&assets.store)
    assets.records[1].delay_ms = 40
    AssetRequest(&assets.store, 1, true)
    ready: [8]AssetId
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])

    AssetStoreRebind(&assets.store, assets.defs[:], assets.loaders[:])               // a hot reload: waits for the decode, keeps its result
    testing.expect(t, pump(&assets, {1}))
    testing.expect(t, AssetIsReady(&assets.store, 1))
}

@(test)
test_automatic_worker_count_follows_the_platform :: proc(t: ^testing.T) {
    testing.expect_value(t, LoaderThreadsAvailable(), thread.IS_SUPPORTED)
    assets: ThreadedAssets
    threaded_init(rawptr(&assets), 0)                                                // automatic
    defer AssetStoreShutdown(&assets.store)
    expected: int = clamp(os.get_processor_core_count() - 1, 0, AUTO_WORKERS_MAX)
    testing.expect_value(t, WorkersCount(&assets.store), expected)
}

@(test)
test_cancel_drops_a_queued_request_and_a_priority_goes_first :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    ready: [8]AssetId
    assets.loader.config.max_per_frame = 1
    AssetRequestPriority(&assets.store, 1, false, 0)
    AssetRequestPriority(&assets.store, 2, false, 0)
    AssetRequestPriority(&assets.store, 3, false, 5)
    AssetCancel(&assets.store, 2)
    testing.expect_value(t, AssetGetState(&assets.store, 2), AssetState.UNLOADED)
    testing.expect_value(t, assets.store.queue_count, 2)
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect(t, AssetIsReady(&assets.store, 3), "the higher priority is loaded first")
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect(t, AssetIsReady(&assets.store, 1))
    testing.expect(t, !AssetIsReady(&assets.store, 2), "the cancelled one never loaded")
}

@(test)
test_reload_serves_the_old_value_until_the_new_one_is_ready :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    ready: [8]AssetId
    AssetRequest(&assets.store, 1, false)
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect_value(t, AssetGeneration(&assets.store, 1), u32(0))
    testing.expect(t, AssetReload(&assets.store, 1))
    testing.expect(t, AssetIsStale(&assets.store, 1))
    testing.expect_value(t, AssetGetState(&assets.store, 1), AssetState.READY)
    testing.expect_value(t, AssetGet(&assets.store, 1).handle, u64(101))
    unloaded: int = unload_count
    count: int = LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect_value(t, count, 1)
    testing.expect(t, !AssetIsStale(&assets.store, 1))
    testing.expect_value(t, AssetGeneration(&assets.store, 1), u32(1))
    testing.expect_value(t, unload_count, unloaded + 1)          // the old value was unloaded
    testing.expect(t, AssetIsReady(&assets.store, 1))
}

@(test)
test_cancelled_reload_and_failed_reload_keep_the_old_value :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    ready: [8]AssetId
    AssetRequest(&assets.store, 1, false)
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    AssetReload(&assets.store, 1)
    AssetCancel(&assets.store, 1)
    testing.expect(t, !AssetIsStale(&assets.store, 1))
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    testing.expect_value(t, AssetGeneration(&assets.store, 1), u32(0))
    testing.expect_value(t, AssetGet(&assets.store, 1).handle, u64(101))
}

@(test)
test_used_assets_are_not_released_and_idle_ones_are :: proc(t: ^testing.T) {
    assets: TestAssets
    test_assets_init(&assets)
    ready: [8]AssetId
    AssetRequest(&assets.store, 1, false)
    AssetRequest(&assets.store, 2, false)
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    LoaderUpdate(&assets.loader, &assets.store, 1.0 / 60, ready[:])
    store: ^AssetStore = &assets.store
    store.wanted[1] = false
    store.wanted[2] = false
    _ = AssetUse(store, 1)
    testing.expect_value(t, AssetsReleaseUnwanted(store), 1)
    testing.expect(t, AssetIsReady(store, 1), "used in this frame: kept")
    testing.expect(t, !AssetIsReady(store, 2))
    for _ in 0 ..< 5 { LoaderUpdate(&assets.loader, store, 1.0 / 60, ready[:]) }
    testing.expect_value(t, AssetsReleaseIdle(store, 4), 1)
    testing.expect(t, !AssetIsReady(store, 1), "idle for more than 4 frames")
}
