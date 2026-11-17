// Terminal chat over p2p: the demo and the manual test of the library.
//
//   odin run p2p/tool/chat -- host [name]      makes a code, copies it, waits for replies (paste one reply per guest)
//   odin run p2p/tool/chat -- join [name]      asks for the host's code, shows (and copies) the reply to send back
//   odin run p2p/tool/chat -- selftest         both ends in this process over the real network (STUN included)
//
// flags: --no-stun (no internet lookups, same network only)  --loopback (offer 127.0.0.1, two programs on one computer)
//        --upnp (ask the router to forward the port: PCP, NAT-PMP, UPnP)  --no-ipv6
//        --turn host:port user password (a TURN relay from a provider with a free tier)  --relay-only (offer only the relay)
//        --port N (fixed local UDP port)
//        --derp [N] (use a free Tailscale DERP relay, no account: N = its number in the list of tool/derp, none = the fastest one found;
//                    the code then names the relay, the guest's reply goes through it and the connection works even when both sides are
//                    behind strict NATs)  --derp-only (offer no addresses, everything through the relay)  --short (host code without
//                    addresses)  --no-derp (a guest ignores the relay in a code)
//        --find-relay (look for TURN relays that answer from this network and offer to use one you have an account for)
//        --wireguard [--yes] (optional encrypted tunnel: says what it does, installs WireGuard when missing, then the chat runs inside it)
// In the chat: a line is sent to everybody; /code shows and copies the code again, /quit leaves.
//
// The stdin reader is a thread (a blocked read must not stop the network), everything else is one loop.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "core:net"
import p2p "../.."

TurnOptions :: struct {
    host: string,
    user: string,
    password: string,
}

DerpOptions :: struct {
    enabled: bool,
    server: int,                        // 1 = first of p2p.DERP_SERVERS, 0 = look for the fastest
    only: bool,
    short: bool,
    disabled: bool,                     // --no-derp
}

short_codes: bool

MSG_CHAT :: u8(1)
MAX_LINE :: 512
LINE_QUEUE :: 16
TEXT_MAX :: 400

LineQueue :: struct {
    mutex: sync.Mutex,
    lines: [LINE_QUEUE][MAX_LINE]byte,
    lengths: [LINE_QUEUE]int,
    head: int,
    count: int,
    closed: bool,
}

lines: LineQueue

main :: proc() {
    mode: string
    name: string
    config: p2p.LinkConfig
    use_stun: bool = true
    use_portmap: bool
    derp: DerpOptions
    find_relay: bool
    use_wireguard: bool
    yes: bool
    turn: TurnOptions
    for i := 1; i < len(os.args); i += 1 {
        argument: string = os.args[i]
        switch argument {
        case "--no-stun":
            use_stun = false
        case "--loopback":
            config.include_loopback = true
        case "--upnp":
            use_portmap = true
        case "--relay-only":
            config.relay_only = true
        case "--find-relay":
            find_relay = true
        case "--wireguard":
            use_wireguard = true
        case "--wireguard-dry":
            use_wireguard = true
            tunnel_dry = true
        case "--yes":
            yes = true
        case "--derp":
            derp.enabled = true
            if i + 1 < len(os.args) {
                number, is_number := strconv.parse_int(os.args[i + 1])
                if is_number {
                    if number < 1 || number > len(p2p.DERP_SERVERS) {
                        fmt.eprintfln("--derp N: N is 1..%d (see odin run p2p/tool/derp)", len(p2p.DERP_SERVERS))
                        os.exit(2)
                    }
                    derp.server = number
                    i += 1
                }
            }
        case "--derp-only":
            derp.enabled = true
            derp.only = true
        case "--short":
            derp.short = true
        case "--no-derp":
            derp.disabled = true
        case "--no-ipv6":
            config.no_ipv6 = true
        case "--turn":
            if i + 3 >= len(os.args) {
                fmt.eprintln("--turn needs: host:port username password")
                os.exit(2)
            }
            turn.host = os.args[i + 1]
            turn.user = os.args[i + 2]
            turn.password = os.args[i + 3]
            i += 3
        case "--port":
            i += 1
            value, ok := strconv.parse_int(os.args[i] if i < len(os.args) else "")
            if !ok || value < 0 || value > 65535 {
                fmt.eprintln("--port needs a number 0..65535")
                os.exit(2)
            }
            config.port = u16(value)
        case:
            if mode == "" {
                mode = argument
            } else {
                name = argument
            }
        }
    }
    if mode == "selftest" {
        os.exit(SelfTest(use_stun, use_portmap, derp))
    }
    if mode != "host" && mode != "join" {
        fmt.eprintln("usage: chat host|join [name] [--no-stun] [--loopback] [--port N]   or   chat selftest")
        os.exit(2)
    }
    if name == "" {
        name = "host" if mode == "host" else "guest"
    }
    if find_relay {
        FindRelay(&turn)
    }
    if use_wireguard {
        TunnelPrepare(yes)
    }
    config.derp_only = derp.only
    short_codes = derp.short
    Chat(mode == "host", name, config, use_stun, use_portmap, turn, derp)
}

