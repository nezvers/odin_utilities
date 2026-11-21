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

Limits and the list of what comes next: TODO.md.
