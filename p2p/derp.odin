// A DERP client: Tailscale's public relays as a free, account-less relay for p2p. Same idea as the derpnet reference
// (https://github.com/mmozeiko/derpnet, Windows only, SChannel TLS); here it runs on Windows, Linux and macOS through tls13.odin.
//
// What DERP is: a server that forwards small packets between clients that are addressed by their Curve25519 PUBLIC KEY (no account,
// no registration: a client just proves it owns a key). Two peers that know each other's public key and are connected to the same
// relay can exchange packets even when both are behind NAT. The relay only sees who talks to whom and how much, the content is sealed
// end to end with NaCl box (nacl.odin): [nonce 24][auth 16][ciphertext], the same layout as derpnet and Tailscale use.
// It is a relay of last resort (a few hundred KB/s, a detour through a data center): p2p uses it to get connected and keeps trying a
// direct path, like with TURN.
//
// Connection: TCP 443 -> TLS 1.3 -> "GET /derp" with "Upgrade: DERP" and "Derp-Fast-Start: 1" -> frames [type u8][length u32 BE][body].
//   server: ServerKey(1) = magic "DERP" + key emoji bytes (8) + server public key (32)
//   client: ClientInfo(2) = our public key (32) + nonce (24) + box({"version":2}) sealed to the server key
//   server: ServerInfo(3) = nonce (24) + box(...) : proves the server holds the key it announced
//   then SendPacket(4) = destination key (32) + packet; RecvPacket(5) = source key (32) + packet
//   also KeepAlive(6), PeerGone(8), Ping(0x12) which must be answered with Pong(0x13) carrying the same 8 bytes, Health(0x14), Restarting(0x15)
//
// The handshake blocks (DNS, TCP connect, TLS, a few round trips, up to about 10 s): DerpBegin runs it on a thread and the Link polls
// DerpState; after that DerpSend / DerpPoll are non blocking and called from one thread.
package p2p

import "core:fmt"
import "core:net"
import "core:strings"
import "core:os"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

DERP_FRAME_SERVER_KEY :: u8(0x01)
DERP_FRAME_CLIENT_INFO :: u8(0x02)
DERP_FRAME_SERVER_INFO :: u8(0x03)
DERP_FRAME_SEND_PACKET :: u8(0x04)
DERP_FRAME_RECV_PACKET :: u8(0x05)
DERP_FRAME_KEEP_ALIVE :: u8(0x06)
DERP_FRAME_PEER_GONE :: u8(0x08)
DERP_FRAME_PING :: u8(0x12)
DERP_FRAME_PONG :: u8(0x13)
DERP_FRAME_HEALTH :: u8(0x14)
DERP_FRAME_RESTARTING :: u8(0x15)

DERP_MAGIC :: "DERP\xf0\x9f\x94\x91"
DERP_FRAME_MAX :: 2048                   // bigger frames (other people's packets) are skipped, ours stay under MAX_PAYLOAD
DERP_PACKET_OVERHEAD :: BOX_NONCE_SIZE + BOX_AUTH_SIZE
DERP_TIMEOUT_MS :: 8000
DERP_PING_MS :: 25000                    // a Ping to the server now and then keeps NATs and the relay from forgetting us

// One node per region (https://login.tailscale.com/derpmap/default). Two peers must use the same entry (same region is enough for
// Tailscale, the nodes of a region forward to each other, but one host is the simplest and the only thing tested). The index travels in
// invites: never reorder, only append.
DerpServer :: struct {
    host: string,
    place: string,
}

