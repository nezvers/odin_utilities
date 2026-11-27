# godot_spacetimedb

A Godot 4 GDExtension written in Odin (a sub library of `odin_utilities/gdextension`) that connects a game to a SpacetimeDB database (`odin_utilities/spacetimedb`). GDScript gets one class, `SpacetimeDBClient`, that it polls from `_process`: no thread, no callback from the network into Godot.

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

## Build and test
- `odin build gdextension/godot_spacetimedb -build-mode:dll -out:<project>/bin/godot_spacetimedb.dll` (Linux `.so`, macOS `.dylib`), and a `.gdextension` file next to it: `test_project/spacetimedb.gdextension` is the model (`entry_symbol = "spacetimedb_entry"`, Godot 4.4 or newer).
- `odin test gdextension/godot_spacetimedb/godot_test -strict-style -vet` builds the extension, starts a SpacetimeDB server with the Odin test module and runs `test_project/test.gd` in headless Godot (`godot` in PATH; skipped without it or without `odin run spacetimedb/tool/setup`).
- `godot --headless --dump-extension-api --dump-gdextension-interface` writes the interface header (`gdextension.odin` follows it; keep the dump in `godot_api/`, git ignored).

## The arena game: host and join (`ArenaClient`)
The second class of the extension is the whole arena game of `spacetimedb/arena` (a multiplayer game whose world is a database written in Odin) for Godot, with the p2p host and join of its `session` package: `ArenaClient` starts the server of a host, makes the invite, joins a host by a code or a room name, connects the game client (a guest through the tunnel), keeps the rows and smooths the players. `arena_project/` is a complete Godot project that uses it (`main.gd`: start screen, code form, connection steps, scoreboard, the field).

```gdscript
var arena := ArenaClient.new()
arena.host("Ada", OS.get_user_data_dir() + "/arena_server", 0, 1, "")   # name, folder of the server, port (0: 3000), flags, module ("": the built one); flags: 1 invite for friends, 2 free relay, 4 public address (STUN), 8 loopback
# or:  arena.join(code_or_room, "Bob", 0)
func _process(delta):
    arena.update(int(delta * 1000))                  # the p2p link, the tunnel, the game client: once a frame
    arena.set_input(dx, dy)                          # -1, 0 or 1: the direction that is held
    var snapshot := arena.snapshot()                 # PackedByteArray: players (smoothed) and coins, see arena.odin for the layout
```
| Method | |
|---|---|
| `host(name, root, port, flags, module) -> bool`, `join(code, name, flags) -> bool`, `leave()` | start (a host starts its server: a second or two) or join; `error()` says why a call failed |
| `update(delta_ms)`, `set_input(dx, dy)`, `snapshot() -> PackedByteArray` | once a frame |
| `phase()` (0 idle, 1 connecting, 2 playing, 3 failed), `stage()` (p2p: 0 idle, 1 gathering, 2 relay, 3 finding a room, 4 ready, 5 connected, 6 failed), `game_phase()` (0 closed, 1 connecting, 2 joining, 3 playing, 4 lost), `waiting_ms()` | where it is |
| `invite()`, `room()`, `reply()`, `needs_reply()`, `relay_ready()`, `accept_reply(text) -> bool`, `guests()`, `notice()` | the codes: a host gives out the invite (or the room name with the relay); a guest of an invite with no relay sends its reply back and the host accepts it |
| `code_kind(text)` (0 empty, 1 not a code, 2 invite, 3 reply, 4 room), `code_from(text)` | what a pasted text is, before anything starts |

Two windows on one computer or two computers: `godot --path gdextension/godot_spacetimedb/arena_project -- host` prints the invite, `... -- join <code>` joins (and prints the reply when the host used no relay: paste it in the host's window); `--relay`, `--internet`, `--port=N`. `solo` plays alone. The project needs the built library in `arena_project/bin` (`odin build gdextension/godot_spacetimedb -build-mode:dll -out:gdextension/godot_spacetimedb/arena_project/bin/godot_spacetimedb.dll`) and `odin run spacetimedb/tool/setup` for the server and the module. The test (`godot_test`) plays host and guest in one headless process.

Limits and the list of what comes next: TODO.md.
