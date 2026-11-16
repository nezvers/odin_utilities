// The optional WireGuard tunnel of the chat (--wireguard). The p2p Link is already connected when this starts; it carries the key
// exchange, then gives its UDP port to WireGuard (the NAT mapping belongs to the port, so the hole stays open) and the chat goes on
// over a second Link whose only address is the tunnel's: the same chat, now encrypted.
//
//   host                                              guest
//   PEER_CONNECTED
//   makes link2 (tunnel address), OFFER(key, invite) ──►  makes link2, joins it, ANSWER(key, reply)
//   accepts reply later            GO              ◄──►  (both wait until nothing is unacknowledged)
//   closes link1, wg up (ListenPort = link1 port, Endpoint = the peer's address that just worked), link2 connects through the tunnel
//
// One guest only (a tunnel per peer would be needed for more). Everything it does is printed as "[wireguard] ...".
package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"
import p2p "../.."
import "../../wireguard"

MSG_WG_OFFER :: u8(2)                   // host to guest: [2][public key 32][invite text of the tunnel link]
MSG_WG_ANSWER :: u8(3)                  // guest to host: [3][public key 32][reply text]
MSG_WG_GO :: u8(4)                      // host to guest: both have everything, switch
TUNNEL_SETTLE_MS :: 300                 // after GO: time for the last acknowledgements before the link is closed
TUNNEL_WAIT_MS :: 20000                 // the other side did not answer the offer in this time: stay on the direct link

TunnelPhase :: enum {
    OFF,                                // not asked for
    READY,                              // installed, keys made, waiting for a connected peer
    OFFERED,                            // host: offer sent, waiting for the answer
    ANSWERED,                           // guest: answer sent, waiting for GO
    SWITCHING,                          // both have everything: waiting for the last acknowledgements
    ACTIVE,                             // the chat runs over the tunnel
    GAVE_UP,                            // not possible here, the direct link stays
}

Tunnel :: struct {
    phase: TunnelPhase,
    keys: wireguard.KeyPair,
    peer_public: [32]byte,
    link: ^p2p.Link,                    // the tunnel link, joined only when the tunnel is up
    reply: p2p.Invite,                  // host: the guest's reply, accepted when the tunnel is up
    started_ms: i64,
    switch_ms: i64,
}

tunnel: Tunnel
tunnel_dry: bool                        // --wireguard-dry: runs the whole exchange and the switch without touching the system (tests)

TunnelLog :: proc(message: string) {
    fmt.printfln("[wireguard] %s", message)
}

// Before the chat starts reading the keyboard: say what is going to happen, ask, install if needed, get sudo ready, make keys.
TunnelPrepare :: proc(yes: bool) -> bool {
    if tunnel_dry {
        TunnelLog("dry run: no installation, no tunnel, the tunnel link uses 127.0.0.1")
        wireguard.KeyGenerate(&tunnel.keys)
        tunnel.phase = .READY
        return true
    }
    if wireguard.CurrentPlatform() == .UNSUPPORTED {
        fmt.println(wireguard.Describe())
        return false
    }
    fmt.println()
    fmt.println("---- WireGuard tunnel (optional, --wireguard) ----")
    fmt.print(wireguard.Describe())
    fmt.println("It only changes this computer when you answer yes. Nothing of this is needed for the plain chat.")
    if !yes && !Ask("Continue with the WireGuard tunnel? [y/N] ") {
        fmt.println("[wireguard] skipped, the chat stays unencrypted")
        return false
    }
    if !wireguard.Installed() {
        if !wireguard.Install(TunnelLog) {
            fmt.println("[wireguard] could not install WireGuard, the chat stays unencrypted")
            return false
        }
    }
    if !wireguard.SudoPrepare(TunnelLog) {
        fmt.println("[wireguard] no administrator rights, the chat stays unencrypted")
        return false
    }
    if !wireguard.KeyGenerate(&tunnel.keys) {
        fmt.println("[wireguard] no random numbers from the system, the chat stays unencrypted")
        return false
    }
    TunnelLog("key pair made in this program (the private key never leaves this computer)")
    tunnel.phase = .READY
    return true
}

// A blocking yes/no from the keyboard, only for use before the reader thread starts.
Ask :: proc(question: string) -> bool {
    fmt.print(question)
    answer: [64]byte
    length: int
    for length < len(answer) {
        one: [1]byte
        count, error := os.read(os.stdin, one[:])
        if error != nil || count <= 0 || one[0] == '\n' {
            break
        }
        answer[length] = one[0]
        length += 1
    }
    text: string = strings.to_lower(strings.trim_space(string(answer[:length])), context.temp_allocator)
    return text == "y" || text == "yes"
}

