#+build !js
package session

// The host and the guest of session.odin in ONE object that a game (or a binding to an engine) holds: it is either the host of a game or a guest that joined one. It owns what the session keeps
// by reference (the strings of the options), keeps the text of an error that a call made, and brings the guest to the point where the game can connect:
//
//     lobby: ^Lobby = new(Lobby)                                       // on the heap: SetIdle keeps pointers into it
//     LobbyHost(lobby, {root = "server", module_path = "game.wasm", database = "mygame", name = "Ada", derp = true})      // or LobbyJoin(lobby, code_or_room, {name = "Bob"})
//     every frame: LobbyUpdate(lobby)
//     when lobby.ready: connect the game client to lobby.endpoint, database LobbyDatabase(lobby)
//     LobbyInvite(lobby) / LobbyRoom(lobby) are what a host gives out; a guest of an invite without a relay shows LobbyReply and the host calls LobbyAcceptReply
//     LobbyLeave(lobby) after the game client was closed
//
// A host is `ready` as soon as its server is up (the game on the same computer connects at once, the invite follows); a guest is `ready` when the p2p connection is made and the tunnel is open.
// `failed` is set with a text in `LobbyError`.

import "core:strings"
import "core:time"
import st ".."

LobbyKind :: enum u8 {
    NONE,
    HOST,
    GUEST,
}

Lobby :: struct {
    kind: LobbyKind,
    host: ^Host,
    guest: ^Guest,
    options: HostOptions,           // heap copies of the strings (the session keeps them by reference)
    guest_name: string,
    endpoint: st.Endpoint,          // where the game client connects (valid when `ready`)
    ready: bool,
    failed: bool,
    error: [400]u8,
    error_length: int,
    code: [512]u8,                  // the text of LobbyCodeFrom
}

// The host of this process (the last one started): a guest in the SAME process (a test, two lobbies in one program) steps it while it waits in a blocking call. Nil when there is none.
@(private = "file")
active_host: ^Host

LobbyError :: proc(lobby: ^Lobby) -> string {
    return string(lobby.error[:lobby.error_length])
}

@(private = "file")
lobbyFail :: proc(lobby: ^Lobby, message: string) {
    lobby.error_length = copy(lobby.error[:], message)
    lobby.failed = true
    lobby.ready = false
}

// The name of the database the game connects to
LobbyDatabase :: proc(lobby: ^Lobby) -> string {
    return lobby.options.database
}

// Stops everything: the p2p link, the tunnel, the server of a host. Close the game client first: the close of its websocket then reaches the host before the tunnel is gone.
LobbyLeave :: proc(lobby: ^Lobby) {
    if lobby.guest != nil && lobby.guest.tunnel_started {
        // step the tunnel a few times so that the host hears the close now and not after the p2p timeout (more than 15 s)
        for _ in 0 ..< 12 {
            GuestUpdate(lobby.guest)
            if active_host != nil { HostUpdate(active_host) }
            time.sleep(5 * time.Millisecond)
        }
    }
    ClearIdle()
    if lobby.host != nil {
        if active_host == lobby.host { active_host = nil }
        HostStop(lobby.host)
        free(lobby.host)
    }
    if lobby.guest != nil {
        GuestStop(lobby.guest)
        free(lobby.guest)
    }
    delete(lobby.options.root)
    delete(lobby.options.module_path)
    delete(lobby.options.database)
    delete(lobby.options.name)
    delete(lobby.options.room)
    delete(lobby.guest_name)
    lobby^ = {}
}

// Starts the server with the module (a second or two: the call blocks) and begins the p2p side. False with `LobbyError` set. `options.derp` / `internet` / `loopback` are for friends: see HostOptions.
LobbyHost :: proc(lobby: ^Lobby, options: HostOptions) -> bool {
    LobbyLeave(lobby)
    lobby.options = options
    lobby.options.root = strings.clone(options.root)
    lobby.options.module_path = strings.clone(options.module_path)
    lobby.options.database = strings.clone(options.database)
    lobby.options.name = strings.clone(options.name if options.name != "" else "host")
    lobby.options.room = strings.clone(options.room)
    lobby.kind = .HOST
    lobby.host = new(Host)
    if !HostBegin(lobby.host, lobby.options) {
        lobbyFail(lobby, lobby.host.error)
        return false
    }
    active_host = lobby.host
    lobby.endpoint = lobby.host.server.endpoint
    lobby.ready = true
    return true
}

