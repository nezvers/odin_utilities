#+build !js
// Finding the other members of a channel without anybody pasting a code, on the same computer or the same network.
//
// The channel name is the only thing the people agree on. The host (whoever got there first) listens on a UDP port of a small
// range (47500..47563, the first free one, so several channels can live on one computer); a newcomer asks everybody (the loopback
// address and the broadcast address, on every port of the range): "WHO, channel hash". The host answers HERE with its invite code,
// the newcomer joins and sends its reply code back as JOIN. From there it is the normal p2p connection (hole punching, reliable
// channel). Nothing leaves the local network: across the internet the codes are pasted (or carried by something else).
//
// A beacon only answers a matching channel hash (first 8 bytes of sha256 of the name). Without a password the name is not a secret:
// anybody on the same network who knows it (or just listens) can join, exactly like a pasted code that was shown to a stranger. With a
// password the hash covers both and every beacon is sealed with a key made from both, so a listener learns neither the invite nor
// the session secret in it.
package ai_messaging

import "core:crypto"
import "core:crypto/sha2"
import "../p2p"
import "core:net"
import "core:testing"
import "core:time"

BEACON_PORT_FIRST :: 47500
BEACON_PORTS :: 64
BEACON_HEADER :: 4 + 1 + 8
BEACON_MAX :: 1200

BeaconKind :: enum u8 {
    NONE,
    WHO,                                // a newcomer asks
    HERE,                               // the host answers with its invite code
    JOIN,                               // the newcomer's reply code, to the host's beacon
}

Beacon :: struct {
    socket: net.UDP_Socket,
    open: bool,
    port: int,                          // the bound port
    hash: [8]byte,
    sealed: bool,                       // a password was given
    key: p2p.BoxKey,
    packet: [BEACON_MAX]byte,
    plain: [BEACON_MAX]byte,
}

ChannelHash :: proc(channel: string, password: string = "") -> (hash: [8]byte) {
    context_256: sha2.Context_256
    sha2.init_256(&context_256)
    sha2.update(&context_256, transmute([]byte)string("aimsg1:"))
    sha2.update(&context_256, transmute([]byte)channel)
    if password != "" {
        sha2.update(&context_256, transmute([]byte)string("\x1f"))
        sha2.update(&context_256, transmute([]byte)password)
    }
    full: [32]byte
    sha2.final(&context_256, full[:])
    copy(hash[:], full[:8])
    return
}

// A host listens on the first free port of the range; a newcomer takes any port (it only needs to hear the answer).
BeaconOpen :: proc(beacon: ^Beacon, channel: string, listener: bool, password: string = "") -> bool {
    socket, make_error := net.make_unbound_udp_socket(.IP4)
    if make_error != nil {
        return false
    }
    bound: bool
    if listener {
        for i in 0 ..< BEACON_PORTS {
            if net.bind(socket, {address = net.IP4_Any, port = BEACON_PORT_FIRST + i}) == nil {
                beacon.port = BEACON_PORT_FIRST + i
                bound = true
                break
            }
        }
    } else if net.bind(socket, {address = net.IP4_Any, port = 0}) == nil {
        if endpoint, error := net.bound_endpoint(socket); error == nil {
            beacon.port = endpoint.port
            bound = true
        }
    }
    if !bound || net.set_blocking(socket, false) != nil {
        net.close(socket)
        return false
    }
    net.set_option(socket, .Broadcast, true)
    beacon.socket = socket
    beacon.open = true
    beacon.hash = ChannelHash(channel, password)
    beacon.sealed = password != ""
    if beacon.sealed {
        context_256: sha2.Context_256
        sha2.init_256(&context_256)
        sha2.update(&context_256, transmute([]byte)string("aimsg1-seal:"))
        sha2.update(&context_256, transmute([]byte)channel)
        sha2.update(&context_256, transmute([]byte)string("\x1f"))
        sha2.update(&context_256, transmute([]byte)password)
        sha2.final(&context_256, beacon.key[:])
    }
    return true
}

BeaconClose :: proc(beacon: ^Beacon) {
    if beacon.open {
        net.close(beacon.socket)
        beacon.open = false
    }
}

