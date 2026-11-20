package simd_utils

import "core:fmt"

// Who gets which level. A program with several libraries that use vector instructions (an audio engine, a physics step, an image filter, a decoder) runs them on one core and
// often on one pair of threads that share the vector units. The widest units are the scarce ones: on some CPUs AVX-512 lowers the clock of the core for everything that runs on
// it, and the two threads of a core share one set of 512 bit units. So the program says which library comes first, and the manager hands the wide level out in that order.
//
//     manager: simd_utils.Manager
//     simd_utils.ManagerInit(&manager)
//     audio, _ := simd_utils.ManagerRegister(&manager, "audio", priority = 100)       // wants the best there is
//     physics, _ := simd_utils.ManagerRegister(&manager, "physics", priority = 10)
//     images, _ := simd_utils.ManagerRegister(&manager, "images", priority = 1, wants = .AVX2)
//     simd_utils.ManagerFavor(&manager, audio)                                        // one wide slot, the others run the best level below it
//
//     level := simd_utils.ClientLevel(&manager, physics)                              // AVX2 on an AVX-512 machine, the best it has on any other
//     kernel, got, ok := simd_utils.ManagerSelect(&manager, physics, &dot_table)       // the kernel of the level, and not above what the algorithm is worth
//
// The rules, in the order the manager applies them to every client (highest priority first, the first registered among equals):
//   1. what it asks for (`wants`, default the best there is), limited by its `ceiling` and by what the machine and `SIMD_LEVEL` allow
//   2. a level from the policy's `wide` level up needs a slot (`Policy.slots`, 0 means no limit). A client that gets none is in the queue and runs `Policy.fallback`
//      (default: the level below `wide`) until a slot frees up
//   3. `ManagerRelease` of a client (it is idle, shut down) frees its slot and the next one in the queue is granted it; `ManagerAcquire` puts it back at its priority
// Every change resolves again and counts a generation: a client that keeps a level in a plan compares `ManagerGeneration` at the start of a block and makes new plans when it
// changed (a kernel never changes level in the middle of a block, and the audio thread never calls the manager's setters).
//
// Limits: a client is a library or a part of a program, not a thread or a call: the level is read when plans are made; no frequency model (the policy is the program's rule, measure
//     the machine to choose it); the names live in the caller's memory; 32 clients; set up and change on one thread, read the levels from any (one byte each).

MANAGER_CLIENTS :: 32

// For `wants` and `ceiling`: no limit, the best there is
LEVEL_BEST :: Level(255)

ClientId :: distinct u8        // 1 and up, 0 is no client

Reason :: enum u8 {
    BEST,           // what it asked for (the best there is) and got it
    WANTED,         // it asked for less and got it
    CEILING,        // limited by its own ceiling
    MACHINE,        // limited by what the CPU runs
    FORCED,         // limited by SIMD_LEVEL or CpuForce
    QUEUED,         // the wide level is taken by clients of higher priority: waiting in the queue, running the fallback
    IDLE,           // released: it holds nothing
}

Client :: struct {
    name: string,
    priority: i32,              // higher goes first
    wants: Level,               // LEVEL_BEST: the best
    ceiling: Level,             // LEVEL_BEST: none
    active: bool,
    granted: Level,             // what it gets now: read this with ClientLevel
    reason: Reason,
    queue: int,                 // 0, or the place in the queue for the wide level (1 is next)
    wide: bool,                 // it runs at the wide level (and holds one of the slots when the policy has them)
}

Policy :: struct {
    wide: Level,                // levels from this one up are scarce (AVX512)
    slots: int,                 // how many clients run at `wide` or above at once; 0: no limit, everyone gets what it asks for
    fallback: Level,            // what a client without a slot runs; SCALAR here means "the level below `wide`"
}

Manager :: struct {
    cpu: ^Cpu,
    policy: Policy,
    clients: [MANAGER_CLIENTS]Client,
    count: int,
    generation: u32,
}

