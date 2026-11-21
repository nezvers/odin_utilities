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

Host :: struct {
    server: st.Server,
    link: ^p2p.Link,
    tunnel: ^tunnel.Tunnel,
    invite: [p2p.CODE_TEXT_MAX]u8,
    invite_length: int,
    error: string,
}

// Starts the server, publishes the module, opens the p2p side and makes the invite. False with `host.error` set.
HostStart :: proc(host: ^Host, options: HostOptions) -> bool {
    host^ = {}
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
    if options.derp { derpBegin(host.link) }
    gather(host.link, options.internet)
    p2p.LinkHost(host.link, options.name if options.name != "" else "host")
    text, encoded := p2p.InviteEncode(p2p.LinkMakeInvite(host.link), host.invite[:])
    if !encoded {
        host.error = "the invite does not fit"
        return false
    }
    host.invite_length = len(text)
    tunnel.TunnelHostInit(host.tunnel, host.link, {address = net.IP4_Loopback, port = port})
    return true
}

@(private)
parseLoopback :: proc() -> (address: [4]u8) {
    return {127, 0, 0, 1}
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

// Looks up the public address (STUN) and waits for the gathering: a few hundred milliseconds with the internet, up to 5 seconds without
@(private)
gather :: proc(link: ^p2p.Link, internet: bool) {
    servers: [p2p.STUN_MAX_SERVERS]net.Endpoint
    count: int
    if internet { count = p2p.LinkResolveStun(servers[:]) }
    p2p.LinkGatherBegin(link, servers[:count], p2p.LinkNow())
    for waited := 0; waited < 5000 && !p2p.LinkGathered(link); waited += 10 {
        p2p.LinkUpdate(link, p2p.LinkNow())
        time.sleep(10 * time.Millisecond)
    }
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

// Once a frame
HostUpdate :: proc(host: ^Host) {
    now: i64 = p2p.LinkNow()
    p2p.LinkUpdate(host.link, now)
    tunnel.TunnelUpdate(host.tunnel, now)
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
}

// Takes the invite code of a host; `guest.reply` (GuestReply) is the code to send back
GuestJoin :: proc(guest: ^Guest, invite_text: string, options: GuestOptions) -> bool {
    guest^ = {}
    invite, decoded := p2p.InviteDecode(invite_text)
    if !decoded {
        guest.error = "that is not an invite code"
        return false
    }
    guest.link = new(p2p.Link)
    guest.tunnel = new(tunnel.Tunnel)
    if !p2p.LinkInit(guest.link, {include_loopback = options.loopback}) {
        guest.error = "no UDP socket"
        return false
    }
    gather(guest.link, options.internet)
    if invite.derp_server != 0 && !options.no_derp {
        // the invite names a relay: connect to it first, the reply then goes through it by itself
        p2p.LinkDerpBeginInvite(guest.link, invite, p2p.LinkNow())
        for waited := 0; waited < 8000 && guest.link.derp.state == .CONNECTING; waited += 10 {
            p2p.LinkUpdate(guest.link, p2p.LinkNow())
            time.sleep(10 * time.Millisecond)
        }
    }
    if !p2p.LinkJoin(guest.link, invite, options.name if options.name != "" else "guest", p2p.LinkNow()) {
        guest.error = "the invite cannot be used"
        return false
    }
    text, encoded := p2p.InviteEncode(p2p.LinkMakeInvite(guest.link), guest.reply[:])
    if !encoded {
        guest.error = "the reply does not fit"
        return false
    }
    guest.reply_length = len(text)
    return true
}

GuestReply :: proc(guest: ^Guest) -> string {
    return string(guest.reply[:guest.reply_length])
}

// Once a frame (and while waiting for the connection)
GuestUpdate :: proc(guest: ^Guest) {
    now: i64 = p2p.LinkNow()
    p2p.LinkUpdate(guest.link, now)
    if guest.tunnel_started { tunnel.TunnelUpdate(guest.tunnel, now) }
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