BeaconSend :: proc(beacon: ^Beacon, to: net.Endpoint, kind: BeaconKind, text: string) {
    extra: int = p2p.BOX_NONCE_SIZE + p2p.BOX_AUTH_SIZE if beacon.sealed else 0
    if !beacon.open || BEACON_HEADER + extra + len(text) > BEACON_MAX {
        return
    }
    packet: [BEACON_MAX]byte
    packet[0], packet[1], packet[2], packet[3] = 'A', 'I', 'M', '1'
    packet[4] = u8(kind)
    copy(packet[5:13], beacon.hash[:])
    length: int = BEACON_HEADER
    if beacon.sealed {
        nonce: [p2p.BOX_NONCE_SIZE]byte
        crypto.rand_bytes(nonce[:])
        copy(packet[length:], nonce[:])
        p2p.BoxSeal(packet[length + p2p.BOX_NONCE_SIZE:], transmute([]byte)text, nonce, beacon.key)
        length += extra + len(text)
    } else {
        copy(packet[length:], text)
        length += len(text)
    }
    net.send_udp(beacon.socket, packet[:length], to)
}

// The newcomer's question, to every port of the range on this computer and on the local network.
BeaconAskWho :: proc(beacon: ^Beacon) {
    for i in 0 ..< BEACON_PORTS {
        BeaconSend(beacon, {address = net.IP4_Loopback, port = BEACON_PORT_FIRST + i}, .WHO, "")
        BeaconSend(beacon, {address = net.IP4_Address{255, 255, 255, 255}, port = BEACON_PORT_FIRST + i}, .WHO, "")
    }
}

// The next valid beacon packet for this channel, a view into the beacon's buffer (valid until the next call).
BeaconReceive :: proc(beacon: ^Beacon) -> (kind: BeaconKind, text: string, from: net.Endpoint, ok: bool) {
    if !beacon.open {
        return
    }
    // an ICMP "port unreachable" from our own questions shows up as a receive error on Windows: skip those
    for _ in 0 ..< 32 {
        length, source, error := net.recv_udp(beacon.socket, beacon.packet[:])
        if error == .Would_Block {
            return
        }
        if error != nil || length < BEACON_HEADER {
            continue
        }
        packet: []byte = beacon.packet[:length]
        if packet[0] != 'A' || packet[1] != 'I' || packet[2] != 'M' || packet[3] != '1' {
            continue
        }
        if packet[4] == 0 || packet[4] > u8(max(BeaconKind)) {
            continue
        }
        if string(packet[5:13]) != string(beacon.hash[:]) {
            continue
        }
        if beacon.sealed {
            // a packet that does not open was made without the password (or damaged): the same as no packet
            sealed: []byte = packet[BEACON_HEADER:]
            if len(sealed) < p2p.BOX_NONCE_SIZE + p2p.BOX_AUTH_SIZE {
                continue
            }
            nonce: [p2p.BOX_NONCE_SIZE]byte
            copy(nonce[:], sealed[:p2p.BOX_NONCE_SIZE])
            body: []byte = sealed[p2p.BOX_NONCE_SIZE:]
            if !p2p.BoxOpen(beacon.plain[:], body, nonce, beacon.key) {
                continue
            }
            return BeaconKind(packet[4]), string(beacon.plain[:len(body) - p2p.BOX_AUTH_SIZE]), source, true
        }
        return BeaconKind(packet[4]), string(packet[BEACON_HEADER:]), source, true
    }
    return
}

@(test)
BeaconTest :: proc(t: ^testing.T) {
    host: Beacon
    guest: Beacon
    other: Beacon
    testing.expect(t, BeaconOpen(&host, "beacon-test-channel", true))
    testing.expect(t, BeaconOpen(&guest, "beacon-test-channel", false))
    testing.expect(t, BeaconOpen(&other, "some-other-channel", true))
    defer BeaconClose(&host)
    defer BeaconClose(&guest)
    defer BeaconClose(&other)
    testing.expect(t, host.port != other.port)              // the second listener took the next port

    BeaconSend(&guest, {address = net.IP4_Loopback, port = host.port}, .WHO, "")
    BeaconSend(&guest, {address = net.IP4_Loopback, port = other.port}, .WHO, "")
    got: bool
    for _ in 0 ..< 200 {
        kind, text, from, ok := BeaconReceive(&host)
        if ok {
            testing.expect_value(t, kind, BeaconKind.WHO)
            testing.expect_value(t, from.port, guest.port)
            got = true
            BeaconSend(&host, from, .HERE, "invite-text")
            break
        }
        _ = text
        time.sleep(time.Millisecond)
    }
    testing.expect(t, got)
    for _ in 0 ..< 200 {
        kind, text, _, ok := BeaconReceive(&guest)
        if ok {
            testing.expect_value(t, kind, BeaconKind.HERE)
            testing.expect_value(t, text, "invite-text")
            break
        }
        time.sleep(time.Millisecond)
    }
    // the other channel's listener got a packet with a different hash: it is ignored
    _, _, _, stray := BeaconReceive(&other)
    testing.expect(t, !stray)
}
