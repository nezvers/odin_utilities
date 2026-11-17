// Tries Tailscale's public DERP relays from this network: free, no account, nothing to install. They are a relay of last resort for p2p.
//
//   odin run p2p/tool/derp                    probe: connect to every relay at once, report time and what failed
//   odin run p2p/tool/derp -- probe a.example.com b.example.com   (or a file written by `map`) probe those instead
//   odin run p2p/tool/derp -- diagnose        is it the network, one relay, or all relays (gone, moved, changed)? and what to do about it
//   odin run p2p/tool/derp -- map [file]      the current list of Tailscale relays, fetched with our own HTTPS client (and saved for probe)
//   odin run p2p/tool/derp -- pair [host]     two clients of this program through one relay: packets both ways, round trip times
//   odin run p2p/tool/derp -- listen [host]   print this program's public key and show what arrives (try derpnet_example.exe s <key> "hi")
//   odin run p2p/tool/derp -- send <key> <text> [host]   one packet to a public key (a derpnet or other client that listens)
//
// The default relay is the fastest one the probe found. Everything sent is sealed end to end (NaCl box), the relay learns only who talks
// to whom. The TLS to the relay does not check its certificate (see p2p/tls13.odin).
package main

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import p2p "../.."

main :: proc() {
    mode: string = os.args[1] if len(os.args) > 1 else "probe"
    switch mode {
    case "probe":
        Probe(os.args[2:])
    case "diagnose":
        Diagnose(os.args[2:])
    case "map":
        os.exit(0 if FetchMap(false, os.args[2] if len(os.args) > 2 else "") else 1)
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
        fmt.eprintln("modes: probe [hosts or map file], diagnose, map [file], pair [host], listen [host], send <key> <text> [host]")
        os.exit(2)
    }
}

