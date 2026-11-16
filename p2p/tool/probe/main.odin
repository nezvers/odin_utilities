// Finds out which free public servers work from THIS network, and what this NAT does to packets that come from outside.
//
//   odin run p2p/tool/probe
//
// Phase 1  every STUN server gets a binding request (round trip, the address it saw, a second address if it has one)
// Phase 2  servers that can answer "from the outside" (RFC 5780 CHANGE-REQUEST: reply from another IP and port) are asked to.
//          A reply that arrives means the NAT lets strangers in (full cone). Silence from a server that does support it
//          means the NAT filtered it.
// Phase 3  the same with "another port, same IP" (tells address restricted from port restricted)
// Phase 4  TURN servers are asked for an allocation without credentials: a 401 answer (with its realm) means the relay is
//          alive and wants a login, so it can be used by whoever owns an account or the published public credentials
// Results are only valid for the network the tool runs on. Run it on every network you care about.
package main

import "core:crypto"
import "core:fmt"
import "core:net"
import "core:os"
import "core:time"
import p2p "../.."

STUN_CANDIDATES := [?]string{
    "stun.l.google.com:19302", "stun1.l.google.com:19302", "stun2.l.google.com:19302", "stun3.l.google.com:19302",
    "stun4.l.google.com:19302", "stun.cloudflare.com:3478", "stun.stunprotocol.org:3478", "stun.nextcloud.com:3478", "stun.sipgate.net:3478", "stun.sipgate.net:10000", "stun.ekiga.net:3478",
    "stun.services.mozilla.com:3478", "stun.12connect.com:3478", "stun.counterpath.com:3478", "stun.3cx.com:3478",
    "stun.1und1.de:3478", "stun.t-online.de:3478", "stun.freeswitch.org:3478", "stun.callwithus.com:3478",
    "stun.ideasip.com:3478", "stun.voxgratia.org:3478", "stun.xten.com:3478", "stun.zoiper.com:3478",
    "stun.linphone.org:3478", "stun.miwifi.com:3478", "stun.qq.com:3478", "stun.syncthing.net:3478",
    "stun.hot-chilli.net:3478", "stun.bluesip.net:3478", "stun.sonetel.com:3478", "stun.gmx.net:3478",
    "stun.finsterwalder.com:3478", "stun.vo.lu:3478", "stun.voip.blackberry.com:3478", "stun.voipgate.com:3478",
    "stun.nottingham.ac.uk:3478", "stun.schlund.de:3478", "stun.cheapvoip.com:3478", "stun.ipfire.org:3478",
    "stun.siptrunk.com:3478", "stun.threema.ch:3478", "stun.arkadiyt.com:3478", "stun.sipnet.net:3478",
    "stun.poivy.com:3478", "stun.annatel.net:3478", "stun.wtfismyip.com:3478", "stun.lundimatin.fr:3478",
}

TURN_CANDIDATES := [?]string{
    "openrelay.metered.ca:80", "openrelay.metered.ca:443", "openrelay.metered.ca:3478", "freestun.net:3478",
    "freestun.net:5349", "turn.anyfirewall.com:3478", "turn.anyfirewall.com:443", "numb.viagenie.ca:3478",
    "relay1.expressturn.com:3478", "turn.bistri.com:80", "global.turn.twilio.com:3478", "turn.speed.cloudflare.com:50000",
    "turn.cloudflare.com:3478", "standard.relay.metered.ca:80", "eu-turn1.xirsys.com:80", "turn.nextcloud.com:3478",
    "turn.stunprotocol.org:3478", "stun.stunprotocol.org:3479",
}

MAX_SERVERS :: len(STUN_CANDIDATES) + len(TURN_CANDIDATES)
PHASE_MS :: 2500

