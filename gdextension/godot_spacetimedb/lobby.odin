#+build !js
package godot_spacetimedb

// The class `SpacetimeDBLobby` (a RefCounted): the p2p side of ANY game that keeps its world in a SpacetimeDB database. It starts the server of a host with the module of the game, makes the invite code
// and the room name, joins a host by a code, and gives the address where the game connects: with `SpacetimeDBClient.open(lobby.endpoint_host(), lobby.endpoint_port(), lobby.database(), token)`. Nothing in it
// knows a game; the module (a .wasm file) and the name of the database are arguments. The arena example (arena_example/) is one user, and so is test_lobby.gd.
//
//     var lobby := SpacetimeDBLobby.new()
//     lobby.host(OS.get_user_data_dir() + "/server", "mygame", "res://mygame.wasm", "Ada", 0, 1)     # a host: root folder, database, module file, name, port (0: 3000), flags
//     # or:  lobby.join(code_or_room, "mygame", "Bob", 0)                                           # a guest
//     func _process(_delta):
//         lobby.update()                                   # once a frame: the link, the tunnel, the stages (it emits the signals below)
//         if lobby.ready() and not client.is_open():       # the host at once, a guest when the tunnel is open
//             client.open(lobby.endpoint_host(), lobby.endpoint_port(), lobby.database(), "")
//
// The flags: 1 invite for friends (a host), 2 free relay (a friend joins with the room name or the one code, even behind strict NATs), 4 public address with STUN (needs the internet), 8 loopback (two
// programs on one computer). Close the game client before `leave()`.

import ge "../../gdextension"
import "../../spacetimedb/session"

FLAG_P2P :: 1
FLAG_RELAY :: 2
FLAG_INTERNET :: 4
FLAG_LOOPBACK :: 8

// The lobby and what is needed to tell GDScript about its changes: `update` emits the signals `became_ready`, `became_failed(error)`, `guest_joined(count)` and `guest_left(count)` when the state changed
LobbyObject :: struct {
    lobby: session.Lobby,
    object: rawptr,
    was_ready, was_failed: bool,
    guests: int,
}

@(private = "file")
lobbyOf :: proc(instance: rawptr) -> ^session.Lobby {
    return &(cast(^LobbyObject)instance).lobby
}

@(private = "file")
lobbyUpdate :: proc(instance: rawptr) {
    state: ^LobbyObject = cast(^LobbyObject)instance
    session.LobbyUpdate(&state.lobby)
    if state.lobby.ready && !state.was_ready { ge.Emit(state.object, "became_ready", {}) }
    if state.lobby.failed && !state.was_failed { ge.Emit(state.object, "became_failed", {ge.ValueText(session.LobbyError(&state.lobby))}) }
    guests: int = session.LobbyGuests(&state.lobby)
    if guests > state.guests { ge.Emit(state.object, "guest_joined", {ge.ValueInt(i64(guests))}) }
    if guests < state.guests { ge.Emit(state.object, "guest_left", {ge.ValueInt(i64(guests))}) }
    state.was_ready, state.was_failed, state.guests = state.lobby.ready, state.lobby.failed, guests
}

