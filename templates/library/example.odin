package example

// The core of a library: framework agnostic (no raylib, no Karl2D), no hidden allocations (the caller owns the memory), builds for
// js_wasm32 when it uses nothing that does not. Rename the package, the procs and this file.
//
// Style: procs are PascalCase and start with the abstraction (CounterInit, CounterAdd), constants are UPPER_CASE, types PascalCase,
// typed locals (`name: Type = value`), `assert` for preconditions, comments say why.

COUNTER_LIMIT_DEFAULT :: 10

Counter :: struct {
    value: int,
    limit: int,
}

// A counter that stops at `limit`. Plain data: it can live in a struct, be copied and saved.
CounterInit :: proc(counter: ^Counter, limit: int = COUNTER_LIMIT_DEFAULT) {
    assert(limit > 0)
    counter^ = {limit = limit}
}

// Add to the counter, it does not pass its limit. Returns how much was really added.
CounterAdd :: proc(counter: ^Counter, amount: int) -> int {
    before: int = counter.value
    counter.value = clamp(counter.value + amount, 0, counter.limit)
    return counter.value - before
}

CounterIsFull :: proc(counter: ^Counter) -> bool {
    return counter.value >= counter.limit
}
