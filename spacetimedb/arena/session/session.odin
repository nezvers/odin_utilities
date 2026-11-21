#+build !js
package arena_session

// How the players of the arena get together, with no server of anybody's: the host starts a SpacetimeDB server on its own machine with the game module published, makes a p2p invite
// code and hands it out; a guest pastes the code, gets a reply code to send back, and then talks to the host's server through a tunnel over the p2p Link (a local port that is the other
// computer's database). The game client (arena/game) does not know the difference: it connects to an endpoint.
//
//     host:   HostStart(host, {name = "Ada"})  ->  HostInvite(host) is the code to give out  ->  HostAcceptReply(host, reply code of a guest)
//     guest:  GuestJoin(guest, invite code, "Bob") -> the reply code to send back  ->  GuestConnected(guest) -> GuestEndpoint(guest) is where the game connects
//     both:   HostUpdate(host) / GuestUpdate(guest) once a frame (and `SetIdle` for the blocking calls of the client, see below)
//
// The blocking calls of the client (an HTTP request, the websocket handshake) go through the tunnel too, so the thread that waits has to keep stepping the tunnel: `SetIdle(guest)` makes
// every wait of the client step it (spacetimedb.StreamIdle). A host process steps itself in its frame loop.

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"
import st "../.."
import "../../../p2p"
import "../../tunnel"

SERVER_PORT :: 3000

HostOptions :: struct {
    root: string,               // the folder of the server (its data and keys)
    port: int,                  // of the server on this machine (0: SERVER_PORT)
    module_path: string,        // the built game module ("": bin/arena-odin.wasm of the library)
    name: string,               // the name of the host in the p2p session
    internet: bool,             // gather the public address with STUN so that a guest on another network can connect (needs the internet at the start)
    derp: bool,                 // also use a free DERP relay (Tailscale, no account): the invite names it, a guest connects through it with no reply code to send back, even behind strict NATs
    loopback: bool,             // also offer 127.0.0.1: two programs on one computer (tests)
}

// Where a connection is, for a window that shows it (and for the loops of `HostStart` / `GuestJoin` that wait for it). The p2p side never blocks: `HostUpdate` / `GuestUpdate` move it on.
Stage :: enum u8 {
    IDLE,
    GATHERING,          // finding the addresses that a friend can reach (the network cards, the public one through STUN)
    RELAY,              // waiting for the free relay (DERP)
    READY,              // a host: the invite code is made; a guest: joined, the reply code is made, waiting for the host to answer
    CONNECTED,          // a guest: the host answered (a host counts its friends: HostGuests)
    FAILED,
}

STAGE_GATHER_MS :: 5000
STAGE_RELAY_MS :: 8000

Host :: struct {
    server: st.Server,
    link: ^p2p.Link,
    tunnel: ^tunnel.Tunnel,
    invite: [p2p.CODE_TEXT_MAX]u8,
    invite_length: int,
    error: string,
    stage: Stage,
    stage_started: time.Tick,
    options: HostOptions,
    port: int,
    relay_used: bool,
}

// Starts the server, publishes the module, opens the p2p side and makes the invite: `HostBegin` and then the waiting (a few hundred milliseconds with the internet). False with `host.error` set.
HostStart :: proc(host: ^Host, options: HostOptions) -> bool {
    if !HostBegin(host, options) { return false }
    for host.stage == .GATHERING || host.stage == .RELAY {
        HostUpdate(host)
        time.sleep(10 * time.Millisecond)
    }
    return host.stage == .READY
}