Server :: struct {
    host: string,
    is_turn: bool,
    endpoint: net.Endpoint,
    resolved: bool,
    txid: p2p.StunTxId,

    answered: bool,                 // phase 1 (or the TURN answer)
    rtt_ms: f64,
    sent_ms: i64,
    result: p2p.StunResult,
    change_both: Reply,             // phase 2
    change_port: Reply,             // phase 3
    turn_code: int,                 // 401 = alive and wants credentials
    turn_realm: [64]byte,
    turn_realm_len: int,
}

Reply :: enum {
    NONE,                           // silence
    SAME_ADDRESS,                   // an answer, but from the address we asked: the flag was ignored
    OTHER_ADDRESS,                  // an answer from another address: the NAT let a stranger in
}

servers: [MAX_SERVERS]Server
server_count: int
socket: net.UDP_Socket

main :: proc() {
    made, make_error := net.make_unbound_udp_socket(.IP4)
    if make_error != nil || net.bind(made, {address = net.IP4_Any, port = 0}) != nil || net.set_blocking(made, false) != nil {
        fmt.eprintln("cannot open a UDP socket")
        os.exit(1)
    }
    socket = made
    local, _ := net.bound_endpoint(socket)
    fmt.printfln("probing from local UDP port %d, all at once, %d ms per phase", local.port, PHASE_MS)

    for host in STUN_CANDIDATES {
        Add(host, false)
    }
    for host in TURN_CANDIDATES {
        Add(host, true)
    }
    resolved: int
    for i in 0 ..< server_count {
        endpoint, error := net.resolve_ip4(servers[i].host)
        if error == nil {
            servers[i].endpoint = endpoint
            servers[i].resolved = true
            resolved += 1
        }
    }
    fmt.printfln("resolved %d of %d names", resolved, server_count)

    // phase 1 and 4 together: plain binding for STUN servers, allocate without login for TURN ones
    Send(proc(s: ^Server, buffer: []byte) -> int {
        if s.is_turn {
            return BuildAllocate(buffer, s.txid)
        }
        return p2p.StunBuildRequest(buffer, s.txid)
    }, true, HandleFirst)
    Wait(PHASE_MS, HandleFirst)

    Send(proc(s: ^Server, buffer: []byte) -> int {
        if s.is_turn || !s.answered || Contaminated(s) {
            return 0
        }
        return p2p.StunBuildRequest(buffer, s.txid, p2p.STUN_CHANGE_IP | p2p.STUN_CHANGE_PORT)
    }, false, nil)
    Wait(PHASE_MS, proc(s: ^Server, from: net.Endpoint, data: []byte, now: i64) {
        if _, ok := p2p.StunParseResult(data, s.txid); ok {
            s.change_both = .SAME_ADDRESS if from == s.endpoint else .OTHER_ADDRESS
        }
    })

    Send(proc(s: ^Server, buffer: []byte) -> int {
        if s.is_turn || !s.answered || Contaminated(s) {
            return 0
        }
        return p2p.StunBuildRequest(buffer, s.txid, p2p.STUN_CHANGE_PORT)
    }, false, nil)
    Wait(PHASE_MS, proc(s: ^Server, from: net.Endpoint, data: []byte, now: i64) {
        if _, ok := p2p.StunParseResult(data, s.txid); ok {
            s.change_port = .SAME_ADDRESS if from == s.endpoint else .OTHER_ADDRESS
        }
    })

    Report()
}

Add :: proc(host: string, is_turn: bool) {
    servers[server_count] = {host = host, is_turn = is_turn}
    server_count += 1
}

BuildAllocate :: proc(buffer: []byte, txid: p2p.StunTxId) -> int {
    id: p2p.StunTxId = txid
    p2p.PutU16BE(buffer[0:], 0x0003)                 // Allocate request
    p2p.PutU16BE(buffer[2:], 8)
    p2p.PutU32BE(buffer[4:], p2p.STUN_MAGIC)
    copy(buffer[8:20], id[:])
    p2p.PutU16BE(buffer[20:], 0x0019)                // REQUESTED-TRANSPORT
    p2p.PutU16BE(buffer[22:], 4)
    p2p.PutU32BE(buffer[24:], 17 << 24)              // UDP
    return 28
}