ManagerInit :: proc(manager: ^Manager, cpu: ^Cpu = nil) {
    manager^ = {}
    manager.cpu = cpu if cpu != nil else CpuGet()
    manager.policy = {wide = .AVX512}
    manager.generation = 1
}

// A client. False when the 32 places are taken. `name` has to live as long as the manager.
ManagerRegister :: proc(manager: ^Manager, name: string, priority: i32 = 0, wants: Level = LEVEL_BEST, ceiling: Level = LEVEL_BEST) -> (id: ClientId, ok: bool) {
    if manager.count >= MANAGER_CLIENTS { return 0, false }
    manager.clients[manager.count] = {name = name, priority = priority, wants = wants, ceiling = ceiling, active = true}
    manager.count += 1
    id = ClientId(manager.count)
    ManagerResolve(manager)
    return id, true
}

@(private)
clientOf :: proc(manager: ^Manager, id: ClientId) -> ^Client {
    if id == 0 || int(id) > manager.count { return nil }
    return &manager.clients[int(id) - 1]
}

// The client's record, to read (nil for an id that is not one)
ClientInfo :: proc(manager: ^Manager, id: ClientId) -> ^Client {
    return clientOf(manager, id)
}

// The level the client runs now. SCALAR for an id that is not a client.
ClientLevel :: proc(manager: ^Manager, id: ClientId) -> Level {
    client: ^Client = clientOf(manager, id)
    return client.granted if client != nil else .SCALAR
}

// The count of changes so far: a plan made at generation N is current while this is N
ManagerGeneration :: proc(manager: ^Manager) -> u32 {
    return manager.generation
}

ManagerSetPolicy :: proc(manager: ^Manager, policy: Policy) {
    manager.policy = policy
    ManagerResolve(manager)
}

ManagerSetPriority :: proc(manager: ^Manager, id: ClientId, priority: i32) {
    if client: ^Client = clientOf(manager, id); client != nil {
        client.priority = priority
        ManagerResolve(manager)
    }
}

ManagerSetWants :: proc(manager: ^Manager, id: ClientId, wants: Level) {
    if client: ^Client = clientOf(manager, id); client != nil {
        client.wants = wants
        ManagerResolve(manager)
    }
}

ManagerSetCeiling :: proc(manager: ^Manager, id: ClientId, ceiling: Level) {
    if client: ^Client = clientOf(manager, id); client != nil {
        client.ceiling = ceiling
        ManagerResolve(manager)
    }
}

// Puts the client first and gives the wide level `slots` places: the favored library runs the best level, every other one runs the fallback (or the best it can get once the
// slots are not all used). The usual single call for "this library comes first".
ManagerFavor :: proc(manager: ^Manager, id: ClientId, slots: int = 1) {
    client: ^Client = clientOf(manager, id)
    if client == nil { return }
    highest: i32 = client.priority
    for other, i in manager.clients[:manager.count] {
        if i + 1 != int(id) { highest = max(highest, other.priority) }
    }
    client.priority = highest + 1 if client.priority <= highest else client.priority
    manager.policy.slots = max(slots, 1)
    ManagerResolve(manager)
}

// The client has nothing to run for now (an engine that is stopped): it gives its slot back and the next client in the queue gets it
ManagerRelease :: proc(manager: ^Manager, id: ClientId) {
    if client: ^Client = clientOf(manager, id); client != nil && client.active {
        client.active = false
        ManagerResolve(manager)
    }
}

// The client runs again, at its priority: it takes a slot back from a client of lower priority, or waits in the queue
ManagerAcquire :: proc(manager: ^Manager, id: ClientId) {
    if client: ^Client = clientOf(manager, id); client != nil && !client.active {
        client.active = true
        ManagerResolve(manager)
    }
}