// The first part: the server (blocking, a second or two), the module, the link; then the stage is GATHERING and `HostUpdate` brings it to READY. False with `host.error` set.
HostBegin :: proc(host: ^Host, options: HostOptions) -> bool {
    host^ = {}
    host.options = options
    defer if host.error != "" { host.stage = .FAILED }
    module_path: string = options.module_path if options.module_path != "" else st.FixturePath("arena-odin")
    if module_path == "" || !os.exists(st.ServerCliPath()) {
        host.error = "the server or the module is not built: run `odin run spacetimedb/tool/setup`"
        return false
    }
    module, read_error := os.read_entire_file(module_path, context.allocator)
    if read_error != nil {
        host.error = "cannot read the module"
        return false
    }
    defer delete(module)
    port: int = options.port if options.port > 0 else SERVER_PORT
    log_file: string = fmt.tprintf("%s/server.log", options.root)
    os.make_directory_all(options.root)
    if !st.ServerStart(&host.server, {root = options.root, port = port, log_file = log_file}) {
        host.error = "the server does not start"
        if log, log_error := os.read_entire_file(log_file, context.temp_allocator); log_error == nil && len(log) > 0 {
            host.error = fmt.tprintf("the server does not start: %s", string(log[max(0, len(log) - 2500):]))
        }
        return false
    }
    response := make([]u8, 1 << 16)
    defer delete(response)
    // the identity that owns the database is kept in the folder of the server, so the next start can update the same database (the world of the last session is still there)
    token_file: string = fmt.tprintf("%s/owner.token", options.root)
    token: string
    if saved, saved_error := os.read_entire_file(token_file, context.temp_allocator); saved_error == nil && len(saved) > 20 {
        token = string(saved)
    } else {
        _, token_view, made := st.IdentityCreate(host.server.endpoint, response)
        if !made {
            host.error = "no identity"
            return false
        }
        token = strings.clone(string(token_view), context.temp_allocator)
        _ = os.write_entire_file(token_file, transmute([]u8)token)
    }
    published: st.HttpResult = st.DatabasePublish(host.server.endpoint, "arena", module, token, response)
    if !published.ok || published.status != 200 {
        host.error = fmt.tprintf("the module is not published: %s", string(published.body))
        return false
    }
    host.link = new(p2p.Link)
    host.tunnel = new(tunnel.Tunnel)
    if !p2p.LinkInit(host.link, {include_loopback = options.loopback}) {
        host.error = "no UDP socket"
        return false
    }
    if options.derp { host.relay_used = derpBegin(host.link) }
    gatherBegin(host.link, options.internet)
    host.port = port
    host.stage, host.stage_started = .GATHERING, time.tick_now()
    return true
}

// The invite is made once the addresses are known (and the relay is up, when one is used): the code then carries them
@(private)
hostFinish :: proc(host: ^Host) {
    p2p.LinkHost(host.link, host.options.name if host.options.name != "" else "host")
    text, encoded := p2p.InviteEncode(p2p.LinkMakeInvite(host.link), host.invite[:])
    if !encoded {
        host.error = "the invite does not fit"
        host.stage = .FAILED
        return
    }
    host.invite_length = len(text)
    tunnel.TunnelHostInit(host.tunnel, host.link, {address = net.IP4_Loopback, port = host.port})
    host.stage = .READY
}

HostElapsedMs :: proc(host: ^Host) -> int {
    return int(time.duration_milliseconds(time.tick_since(host.stage_started)))
}

// The fastest of a few relays, connected before the invite is made (the invite then carries it); the connection takes a moment, so the gathering waits for it
@(private)
derpBegin :: proc(link: ^p2p.Link) -> bool {
    candidates: [6]int = {4, 8, 1, 14, 22, 2}
    server: int = p2p.DerpRace(candidates[:], 6000)
    if server == 0 { return false }
    p2p.LinkDerpBegin(link, server, p2p.LinkNow())
    return true
}

// Looks up the public address (STUN) and starts the gathering; `LinkUpdate` finishes it
@(private)
gatherBegin :: proc(link: ^p2p.Link, internet: bool) {
    servers: [p2p.STUN_MAX_SERVERS]net.Endpoint
    count: int
    if internet { count = p2p.LinkResolveStun(servers[:]) }
    p2p.LinkGatherBegin(link, servers[:count], p2p.LinkNow())
}

// The code to hand out
HostInvite :: proc(host: ^Host) -> string {
    return string(host.invite[:host.invite_length])
}