Chat :: proc(is_host: bool, name: string, config: p2p.LinkConfig, use_stun: bool, use_portmap: bool, turn: TurnOptions, derp: DerpOptions) {
    link: ^p2p.Link = new(p2p.Link)
    if !p2p.LinkInit(link, config) {
        fmt.eprintln("cannot open the UDP socket (port in use?)")
        os.exit(1)
    }
    servers: [p2p.STUN_MAX_SERVERS]net.Endpoint
    server_count: int
    if use_stun {
        fmt.println("Looking up the STUN servers (free public ones, only used to learn your public address)...")
        server_count = p2p.LinkResolveStun(servers[:])
        if server_count == 0 {
            fmt.println("No STUN server could be resolved (offline?). Only same network connections will work.")
        }
    }
    if turn.host != "" {
        server, resolved := p2p.LinkResolve(turn.host)
        if resolved {
            fmt.printfln("Asking the TURN relay %s for a relayed address...", turn.host)
            p2p.LinkTurnBegin(link, server, turn.user, turn.password, p2p.LinkNow())
        } else {
            fmt.printfln("Cannot resolve the TURN server %s, going without a relay.", turn.host)
        }
    }
    if derp.enabled && is_host {
        server: int = derp.server
        if server == 0 {
            fmt.println("Looking for the fastest DERP relay (free Tailscale relays, no account)...")
            candidates: [6]int = {4, 8, 1, 14, 22, 2}
            server = p2p.DerpRace(candidates[:], 6000)
        }
        if server == 0 {
            fmt.println("No DERP relay answered (offline, or TCP 443 to them is blocked), going without one.")
        } else {
            fmt.printfln("Using the DERP relay %s (%s).", p2p.DERP_SERVERS[server - 1].host, p2p.DERP_SERVERS[server - 1].place)
            p2p.LinkDerpBegin(link, server, p2p.LinkNow())
        }
    }
    p2p.LinkGatherBegin(link, servers[:server_count], p2p.LinkNow())
    for !p2p.LinkGathered(link) {
        p2p.LinkUpdate(link, p2p.LinkNow())
        time.sleep(10 * time.Millisecond)
    }
    if use_portmap {
        fmt.println("Asking the router to forward the port (PCP, NAT-PMP, UPnP)...")
        mapping: ^p2p.PortMapState = new(p2p.PortMapState)
        if p2p.LinkPortMap(link, mapping, p2p.LinkNow()) {
            fmt.printfln("Router forwards it: %v via %v", net.endpoint_to_string(mapping.external, context.temp_allocator), mapping.protocol)
            fmt.println("(The filtering result below includes this PC's firewall: if it says restricted, allow the program for private networks.)")
        } else if mapping.double_nat {
            fmt.println("The router answered, but its own address is private (another NAT in front): not usable.")
        } else {
            fmt.println("The router did not forward the port (no UPnP / NAT-PMP / PCP, or it is switched off).")
        }
    }
    PrintAddresses(link)

    thread.create_and_start(ReadLines, context)
    code_text: [p2p.CODE_TEXT_MAX]byte
    code: string
    if is_host {
        p2p.LinkHost(link, name)
        code = ShowCode(link, code_text[:], "Send this code to your friend. Then paste their reply code here.")
    } else {
        fmt.println("Paste the code you got from the host:")
    }

    peer_names: [p2p.MAX_PEERS][p2p.NAME_MAX]byte
    _ = peer_names
    pending_invite: p2p.Invite                   // a guest that waits for its relay connection before it joins
    has_pending: bool
    buffer: [p2p.MAX_PAYLOAD]byte
    for {
        now: i64 = p2p.LinkNow()
        p2p.LinkUpdate(link, now)
        link = TunnelUpdate(link, is_host, now)
        if has_pending && link.derp.state != .CONNECTING {
            has_pending = false
            p2p.LinkJoin(link, pending_invite, name, now)
            title: string = "Send this reply code back to the host, connecting meanwhile..."
            if link.derp.state == .READY {
                title = "Connecting through the relay: no reply code needs to be sent. (This one is only a fallback if the host does not see you.)"
            }
            code = ShowCode(link, code_text[:], title)
        }

        for {
            event, ok := p2p.LinkPollEvent(link)
            if !ok {
                break
            }
            switch event.kind {
            case .GATHERED:
            case .DERP_READY:
                fmt.printfln("DERP relay ready: %s (%s), our key there %s...", p2p.DERP_SERVERS[link.derp.server - 1].host, p2p.DERP_SERVERS[link.derp.server - 1].place, KeyStart(link.derp.public))
            case .DERP_FAILED:
                fmt.printfln("The DERP relay could not be used: %s", link.derp.failure)
            case .RELAY_READY:
                fmt.printfln("Relay ready: %s (used only when a direct path does not work)", net.endpoint_to_string(link.turn.relayed, context.temp_allocator))
            case .RELAY_FAILED:
                if link.turn.failure == 401 {
                    fmt.println("The TURN server refused the username or password.")
                } else {
                    fmt.println("The TURN relay could not be allocated, going without it.")
                }
            case .NAT_MEASURED:
                PrintFiltering(link)
            case .PEER_CONNECTED:
                Announce(link, is_host, fmt.tprintf("* %s connected%s", p2p.LinkPeerName(link, event.peer), " (through a relay, a direct path is tried every few seconds)" if link.peers[event.peer].via_relay else ""), event.peer, now)
                if is_host {
                    TunnelStart(link, name, now)
                }
            case .PEER_FAILED:
                fmt.printfln("* could not reach %s.", p2p.LinkPeerName(link, event.peer))
                PrintFailureHint(link)
            case .PEER_LOST:
                Announce(link, is_host, fmt.tprintf("* %s left", p2p.LinkPeerName(link, event.peer)), event.peer, now)
            }
        }

        for {
            peer, length, ok := p2p.LinkReceive(link, buffer[:])
            if !ok {
                break
            }
            if TunnelHandle(link, buffer[:length], is_host, name, now) {
                continue
            }
            if length < 2 || buffer[0] != MSG_CHAT {
                continue
            }
            text: string = string(buffer[1:length])
            if is_host {
                // the host puts the name on it and passes it to the other guests
                line: string = fmt.tprintf("%s: %s", p2p.LinkPeerName(link, peer), text)
                fmt.println(line)
                Broadcast(link, line, now, peer)
            } else {
                fmt.println(text)
            }
        }

        input: [MAX_LINE]byte
        length, has_line := PopLine(input[:])
        if has_line {
            line: string = strings.trim_space(string(input[:length]))
            switch {
            case line == "":
            case line == "/quit":
                p2p.LinkClose(link)
                TunnelStop()
                os.exit(0)
            case line == "/code":
                if link.role != .NONE {
                    code = ShowCode(link, code_text[:], "Your code:")
                }
            case strings.has_prefix(line, "/"):
                fmt.println("commands: /code  /quit")
            case:
                invite, is_code := p2p.InviteDecode(line)
                if is_code {
                    if is_host && invite.kind == .REPLY {
                        _, accepted := p2p.LinkAcceptReply(link, invite, now)
                        if accepted {
                            fmt.printfln("Reply of %s accepted, connecting...", p2p.InviteName(&invite))
                        } else {
                            fmt.println("That reply is not for this session (or the room is full).")
                        }
                    } else if !is_host && invite.kind == .INVITE && link.role == .NONE && !has_pending {
                        if invite.derp_server != 0 && link.derp.state == .OFF && !derp.disabled {
                            fmt.printfln("The code names the DERP relay %s: connecting to it first...", p2p.DERP_SERVERS[invite.derp_server - 1].host)
                            p2p.LinkDerpBegin(link, int(invite.derp_server), now)
                            pending_invite = invite
                            has_pending = true
                        } else {
                            p2p.LinkJoin(link, invite, name, now)
                            code = ShowCode(link, code_text[:], "Send this reply code back to the host, connecting meanwhile...")
                        }
                    } else {
                        fmt.println("That code is not the kind needed now.")
                    }
                } else if p2p.LinkPeerCount(link) == 0 {
                    fmt.println("(not connected yet, nobody got that)")
                } else {
                    SendChat(link, is_host, name, line, now)
                }
            }
        }
        time.sleep(10 * time.Millisecond)
    }
}

