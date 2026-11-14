#+build js
package scene

// A browser build has no threads here: everything loads on the main thread, a few items per frame (see asset_workers.odin)

import "base:runtime"

Workers :: struct {}

LoaderThreadsAvailable :: proc() -> bool {
    return false
}

@(private)
WorkersStart :: proc(store: ^AssetStore, requested: int, memory: []byte, allocator: runtime.Allocator) {}

@(private)
WorkersStop :: proc(store: ^AssetStore) {}

@(private)
WorkersCount :: proc(store: ^AssetStore) -> int {
    return 0
}

@(private)
WorkersBusy :: proc(store: ^AssetStore) -> int {
    return 0
}

@(private)
WorkersSubmit :: proc(store: ^AssetStore, id: AssetId) -> bool {
    return false
}

@(private)
WorkersTake :: proc(store: ^AssetStore, slot: int) -> (id: AssetId, decoded: rawptr, ok: bool, done: bool) {
    return
}

@(private)
WorkersRelease :: proc(store: ^AssetStore, slot: int) {}

@(private)
WorkersWaitIdle :: proc(store: ^AssetStore) {}

@(private)
WorkersDiscardAll :: proc(store: ^AssetStore) {}