DERP_SERVERS := [?]DerpServer{
    {"derp1f.tailscale.com", "New York"},
    {"derp2d.tailscale.com", "San Francisco"},
    {"derp3e.tailscale.com", "Singapore"},
    {"derp4f.tailscale.com", "Frankfurt"},
    {"derp5e.tailscale.com", "Sydney"},
    {"derp6b.tailscale.com", "Mumbai"},
    {"derp7e.tailscale.com", "Tokyo"},
    {"derp8e.tailscale.com", "London"},
    {"derp9d.tailscale.com", "Dallas"},
    {"derp10b.tailscale.com", "Seattle"},
    {"derp11e.tailscale.com", "Sao Paulo"},
    {"derp12d.tailscale.com", "Chicago"},
    {"derp13b.tailscale.com", "Denver"},
    {"derp14b.tailscale.com", "Amsterdam"},
    {"derp15b.tailscale.com", "Johannesburg"},
    {"derp16b.tailscale.com", "Miami"},
    {"derp17b.tailscale.com", "Los Angeles"},
    {"derp18b.tailscale.com", "Paris"},
    {"derp19b.tailscale.com", "Madrid"},
    {"derp20b.tailscale.com", "Hong Kong"},
    {"derp21b.tailscale.com", "Toronto"},
    {"derp22b.tailscale.com", "Warsaw"},
    {"derp23b.tailscale.com", "Dubai"},
    {"derp24b.tailscale.com", "Honolulu"},
    {"derp25b.tailscale.com", "Nairobi"},
    {"derp26b.tailscale.com", "Nuremberg"},
    {"derp27b.tailscale.com", "Ashburn"},
    {"derp28b.tailscale.com", "Helsinki"},
}

// Why a connection failed, so a program (and the person) can tell "my network" from "the relay is gone or changed".
DerpFailure :: enum {
    NONE,
    NO_NETWORK,                          // the name does not resolve or TCP to the relay did not connect
    TLS,                                 // connected, but no TLS 1.3 handshake
    TIMEOUT,                             // it stopped answering
    NOT_DERP,                            // an answer, but not the DERP protocol (it moved, an error page, no longer offered there)
    REFUSED,                             // DERP, but it did not accept this client
    CLOSED,                              // an established connection ended
}

DerpAdvice :: proc(kind: DerpFailure) -> string {
    switch kind {
    case .NONE:
        return ""
    case .NO_NETWORK:
        return "No connection to the relay. Check the network: a firewall or proxy must allow outgoing TCP 443, and the name must resolve. If this relay is gone, use another one (--derp N, or --derp-host name for any DERP server)."
    case .TLS:
        return "The relay did not complete a TLS 1.3 handshake. It may be down, overloaded, or something on the network interferes with HTTPS. Try another relay."
    case .TIMEOUT:
        return "The relay stopped answering in time. It may be overloaded or the network drops this traffic. Try another relay."
    case .NOT_DERP:
        return "The server answered, but not with the DERP protocol: it has moved or no longer offers DERP at that address. Get the current list with `odin run p2p/tool/derp -- map`, or run your own relay (derper, see p2p/README.md) and pass it with --derp-host."
    case .REFUSED:
        return "The relay speaks DERP but refused this client, possibly because it now only accepts devices of its own network. A relay of your own (derper accepts anybody by default) or another public one will work; direct connections and pasted codes still work without any relay."
    case .CLOSED:
        return "The relay connection ended. It is reconnected automatically; if that keeps failing the relay is down or the network changed."
    }
    return ""
}

DerpState :: enum {
    IDLE,
    CONNECTING,                          // the thread is doing DNS / TCP / TLS / handshake
    READY,
    FAILED,                              // see `failure`
    CLOSED,
}

DerpPacket :: struct {
    from: BoxKey,                        // the sender's public key
    length: int,                         // bytes of the opened packet in `data`
}

Derp :: struct {
    state: DerpState,                    // written by the connect thread, read through DerpGetState
    tls: Tls,
    socket: net.TCP_Socket,
    private: BoxKey,
    public: BoxKey,
    server_public: BoxKey,
    host: [64]byte,
    host_length: int,
    failure: string,
    failure_kind: DerpFailure,
    http_status: int,                    // when the server answered HTTP instead of DERP: its status code
    thread: ^thread.Thread,
    frame: [5 + DERP_FRAME_MAX]byte,     // the frame being assembled
    frame_length: int,
    skip: int,                           // bytes of an oversized frame still to throw away
    peer: BoxKey,                        // the shared key of the last peer talked to (computing it costs a scalar multiplication)
    peer_shared: BoxKey,
    has_peer: bool,
    ping_ms: i64,
    sent: u64,
    received: u64,
    connect_ms: i64,                     // how long the connection took, for reports
    abandoned: bool,                     // DerpRace: nobody wants this connection any more (atomic)
    closed: bool,                        // the connection was closed already, by whoever came first (atomic)
}

DerpGetState :: proc(derp: ^Derp) -> DerpState {
    return sync.atomic_load(&derp.state)
}

@(private)
DerpSetState :: proc(derp: ^Derp, state: DerpState) {
    sync.atomic_store(&derp.state, state)
}