SendChat :: proc(link: ^p2p.Link, is_host: bool, name: string, text: string, now: i64) {
    message: [p2p.MAX_PAYLOAD]byte
    clipped: string = text[:min(len(text), TEXT_MAX)]
    if is_host {
        line: string = fmt.tprintf("%s: %s", name, clipped)
        Broadcast(link, line, now, -1)
        return
    }
    message[0] = MSG_CHAT
    copy(message[1:], clipped)
    p2p.LinkSend(link, 0, message[:1 + len(clipped)], true, now)
}

Broadcast :: proc(link: ^p2p.Link, line: string, now: i64, except: int) {
    message: [p2p.MAX_PAYLOAD]byte
    clipped: string = line[:min(len(line), p2p.MAX_PAYLOAD - 1)]
    message[0] = MSG_CHAT
    copy(message[1:], clipped)
    p2p.LinkBroadcast(link, message[:1 + len(clipped)], true, now, except)
}

Announce :: proc(link: ^p2p.Link, is_host: bool, line: string, except: int, now: i64) {
    fmt.println(line)
    if is_host {
        Broadcast(link, line, now, except)
    }
}

KeyStart :: proc(key: p2p.BoxKey) -> string {
    return fmt.tprintf("%02x%02x%02x%02x", key[0], key[1], key[2], key[3])
}