TunnelAddress :: proc(is_host: bool) -> net.IP4_Address {
    return {10, 73, 82, 1} if is_host else {10, 73, 82, 2}
}

TunnelMakeLink :: proc(is_host: bool, now: i64) -> ^p2p.Link {
    link: ^p2p.Link = new(p2p.Link)
    config: p2p.LinkConfig
    config.no_ipv6 = true
    config.local_addresses[0] = {127, 0, 0, 1} if tunnel_dry else TunnelAddress(is_host)
    config.local_address_count = 1
    if !p2p.LinkInit(link, config) {
        free(link)
        return nil
    }
    p2p.LinkGatherBegin(link, nil, now)
    for _ in 0 ..< 100 {
        if p2p.LinkGathered(link) {
            break
        }
        p2p.LinkUpdate(link, p2p.LinkNow())
        time.sleep(time.Millisecond)
    }
    return link
}

// The host starts it as soon as the first guest is connected.
TunnelStart :: proc(link: ^p2p.Link, name: string, now: i64) {
    if tunnel.phase != .READY {
        return
    }
    if p2p.LinkPeerCount(link) > 1 {
        TunnelGiveUp("a second guest joined: the tunnel is one to one, the chat stays on the direct link")
        return
    }
    if link.peers[0].via_relay {
        TunnelGiveUp("the connection goes through a TURN relay, a tunnel needs a direct path: the chat stays on the relay")
        return
    }
    TunnelLog("connected directly: offering the other side an encrypted tunnel (public key + tunnel address)")
    tunnel.link = TunnelMakeLink(true, now)
    if tunnel.link == nil {
        TunnelGiveUp("cannot open the tunnel link")
        return
    }
    p2p.LinkHost(tunnel.link, name)
    code: [p2p.CODE_TEXT_MAX]byte
    text, ok := p2p.InviteEncode(p2p.LinkMakeInvite(tunnel.link), code[:])
    assert(ok)
    TunnelSend(link, MSG_WG_OFFER, text, now)
    tunnel.phase = .OFFERED
    tunnel.started_ms = now
}

TunnelSend :: proc(link: ^p2p.Link, kind: u8, text: string, now: i64) {
    message: [p2p.MAX_PAYLOAD]byte
    message[0] = kind
    copy(message[1:33], tunnel.keys.public[:])
    copy(message[33:], text)
    p2p.LinkSend(link, 0, message[:33 + len(text)], true, now)
}

TunnelGiveUp :: proc(reason: string) {
    TunnelLog(reason)
    if tunnel.link != nil {
        p2p.LinkClose(tunnel.link)
        free(tunnel.link)
        tunnel.link = nil
    }
    tunnel.phase = .GAVE_UP
}

// A tunnel message from the direct link. Returns false when the message is not a tunnel message.
TunnelHandle :: proc(link: ^p2p.Link, message: []byte, is_host: bool, name: string, now: i64) -> bool {
    if len(message) < 1 || message[0] < MSG_WG_OFFER || message[0] > MSG_WG_GO {
        return false
    }
    if tunnel.phase == .OFF || tunnel.phase == .GAVE_UP || tunnel.phase == .ACTIVE {
        return true
    }
    switch message[0] {
    case MSG_WG_OFFER:
        if is_host || tunnel.phase != .READY || len(message) <= 33 {
            return true
        }
        if link.peers[0].via_relay {
            TunnelGiveUp("the host offered a tunnel but this side is on a TURN relay: staying on the direct chat")
            return true
        }
        copy(tunnel.peer_public[:], message[1:33])
        invite, ok := p2p.InviteDecode(string(message[33:]))
        if !ok || invite.kind != .INVITE {
            TunnelGiveUp("the tunnel offer was damaged")
            return true
        }
        TunnelLog("the host offers an encrypted tunnel, answering with this computer's public key")
        tunnel.link = TunnelMakeLink(false, now)
        if tunnel.link == nil {
            TunnelGiveUp("cannot open the tunnel link")
            return true
        }
        p2p.LinkJoin(tunnel.link, invite, name, now)
        code: [p2p.CODE_TEXT_MAX]byte
        text, encoded := p2p.InviteEncode(p2p.LinkMakeInvite(tunnel.link), code[:])
        assert(encoded)
        TunnelSend(link, MSG_WG_ANSWER, text, now)
        tunnel.phase = .ANSWERED
        tunnel.started_ms = now
    case MSG_WG_ANSWER:
        if !is_host || tunnel.phase != .OFFERED || len(message) <= 33 {
            return true
        }
        reply, ok := p2p.InviteDecode(string(message[33:]))
        if !ok || reply.kind != .REPLY {
            TunnelGiveUp("the tunnel answer was damaged")
            return true
        }
        copy(tunnel.peer_public[:], message[1:33])
        tunnel.reply = reply
        TunnelLog("the guest accepted: both sides have the other's public key, switching to the tunnel")
        go: [1]byte = {MSG_WG_GO}
        p2p.LinkSend(link, 0, go[:], true, now)
        tunnel.phase = .SWITCHING
        tunnel.switch_ms = now + TUNNEL_SETTLE_MS
    case MSG_WG_GO:
        if is_host || tunnel.phase != .ANSWERED {
            return true
        }
        TunnelLog("the host has everything: switching to the tunnel")
        tunnel.phase = .SWITCHING
        tunnel.switch_ms = now + TUNNEL_SETTLE_MS
    }
    return true
}