// The reply code that a guest sent back: the guest is connected after a few updates
HostAcceptReply :: proc(host: ^Host, reply_text: string) -> bool {
    reply, decoded := p2p.InviteDecode(reply_text)
    if !decoded { return false }
    _, accepted := p2p.LinkAcceptReply(host.link, reply, p2p.LinkNow())
    return accepted
}

HostGuests :: proc(host: ^Host) -> int {
    return p2p.LinkPeerCount(host.link)
}

// Once a frame: the link, the tunnel, and the stage (GATHERING, RELAY, READY)
HostUpdate :: proc(host: ^Host) {
    now: i64 = p2p.LinkNow()
    p2p.LinkUpdate(host.link, now)
    tunnel.TunnelUpdate(host.tunnel, now)
    switch host.stage {
    case .GATHERING:
        if p2p.LinkGathered(host.link) || HostElapsedMs(host) > STAGE_GATHER_MS {
            if host.relay_used && host.link.derp.state == .CONNECTING {
                host.stage, host.stage_started = .RELAY, time.tick_now()
            } else {
                hostFinish(host)
            }
        }
    case .RELAY:
        if host.link.derp.state != .CONNECTING || HostElapsedMs(host) > STAGE_RELAY_MS { hostFinish(host) }
    case .IDLE, .READY, .CONNECTED, .FAILED:
    }
}

HostStop :: proc(host: ^Host) {
    if host.tunnel != nil {
        tunnel.TunnelClose(host.tunnel)
        free(host.tunnel)
    }
    if host.link != nil {
        p2p.LinkClose(host.link)
        free(host.link)
    }
    st.ServerStop(&host.server)
    host^ = {}
}

GuestOptions :: struct {
    no_derp: bool,              // ignore the relay that the invite names
    internet: bool,
    loopback: bool,
    name: string,
}

Guest :: struct {
    link: ^p2p.Link,
    tunnel: ^tunnel.Tunnel,
    reply: [p2p.CODE_TEXT_MAX]u8,
    reply_length: int,
    tunnel_started: bool,
    error: string,
    stage: Stage,
    stage_started: time.Tick,
    invite: p2p.Invite,
    options: GuestOptions,
    name: [32]u8,
    name_length: int,
}

// Takes the invite code of a host and waits until the reply code is made (`GuestBegin` and the waiting); `guest.reply` (GuestReply) is the code to send back
GuestJoin :: proc(guest: ^Guest, invite_text: string, options: GuestOptions) -> bool {
    if !GuestBegin(guest, invite_text, options) { return false }
    for guest.stage == .GATHERING || guest.stage == .RELAY {
        GuestUpdate(guest)
        time.sleep(10 * time.Millisecond)
    }
    return guest.stage == .READY || guest.stage == .CONNECTED
}

// Decodes the code and opens the link; the stage is GATHERING and `GuestUpdate` brings it to READY. False with `guest.error` set.
GuestBegin :: proc(guest: ^Guest, invite_text: string, options: GuestOptions) -> bool {
    guest^ = {}
    guest.options = options
    guest.name_length = copy(guest.name[:], options.name if options.name != "" else "guest")
    invite, decoded := p2p.InviteDecode(invite_text)
    if !decoded {
        guest.error, guest.stage = "that is not an invite code", .FAILED
        return false
    }
    guest.invite = invite
    guest.link = new(p2p.Link)
    guest.tunnel = new(tunnel.Tunnel)
    if !p2p.LinkInit(guest.link, {include_loopback = options.loopback}) {
        guest.error, guest.stage = "no UDP socket", .FAILED
        return false
    }
    gatherBegin(guest.link, options.internet)
    // the invite names a relay: connect to it too, the reply then goes through it by itself
    if invite.derp_server != 0 && !options.no_derp { p2p.LinkDerpBeginInvite(guest.link, invite, p2p.LinkNow()) }
    guest.stage, guest.stage_started = .GATHERING, time.tick_now()
    return true
}

