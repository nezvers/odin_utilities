// Tries Tailscale's public DERP relays from this network: free, no account, nothing to install. They are a relay of last resort for p2p.
//
//   odin run p2p/tool/derp                    probe: connect to every relay at once, report time and what failed
//   odin run p2p/tool/derp -- pair [host]     two clients of this program through one relay: packets both ways, round trip times
//   odin run p2p/tool/derp -- listen [host]   print this program's public key and show what arrives (try derpnet_example.exe s <key> "hi")
//   odin run p2p/tool/derp -- send <key> <text> [host]   one packet to a public key (a derpnet or other client that listens)
//
// The default relay is the fastest one the probe found. Everything sent is sealed end to end (NaCl box), the relay learns only who talks
// to whom. The TLS to the relay does not check its certificate (see p2p/tls13.odin).
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import p2p "../.."

main :: proc() {
    mode: string = os.args[1] if len(os.args) > 1 else "probe"
    switch mode {
    case "probe":
        Probe()
    case "pair":
        os.exit(Pair(os.args[2] if len(os.args) > 2 else ""))
    case "listen":
        Listen(os.args[2] if len(os.args) > 2 else "")
    case "send":
        if len(os.args) < 4 {
            fmt.eprintln("usage: send <public key as 64 hex digits> <text> [host]")
            os.exit(2)
        }
        os.exit(Send(os.args[2], os.args[3], os.args[4] if len(os.args) > 4 else ""))
    case:
        fmt.eprintln("modes: probe, pair [host], listen [host], send <key> <text> [host]")
        os.exit(2)
    }
}

// All relays at once, each on its own thread.
Probe :: proc() {
    count: int = len(p2p.DERP_SERVERS)
    clients: []^p2p.Derp = make([]^p2p.Derp, count)
    fmt.printfln("connecting to %d public DERP relays (TCP, TLS 1.3, key exchange)...", count)
    for i in 0 ..< count {
        clients[i] = new(p2p.Derp)
        private, public: p2p.BoxKey
        p2p.BoxKeyGenerate(&private, &public)
        p2p.DerpBegin(clients[i], p2p.DERP_SERVERS[i].host, private)
    }
    start: time.Tick = time.tick_now()
    for time.duration_seconds(time.tick_since(start)) < 14 {
        pending: int
        for client in clients {
            pending += 1 if p2p.DerpGetState(client) == .CONNECTING else 0
        }
        if pending == 0 {
            break
        }
        time.sleep(50 * time.Millisecond)
    }
    ready: int
    best: int = -1
    for client, i in clients {
        server: p2p.DerpServer = p2p.DERP_SERVERS[i]
        switch p2p.DerpGetState(client) {
        case .READY:
            ready += 1
            fmt.printfln("  OK      %-26s %-14s %5d ms", server.host, server.place, client.connect_ms)
            if best < 0 || client.connect_ms < clients[best].connect_ms {
                best = i
            }
        case .FAILED:
            fmt.printfln("  failed  %-26s %-14s %s", server.host, server.place, client.failure)
        case .CONNECTING:
            fmt.printfln("  slow    %-26s %-14s no answer in time", server.host, server.place)
        case .IDLE, .CLOSED:
        }
    }
    fmt.printfln("%d of %d relays answered.", ready, count)
    if best >= 0 {
        fmt.printfln("fastest: %s (%s), %d ms. Use it in the other modes: p2p/tool/derp -- pair %s", p2p.DERP_SERVERS[best].host, p2p.DERP_SERVERS[best].place, clients[best].connect_ms, p2p.DERP_SERVERS[best].host)
    } else {
        fmt.println("No relay could be reached from this network (offline, a proxy, or TCP 443 to them is blocked).")
    }
    for client in clients {
        if p2p.DerpGetState(client) == .READY {
            p2p.DerpClose(client)
        }
    }
}

OpenRelay :: proc(host_wanted: string, private: p2p.BoxKey, derp: ^p2p.Derp) -> bool {
    host: string = host_wanted if host_wanted != "" else p2p.DERP_SERVERS[7].host
    fmt.printfln("connecting to %s ...", host)
    if !p2p.DerpOpen(derp, host, private) {
        fmt.printfln("cannot connect: %s", derp.failure)
        return false
    }
    fmt.printfln("connected in %d ms (the relay proved its key)", derp.connect_ms)
    return true
}

HexOf :: proc(key: p2p.BoxKey) -> string {
    key_copy: p2p.BoxKey = key
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    for b in key_copy {
        fmt.sbprintf(&builder, "%02x", b)
    }
    return strings.to_string(builder)
}

