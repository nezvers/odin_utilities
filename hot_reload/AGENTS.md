# hot_reload: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `hot_reload.odin` (`HotReload*` procs, `Api` that the DLL exports with the `game_` prefix, `LayoutHash`; tests at the bottom build `demo_game` as a DLL), `demo_game/` (framework free demo game DLL, `demo_game/api` is the host proc table), demos in `demo_raylib/` and `demo_karl2d/` (a Reload button rebuilds the DLL and calls `HotReloadRequest`).