// Every frame. Returns the link the chat should use from now on (the direct one until the tunnel took over).
TunnelUpdate :: proc(link: ^p2p.Link, is_host: bool, now: i64) -> ^p2p.Link {
    #partial switch tunnel.phase {
    case .OFFERED, .ANSWERED:
        if now - tunnel.started_ms >= TUNNEL_WAIT_MS {
            TunnelGiveUp("the other side did not go on with the tunnel (an old version, a relay, or it said no): the chat stays on the direct link")
        }
    case .SWITCHING:
        if now < tunnel.switch_ms || p2p.LinkPending(link, 0) > 0 {
            return link
        }
        return TunnelSwitch(link, is_host, now)
    }
    return link
}

// Closes the direct link, starts WireGuard on its port towards the address that just worked, then joins the tunnel link.
TunnelSwitch :: proc(link: ^p2p.Link, is_host: bool, now: i64) -> ^p2p.Link {
    endpoint: net.Endpoint = link.peers[0].endpoint
    port: int = link.local_port
    if _, is_v6 := endpoint.address.(net.IP6_Address); is_v6 {
        port = link.local_port6
    }
    // the person may need time to allow the Windows prompt, so the closing is announced first
    TunnelLog(fmt.tprintf("closing the direct link to free UDP port %d for WireGuard; the peer address %s stays open in the NAT", port, net.endpoint_to_string(endpoint, context.temp_allocator)))
    p2p.LinkClose(link)
    free(link)

    own: string = wireguard.HOST_ADDRESS if is_host else wireguard.GUEST_ADDRESS
    peer: string = wireguard.GUEST_ADDRESS if is_host else wireguard.HOST_ADDRESS
    config: [wireguard.CONFIG_MAX]byte
    text: string = wireguard.ConfigWrite(config[:], tunnel.keys.private, own, port, tunnel.peer_public, peer, net.endpoint_to_string(endpoint, context.temp_allocator))
    if tunnel_dry {
        TunnelLog("dry run, the configuration that would be used (private key hidden):")
        for line in strings.split_lines(text, context.temp_allocator) {
            if !strings.has_prefix(line, "PrivateKey") {
                TunnelLog(fmt.tprintf("  %s", line))
            }
        }
    } else if !wireguard.Up(TunnelLog, text) {
        fmt.println("[wireguard] the tunnel could not be created. The direct link was already closed, so this chat ends. Start again without --wireguard.")
        wireguard.Down(TunnelLog)
        os.exit(1)
    }
    TunnelLog(fmt.tprintf("tunnel up: this side is %s, the other %s. Connecting the chat through it (the first handshake takes a few seconds)...", own, peer))
    now_after: i64 = p2p.LinkNow()
    if is_host {
        p2p.LinkAcceptReply(tunnel.link, tunnel.reply, now_after)
    } else {
        p2p.LinkRestartPunch(tunnel.link, now_after)
    }
    tunnel.phase = .ACTIVE
    return tunnel.link
}

// The end of the chat: the tunnel interface does not outlive the program.
TunnelStop :: proc() {
    if tunnel.phase == .ACTIVE || tunnel.phase == .SWITCHING {
        wireguard.Down(TunnelLog)
    }
}
