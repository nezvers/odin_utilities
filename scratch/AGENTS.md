# scratch: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `scratch/scratch.odin`: two thread local `core:mem/virtual` arenas per thread (64 MB reserve), `ScratchBegin(conflicts..)` / `ScratchEnd` / `ScratchAllocator` / `ScratchRelease`: a function that writes its result into an arena names it as the conflict and gets the other arena for temporaries. For tools and loaders, not realtime.
- `lanes/lanes.odin`: SPMD fan out, `Run(count, work, user)` runs the same proc on every lane, `LaneRange` / `LaneSync` / `LaneBroadcast`. Not realtime. Both are `#+build !js`, tests inside, `odin test scratch`, `odin test lanes`.
- `TODO.md` (this folder) is the list of improvements under way: tick items when verified and committed.
