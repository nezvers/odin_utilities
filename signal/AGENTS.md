# signal: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `signal.odin` (`Signal($T,$N,$Q)`: payload, connection capacity, deferred queue size; connections in `core:container/handle_map`, order list kept apart because slots are reused; `Signal*` procs: Connect with `.ONE_SHOT`/`.DEFERRED`, Emit, Flush, Disconnect*, Block; safe to change connections while emitting; builds for js so tests are in `signal_test.odin`), `demo_common/` (framework free model of the demos), `demo_raylib/`, `demo_karl2d/game/`.