// ---------------------------------------------------------------------------------------------------------------- frames (pure)

DerpFrameHeader :: proc(buffer: []byte, kind: u8, length: int) {
    buffer[0] = kind
    buffer[1] = u8(length >> 24)
    buffer[2] = u8(length >> 16)
    buffer[3] = u8(length >> 8)
    buffer[4] = u8(length)
}

// A ClientInfo frame: our key, then the JSON sealed to the server. Returns its length.
DerpClientInfo :: proc(out: []byte, private: BoxKey, public: BoxKey, server_public: BoxKey, nonce: [BOX_NONCE_SIZE]byte) -> int {
    info: string = `{"version":2}`
    length: int = 32 + BOX_NONCE_SIZE + BOX_AUTH_SIZE + len(info)
    DerpFrameHeader(out, DERP_FRAME_CLIENT_INFO, length)
    public_copy: BoxKey = public
    copy(out[5:], public_copy[:])
    nonce_copy: [BOX_NONCE_SIZE]byte = nonce
    copy(out[5 + 32:], nonce_copy[:])
    BoxSeal(out[5 + 32 + BOX_NONCE_SIZE:], transmute([]byte)info, nonce, BoxShared(private, server_public))
    return 5 + length
}

// A SendPacket frame towards `peer`: the data is sealed for that peer. `shared` is BoxShared(our private, peer public).
DerpSendFrame :: proc(out: []byte, peer: BoxKey, shared: BoxKey, nonce: [BOX_NONCE_SIZE]byte, data: []byte) -> int {
    length: int = 32 + DERP_PACKET_OVERHEAD + len(data)
    assert(len(out) >= 5 + length)
    DerpFrameHeader(out, DERP_FRAME_SEND_PACKET, length)
    peer_copy: BoxKey = peer
    copy(out[5:], peer_copy[:])
    nonce_copy: [BOX_NONCE_SIZE]byte = nonce
    copy(out[5 + 32:], nonce_copy[:])
    BoxSeal(out[5 + 32 + BOX_NONCE_SIZE:], data, nonce, shared)
    return 5 + length
}

// ---------------------------------------------------------------------------------------------------------------- connecting

// Blocking. Resolves, connects, TLS, upgrade, key exchange. `private` is our identity (BoxKeyGenerate, or any 32 bytes you keep).
DerpOpen :: proc(derp: ^Derp, host: string, private: BoxKey) -> bool {
    derp^ = {private = private}
    derp.host_length = min(len(host), len(derp.host))
    copy(derp.host[:derp.host_length], host)
    return DerpConnect(derp)
}