// One table of methods for both flavours: a RefCounted (the script calls `update`) and a Node (it updates itself from the engine's `_process`)
lobby_methods := [?]ge.Method{
        // host(root, database, module, name, port, flags): `root` is the folder of the server, `module` the file of the built module (a res:// path is globalized by the script), `port` 0 is 3000
        {"host", {.STRING, .STRING, .STRING, .STRING, .INT, .INT}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            flags: int = int(a[5].number)
            options: session.HostOptions = {
                root = string(a[0].text), database = string(a[1].text), module_path = string(a[2].text), name = string(a[3].text), port = int(a[4].number),
                internet = flags & FLAG_P2P != 0 && flags & FLAG_INTERNET != 0,
                derp = flags & FLAG_P2P != 0 && flags & FLAG_RELAY != 0,
                loopback = flags & FLAG_LOOPBACK != 0,
            }
            return ge.ValueBool(session.LobbyHost(lobbyOf(instance), options))
        }},
        // join(code, database, name, flags): `code` is an invite code or a room name, `database` the name the host published
        {"join", {.STRING, .STRING, .STRING, .INT}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            flags: int = int(a[3].number)
            return ge.ValueBool(session.LobbyJoin(lobbyOf(instance), string(a[0].text), string(a[1].text), {name = string(a[2].text), internet = flags & FLAG_INTERNET != 0, loopback = flags & FLAG_LOOPBACK != 0}))
        }},
        {"update", {}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            lobbyUpdate(instance)
            return {}
        }},
        {"leave", {}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            lobbyLeave(instance)
            return {}
        }},
        // the game can connect: a host once its server is up, a guest once the tunnel is open
        {"ready", {}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueBool(lobbyOf(instance).ready) }},
        {"failed", {}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueBool(lobbyOf(instance).failed) }},
        {"error", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueText(session.LobbyError(lobbyOf(instance))) }},
        {"endpoint_host", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueText(lobbyOf(instance).endpoint.host) }},
        {"endpoint_port", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueInt(i64(lobbyOf(instance).endpoint.port)) }},
        {"database", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueText(session.LobbyDatabase(lobbyOf(instance))) }},
        // the step of the p2p connection: 0 idle, 1 gathering addresses, 2 waiting for the relay, 3 finding a room, 4 ready (a host: the invite is made; a guest: the reply is made), 5 connected, 6 failed
        {"stage", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueInt(i64(session.LobbyStage(lobbyOf(instance)))) }},
        {"invite", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueText(session.LobbyInvite(lobbyOf(instance))) }},
        {"room", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueText(session.LobbyRoom(lobbyOf(instance))) }},
        {"reply", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueText(session.LobbyReply(lobbyOf(instance))) }},
        // a guest of an invite with no relay has to send its reply() back to the host
        {"needs_reply", {}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueBool(session.LobbyNeedsReply(lobbyOf(instance))) }},
        // a host whose relay is up: a friend needs only the invite or the room name
        {"relay_ready", {}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueBool(session.LobbyRelayReady(lobbyOf(instance))) }},
        {"accept_reply", {.STRING}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueBool(session.LobbyAcceptReply(lobbyOf(instance), string(a[0].text))) }},
        // friends whose connection is made
        {"guests", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueInt(i64(session.LobbyGuests(lobbyOf(instance)))) }},
        {"notice", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueText(session.LobbyNotice(lobbyOf(instance))) }},
        // what a pasted text is: 0 empty, 1 not a code, 2 an invite, 3 a reply, 4 a room name
        {"code_kind", {.STRING}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            kind, _, _ := session.CodeInspect(string(a[0].text))
            return ge.ValueInt(i64(kind))
        }},
        // who made the code (the name in it, or the room name)
        {"code_from", {.STRING}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueText(session.LobbyCodeFrom(lobbyOf(instance), string(a[0].text))) }},
}

@(private = "file")
lobbyCreate :: proc() -> rawptr {
    return new(LobbyObject)
}

@(private = "file")
lobbyBind :: proc(instance: rawptr, object: rawptr) {
    (cast(^LobbyObject)instance).object = object
}

@(private = "file")
lobbyDestroy :: proc(instance: rawptr) {
    session.LobbyLeave(lobbyOf(instance))
    free(instance)
}

// leaves and forgets what was told, so the signals come again for the next game
@(private = "file")
lobbyLeave :: proc(instance: rawptr) {
    session.LobbyLeave(lobbyOf(instance))
    state: ^LobbyObject = cast(^LobbyObject)instance
    state.was_ready, state.was_failed, state.guests = false, false, 0
}

lobby_signals := [?]ge.Signal{
    {"became_ready", {}},                       // the game can connect: a host once its server is up, a guest once the tunnel is open
    {"became_failed", {.STRING}},               // with the text of `error()`
    {"guest_joined", {.INT}},                   // a friend connected: the number of friends
    {"guest_left", {.INT}},
}

lobby_class: ge.Class = {
    name = "SpacetimeDBLobby",
    parent = "RefCounted",
    create = lobbyCreate,
    destroy = lobbyDestroy,
    bind = lobbyBind,
    signals = lobby_signals[:],
    methods = lobby_methods[:],
}

// The Node flavour: add it to the tree and it updates every frame by itself, and leaves when it leaves the tree. Same methods and signals as SpacetimeDBLobby.
lobby_node_class: ge.Class = {
    name = "SpacetimeDBLobbyNode",
    parent = "Node",
    create = lobbyCreate,
    destroy = lobbyDestroy,
    bind = lobbyBind,
    signals = lobby_signals[:],
    methods = lobby_methods[:],
    virtuals = {
        {"_process", proc(instance: rawptr, delta: f64) { lobbyUpdate(instance) }},
        {"_exit_tree", proc(instance: rawptr, delta: f64) { lobbyLeave(instance) }},
    },
}