ReadTurn :: proc(s: ^Server, data: []byte, now: i64) {
    if !p2p.StunLooksLikeStun(data) {
        return
    }
    for i in 0 ..< 12 {
        if data[8 + i] != s.txid[i] {
            return
        }
    }
    s.answered = true
    s.rtt_ms = f64(now - s.sent_ms)
    if code, ok := p2p.StunFindAttribute(data, 0x0009); ok && len(code) >= 4 {
        s.turn_code = int(code[2]) * 100 + int(code[3])
    }
    if realm, ok := p2p.StunFindAttribute(data, 0x0014); ok {
        s.turn_realm_len = min(len(realm), len(s.turn_realm))
        copy(s.turn_realm[:], realm[:s.turn_realm_len])
    }
}

// New transaction ids per phase, then one datagram per server (twice in the first phase: UDP can lose the first).
Send :: proc(build: proc(s: ^Server, buffer: []byte) -> int, twice: bool, handle: proc(s: ^Server, from: net.Endpoint, data: []byte, now: i64)) {
    for round in 0 ..< (2 if twice else 1) {
        for i in 0 ..< server_count {
            s: ^Server = &servers[i]
            if !s.resolved {
                continue
            }
            buffer: [64]byte
            if round == 0 {
                crypto.rand_bytes(s.txid[:])
            }
            length: int = build(s, buffer[:])
            if length > 0 {
                if round == 0 {
                    s.sent_ms = Now()
                }
                net.send_udp(socket, buffer[:length], s.endpoint)
            }
        }
        if round == 0 && twice {
            Wait(PHASE_MS / 3, handle)
        }
    }
}

HandleFirst :: proc(s: ^Server, from: net.Endpoint, data: []byte, now: i64) {
    if s.is_turn {
        ReadTurn(s, data, now)
        return
    }
    result, ok := p2p.StunParseResult(data, s.txid)
    if ok && !s.answered {
        s.answered = true
        s.result = result
        s.rtt_ms = f64(now - s.sent_ms)
    }
}

Wait :: proc(ms: i64, handle: proc(s: ^Server, from: net.Endpoint, data: []byte, now: i64)) {
    start: i64 = Now()
    buffer: [1500]byte
    for Now() - start < ms {
        length, from, error := net.recv_udp(socket, buffer[:])
        if error != nil || length <= 0 {
            time.sleep(2 * time.Millisecond)
            continue
        }
        if handle == nil || length < p2p.STUN_HEADER_SIZE {
            continue
        }
        // the transaction id says which server it was for, whatever address the answer came from
        for i in 0 ..< server_count {
            s: ^Server = &servers[i]
            if s.resolved && string(buffer[8:20]) == string(s.txid[:]) {
                handle(s, from, buffer[:length], Now())
                break
            }
        }
    }
}

Now :: proc() -> i64 {
    return p2p.LinkNow()
}