// Works out what every client gets. Called by every setter; call it after changing `cpu` (CpuForce) by hand. Counts a generation when anything changed.
ManagerResolve :: proc(manager: ^Manager) {
    cpu: ^Cpu = manager.cpu
    // the order: priority, then the order of registration
    order: [MANAGER_CLIENTS]u8
    for i in 0 ..< manager.count { order[i] = u8(i) }
    for i in 1 ..< manager.count {
        at: u8 = order[i]
        j: int = i
        for j > 0 && manager.clients[order[j - 1]].priority < manager.clients[at].priority {
            order[j] = order[j - 1]
            j -= 1
        }
        order[j] = at
    }
    fallback: Level = manager.policy.fallback if manager.policy.fallback != .SCALAR else LevelBelow(manager.policy.wide)
    used: int
    waiting: int
    changed: bool
    for n in 0 ..< manager.count {
        client: ^Client = &manager.clients[order[n]]
        before: Level = client.granted
        before_reason: Reason = client.reason
        client.wide, client.queue = false, 0
        if !client.active {
            client.granted, client.reason = .SCALAR, .IDLE
        } else {
            granted: Level = cpu.level
            reason: Reason = .BEST
            // what it asks for, limited to the machine (a level of another family means the best there is)
            if client.wants != LEVEL_BEST {
                wanted: Level = LevelClamp(client.wants, cpu.level)
                if wanted < granted {
                    granted, reason = wanted, .WANTED
                } else if LevelFamily(client.wants) == LevelFamily(cpu.level) && client.wants > cpu.level {
                    reason = .MACHINE                   // it asked for more than the CPU has and gets all of it
                }
            }
            if client.ceiling != LEVEL_BEST {
                ceiling: Level = LevelClamp(client.ceiling, cpu.level)
                if ceiling < granted { granted, reason = ceiling, .CEILING }
            }
            if cpu.forced < granted { granted, reason = cpu.forced, .FORCED }
            // the wide level is handed out in order
            is_wide: bool = LevelFamily(granted) == LevelFamily(manager.policy.wide) && granted >= manager.policy.wide
            if is_wide && manager.policy.slots > 0 {
                if used < manager.policy.slots {
                    used += 1
                    client.wide = true
                } else {
                    waiting += 1
                    client.queue = waiting
                    granted, reason = min(granted, fallback), .QUEUED
                }
            } else if is_wide {
                client.wide = true
            }
            client.granted, client.reason = granted, reason
        }
        if client.granted != before || client.reason != before_reason { changed = true }
    }
    if changed { manager.generation += 1 }
}

// Picks the kernel of an algorithm for a client: the best kernel at or below the client's level, and not above what the algorithm is worth (`TableUseful`).
ManagerSelect :: proc(manager: ^Manager, id: ClientId, table: ^Table($P)) -> (kernel: P, got: Level, ok: bool) {
    level: Level = ClientLevel(manager, id)
    if table.capped && LevelFamily(table.useful) == LevelFamily(level) { level = min(level, table.useful) }
    if table.capped && table.useful == .SCALAR { level = .SCALAR }
    return TablePick(table, level)
}

ReasonName :: proc "contextless" (reason: Reason) -> string {
    switch reason {
    case .BEST: return "the best this machine runs"
    case .WANTED: return "what it asked for"
    case .CEILING: return "its ceiling"
    case .MACHINE: return "what the machine runs"
    case .FORCED: return "limited to SIMD_LEVEL"
    case .QUEUED: return "waiting for a wide slot"
    case .IDLE: return "released"
    }
    return ""
}

// A line about a client for a log or a help page: "audio: AVX-512 (the best this machine runs, wide slot)"
ManagerExplain :: proc(manager: ^Manager, id: ClientId, out: []u8) -> string {
    client: ^Client = clientOf(manager, id)
    if client == nil { return "" }
    if client.queue > 0 {
        return fmt.bprintf(out, "%s: %s (%s, place %d in the queue)", client.name, LevelName(client.granted), ReasonName(client.reason), client.queue)
    }
    return fmt.bprintf(out, "%s: %s (%s%s)", client.name, LevelName(client.granted), ReasonName(client.reason), ", wide slot" if client.wide && manager.policy.slots > 0 else "")
}
