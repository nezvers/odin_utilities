# godot_spacetimedb

A Godot 4 GDExtension written in Odin (a sub library of `odin_utilities/gdextension`) that connects a game to a SpacetimeDB database (`odin_utilities/spacetimedb`). GDScript gets a class, `SpacetimeDBClient`, that it polls from `_process` (or its Node flavour `SpacetimeDBClientNode` that polls itself and emits signals): no thread, no callback from the network into Godot.

```gdscript
var client := SpacetimeDBClient.new()
client.open("127.0.0.1", 3000, "chat", "")           # port 443 means TLS; the last argument is a saved token ("" makes a new identity)
client.subscribe("SELECT * FROM person")

func _process(_delta):
    client.poll()
    while client.next_event():
        match client.event_kind():
            1: print("connected as ", client.event_text())                       # CONNECTED: our identity
            2: print("insert ", client.event_table(), " ", client.event_row())   # INSERT: the BSATN of the row as hex
            3: print("delete ", client.event_table(), " ", client.event_row())   # DELETE (an update is a DELETE and an INSERT)
            4: print("subscribed")                                               # SUBSCRIBED
            5: print("reducer ", client.event_request(), client.event_ok(), client.event_text())
```

Calling a reducer: `client.call_reducer("add", args_hex)` where `args_hex` is the BSATN of the arguments in hex (`StreamPeerBuffer`: `put_u32(len)` and the bytes for a string, `data_array.hex_encode()`). Rows are hex too: `row.hex_decode()` gives a `PackedByteArray` that a `StreamPeerBuffer` reads (little endian, as BSATN is).

| Method | |
|---|---|
| `open(host, port, database, token) -> bool` | connects; `token()` has the token to keep |
| `close()`, `is_open() -> bool`, `error() -> String` | |
| `subscribe(query) -> int` | one query per call; the request id, 0 when it could not be sent |
| `call_reducer(name, args_hex) -> int`, `call_reducer_bytes(name, PackedByteArray) -> int` | the request id, 0 when it could not be sent |
| `poll() -> int` | reads the network, returns how many events there are (and reconnects when the socket was lost) |
| `next_event() -> bool`, `event_kind()`, `event_request()`, `event_ok()`, `event_table()`, `event_row()`, `event_text()`, `event_row_bytes() -> PackedByteArray` | the events of the last poll |

Event kinds: 1 CONNECTED, 2 INSERT, 3 DELETE, 4 SUBSCRIBED, 5 REDUCER, 6 SUBSCRIPTION_ERROR, 7 DISCONNECTED, 8 RECONNECTED (see `client.odin`).

### The Node flavour: signals instead of polling (`SpacetimeDBClientNode`)
The same class (same methods: `open`, `subscribe`, `call_reducer`, ...) as a Node. Add it to the tree and it reads the network every frame by itself and tells the script with signals; it closes when it leaves the tree. Do not call `poll()` or `next_event()` on it.
```gdscript
var client := SpacetimeDBClientNode.new()
add_child(client)
client.row_inserted.connect(func(table: String, row: PackedByteArray) -> void: ...)   # BSATN bytes of the row
client.subscribed.connect(func(request: int) -> void: client.call_reducer_bytes("add", bytes))
client.open("127.0.0.1", 3000, "mygame", "")
client.subscribe("SELECT * FROM person")
```
Signals: `connected(identity)`, `row_inserted(table, row)`, `row_deleted(table, row)` (an update is a delete and an insert of the same key), `subscribed(request)`, `reducer_result(request, ok, error)`, `subscription_error(text)`, `disconnected(text)`, `reconnected` (the rows of the subscriptions come again: clear what you keep).

## Build and test
- `odin build gdextension/godot_spacetimedb -build-mode:dll -out:<project>/bin/godot_spacetimedb.dll` (Linux `.so`, macOS `.dylib`), and a `.gdextension` file next to it: `test_project/spacetimedb.gdextension` is the model (`entry_symbol = "spacetimedb_entry"`, Godot 4.4 or newer).
- `odin test gdextension/godot_spacetimedb/godot_test -strict-style -vet` builds the extension, starts a SpacetimeDB server with the Odin test module and runs `test_project/test.gd` in headless Godot (`godot` in PATH; skipped without it or without `odin run spacetimedb/tool/setup`).
- `godot --headless --dump-extension-api --dump-gdextension-interface` writes the interface header (`gdextension.odin` follows it; keep the dump in `godot_api/`, git ignored).

## Host and join for any game (`SpacetimeDBLobby`)
The third class is the p2p side of ANY game whose world is a SpacetimeDB database: `SpacetimeDBLobby` starts the server of a host with YOUR module, makes an invite code (and a room name with the free relay), joins a host by a code, and gives the address where the game connects. A friend needs no server and no port forwarding: a guest reaches the host's database through a tunnel over the p2p link. The module and the name of the database are arguments; the game connects with `SpacetimeDBClient`.