// The connection itself, for the host and key already stored in `derp` (DerpOpen and the thread of DerpBegin both end up here).
@(private)
DerpConnect :: proc(derp: ^Derp) -> bool {
    host_and_port: string = string(derp.host[:derp.host_length])
    host, port := DerpSplitHost(host_and_port)
    derp.public = BoxPublicKey(derp.private)
    derp.failure = ""
    derp.failure_kind = .NONE
    derp.http_status = 0
    DerpSetState(derp, .CONNECTING)
    start: time.Tick = time.tick_now()
    fail :: proc(derp: ^Derp, kind: DerpFailure, why: string) -> bool {
        derp.failure = why
        derp.failure_kind = kind
        if derp.tls.socket != {} {
            net.close(derp.tls.socket)
        }
        DerpSetState(derp, .FAILED)
        return false
    }

    socket, dial_error := net.dial_tcp_from_hostname_with_port_override(host, port)
    if dial_error != nil {
        return fail(derp, .NO_NETWORK, fmt.aprintf("cannot connect to %s: %v", host_and_port, dial_error))
    }
    derp.socket = socket
    net.set_option(socket, .Receive_Timeout, time.Millisecond * DERP_TIMEOUT_MS)
    net.set_option(socket, .Send_Timeout, time.Millisecond * DERP_TIMEOUT_MS)
    tls: ^Tls = &derp.tls
    if !TlsConnect(tls, socket, host) {
        net.close(socket)
        derp.failure = tls.failure
        derp.failure_kind = .TIMEOUT if strings.contains(tls.failure, "stopped answering") else .TLS
        DerpSetState(derp, .FAILED)
        return false
    }
    request: string = fmt.tprintf("GET /derp HTTP/1.1\r\nHost: %s\r\nConnection: Upgrade\r\nUpgrade: DERP\r\nDerp-Fast-Start: 1\r\n\r\n", host_and_port)
    if !TlsWrite(tls, transmute([]byte)request) {
        return fail(derp, .CLOSED, "cannot send the upgrade request")
    }

    // ServerKey
    kind, length, ok := DerpReadFirst(derp)
    if derp.http_status != 0 && derp.http_status != 101 {
        return fail(derp, .NOT_DERP, fmt.aprintf("the server answered HTTP %d instead of DERP", derp.http_status))
    }
    if !ok && tls.failure != "" && strings.contains(tls.failure, "stopped answering") {
        return fail(derp, .TIMEOUT, "the relay did not send its key in time")
    }
    if !ok || kind != DERP_FRAME_SERVER_KEY || length < 8 + 32 || string(derp.frame[5:13]) != DERP_MAGIC {
        return fail(derp, .NOT_DERP, "the server did not send a DERP key (not a DERP server, or the protocol changed)")
    }
    copy(derp.server_public[:], derp.frame[13:13 + 32])

    info: [5 + 32 + BOX_NONCE_SIZE + BOX_AUTH_SIZE + 32]byte
    info_length: int = DerpClientInfo(info[:], derp.private, derp.public, derp.server_public, BoxNonce())
    if !TlsWrite(tls, info[:info_length]) {
        return fail(derp, .CLOSED, "cannot send our key to the relay")
    }

    // ServerInfo: opening it proves the server owns the key it announced (and that ours was accepted)
    derp.frame_length = 0
    kind, length, ok = DerpReadFrameBlocking(derp)
    if !ok || kind != DERP_FRAME_SERVER_INFO || length < BOX_NONCE_SIZE + BOX_AUTH_SIZE {
        return fail(derp, .REFUSED, "the relay refused our key (it closed the connection or sent no ServerInfo)")
    }
    nonce: [BOX_NONCE_SIZE]byte
    copy(nonce[:], derp.frame[5:5 + BOX_NONCE_SIZE])
    opened: [DERP_FRAME_MAX]byte
    if !BoxOpen(opened[:], derp.frame[5 + BOX_NONCE_SIZE:5 + length], nonce, BoxShared(derp.private, derp.server_public)) {
        return fail(derp, .REFUSED, "the relay answer does not verify")
    }
    derp.frame_length = 0
    net.set_blocking(socket, false)
    derp.connect_ms = i64(time.duration_milliseconds(time.tick_since(start)))
    derp.ping_ms = DerpNow()
    DerpSetState(derp, .READY)
    return true
}

@(private)
DerpNow :: proc() -> i64 {
    return LinkNow()
}

// "name" or "name:port" (443 when no port).
DerpSplitHost :: proc(host_and_port: string) -> (host: string, port: int) {
    colon: int = strings.last_index_byte(host_and_port, ':')
    if colon <= 0 || colon == len(host_and_port) - 1 {
        return host_and_port, 443
    }
    number: int
    for c in host_and_port[colon + 1:] {
        if c < '0' || c > '9' || number > 65535 {
            return host_and_port, 443
        }
        number = number * 10 + int(c - '0')
    }
    return host_and_port[:colon], number if number > 0 && number < 65536 else 443
}

// The status code of an HTTP answer ("HTTP/1.1 302 Found"), 0 when it is not one.
DerpHttpStatus :: proc(head: []byte) -> int {
    if len(head) < 12 || string(head[:5]) != "HTTP/" {
        return 0
    }
    space: int = -1
    for i in 5 ..< len(head) {
        if head[i] == ' ' {
            space = i
            break
        }
    }
    if space < 0 || space + 4 > len(head) {
        return 0
    }
    status: int
    for i in space + 1 ..< space + 4 {
        if head[i] < '0' || head[i] > '9' {
            return 0
        }
        status = status * 10 + int(head[i] - '0')
    }
    return status
}

