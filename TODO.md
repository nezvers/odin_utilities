# TODO

Tick an item when it is done and verified (tests pass, committed). The ui items are in `ui/TODO.md`, the p2p items in `p2p/TODO.md`.

## Libraries
- [x] `scratch`: two thread local scratch arenas with the conflict rule (`ScratchBegin(conflict)` / `ScratchEnd`), for non realtime tools
- [x] `scene` assets: cancellation tokens for superseded requests, a generation so a reloaded asset is served stale until the new one is ready,
      a per frame "held" guard against eviction, priority levels, eviction by time
- [x] `thread_lanes`: barrier, broadcast and index range for fan out of non realtime work
