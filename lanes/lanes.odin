#+build !js
package lanes

// Lanes: SPMD fan out for non realtime work, after the RAD Debugger (references/raddebugger/src/base/base_thread_context.c). Every thread of a
// group runs the SAME procedure; the lane index and a barrier are all they need to divide the work and to wait for each other, there is no task queue
// and no allocation while it runs:
//
//     Work :: proc(lane: ^lanes.Lane, user: rawptr) {
//         range := lanes.LaneRange(lane, len(items))               // this lane's part of the items
//         for i in range.start ..< range.end { Process(&items[i]) }
//         lanes.LaneSync(lane)                                      // everybody is done with the first stage
//         total: int = 0
//         if lanes.LaneIndex(lane) == 0 { total = Summarize(items) }
//         lanes.LaneBroadcast(lane, &total, 0)                      // now every lane has what lane 0 computed
//     }
//     lanes.Run(8, Work, nil)                                       // the caller is lane 0, seven threads more
//
// Not for the audio thread (it creates threads and waits on a barrier): the realtime pool of odin_plug (graph/pool.odin) is made for that.
// Offline bounce of tracks, batch checks, asset conversion, tests that need many threads at once.

import "core:sync"
import "core:testing"
import "core:thread"

LANES_MAX :: 64
BROADCAST_BYTES :: 64

Group :: struct {
    count: int,
    barrier: sync.Barrier,
    broadcast: [BROADCAST_BYTES]u8,
    work: proc(lane: ^Lane, user: rawptr),
    user: rawptr,
}

Lane :: struct {
    index: int,
    group: ^Group,
}

Range :: struct {
    start, end: int,
}

// Runs `work` on `count` lanes at the same time (the calling thread is lane 0) and returns when all are done
Run :: proc(count: int, work: proc(lane: ^Lane, user: rawptr), user: rawptr = nil) {
    assert(count >= 1 && count <= LANES_MAX)
    group: Group = {count = count, work = work, user = user}
    sync.barrier_init(&group.barrier, count)
    lanes: [LANES_MAX]Lane
    threads: [LANES_MAX]^thread.Thread
    for i in 0 ..< count { lanes[i] = {index = i, group = &group} }
    for i in 1 ..< count {
        threads[i] = thread.create_and_start_with_poly_data(&lanes[i], proc(lane: ^Lane) {
            lane.group.work(lane, lane.group.user)
        })
    }
    work(&lanes[0], user)
    for i in 1 ..< count {
        thread.join(threads[i])
        thread.destroy(threads[i])
    }
}

LaneIndex :: proc(lane: ^Lane) -> int {
    return lane.index
}

LaneCount :: proc(lane: ^Lane) -> int {
    return lane.group.count
}

// All lanes wait here until every lane has arrived
LaneSync :: proc(lane: ^Lane) {
    sync.barrier_wait(&lane.group.barrier)
}

// This lane's part of `count` items: contiguous ranges that differ in size by at most one item and together are all of them
LaneRange :: proc(lane: ^Lane, count: int) -> Range {
    lanes: int = lane.group.count
    base: int = count / lanes
    extra: int = count % lanes
    start: int = lane.index * base + min(lane.index, extra)
    return {start, start + base + (1 if lane.index < extra else 0)}
}

// The value of `value` in lane `source` is copied to all the other lanes (a small value: at most BROADCAST_BYTES bytes). Every lane calls it.
LaneBroadcast :: proc(lane: ^Lane, value: ^$T, source: int) where size_of(T) <= BROADCAST_BYTES {
    group: ^Group = lane.group
    if lane.index == source { (^T)(&group.broadcast[0])^ = value^ }
    sync.barrier_wait(&group.barrier)
    if lane.index != source { value^ = (^T)(&group.broadcast[0])^ }
    sync.barrier_wait(&group.barrier)           // nobody reads the buffer while the next broadcast writes it
}

// ---------------------------------------------------------------- Tests

@(test)
test_lanes_split_the_items_and_sum_them :: proc(t: ^testing.T) {
    Shared :: struct { items: [1000]int, partial: [LANES_MAX]int, total: [LANES_MAX]int }
    shared: ^Shared = new(Shared)
    defer free(shared)
    for i in 0 ..< len(shared.items) { shared.items[i] = i + 1 }
    Run(7, proc(lane: ^Lane, user: rawptr) {
        shared: ^Shared = (^Shared)(user)
        range: Range = LaneRange(lane, len(shared.items))
        sum: int = 0
        for i in range.start ..< range.end { sum += shared.items[i] }
        shared.partial[lane.index] = sum
        LaneSync(lane)
        total: int = 0
        if lane.index == 0 {
            for i in 0 ..< LaneCount(lane) { total += shared.partial[i] }
        }
        LaneBroadcast(lane, &total, 0)
        shared.total[lane.index] = total
    }, shared)
    for i in 0 ..< 7 { testing.expectf(t, shared.total[i] == 500500, "lane %d saw %d", i, shared.total[i]) }
}

@(test)
test_ranges_cover_everything_once :: proc(t: ^testing.T) {
    group: Group = {count = 6}
    for count in ([?]int{0, 1, 5, 6, 7, 100, 1001}) {
        covered: int = 0
        previous_end: int = 0
        for index in 0 ..< 6 {
            lane: Lane = {index = index, group = &group}
            range: Range = LaneRange(&lane, count)
            testing.expect_value(t, range.start, previous_end)
            covered += range.end - range.start
            previous_end = range.end
        }
        testing.expect_value(t, covered, count)
    }
}

@(test)
test_many_syncs_and_one_lane :: proc(t: ^testing.T) {
    Shared :: struct { stages: [8]int }
    shared: Shared
    Run(4, proc(lane: ^Lane, user: rawptr) {
        shared: ^Shared = (^Shared)(user)
        for stage in 0 ..< 8 {
            if lane.index == stage % 4 { shared.stages[stage] = stage + 1 }
            LaneSync(lane)
        }
    }, &shared)
    for stage in 0 ..< 8 { testing.expect_value(t, shared.stages[stage], stage + 1) }
    // a group of one lane is the caller alone
    ran: int
    Run(1, proc(lane: ^Lane, user: rawptr) {
        (^int)(user)^ += 1
        LaneSync(lane)
        LaneRange(lane, 10)
    }, &ran)
    testing.expect_value(t, ran, 1)
}