// The first thing a relay sends. Normally a ServerKey frame (we asked for "fast start"), but a server without that feature answers
// "101 Switching Protocols" first, and a server that changed or moved answers an error page: both are recognised and reported.
@(private)
DerpReadFirst :: proc(derp: ^Derp) -> (kind: u8, length: int, ok: bool) {
    derp.frame_length = 0
    for derp.frame_length < 5 {
        count: int = TlsRead(&derp.tls, derp.frame[derp.frame_length:5], true)
        if count <= 0 {
            return
        }
        derp.frame_length += count
    }
    if string(derp.frame[:4]) == "HTTP" {
        head: [2048]byte
        copy(head[:5], derp.frame[:5])
        used: int = 5
        for used < len(head) && !(used >= 4 && string(head[used - 4:used]) == "\r\n\r\n") {
            count: int = TlsRead(&derp.tls, head[used:used + 1], true)
            if count <= 0 {
                return
            }
            used += count
        }
        derp.http_status = DerpHttpStatus(head[:used])
        if derp.http_status != 101 {
            return
        }
        derp.frame_length = 0
    }
    return DerpReadFrameBlocking(derp)
}

// One whole frame into derp.frame (header included), waiting for it. Only for the handshake.
@(private)
DerpReadFrameBlocking :: proc(derp: ^Derp) -> (kind: u8, length: int, ok: bool) {
    for derp.frame_length < 5 {
        count: int = TlsRead(&derp.tls, derp.frame[derp.frame_length:5], true)
        if count <= 0 {
            return
        }
        derp.frame_length += count
    }
    kind = derp.frame[0]
    length = int(derp.frame[1]) << 24 | int(derp.frame[2]) << 16 | int(derp.frame[3]) << 8 | int(derp.frame[4])
    if length > DERP_FRAME_MAX {
        return
    }
    for derp.frame_length < 5 + length {
        count: int = TlsRead(&derp.tls, derp.frame[derp.frame_length:5 + length], true)
        if count <= 0 {
            return
        }
        derp.frame_length += count
    }
    return kind, length, true
}

@(private)
DerpThread :: proc(data: rawptr) {
    derp: ^Derp = cast(^Derp)data
    DerpConnect(derp)
    if sync.atomic_load(&derp.abandoned) {
        DerpCloseConnection(derp)
    }
}

// Closes the TLS connection and the socket once, whoever asks first (the connect thread of a lost race, or its owner).
@(private)
DerpCloseConnection :: proc(derp: ^Derp) {
    if DerpGetState(derp) != .READY || sync.atomic_exchange(&derp.closed, true) {
        return
    }
    TlsClose(&derp.tls)
    net.close(derp.socket)
    DerpSetState(derp, .CLOSED)
}

// Which relay answers fastest from here: connects to the candidates (server numbers, 1 = the first of DERP_SERVERS) all at once and
// returns the first that is ready, 0 when none was within `timeout_ms`. The attempts that lose close themselves when they finish.
// Their memory (about 110 KB each) is not given back: this is a start-up helper for a tool, not something to call in a loop.
DerpRace :: proc(candidates: []int, timeout_ms: i64) -> int {
    clients: [8]^Derp
    count: int = min(len(candidates), len(clients))
    for i in 0 ..< count {
        if candidates[i] < 1 || candidates[i] > len(DERP_SERVERS) {
            continue
        }
        private, public: BoxKey
        BoxKeyGenerate(&private, &public)
        clients[i] = new(Derp)
        DerpBegin(clients[i], DERP_SERVERS[candidates[i] - 1].host, private)
    }
    winner: int
    start: time.Tick = time.tick_now()
    for winner == 0 && i64(time.duration_milliseconds(time.tick_since(start))) < timeout_ms {
        for i in 0 ..< count {
            if clients[i] != nil && DerpGetState(clients[i]) == .READY {
                winner = candidates[i]
                break
            }
        }
        if winner == 0 {
            time.sleep(10 * time.Millisecond)
        }
    }
    for i in 0 ..< count {
        if clients[i] != nil {
            sync.atomic_store(&clients[i].abandoned, true)
            DerpCloseConnection(clients[i])
        }
    }
    return winner
}

// Starts connecting on a thread. Poll DerpGetState: READY, or FAILED with `failure`.
DerpBegin :: proc(derp: ^Derp, host: string, private: BoxKey) {
    derp^ = {private = private}
    derp.host_length = min(len(host), len(derp.host))
    copy(derp.host[:derp.host_length], host)
    DerpSetState(derp, .CONNECTING)
    derp.thread = thread.create_and_start_with_data(derp, DerpThread)
}

DerpClose :: proc(derp: ^Derp) {
    if derp.thread != nil {
        thread.join(derp.thread)
        thread.destroy(derp.thread)
        derp.thread = nil
    }
    DerpCloseConnection(derp)
    DerpSetState(derp, .CLOSED)
}