```gdscript
var lobby := SpacetimeDBLobby.new()
var client := SpacetimeDBClient.new()
lobby.host(OS.get_user_data_dir() + "/server", "mygame", ProjectSettings.globalize_path("res://mygame.wasm"), "Ada", 0, 1)   # root folder, database, module file, name, port (0: 3000), flags
# or a guest:  lobby.join(code_or_room, "mygame", "Bob", 0)
func _process(_delta):
    lobby.update()                                                  # once a frame: the link, the tunnel, the stages
    if lobby.ready() and not client.is_open():                      # a host at once, a guest when the tunnel is open
        client.open(lobby.endpoint_host(), lobby.endpoint_port(), lobby.database(), "")
    # ... client.poll() and the events, as in the first section
```
| Method | |
|---|---|
| `host(root, database, module, name, port, flags) -> bool`, `join(code, database, name, flags) -> bool`, `leave()` | a host starts its server (a second or two); `error()` says why a call failed; close the client before `leave()` |
| `update()`, `ready()`, `failed()`, `endpoint_host()`, `endpoint_port()`, `database()` | once a frame; where the game connects |
| `invite()`, `room()`, `reply()`, `needs_reply()`, `relay_ready()`, `accept_reply(text) -> bool`, `guests()`, `notice()`, `stage()` | the codes: a host gives out the invite (or the room name with the relay); a guest of an invite with no relay sends its reply back and the host accepts it. `stage()`: 0 idle, 1 gathering, 2 relay, 3 finding a room, 4 ready, 5 connected, 6 failed |
| `code_kind(text)` (0 empty, 1 not a code, 2 invite, 3 reply, 4 room), `code_from(text)` | what a pasted text is, before anything starts |

`SpacetimeDBLobbyNode` is the same class as a Node: add it to the tree and it updates itself every frame (no `update()` call) and leaves when it leaves the tree; `arena_project/test_lobby_node.gd` reacts to the signals only.

Signals (emitted by `update()`): `became_ready`, `became_failed(error)`, `guest_joined(count)`, `guest_left(count)`.

Flags: 1 invite for friends (a host), 2 free relay (a friend joins with the room name or the one code, even behind strict NATs), 4 public address with STUN (needs the internet), 8 loopback (two programs on one computer). The same thing for Odin programs is `spacetimedb/session` (`Lobby`, `Host`, `Guest`). `arena_project/test_lobby.gd` shows it with a module that is not the arena.

## Example: the arena game (`ArenaClient`)
`arena_example/` is a complete small game on those parts, not part of the generic API (drop the package and its line in `entry.odin` to leave it out): the arena of `spacetimedb/arena` (move, pick up coins, a scoreboard). `ArenaClient` adds what the arena knows to a lobby: its database and module, the game client (the rows of `player` and `coin`, smoothing, input) and a packed `snapshot()` of the field. `arena_project/` is the Godot project (`main.gd`: start screen, code form, connection steps, scoreboard, the field).

```gdscript
var arena := ArenaClient.new()
arena.host("Ada", OS.get_user_data_dir() + "/arena_server", 0, 1, "")      # name, folder of the server, port, flags (as above), module ("": the built one)
# or:  arena.join(code_or_room, "Bob", 0)
func _process(delta):
    arena.update(int(delta * 1000))          # the lobby, the game client and the smoothing
    arena.set_input(dx, dy)                  # -1, 0 or 1
    var snapshot := arena.snapshot()         # PackedByteArray: players (smoothed) and coins, layout at the top of arena_example/arena.odin
```
`ArenaClientNode` is the same class as a Node (it updates itself, no `update` call) with the signals `phase_changed(phase)`, `guest_count_changed(count)` and `failed(error)`; `arena_project/test_arena_node.gd` uses it.

`ArenaClient` has the lobby methods above (`phase()` 0 idle, 1 connecting, 2 playing, 3 failed; `game_phase()` 0 closed ... 3 playing, 4 lost; `waiting_ms()`).

Two windows on one computer or two computers: `godot --path gdextension/godot_spacetimedb/arena_project -- host` prints the invite, `... -- join <code>` joins (and prints the reply when the host used no relay: paste it in the host window); `--relay`, `--internet`, `--port=N`. `solo` plays alone. The project needs the built library in `arena_project/bin` (`odin build gdextension/godot_spacetimedb -build-mode:dll -out:gdextension/godot_spacetimedb/arena_project/bin/godot_spacetimedb.dll`) and `odin run spacetimedb/tool/setup` for the server and the modules. The tests (`godot_test`) play host and guest in one headless process, once with the arena and once with the `basic` module through the generic classes.

Limits and the list of what comes next: TODO.md.