// Connects to every relay in `hosts` at once (each on its own thread) and prints time or the reason. Returns how many answered and the
// index of the fastest one (-1 when none), and counts the failure kinds.
ProbeHosts :: proc(hosts: []string, places: []string, kinds: ^[p2p.DerpFailure]int) -> (ready: int, best: int) {
    count: int = len(hosts)
    clients: []^p2p.Derp = make([]^p2p.Derp, count)
    for i in 0 ..< count {
        clients[i] = new(p2p.Derp)
        private, public: p2p.BoxKey
        p2p.BoxKeyGenerate(&private, &public)
        p2p.DerpBegin(clients[i], hosts[i], private)
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
    best = -1
    for client, i in clients {
        place: string = places[i] if i < len(places) else ""
        switch p2p.DerpGetState(client) {
        case .READY:
            ready += 1
            fmt.printfln("  OK      %-30s %-14s %5d ms", hosts[i], place, client.connect_ms)
            if best < 0 || client.connect_ms < clients[best].connect_ms {
                best = i
            }
        case .FAILED:
            kinds[client.failure_kind] += 1
            fmt.printfln("  failed  %-30s %-14s [%v] %s", hosts[i], place, client.failure_kind, client.failure)
        case .CONNECTING:
            kinds[.TIMEOUT] += 1
            fmt.printfln("  slow    %-30s %-14s no answer in time", hosts[i], place)
        case .IDLE, .CLOSED:
        }
    }
    for client in clients {
        if p2p.DerpGetState(client) == .READY {
            p2p.DerpClose(client)
        }
    }
    return
}

BuiltinHosts :: proc() -> (hosts: []string, places: []string) {
    hosts = make([]string, len(p2p.DERP_SERVERS))
    places = make([]string, len(p2p.DERP_SERVERS))
    for server, i in p2p.DERP_SERVERS {
        hosts[i] = server.host
        places[i] = server.place
    }
    return
}

// Hosts given on the command line after the mode (or read from a file written by `map`), else the built in list.
HostsFrom :: proc(arguments: []string) -> (hosts: []string, places: []string) {
    if len(arguments) == 0 {
        return BuiltinHosts()
    }
    list: [dynamic]string
    names: [dynamic]string
    for argument in arguments {
        if os.exists(argument) {
            data, error := os.read_entire_file(argument, context.allocator)
            if error != nil {
                continue
            }
            for line in strings.split_lines(string(data)) {
                fields: []string = strings.fields(line)
                if len(fields) >= 4 && fields[0] != "#" {
                    append(&list, fields[len(fields) - 1])
                    append(&names, fields[2])
                }
            }
        } else {
            append(&list, argument)
            append(&names, "(given)")
        }
    }
    return list[:], names[:]
}

Probe :: proc(arguments: []string) {
    hosts, places := HostsFrom(arguments)
    fmt.printfln("connecting to %d DERP relays (TCP, TLS 1.3, key exchange)...", len(hosts))
    kinds: [p2p.DerpFailure]int
    ready, best := ProbeHosts(hosts, places, &kinds)
    fmt.printfln("%d of %d relays answered.", ready, len(hosts))
    if best >= 0 {
        fmt.printfln("fastest: %s. Use it: p2p/tool/derp -- pair %s   (chat: --derp-host %s)", hosts[best], hosts[best], hosts[best])
    } else {
        fmt.println("No relay could be reached. Run `odin run p2p/tool/derp -- diagnose` to find out why and what to do.")
    }
}

// Is the internet there at all? (a TCP connection to a few well known places)
InternetReachable :: proc() -> bool {
    for target in ([?]string{"1.1.1.1:443", "8.8.8.8:443", "www.cloudflare.com:443"}) {
        socket, error := net.dial_tcp_from_hostname_and_port_string(target)
        if error == nil {
            net.close(socket)
            return true
        }
    }
    return false
}

// Tells the person what is wrong and what to do: is it this network, one relay, or all relays (Tailscale changed or went away)?
Diagnose :: proc(arguments: []string) {
    fmt.println("1. Is the internet reachable from here?")
    internet: bool = InternetReachable()
    fmt.printfln("   %s", "yes (TCP 443 to a public address works)" if internet else "NO: no TCP connection to 1.1.1.1, 8.8.8.8 or cloudflare.com on port 443")
    if !internet {
        fmt.println("   Nothing can be relayed without a connection. Check the network, a proxy or a firewall that blocks outgoing 443.")
        fmt.println("   The same network (LAN) still works without any relay: `chat host|join`, `amsg <channel>`.")
        return
    }
    fmt.println("2. Do the relays answer?")
    hosts, places := HostsFrom(arguments)
    kinds: [p2p.DerpFailure]int
    ready, best := ProbeHosts(hosts, places, &kinds)
    fmt.printfln("   %d of %d answered.", ready, len(hosts))
    if ready > 0 {
        fmt.printfln("VERDICT: relays work from here. Fastest: %s. Everybody in one channel must use the same relay (--derp N or --derp-host %s).", hosts[best], hosts[best])
        if ready < len(hosts) {
            fmt.println("Some relays failed: normal (a region can be down or far away); the list above says why for each.")
        }
        return
    }
    dominant: p2p.DerpFailure
    most: int
    for kind in p2p.DerpFailure {
        if kinds[kind] > most {
            most = kinds[kind]
            dominant = kind
        }
    }
    fmt.println()
    fmt.printfln("VERDICT: the internet works but NO relay answered (most common reason: %v).", dominant)
    fmt.println(p2p.DerpAdvice(dominant))
    fmt.println()
    fmt.println("3. Current list of Tailscale relays (they may have been renamed or moved):")
    if FetchMap(true, "") {
        fmt.println("   Probe those names: `odin run p2p/tool/derp -- probe derpmap.txt` (after `map derpmap.txt`).")
    } else {
        fmt.println("   The list could not be fetched either (login.tailscale.com unreachable or changed).")
    }
    fmt.println()
    fmt.println("WHAT TO DO, in the order of effort:")
    fmt.println("  a) Another public relay: any DERP server name works, nothing else changes:  chat --derp-host name   amsg <channel> --derp-host name")
    fmt.println("  b) A relay of your own (free, one small server with a domain name, accepts anybody by default):")
    fmt.println("       go install tailscale.com/cmd/derper@latest")
    fmt.println("       derper --hostname=derp.yourdomain.example           (needs ports 443 and 80, it gets its certificate itself)")
    fmt.println("       then every member uses  --derp-host derp.yourdomain.example   (see p2p/README.md, \"If the relays go away\")")
    fmt.println("  c) A TURN relay from any provider:  chat --turn host:port user password")
    fmt.println("  d) No relay at all: the same network works, a direct path works through most routers (hole punching), and pasted codes need no relay.")
}

// GET https://host/path with the TLS client of p2p (no certificate check, fine for a public list). Returns the body.
HttpsGet :: proc(host: string, path: string) -> (body: []byte, status: int, ok: bool) {
    socket, dial_error := net.dial_tcp_from_hostname_with_port_override(host, 443)
    if dial_error != nil {
        return
    }
    defer net.close(socket)
    net.set_option(socket, .Receive_Timeout, time.Millisecond * 8000)
    tls: ^p2p.Tls = new(p2p.Tls)
    defer free(tls)
    if !p2p.TlsConnect(tls, socket, host) {
        return
    }
    request: string = fmt.tprintf("GET %s HTTP/1.1\r\nHost: %s\r\nAccept: */*\r\nConnection: close\r\n\r\n", path, host)
    if !p2p.TlsWrite(tls, transmute([]byte)request) {
        return
    }
    received: [dynamic]byte
    chunk: [4096]byte
    for len(received) < 4 * 1024 * 1024 {
        count: int = p2p.TlsRead(tls, chunk[:], true)
        if count <= 0 {
            break
        }
        append(&received, ..chunk[:count])
    }
    text: string = string(received[:])
    head_end: int = strings.index(text, "\r\n\r\n")
    if head_end < 0 {
        return
    }
    status = p2p.DerpHttpStatus(received[:head_end])
    payload: string = text[head_end + 4:]
    if strings.contains(strings.to_lower(text[:head_end], context.temp_allocator), "transfer-encoding: chunked") {
        decoded: [dynamic]byte
        for len(payload) > 0 {
            line_end: int = strings.index(payload, "\r\n")
            if line_end < 0 {
                break
            }
            size: int
            for c in payload[:line_end] {
                switch {
                case c >= '0' && c <= '9':
                    size = size * 16 + int(c - '0')
                case c >= 'a' && c <= 'f':
                    size = size * 16 + int(c - 'a') + 10
                case c >= 'A' && c <= 'F':
                    size = size * 16 + int(c - 'A') + 10
                }
            }
            if size == 0 || line_end + 2 + size > len(payload) {
                break
            }
            append(&decoded, ..transmute([]byte)payload[line_end + 2:line_end + 2 + size])
            payload = payload[min(line_end + 2 + size + 2, len(payload)):]
        }
        return decoded[:], status, status == 200
    }
    return transmute([]byte)payload, status, status == 200
}

// The current DERP map from Tailscale: prints the relays and, with a file name, saves "region code name host" lines that `probe` reads.
FetchMap :: proc(brief: bool, save_to: string) -> bool {
    body, status, ok := HttpsGet("login.tailscale.com", "/derpmap/default")
    if !ok {
        fmt.printfln("   cannot fetch https://login.tailscale.com/derpmap/default (status %d)", status)
        return false
    }
    value, error := json.parse(body)
    if error != nil {
        fmt.printfln("   the list is not JSON any more (%v): the format changed", error)
        return false
    }
    root, is_object := value.(json.Object)
    regions: json.Object
    if is_object {
        regions, is_object = root["Regions"].(json.Object)
    }
    if !is_object {
        fmt.println("   the list has no \"Regions\" any more: the format changed")
        return false
    }
    lines: [dynamic]string
    hosts: int
    for _, region_value in regions {
        region, is_region := region_value.(json.Object)
        if !is_region {
            continue
        }
        id: int = int(region["RegionID"].(json.Float) or_else 0)
        code: string = region["RegionCode"].(json.String) or_else "?"
        name: string = strings.replace_all(region["RegionName"].(json.String) or_else "?", " ", "_", context.temp_allocator) or_else "?"
        nodes, has_nodes := region["Nodes"].(json.Array)
        if !has_nodes {
            continue
        }
        for node_value in nodes {
            node, is_node := node_value.(json.Object)
            if !is_node || (node["STUNOnly"].(json.Boolean) or_else false) {
                continue
            }
            host: string = node["HostName"].(json.String) or_else ""
            port: int = int(node["DERPPort"].(json.Float) or_else 0)
            if host == "" {
                continue
            }
            if port != 0 && port != 443 {
                host = fmt.tprintf("%s:%d", host, port)
            }
            hosts += 1
            append(&lines, fmt.aprintf("%d %s %s %s", id, code, name, host))
        }
    }
    fmt.printfln("   %d relay servers in %d regions", hosts, len(regions))
    if !brief {
        slice.sort(lines[:])
        for line in lines {
            fmt.printfln("   %s", line)
        }
    }
    if save_to != "" {
        builder: strings.Builder
        strings.builder_init(&builder)
        strings.write_string(&builder, "# region code name host  (from https://login.tailscale.com/derpmap/default)\n")
        for line in lines {
            strings.write_string(&builder, line)
            strings.write_string(&builder, "\n")
        }
        if os.write_entire_file(save_to, strings.to_string(builder)) == nil {
            fmt.printfln("   saved to %s: probe them with `odin run p2p/tool/derp -- probe %s`", save_to, save_to)
        }
    }
    return true
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