// ---------------------------------------------------------------------------------------------------------------- send / receive

// Sealed packet towards a peer (identified by its public key). False: the connection is gone or the packet is too big.
DerpSend :: proc(derp: ^Derp, peer: BoxKey, data: []byte) -> bool {
    if DerpGetState(derp) != .READY || len(data) > DERP_FRAME_MAX - 5 - 32 - DERP_PACKET_OVERHEAD {
        return false
    }
    if !derp.has_peer || derp.peer != peer {
        derp.peer = peer
        derp.peer_shared = BoxShared(derp.private, peer)
        derp.has_peer = true
    }
    frame: [5 + DERP_FRAME_MAX]byte
    length: int = DerpSendFrame(frame[:], peer, derp.peer_shared, BoxNonce(), data)
    if !TlsWrite(&derp.tls, frame[:length]) {
        derp.failure = derp.tls.failure
        DerpSetState(derp, .FAILED)
        return false
    }
    derp.sent += u64(len(data))
    return true
}

// The next packet from a peer, opened into `out`. ok=false: nothing now. closed=true: the relay connection ended (reconnect to go on).
// Packets that do not verify (a peer that guessed our key, damaged data) are dropped. Answers the relay's Ping on the way.
DerpPoll :: proc(derp: ^Derp, out: []byte) -> (packet: DerpPacket, ok: bool, closed: bool) {
    if DerpGetState(derp) != .READY {
        return {}, false, DerpGetState(derp) != .CONNECTING
    }
    now: i64 = DerpNow()
    if now - derp.ping_ms >= DERP_PING_MS {
        derp.ping_ms = now
        ping: [5 + 8]byte
        DerpFrameHeader(ping[:], DERP_FRAME_PING, 8)
        for i in 0 ..< 8 {
            ping[5 + i] = u8(now >> uint(8 * i))
        }
        TlsWrite(&derp.tls, ping[:])
    }
    for {
        // bytes of the frame in progress
        if derp.skip > 0 {
            count: int = TlsReadSkip(derp)
            if count < 0 {
                return {}, false, DerpFail(derp)
            }
            if derp.skip > 0 {
                return {}, false, false
            }
        }
        want: int = 5
        if derp.frame_length >= 5 {
            length: int = int(derp.frame[1]) << 24 | int(derp.frame[2]) << 16 | int(derp.frame[3]) << 8 | int(derp.frame[4])
            if length > DERP_FRAME_MAX {
                // not ours to read: throw the body away without buffering it
                derp.skip = length - (derp.frame_length - 5)
                derp.frame_length = 0
                continue
            }
            want = 5 + length
        }
        if derp.frame_length < want {
            count: int = TlsRead(&derp.tls, derp.frame[derp.frame_length:want], false)
            if count < 0 {
                return {}, false, DerpFail(derp)
            }
            if count == 0 {
                return {}, false, false
            }
            derp.frame_length += count
            continue
        }
        // a whole frame
        kind: u8 = derp.frame[0]
        body: []byte = derp.frame[5:want]
        derp.frame_length = 0
        switch kind {
        case DERP_FRAME_RECV_PACKET:
            if len(body) >= 32 + DERP_PACKET_OVERHEAD && len(body) - 32 - DERP_PACKET_OVERHEAD <= len(out) {
                from: BoxKey
                copy(from[:], body[:32])
                nonce: [BOX_NONCE_SIZE]byte
                copy(nonce[:], body[32:32 + BOX_NONCE_SIZE])
                if !derp.has_peer || derp.peer != from {
                    derp.peer = from
                    derp.peer_shared = BoxShared(derp.private, from)
                    derp.has_peer = true
                }
                if BoxOpen(out, body[32 + BOX_NONCE_SIZE:], nonce, derp.peer_shared) {
                    derp.received += u64(len(body))
                    return {from = from, length = len(body) - 32 - DERP_PACKET_OVERHEAD}, true, false
                }
            }
        case DERP_FRAME_PING:
            if len(body) == 8 {
                pong: [5 + 8]byte
                DerpFrameHeader(pong[:], DERP_FRAME_PONG, 8)
                copy(pong[5:], body)
                TlsWrite(&derp.tls, pong[:])
            }
        case DERP_FRAME_RESTARTING:
            return {}, false, DerpFail(derp)
        }
        // KeepAlive, PeerGone, Health, Pong and unknown frames need nothing
    }
}