KeyFromHex :: proc(text: string) -> (key: p2p.BoxKey, ok: bool) {
    if len(text) != 64 {
        return
    }
    for i in 0 ..< 32 {
        high, low: u8
        for pair, j in ([2]u8{text[2 * i], text[2 * i + 1]}) {
            value: u8
            switch {
            case pair >= '0' && pair <= '9':
                value = pair - '0'
            case pair >= 'a' && pair <= 'f':
                value = pair - 'a' + 10
            case pair >= 'A' && pair <= 'F':
                value = pair - 'A' + 10
            case:
                return
            }
            if j == 0 {
                high = value
            } else {
                low = value
            }
        }
        key[i] = high << 4 | low
    }
    return key, true
}

// Two clients through the real relay: each sends 20 numbered packets, the other answers each one; round trips are timed.
Pair :: proc(host: string) -> int {
    private_a, public_a, private_b, public_b: p2p.BoxKey
    p2p.BoxKeyGenerate(&private_a, &public_a)
    p2p.BoxKeyGenerate(&private_b, &public_b)
    a: ^p2p.Derp = new(p2p.Derp)
    b: ^p2p.Derp = new(p2p.Derp)
    if !OpenRelay(host, private_a, a) || !OpenRelay(host, private_b, b) {
        return 1
    }
    defer p2p.DerpClose(a)
    defer p2p.DerpClose(b)
    fmt.printfln("client A %s", HexOf(public_a)[:16])
    fmt.printfln("client B %s", HexOf(public_b)[:16])
    buffer: [1500]byte
    total: f64
    worst: f64
    got: int
    for round in 0 ..< 20 {
        text: string = fmt.tprintf("packet %d from A: %s", round, strings.repeat("x", round * 40, context.temp_allocator))
        sent: time.Tick = time.tick_now()
        if !p2p.DerpSend(a, public_b, transmute([]byte)text) {
            fmt.println("send failed")
            return 1
        }
        arrived: bool
        for time.duration_seconds(time.tick_since(sent)) < 3 && !arrived {
            packet, ok, closed := p2p.DerpPoll(b, buffer[:])
            if closed {
                fmt.println("relay connection closed")
                return 1
            }
            if ok {
                arrived = string(buffer[:packet.length]) == text && packet.from == public_a
                if !arrived {
                    fmt.println("a packet arrived but it is not what A sent")
                    return 1
                }
                reply: string = fmt.tprintf("ack %d", round)
                p2p.DerpSend(b, public_a, transmute([]byte)reply)
            } else {
                time.sleep(time.Millisecond)
            }
        }
        for time.duration_seconds(time.tick_since(sent)) < 3 && arrived {
            packet, ok, _ := p2p.DerpPoll(a, buffer[:])
            if ok {
                if string(buffer[:packet.length]) == fmt.tprintf("ack %d", round) && packet.from == public_b {
                    milliseconds: f64 = time.duration_milliseconds(time.tick_since(sent))
                    total += milliseconds
                    worst = max(worst, milliseconds)
                    got += 1
                }
                break
            }
            time.sleep(time.Millisecond)
        }
    }
    fmt.printfln("%d of 20 round trips through the relay, average %.0f ms, worst %.0f ms (packets grew from 20 to 800 bytes)", got, total / f64(max(got, 1)), worst)
    return 0 if got == 20 else 1
}

Listen :: proc(host: string) {
    private, public: p2p.BoxKey
    p2p.BoxKeyGenerate(&private, &public)
    derp: ^p2p.Derp = new(p2p.Derp)
    if !OpenRelay(host, private, derp) {
        os.exit(1)
    }
    fmt.printfln("My PUBLIC key is: %s", HexOf(public))
    fmt.printfln("send to it with: p2p/tool/derp -- send %s \"hello\" %s   (or derpnet_example.exe s <key> \"hello\")", HexOf(public), p2p.DERP_SERVERS[7].host if host == "" else host)
    buffer: [2048]byte
    for {
        packet, ok, closed := p2p.DerpPoll(derp, buffer[:])
        if closed {
            fmt.println("relay connection closed")
            return
        }
        if ok {
            fmt.printfln("%s: %s", HexOf(packet.from), string(buffer[:packet.length]))
        } else {
            time.sleep(5 * time.Millisecond)
        }
    }
}

Send :: proc(key_text: string, text: string, host: string) -> int {
    peer, ok := KeyFromHex(key_text)
    if !ok {
        fmt.eprintln("the key must be 64 hex digits")
        return 2
    }
    private, public: p2p.BoxKey
    p2p.BoxKeyGenerate(&private, &public)
    derp: ^p2p.Derp = new(p2p.Derp)
    if !OpenRelay(host, private, derp) {
        return 1
    }
    defer p2p.DerpClose(derp)
    if !p2p.DerpSend(derp, peer, transmute([]byte)text) {
        fmt.println("send failed")
        return 1
    }
    fmt.println("sent (no confirmation: the relay does not tell whether the peer is there)")
    time.sleep(300 * time.Millisecond)
    return 0
}
