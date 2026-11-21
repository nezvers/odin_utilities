# spacetimedb/arena: notes for agents

What is not obvious from the code. The rules for every library are in [../../AGENTS.md](../../AGENTS.md), `spacetimedb` in [../AGENTS.md](../AGENTS.md), the use in README.md.

- Layers: `module/` (the game in the database, Odin wasm) -> `schema/` (GENERATED, never edit: `odin run spacetimedb/arena/tool/schema` after the module changed; it starts a server) -> `game/` (client logic) -> `session/` (p2p: host, guest, tunnel) -> `demo_common/` (window).
- Build the module with `odin run spacetimedb/tool/build_module -- spacetimedb/arena/module spacetimedb/bin/arena-odin.wasm` (the setup does it too: `SetupOdinModule` looks in `module/example/<name>` and in `<name>/module`).
- The blocking calls of the client (HTTP, the websocket handshake) through a tunnel need the same thread to step the tunnel: `session.SetIdle` sets `spacetimedb.StreamIdle`. A host process steps itself in its frame loop. If a join hangs, look there first.
- A host keeps its database in `<root>` and the owner identity in `<root>/owner.token`: without the token a second start cannot update the database ("not authorized").
- Tests start servers on ports 3143 to 3145 (and 3144 live); the folders are removed with `spacetimedb.ServerRemove` (the database files are locked for a moment after the kill).
- `Host`/`Guest` structs go on the heap in tests: `SetIdle` keeps pointers to them (the compiler warns about stack addresses).
- The demo reads `os.args` once (`parseArguments`); a test sets `config` itself (`parsed = true`) and `sleep_ms` because a headless run has no real time for the network.
- A test that is killed leaves `spacetimedb-standalone.exe` running on its port; the next run then talks to the old server ("not authorized"): kill the orphans (`taskkill /F /IM spacetimedb-standalone.exe /IM spacetimedb-cli.exe`).
- The stdin reader of a host is a thread with a one slot mailbox (`console.odin`), the only thread of the game.
- The start screen is in `demo_arena.odin` (`Phase.MENU/JOIN_FORM`, `pending` is done in the next update so that "starting..." is drawn first). Command line arguments skip it (`config.menu`). Its test is `script_menu.odin` (clicks at fixed places of the 1280 x 720 screen: move a widget and the script moves with it) and the two tests share the demo state, so they take `tests_lock`.
- `ServerStop` waits until the port answers no more: a server that starts right after on the same port (Escape then Host a game) used to find the old one and time out.
