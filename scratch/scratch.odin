#+build !js
package scratch

// Thread local scratch memory, after the RAD Debugger (references/raddebugger/src/base/base_thread_context.c): every thread has TWO arenas that
// reserve a big range and commit it as it is used (core:mem/virtual), and a function that needs temporary memory takes one with a mark and gives it
// back with ScratchEnd. The second arena is the point: a function that writes its RESULT into an arena (a caller's, or a scratch arena of the
// caller) names that arena as a conflict, and gets the other one for its temporaries, so the temporaries are released at ScratchEnd without
// taking the result with them. No allocator has to be passed down and nothing is freed one piece at a time.
//
//     Parse :: proc(text: string, result: mem.Allocator, result_arena: ^virtual.Arena) -> Table {
//         scratch := scratch.ScratchBegin(result_arena)          // not the arena the result goes to
//         defer scratch.ScratchEnd(scratch)
//         words := make([dynamic]string, scratch.ScratchAllocator(scratch))
//         ...                                                    // the words are gone at the end, the table lives in `result`
//     }
//
// For tools, loaders and tests: not for the audio thread (a first call on a thread reserves address space and commits memory).
// A thread that ends should call ScratchRelease (nothing else frees its arenas).

import "core:mem"
import "core:mem/virtual"
import "core:testing"
import "core:thread"

// Address space each of the two arenas of a thread reserves (physical memory is committed as it is used, 64 KB at a time)
SCRATCH_RESERVE :: #config(SCRATCH_RESERVE, 64 * mem.Megabyte)
SCRATCH_COMMIT :: 64 * mem.Kilobyte

@(private)
arenas: [2]virtual.Arena

@(private)
ready: bool

@(thread_local, private)
thread_arenas: [2]virtual.Arena

@(thread_local, private)
thread_ready: bool

// A mark in one of the thread's arenas: everything allocated from it after ScratchBegin is released by ScratchEnd
Scratch :: struct {
    arena: ^virtual.Arena,
    temp: virtual.Arena_Temp,
}

@(private)
threadInit :: proc() {
    for &arena in thread_arenas {
        err: mem.Allocator_Error = virtual.arena_init_static(&arena, SCRATCH_RESERVE, SCRATCH_COMMIT)
        assert(err == nil, "scratch: no address space for the scratch arenas")
    }
    thread_ready = true
}

// Memory for temporaries from the arena of this thread that is not one of `conflicts` (the arenas the caller's results are written to).
// At most one conflict can be given for the thread's two arenas to be enough: more conflicts than arenas is a programming error.
ScratchBegin :: proc(conflicts: ..^virtual.Arena) -> Scratch {
    if !thread_ready { threadInit() }
    for &arena in thread_arenas {
        taken: bool = false
        for conflict in conflicts {
            if conflict == &arena { taken = true }
        }
        if !taken { return {arena = &arena, temp = virtual.arena_temp_begin(&arena)} }
    }
    panic("scratch: every arena of the thread is a conflict")
}

// Releases everything allocated since ScratchBegin
ScratchEnd :: proc(scratch: Scratch) {
    virtual.arena_temp_end(scratch.temp)
}

// The allocator of the scratch memory
ScratchAllocator :: proc(scratch: Scratch) -> mem.Allocator {
    return virtual.arena_allocator(scratch.arena)
}

// The arena of the scratch memory: pass it as a conflict to what you call when your own result goes into it
ScratchArena :: proc(scratch: Scratch) -> ^virtual.Arena {
    return scratch.arena
}

// Gives the thread's scratch arenas back (call before a thread ends)
ScratchRelease :: proc() {
    if !thread_ready { return }
    for &arena in thread_arenas { virtual.arena_destroy(&arena) }
    thread_ready = false
}

// ---------------------------------------------------------------- Tests

@(test)
test_scratch_is_released_at_the_end :: proc(t: ^testing.T) {
    defer ScratchRelease()
    first := ScratchBegin()
    pointer, _ := mem.alloc(1024, 8, ScratchAllocator(first))
    testing.expect(t, pointer != nil)
    position: uint = virtual.arena_total_used(first.arena)
    testing.expect(t, position >= 1024)
    ScratchEnd(first)
    testing.expect(t, virtual.arena_total_used(first.arena) < position, "the mark gave the memory back")
    again := ScratchBegin()
    defer ScratchEnd(again)
    testing.expect(t, again.arena == first.arena, "the same arena is reused")
}

@(test)
test_a_conflict_gets_the_other_arena :: proc(t: ^testing.T) {
    defer ScratchRelease()
    outer := ScratchBegin()
    defer ScratchEnd(outer)
    // the callee writes its result into `outer` and takes the other arena for its own temporaries
    callee :: proc(result: Scratch, t: ^testing.T) -> []int {
        scratch := ScratchBegin(ScratchArena(result))
        defer ScratchEnd(scratch)
        testing.expect(t, scratch.arena != result.arena)
        temporaries: []int = make([]int, 1000, ScratchAllocator(scratch))
        for &value, i in temporaries { value = i }
        answer: []int = make([]int, 3, ScratchAllocator(result))
        answer[0], answer[1], answer[2] = temporaries[10], temporaries[20], temporaries[999]
        return answer
    }
    answer: []int = callee(outer, t)
    testing.expect_value(t, answer[0], 10)
    testing.expect_value(t, answer[1], 20)
    testing.expect_value(t, answer[2], 999)         // the result outlived the callee's temporaries
}

@(test)
test_every_thread_has_its_own_scratch :: proc(t: ^testing.T) {
    defer ScratchRelease()
    mine := ScratchBegin()
    defer ScratchEnd(mine)
    Probe :: struct { arena: ^virtual.Arena }
    probe: Probe
    worker: ^thread.Thread = thread.create_and_start_with_poly_data(&probe, proc(probe: ^Probe) {
        scratch := ScratchBegin()
        probe.arena = scratch.arena
        ScratchEnd(scratch)
        ScratchRelease()
    })
    thread.join(worker)
    thread.destroy(worker)
    testing.expect(t, probe.arena != nil && probe.arena != mine.arena)
}