// Begins joining a host by the code of its invite or by its room name; `LobbyUpdate` goes on. False with `LobbyError` set. `database` is the one the host publishes (the game client needs it).
LobbyJoin :: proc(lobby: ^Lobby, code: string, database: string, options: GuestOptions) -> bool {
    LobbyLeave(lobby)
    lobby.kind = .GUEST
    lobby.options.database = strings.clone(database)
    lobby.guest_name = strings.clone(options.name if options.name != "" else "guest")
    lobby.guest = new(Guest)
    trimmed: string = strings.trim_space(code)
    if trimmed == "" {
        lobbyFail(lobby, "paste the code of the host first")
        return false
    }
    guest_options: GuestOptions = options
    guest_options.name = lobby.guest_name
    began: bool = GuestBeginRoom(lobby.guest, trimmed, guest_options) if RoomLooksLike(trimmed) else GuestBegin(lobby.guest, trimmed, guest_options)
    if !began {
        lobbyFail(lobby, lobby.guest.error)
        return false
    }
    return true
}

// Once a frame: the link, the tunnel and the stages; a guest becomes `ready` here
LobbyUpdate :: proc(lobby: ^Lobby) {
    if lobby.failed { return }
    if lobby.host != nil { HostUpdate(lobby.host) }
    if lobby.guest != nil {
        GuestUpdate(lobby.guest)
        if lobby.guest.stage == .FAILED {
            lobbyFail(lobby, lobby.guest.error)
            return
        }
        if !lobby.ready && lobby.guest.stage == .CONNECTED && GuestStartTunnel(lobby.guest) {
            // the tunnel is the way to the server: the blocking calls of the client step it while they wait
            SetIdle(lobby.guest, active_host)
            lobby.endpoint = GuestEndpoint(lobby.guest)
            lobby.ready = true
        }
    }
}

// The step of the p2p connection of the host or the guest
LobbyStage :: proc(lobby: ^Lobby) -> Stage {
    if lobby.host != nil { return lobby.host.stage }
    if lobby.guest != nil { return lobby.guest.stage }
    return .IDLE
}

LobbyInvite :: proc(lobby: ^Lobby) -> string {
    return HostInvite(lobby.host) if lobby.host != nil else ""
}

LobbyRoom :: proc(lobby: ^Lobby) -> string {
    return HostRoom(lobby.host) if lobby.host != nil else ""
}

// The reply code of a guest: a host whose invite names no relay needs it
LobbyReply :: proc(lobby: ^Lobby) -> string {
    return GuestReply(lobby.guest) if lobby.guest != nil else ""
}

// A guest of an invite with no relay has to send its reply back to the host
LobbyNeedsReply :: proc(lobby: ^Lobby) -> bool {
    return lobby.guest != nil && !lobby.guest.room_mode && (lobby.guest.invite.derp_server == 0 || lobby.guest.options.no_derp)
}

// A host whose relay is up: a friend needs only the invite (or the room name), no reply
LobbyRelayReady :: proc(lobby: ^Lobby) -> bool {
    return lobby.host != nil && lobby.host.relay_used && lobby.host.link.derp.state == .READY
}

LobbyAcceptReply :: proc(lobby: ^Lobby, reply: string) -> bool {
    return lobby.host != nil && HostAcceptReply(lobby.host, strings.trim_space(reply))
}

// Friends whose connection is made
LobbyGuests :: proc(lobby: ^Lobby) -> int {
    return HostConnectedGuests(lobby.host) if lobby.host != nil else 0
}

// The last thing the link wanted to say (a relay that failed, a friend who joined or left)
LobbyNotice :: proc(lobby: ^Lobby) -> string {
    if lobby.host != nil { return HostNotice(lobby.host) }
    if lobby.guest != nil { return GuestNotice(lobby.guest) }
    return ""
}

// Who made the code that a person pasted (the name in it, or the room name); temp memory is not used: the text is in the lobby
LobbyCodeFrom :: proc(lobby: ^Lobby, text: string) -> string {
    _, from, _ := CodeInspect(text)
    return string(lobby.code[:copy(lobby.code[:], from)])
}
