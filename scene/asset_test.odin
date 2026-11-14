#+build !js
// Tests of asset.odin. They are in their own file because the scene system is imported by games with a web build, and core:testing does not compile for js_wasm32.
package scene

import "core:testing"
import "base:runtime"

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
    AssetStoreInit(&assets.store, assets.defs[:], assets.loaders[:], &assets.storage, assets.scratch[:])
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
