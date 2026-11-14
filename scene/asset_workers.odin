#+build !js
package scene

// Worker threads that run the decode step of loaders (see AssetLoader). One job slot per worker: the main thread hands a slot an
// asset id, the worker decodes into its own arena, the main thread takes the result and runs `finish`. No queue, no locks: a slot
// is owned by whoever its state says, the state is an atomic and a semaphore wakes the worker.
//
// The threads are created once in AssetStoreInit and joined in AssetStoreShutdown. The memory is the user's `decode_memory`, split
// between the workers. The platform decides: a target without threads (the web) gets no workers and everything stays on the main thread.

import "base:runtime"
import "core:mem"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"

MAX_WORKERS :: 8
AUTO_WORKERS_MAX :: 4           // enough to keep the loading fast, few enough to leave cores to the game
MIN_WORKER_MEMORY :: 4096

@(private)
JOB_IDLE :: u32(0)
@(private)
JOB_ASSIGNED :: u32(1)     // the worker is decoding or about to
@(private)
JOB_DONE :: u32(2)         // the result waits for the main thread

@(private)
WorkerJob :: struct {
    store: ^AssetStore,
    thread: ^thread.Thread,
    sema: sync.Sema,
    state: u32,             // atomic
    quit: u32,              // atomic
    id: AssetId,
    decoded: rawptr,
    ok: bool,
    memory: mem.Arena,
    thread_id: int,         // the thread that decoded, for tests and statistics
}

Workers :: struct {
    jobs: [MAX_WORKERS]WorkerJob,
    count: int,
    allocator: runtime.Allocator,
}

// The platform can run threads
LoaderThreadsAvailable :: proc() -> bool {
    return thread.IS_SUPPORTED
}

@(private)
worker_main :: proc(self: ^thread.Thread) {
    job: ^WorkerJob = cast(^WorkerJob)self.data
    for {
        sync.sema_wait(&job.sema)
        if sync.atomic_load(&job.quit) != 0 { break }

        store: ^AssetStore = job.store
        def: ^AssetDef = &store.defs[job.id]
        allocator: runtime.Allocator = mem.arena_allocator(&job.memory)
        // whatever the decoder allocates without being told to comes from the same arena
        context.allocator = allocator
        decoded, ok := store.loaders[def.kind].decode(def, allocator)
        free_all(context.temp_allocator)

        job.decoded = decoded
        job.ok = ok
        job.thread_id = sync.current_thread_id()
        sync.atomic_store(&job.state, JOB_DONE)
    }
}

// Start the worker threads. `requested`: 0 - as many as the platform suggests, negative - none. Without memory there are none.
@(private)
WorkersStart :: proc(store: ^AssetStore, requested: int, memory: []byte, allocator: runtime.Allocator) {
    if !thread.IS_SUPPORTED || requested < 0 || len(memory) < MIN_WORKER_MEMORY { return }

    count: int = requested
    if count == 0 {
        count = clamp(os.get_processor_core_count() - 1, 0, AUTO_WORKERS_MAX)
    }
    count = min(count, MAX_WORKERS, len(memory) / MIN_WORKER_MEMORY)
    if count == 0 { return }
    per_worker: int = len(memory) / count

    store.workers.allocator = allocator if allocator.procedure != nil else context.allocator
    context.allocator = store.workers.allocator
    for i in 0 ..< count {
        job: ^WorkerJob = &store.workers.jobs[i]
        job.store = store
        mem.arena_init(&job.memory, memory[i * per_worker:(i + 1) * per_worker])
        job.thread = thread.create(worker_main)
        if job.thread == nil { break }
        job.thread.data = job
        thread.start(job.thread)
        store.workers.count += 1
    }
}

// Ask the workers to leave and wait for them
@(private)
WorkersStop :: proc(store: ^AssetStore) {
    context.allocator = store.workers.allocator
    for i in 0 ..< store.workers.count {
        job: ^WorkerJob = &store.workers.jobs[i]
        sync.atomic_store(&job.quit, 1)
        sync.sema_post(&job.sema)
        thread.join(job.thread)
        thread.destroy(job.thread)
        job.thread = nil
    }
    store.workers.count = 0
}

@(private)
WorkersCount :: proc(store: ^AssetStore) -> int {
    return store.workers.count
}

// Slots that are decoding or hold a result that has not been taken yet
@(private)
WorkersBusy :: proc(store: ^AssetStore) -> (busy: int) {
    for i in 0 ..< store.workers.count {
        if sync.atomic_load(&store.workers.jobs[i].state) != JOB_IDLE { busy += 1 }
    }
    return
}

// Give an asset to a free worker. False when all are busy
@(private)
WorkersSubmit :: proc(store: ^AssetStore, id: AssetId) -> bool {
    for i in 0 ..< store.workers.count {
        job: ^WorkerJob = &store.workers.jobs[i]
        if sync.atomic_load(&job.state) != JOB_IDLE { continue }
        job.id = id
        job.decoded = nil
        job.ok = false
        sync.atomic_store(&job.state, JOB_ASSIGNED)
        sync.sema_post(&job.sema)
        return true
    }
    return false
}

// The result of a slot, when its worker has finished
@(private)
WorkersTake :: proc(store: ^AssetStore, slot: int) -> (id: AssetId, decoded: rawptr, ok: bool, done: bool) {
    job: ^WorkerJob = &store.workers.jobs[slot]
    if sync.atomic_load(&job.state) != JOB_DONE { return }
    return job.id, job.decoded, job.ok, true
}

// The slot is free again and its decode memory is reset: the decoded data must not be used after this
@(private)
WorkersRelease :: proc(store: ^AssetStore, slot: int) {
    job: ^WorkerJob = &store.workers.jobs[slot]
    free_all(mem.arena_allocator(&job.memory))
    sync.atomic_store(&job.state, JOB_IDLE)
}

// Wait until no worker is decoding. Results that are waiting stay
@(private)
WorkersWaitIdle :: proc(store: ^AssetStore) {
    for {
        decoding: bool
        for i in 0 ..< store.workers.count {
            if sync.atomic_load(&store.workers.jobs[i].state) == JOB_ASSIGNED { decoding = true }
        }
        if !decoding { return }
        time.sleep(100 * time.Microsecond)
    }
}

// Wait for the running decodes and throw every result away
@(private)
WorkersDiscardAll :: proc(store: ^AssetStore) {
    WorkersWaitIdle(store)
    for i in 0 ..< store.workers.count {
        if sync.atomic_load(&store.workers.jobs[i].state) == JOB_DONE {
            WorkersRelease(store, i)
        }
    }
}