ShowCode :: proc(link: ^p2p.Link, buffer: []byte, title: string) -> string {
    text, ok := p2p.InviteEncode(p2p.LinkMakeInvite(link, short_codes && link.derp.state == .READY && link.role == .HOST), buffer)
    assert(ok)
    fmt.println()
    fmt.println(title)
    fmt.println("----------------------------------------------------------------")
    fmt.println(text)
    fmt.println("----------------------------------------------------------------")
    if ClipboardSet(text) {
        fmt.println("(copied to the clipboard)")
    }
    fmt.printfln("CODE: %s", text)
    return text
}

PrintAddresses :: proc(link: ^p2p.Link) {
    for i in 0 ..< link.candidate_count {
        fmt.printfln("address %d: %s", i + 1, net.endpoint_to_string(link.candidates[i], context.temp_allocator))
    }
    switch link.nat_mapping {
    case .UNKNOWN:
        fmt.println("NAT mapping: not measured (needs two STUN answers)")
    case .INDEPENDENT:
        fmt.println("NAT mapping: friendly (same public port towards every server), hole punching should work")
    case .DEPENDENT:
        if link.nat_port_delta != 0 {
            fmt.printfln("NAT mapping: symmetric, but it counts up by %d per destination: the peer can guess the port", link.nat_port_delta)
        } else {
            fmt.println("NAT mapping: symmetric with unpredictable ports, hole punching will fail against a strict NAT")
        }
    }
    PrintFiltering(link)
}

PrintFiltering :: proc(link: ^p2p.Link) {
    switch link.nat_filtering {
    case .UNKNOWN:
        fmt.println("NAT filtering: not measured yet")
    case .OPEN:
        fmt.println("NAT filtering: open (full cone), anybody can send to your public port")
    case .ADDRESS:
        fmt.println("NAT filtering: address restricted, only addresses you sent to can answer")
    case .PORT:
        fmt.println("NAT filtering: port restricted, only the exact address and port you sent to can answer")
    }
}

PrintFailureHint :: proc(link: ^p2p.Link) {
    if link.nat_mapping == .DEPENDENT && link.nat_port_delta == 0 {
        fmt.println("  Your router uses unpredictable public ports per destination (symmetric NAT), so the other side cannot know yours.")
        fmt.println("  Try another network (a phone hotspot usually works) or enable UPnP / forward the UDP port on the router.")
    } else {
        fmt.println("  Check that the codes were pasted whole, both programs are still open, and the firewall allows this program.")
        fmt.println("  If both of you are behind a carrier grade NAT (mobile data, some ISPs) a direct connection is not possible.")
    }
}

// ============================================================ stdin thread

ReadLines :: proc() {
    pending: [MAX_LINE]byte
    count: int
    chunk: [256]byte
    for {
        length, error := os.read(os.stdin, chunk[:])
        if error != nil || length <= 0 {
            break
        }
        for b in chunk[:length] {
            switch b {
            case '\n':
                PushLine(pending[:count])
                count = 0
            case '\r':
            case:
                if count < MAX_LINE {
                    pending[count] = b
                    count += 1
                }
            }
        }
    }
    sync.mutex_guard(&lines.mutex)
    lines.closed = true
}

PushLine :: proc(line: []byte) {
    sync.mutex_guard(&lines.mutex)
    if lines.count >= LINE_QUEUE {
        return
    }
    slot: int = (lines.head + lines.count) % LINE_QUEUE
    copy(lines.lines[slot][:], line)
    lines.lengths[slot] = len(line)
    lines.count += 1
}

PopLine :: proc(out: []byte) -> (length: int, ok: bool) {
    sync.mutex_guard(&lines.mutex)
    if lines.count == 0 {
        // a closed input (a pipe that ended) leaves the program with nothing to wait for
        if lines.closed {
            os.exit(0)
        }
        return
    }
    length = lines.lengths[lines.head]
    copy(out, lines.lines[lines.head][:length])
    lines.head = (lines.head + 1) % LINE_QUEUE
    lines.count -= 1
    return length, true
}