GuestElapsedMs :: proc(guest: ^Guest) -> int {
    return int(time.duration_milliseconds(time.tick_since(guest.stage_started)))
}

@(private)
guestFinish :: proc(guest: ^Guest) {
    if !p2p.LinkJoin(guest.link, guest.invite, string(guest.name[:guest.name_length]), p2p.LinkNow()) {
        guest.error, guest.stage = "the invite cannot be used", .FAILED
        return
    }
    text, encoded := p2p.InviteEncode(p2p.LinkMakeInvite(guest.link), guest.reply[:])
    if !encoded {
        guest.error, guest.stage = "the reply does not fit", .FAILED
        return
    }
    guest.reply_length = len(text)
    guest.stage = .READY
}

GuestReply :: proc(guest: ^Guest) -> string {
    return string(guest.reply[:guest.reply_length])
}

// Once a frame (and while waiting for the connection): the link, the tunnel and the stage (GATHERING, RELAY, READY, CONNECTED)
GuestUpdate :: proc(guest: ^Guest) {
    now: i64 = p2p.LinkNow()
    p2p.LinkUpdate(guest.link, now)
    if guest.tunnel_started { tunnel.TunnelUpdate(guest.tunnel, now) }
    relay_wanted: bool = guest.invite.derp_server != 0 && !guest.options.no_derp
    switch guest.stage {
    case .GATHERING:
        if p2p.LinkGathered(guest.link) || GuestElapsedMs(guest) > STAGE_GATHER_MS {
            if relay_wanted && guest.link.derp.state == .CONNECTING {
                guest.stage, guest.stage_started = .RELAY, time.tick_now()
            } else {
                guestFinish(guest)
            }
        }
    case .RELAY:
        if guest.link.derp.state != .CONNECTING || GuestElapsedMs(guest) > STAGE_RELAY_MS { guestFinish(guest) }
    case .READY:
        if p2p.LinkPeerCount(guest.link) == 1 { guest.stage = .CONNECTED }
    case .IDLE, .CONNECTED, .FAILED:
    }
}

GuestConnected :: proc(guest: ^Guest) -> bool {
    return p2p.LinkPeerCount(guest.link) == 1
}

// Opens the local port that is the host's database (when the p2p connection is up). The game connects to `GuestEndpoint`.
GuestStartTunnel :: proc(guest: ^Guest, port: int = 0) -> bool {
    if guest.tunnel_started { return true }
    if !GuestConnected(guest) || !tunnel.TunnelGuestInit(guest.tunnel, guest.link, 0, port) { return false }
    guest.tunnel_started = true
    return true
}

GuestEndpoint :: proc(guest: ^Guest) -> st.Endpoint {
    return {host = "127.0.0.1", port = guest.tunnel.port}
}

GuestStop :: proc(guest: ^Guest) {
    if guest.tunnel != nil {
        if guest.tunnel_started { tunnel.TunnelClose(guest.tunnel) }
        free(guest.tunnel)
    }
    if guest.link != nil {
        p2p.LinkClose(guest.link)
        free(guest.link)
    }
    guest^ = {}
}

// Makes the blocking calls of the client (HTTP, the websocket handshake) step this guest while they wait: the tunnel is the way to the server, and this thread is the one that moves it
SetIdle :: proc(guest: ^Guest, host: ^Host = nil) {
    Pair :: struct {
        guest: ^Guest,
        host: ^Host,
    }
    @(static) pair: Pair
    pair = {guest, host}
    st.StreamIdle = proc(user: rawptr) {
        pair: ^Pair = cast(^Pair)user
        if pair.guest != nil { GuestUpdate(pair.guest) }
        if pair.host != nil { HostUpdate(pair.host) }       // one process that is both (a test): the host side is stepped too
    }
    st.StreamIdleUser = &pair
}

ClearIdle :: proc() {
    st.StreamIdle = nil
    st.StreamIdleUser = nil
}