@(private)
DerpFail :: proc(derp: ^Derp) -> bool {
    derp.failure = derp.tls.failure
    DerpSetState(derp, .FAILED)
    return true
}

// Throws away the rest of an oversized frame.
@(private)
TlsReadSkip :: proc(derp: ^Derp) -> int {
    scratch: [512]byte
    for derp.skip > 0 {
        count: int = TlsRead(&derp.tls, scratch[:min(len(scratch), derp.skip)], false)
        if count < 0 {
            return -1
        }
        if count == 0 {
            return 0
        }
        derp.skip -= count
    }
    return 0
}

// ---------------------------------------------------------------------------------------------------------------- tests

@(test)
DerpFramesTest :: proc(t: ^testing.T) {
    alice, alice_public, bob, bob_public, server, server_public: BoxKey
    testing.expect(t, BoxKeyGenerate(&alice, &alice_public))
    testing.expect(t, BoxKeyGenerate(&bob, &bob_public))
    testing.expect(t, BoxKeyGenerate(&server, &server_public))

    // ClientInfo: the server (who knows its private key) opens what the client sealed
    info: [5 + 32 + 24 + 16 + 32]byte
    nonce: [BOX_NONCE_SIZE]byte = BoxNonce()
    length: int = DerpClientInfo(info[:], alice, alice_public, server_public, nonce)
    testing.expect_value(t, info[0], DERP_FRAME_CLIENT_INFO)
    testing.expect_value(t, int(info[4]), length - 5)
    testing.expect_value(t, string(info[5:37]), string(alice_public[:]))
    opened: [64]byte
    testing.expect(t, BoxOpen(opened[:], info[5 + 32 + 24:length], nonce, BoxShared(server, alice_public)))
    testing.expect_value(t, string(opened[:13]), `{"version":2}`)

    // SendPacket towards bob: the layout of derpnet, and bob can open it
    data: string = "hello through the relay"
    frame: [256]byte
    sent: int = DerpSendFrame(frame[:], bob_public, BoxShared(alice, bob_public), nonce, transmute([]byte)data)
    testing.expect_value(t, frame[0], DERP_FRAME_SEND_PACKET)
    testing.expect_value(t, sent, 5 + 32 + 24 + 16 + len(data))
    testing.expect_value(t, int(frame[3]) << 8 | int(frame[4]), sent - 5)
    testing.expect_value(t, string(frame[5:37]), string(bob_public[:]))
    packet: [64]byte
    testing.expect(t, BoxOpen(packet[:], frame[5 + 32 + 24:sent], nonce, BoxShared(bob, alice_public)))
    testing.expect_value(t, string(packet[:len(data)]), data)
    // a third party cannot read it
    stranger, stranger_public: BoxKey
    testing.expect(t, BoxKeyGenerate(&stranger, &stranger_public))
    testing.expect(t, !BoxOpen(packet[:], frame[5 + 32 + 24:sent], nonce, BoxShared(stranger, alice_public)))
}

// Against a real public relay, only when asked for (P2P_LIVE=1): the network is not part of the normal test run.
@(test)
DerpLiveTest :: proc(t: ^testing.T) {
    if os.get_env("P2P_LIVE", context.temp_allocator) == "" {
        return
    }
    private_a, public_a, private_b, public_b: BoxKey
    testing.expect(t, BoxKeyGenerate(&private_a, &public_a))
    testing.expect(t, BoxKeyGenerate(&private_b, &public_b))
    a: ^Derp = new(Derp)
    b: ^Derp = new(Derp)
    defer free(a)
    defer free(b)
    host: string = DERP_SERVERS[3].host
    testing.expect(t, DerpOpen(a, host, private_a))
    testing.expect(t, DerpOpen(b, host, private_b))
    defer DerpClose(a)
    defer DerpClose(b)
    message: string = "through a real relay"
    testing.expect(t, DerpSend(a, public_b, transmute([]byte)message))
    buffer: [256]byte
    for _ in 0 ..< 3000 {
        packet, ok, _ := DerpPoll(b, buffer[:])
        if ok {
            testing.expect_value(t, string(buffer[:packet.length]), message)
            testing.expect_value(t, packet.from, public_a)
            return
        }
        time.sleep(time.Millisecond)
    }
    testing.expect(t, false, "nothing arrived through the relay")
}