Report :: proc() {
    fmt.println()
    fmt.println("STUN servers that answered (round trip, address they saw, second address):")
    ports: [MAX_SERVERS]int
    port_count: int
    majority: net.Address = MajorityAddress()
    for i in 0 ..< server_count {
        s: ^Server = &servers[i]
        if s.is_turn || !s.answered {
            continue
        }
        other: string = "-"
        if s.result.has_other {
            other = net.endpoint_to_string(s.result.other, context.temp_allocator)
        }
        fmt.printfln("  %-34s %5.0f ms  saw %-22s other %-22s from-outside: %v / port-only: %v", s.host, s.rtt_ms,
            net.endpoint_to_string(s.result.mapped, context.temp_allocator), other, ReplyText(s.change_both), ReplyText(s.change_port))
        // a server that saw another address (a misconfigured one behind its own NAT) says nothing about ours
        if s.result.mapped.address == majority {
            ports[port_count] = s.result.mapped.port
            port_count += 1
        } else {
            fmt.printfln("    ^ saw a different address than the others, left out of the NAT verdict")
        }
    }

    fmt.println()
    fmt.println("TURN relays that answered (401 = alive, wants a login):")
    turn_alive: int
    for i in 0 ..< server_count {
        s: ^Server = &servers[i]
        if s.is_turn && s.answered {
            fmt.printfln("  %-34s %5.0f ms  code %d realm %q", s.host, s.rtt_ms, s.turn_code, string(s.turn_realm[:s.turn_realm_len]))
            turn_alive += 1
        }
    }
    if turn_alive == 0 {
        fmt.println("  none")
    }

    fmt.println()
    fmt.printfln("STUN servers answering: %d of %d, TURN relays alive: %d of %d", CountAnswered(),
        CountKind(false), turn_alive, CountKind(true))

    // mapping behavior: the same local socket seen by several servers
    different: bool
    for i in 1 ..< port_count {
        different ||= ports[i] != ports[0]
    }
    if port_count >= 2 {
        if different {
            fmt.println("MAPPING: address and port dependent (symmetric NAT): another public port per server")
        } else {
            fmt.println("MAPPING: independent (same public port for every server): hole punching works")
        }
    }
    both_other, port_other, both_silent: int
    for i in 0 ..< server_count {
        s: ^Server = &servers[i]
        if s.is_turn || !s.answered || !s.result.has_other || Contaminated(s) || !p2p.IsPublicAddress(s.result.other.address) {
            continue
        }
        // only servers that announced a second address are known to honour the flags
        both_other += int(s.change_both == .OTHER_ADDRESS)
        port_other += int(s.change_port == .OTHER_ADDRESS)
        both_silent += int(s.change_both == .NONE)
    }
    switch {
    case both_other > 0:
        fmt.println("FILTERING: endpoint independent (full cone): strangers can send to the public port")
    case port_other > 0:
        fmt.println("FILTERING: address restricted: only addresses we sent to may answer")
    case both_silent > 0:
        fmt.println("FILTERING: port restricted or stricter: only the exact address and port we sent to may answer")
    case:
        fmt.println("FILTERING: not measured (no answering server supports CHANGE-REQUEST)")
    }
}

// A server whose second address was also probed as a server of its own: the NAT has seen traffic to that address, so an answer
// from it proves nothing about filtering.
Contaminated :: proc(s: ^Server) -> bool {
    if !s.result.has_other {
        return false
    }
    for i in 0 ..< server_count {
        other: ^Server = &servers[i]
        if other != s && other.resolved && other.endpoint.address == s.result.other.address {
            return true
        }
    }
    return false
}

MajorityAddress :: proc() -> (best: net.Address) {
    best_count: int
    for i in 0 ..< server_count {
        if servers[i].is_turn || !servers[i].answered {
            continue
        }
        count: int
        for j in 0 ..< server_count {
            count += int(!servers[j].is_turn && servers[j].answered && servers[j].result.mapped.address == servers[i].result.mapped.address)
        }
        if count > best_count {
            best_count = count
            best = servers[i].result.mapped.address
        }
    }
    return
}

ReplyText :: proc(reply: Reply) -> string {
    switch reply {
    case .NONE:
        return "silent"
    case .SAME_ADDRESS:
        return "ignored"
    case .OTHER_ADDRESS:
        return "ARRIVED"
    }
    return ""
}

CountAnswered :: proc() -> (count: int) {
    for i in 0 ..< server_count {
        count += int(!servers[i].is_turn && servers[i].answered)
    }
    return
}

CountKind :: proc(turn: bool) -> (count: int) {
    for i in 0 ..< server_count {
        count += int(servers[i].is_turn == turn && servers[i].resolved)
    }
    return
}
