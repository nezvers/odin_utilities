// Ask the router to forward a UDP port: PCP (RFC 6887), NAT-PMP (RFC 6886) and UPnP IGD, in that order.
//
// A forwarded port turns a strict NAT into an open one for that port: the public address is stable and whoever knows it can send
// to it, so no hole punching is needed and even a symmetric NAT works. Many home routers support one of the three, most carrier
// and company NATs none. The mapping is a favor the router may refuse, so the Link only uses it as one more candidate.
//
// These procedures BLOCK, each step for at most `timeout_ms` (a conversation with the router on the local network, normally
// some milliseconds, up to a few seconds when the router is silent): call them at start-up or on a thread, not in a frame.
// Nothing is allocated: the state holds every buffer. Encoders and parsers are pure and tested without a router; the tests also
// run a fake router (UDP for PCP and NAT-PMP, TCP for UPnP) on loopback.
package p2p

import "core:crypto"
import "core:fmt"
import "core:net"
import "core:strconv"
import "core:testing"
import "core:thread"
import "core:time"

PORTMAP_PORT :: 5351                // PCP and NAT-PMP share it
PORTMAP_REQUEST_AREA :: 4096        // the first part of the scratch buffer is the HTTP request, the rest is the answer
PORTMAP_SCRATCH :: 16384
PORTMAP_LIFETIME_S :: 7200
PORTMAP_PCP_SIZE :: 60
PORTMAP_MAX_GATEWAYS :: 4
PORTMAP_PORT_TRIES :: 8             // other external ports tried when the router says one is taken
SSDP_ADDRESS :: net.IP4_Address{239, 255, 255, 250}
SSDP_PORT :: 1900

PortMapProtocol :: enum {
    NONE,
    PCP,
    NAT_PMP,
    UPNP,
}

PortMapState :: struct {
    protocol: PortMapProtocol,
    gateway: net.IP4_Address,
    external: net.Endpoint,         // the public address and port that reach us, valid when protocol != NONE
    internal_port: int,
    lifetime_s: u32,
    double_nat: bool,               // the router got a mapping but its own address is private: another NAT is in front of it

    // UPnP: where the SOAP calls go
    control_endpoint: net.Endpoint,
    control_path: [128]byte,
    control_path_len: int,
    service: [64]byte,              // urn:schemas-upnp-org:service:WANIPConnection:1
    service_len: int,

    scratch: [PORTMAP_SCRATCH]byte,
}

// ============================================================ gateway

// The default gateways of the network cards that are up, IPv4 only. Reads the interface list through the temp allocator.
PortMapGateways :: proc(out: []net.IP4_Address) -> (count: int) {
    defer free_all(context.temp_allocator)
    interfaces, error := net.enumerate_interfaces(context.temp_allocator)
    if error != nil {
        return
    }
    for interface in interfaces {
        if .Up not_in interface.link.state {
            continue
        }
        for gateway in interface.gateways {
            address, is_ip4 := gateway.(net.IP4_Address)
            if !is_ip4 || count >= len(out) || address == (net.IP4_Address{}) {
                continue
            }
            out[count] = address
            count += 1
        }
    }
    return
}

// This computer's address on the network of `gateway`: the one that shares its /24 (home routers, almost always), else the
// first private one. The router needs it to know where to forward.
PortMapLocalAddress :: proc(gateway: net.IP4_Address) -> (address: net.IP4_Address, ok: bool) {
    defer free_all(context.temp_allocator)
    interfaces, error := net.enumerate_interfaces(context.temp_allocator)
    if error != nil {
        return
    }
    fallback: net.IP4_Address
    have_fallback: bool
    for interface in interfaces {
        if .Up not_in interface.link.state {
            continue
        }
        for lease in interface.unicast {
            candidate, is_ip4 := lease.address.(net.IP4_Address)
            if !is_ip4 || candidate[0] == 127 || candidate[0] == 169 {
                continue
            }
            if candidate[0] == gateway[0] && candidate[1] == gateway[1] && candidate[2] == gateway[2] {
                return candidate, true
            }
            if !have_fallback && !IsPublicAddress(candidate) {
                fallback = candidate
                have_fallback = true
            }
        }
    }
    return fallback, have_fallback
}

// ============================================================ NAT-PMP

// "What is my public address?" (2 bytes) and its answer (12 bytes).
PortMapNatPmpAddressRequest :: proc(buffer: []byte) -> int {
    buffer[0] = 0
    buffer[1] = 0
    return 2
}

PortMapNatPmpAddressParse :: proc(data: []byte) -> (address: net.IP4_Address, ok: bool) {
    if len(data) < 12 || data[0] != 0 || data[1] != 128 || GetU16BE(data[2:]) != 0 {
        return
    }
    return net.IP4_Address{data[8], data[9], data[10], data[11]}, true
}

// "Forward UDP internal_port" (12 bytes). Lifetime 0 deletes the mapping.
PortMapNatPmpMapRequest :: proc(buffer: []byte, internal_port: u16, external_port: u16, lifetime_s: u32) -> int {
    buffer[0] = 0
    buffer[1] = 1
    PutU16BE(buffer[2:], 0)
    PutU16BE(buffer[4:], internal_port)
    PutU16BE(buffer[6:], external_port)
    PutU32BE(buffer[8:], lifetime_s)
    return 12
}

PortMapNatPmpMapParse :: proc(data: []byte, internal_port: u16) -> (external_port: u16, lifetime_s: u32, ok: bool) {
    if len(data) < 16 || data[0] != 0 || data[1] != 129 || GetU16BE(data[2:]) != 0 || GetU16BE(data[8:]) != internal_port {
        return
    }
    return GetU16BE(data[10:]), GetU32BE(data[12:]), true
}

// ============================================================ PCP

PortMapNonce :: [12]byte

// A MAP request (60 bytes): version 2, opcode MAP, our address written as an IPv4 mapped IPv6 one, nonce, UDP, the ports.
PortMapPcpRequest :: proc(buffer: []byte, client: net.IP4_Address, nonce: PortMapNonce, internal_port: u16, external_port: u16, lifetime_s: u32) -> int {
    assert(len(buffer) >= PORTMAP_PCP_SIZE)
    for i in 0 ..< PORTMAP_PCP_SIZE {
        buffer[i] = 0
    }
    id: PortMapNonce = nonce
    address: net.IP4_Address = client
    buffer[0] = 2
    buffer[1] = 1
    PutU32BE(buffer[4:], lifetime_s)
    buffer[18] = 0xFF
    buffer[19] = 0xFF
    copy(buffer[20:24], address[:])
    copy(buffer[24:36], id[:])
    buffer[36] = 17
    PutU16BE(buffer[40:], internal_port)
    PutU16BE(buffer[42:], external_port)
    return PORTMAP_PCP_SIZE
}

// The answer to a MAP request: the public address and port assigned. Another nonce or version is not for us.
PortMapPcpParse :: proc(data: []byte, nonce: PortMapNonce) -> (external: net.Endpoint, lifetime_s: u32, ok: bool) {
    id: PortMapNonce = nonce
    if len(data) < PORTMAP_PCP_SIZE || data[0] != 2 || data[1] != 0x81 || data[3] != 0 {
        return
    }
    for i in 0 ..< len(id) {
        if data[24 + i] != id[i] {
            return
        }
    }
    // the assigned external address is an IPv4 mapped one: ten zero bytes, 0xFFFF, the address
    if data[54] != 0xFF || data[55] != 0xFF {
        return
    }
    return {address = net.IP4_Address{data[56], data[57], data[58], data[59]}, port = int(GetU16BE(data[42:]))}, GetU32BE(data[4:]), true
}

// ============================================================ the UDP conversation (PCP, NAT-PMP, SSDP)

// Sends `request` to `to` (again after 250 ms and 750 ms) and returns the first datagram that comes back from that address.
@(private)
PortMapAsk :: proc(socket: net.UDP_Socket, to: net.Endpoint, request: []byte, reply: []byte, timeout_ms: i64) -> int {
    start: i64 = LinkNow()
    sent: int
    for {
        elapsed: i64 = LinkNow() - start
        if elapsed >= timeout_ms {
            return 0
        }
        if sent == 0 && elapsed >= 0 || sent == 1 && elapsed >= 250 || sent == 2 && elapsed >= 750 {
            net.send_udp(socket, request, to)
            sent += 1
        }
        length, from, error := net.recv_udp(socket, reply)
        if error == nil && length > 0 && from.address == to.address {
            return length
        }
        if error != nil && error != .Would_Block {
            continue
        }
        time.sleep(2 * time.Millisecond)
    }
}

@(private)
PortMapSocket :: proc() -> (socket: net.UDP_Socket, ok: bool) {
    made, make_error := net.make_unbound_udp_socket(.IP4)
    if make_error != nil {
        return
    }
    if net.bind(made, {address = net.IP4_Any, port = 0}) != nil || net.set_blocking(made, false) != nil {
        net.close(made)
        return
    }
    return made, true
}

// PCP, then NAT-PMP, at `gateway` (the port is a parameter so a test can run a router on loopback).
PortMapTryUdp :: proc(state: ^PortMapState, gateway: net.Endpoint, internal: net.IP4_Address, internal_port: int, timeout_ms: i64) -> bool {
    socket, ok := PortMapSocket()
    if !ok {
        return false
    }
    defer net.close(socket)
    request: [PORTMAP_PCP_SIZE]byte
    reply: [128]byte

    nonce: PortMapNonce
    crypto.rand_bytes(nonce[:])
    length: int = PortMapPcpRequest(request[:], internal, nonce, u16(internal_port), u16(internal_port), PORTMAP_LIFETIME_S)
    received: int = PortMapAsk(socket, gateway, request[:length], reply[:], timeout_ms)
    if external, lifetime, parsed := PortMapPcpParse(reply[:received], nonce); parsed {
        PortMapSet(state, .PCP, gateway, external, internal_port, lifetime)
        return true
    }

    // a router that only knows NAT-PMP answers the PCP request with version 0 (or not at all): ask the old way
    length = PortMapNatPmpAddressRequest(request[:])
    received = PortMapAsk(socket, gateway, request[:length], reply[:], timeout_ms)
    address, address_ok := PortMapNatPmpAddressParse(reply[:received])
    if !address_ok {
        return false
    }
    length = PortMapNatPmpMapRequest(request[:], u16(internal_port), u16(internal_port), PORTMAP_LIFETIME_S)
    received = PortMapAsk(socket, gateway, request[:length], reply[:], timeout_ms)
    external_port, lifetime, parsed := PortMapNatPmpMapParse(reply[:received], u16(internal_port))
    if !parsed {
        return false
    }
    PortMapSet(state, .NAT_PMP, gateway, {address = address, port = int(external_port)}, internal_port, lifetime)
    return true
}

@(private)
PortMapSet :: proc(state: ^PortMapState, protocol: PortMapProtocol, gateway: net.Endpoint, external: net.Endpoint, internal_port: int, lifetime_s: u32) {
    state.protocol = protocol
    state.gateway = gateway.address.(net.IP4_Address)
    state.external = external
    state.internal_port = internal_port
    state.lifetime_s = lifetime_s
}

// ============================================================ UPnP IGD

// Finds the router's description URL by SSDP: a multicast search and the same search sent straight to the gateway (many
// routers ignore multicast on a busy network but answer a unicast one). The URL is copied into `url`.
PortMapSsdpSearch :: proc(gateway: net.IP4_Address, url: []byte, timeout_ms: i64) -> (length: int) {
    socket, ok := PortMapSocket()
    if !ok {
        return
    }
    defer net.close(socket)
    search: [256]byte
    text: string = fmt.bprintf(search[:], "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n")
    start: i64 = LinkNow()
    reply: [1024]byte
    for sent in 0 ..< 3 {
        net.send_udp(socket, transmute([]byte)text, {address = SSDP_ADDRESS, port = SSDP_PORT})
        net.send_udp(socket, transmute([]byte)text, {address = gateway, port = SSDP_PORT})
        wait_until: i64 = start + (i64(sent) + 1) * timeout_ms / 3
        for LinkNow() < wait_until {
            received, from, error := net.recv_udp(socket, reply[:])
            if error != nil || received <= 0 {
                time.sleep(2 * time.Millisecond)
                continue
            }
            location: string = HeaderValue(string(reply[:received]), "location")
            if location != "" && len(location) <= len(url) && from.address == gateway {
                copy(url, location)
                return len(location)
            }
        }
    }
    return
}

// "http://192.168.1.1:49152/rootDesc.xml": the address, the port and the path. IPv4 literals only, which is what routers use.
PortMapParseUrl :: proc(url: string) -> (endpoint: net.Endpoint, path: string, ok: bool) {
    PREFIX :: "http://"
    if len(url) <= len(PREFIX) || url[:len(PREFIX)] != PREFIX {
        return
    }
    rest: string = url[len(PREFIX):]
    slash: int = IndexOf(rest, "/")
    host: string = rest
    path = "/"
    if slash >= 0 {
        host = rest[:slash]
        path = rest[slash:]
    }
    port: int = 80
    if colon := IndexOf(host, ":"); colon >= 0 {
        parsed, port_ok := strconv.parse_int(host[colon + 1:])
        if !port_ok || parsed <= 0 || parsed > 65535 {
            return
        }
        port = parsed
        host = host[:colon]
    }
    address, address_ok := net.parse_ip4_address(host)
    if !address_ok {
        return
    }
    return {address = address, port = port}, path, true
}

// One HTTP request over TCP, `Connection: close`, the answer read until the router closes. The request is already in
// state.scratch[:request_length]; the answer lands after it and the body is returned as a view.
@(private)
PortMapHttp :: proc(state: ^PortMapState, endpoint: net.Endpoint, request_length: int, timeout_ms: i64) -> (status: int, body: string, ok: bool) {
    socket, dial_error := net.dial_tcp_from_endpoint(endpoint)
    if dial_error != nil {
        return
    }
    defer net.close(socket)
    timeout: time.Duration = time.Duration(timeout_ms) * time.Millisecond
    net.set_option(socket, .Receive_Timeout, timeout)
    net.set_option(socket, .Send_Timeout, timeout)
    if _, send_error := net.send_tcp(socket, state.scratch[:request_length]); send_error != nil {
        return
    }
    answer: []byte = state.scratch[PORTMAP_REQUEST_AREA:]
    total: int
    for total < len(answer) {
        received, receive_error := net.recv_tcp(socket, answer[total:])
        if receive_error != nil || received <= 0 {
            break
        }
        total += received
    }
    text: string = string(answer[:total])
    if len(text) < 12 || text[:5] != "HTTP/" {
        return
    }
    status, _ = strconv.parse_int(text[9:12])
    header_end: int = IndexOf(text, "\r\n\r\n")
    if header_end < 0 {
        return status, "", status > 0
    }
    return status, text[header_end + 4:], true
}

// Reads the router description and remembers the control URL of its WAN connection service.
PortMapUpnpDescribe :: proc(state: ^PortMapState, location: string, timeout_ms: i64) -> bool {
    endpoint, path, url_ok := PortMapParseUrl(location)
    if !url_ok {
        return false
    }
    request: string = fmt.bprintf(state.scratch[:PORTMAP_REQUEST_AREA], "GET %s HTTP/1.1\r\nHOST: %d.%d.%d.%d:%d\r\nConnection: close\r\n\r\n", path,
        endpoint.address.(net.IP4_Address)[0], endpoint.address.(net.IP4_Address)[1], endpoint.address.(net.IP4_Address)[2],
        endpoint.address.(net.IP4_Address)[3], endpoint.port)
    status, body, ok := PortMapHttp(state, endpoint, len(request), timeout_ms)
    if !ok || status != 200 {
        return false
    }
    // the first service of a WAN connection kind, and the control URL that follows its type
    from: int
    for {
        found: int = IndexOf(body[from:], "<serviceType>")
        if found < 0 {
            return false
        }
        start: int = from + found + len("<serviceType>")
        end: int = start + IndexOf(body[start:], "</serviceType>")
        if end < start {
            return false
        }
        service: string = body[start:end]
        from = end
        if IndexOf(service, "WANIPConnection") < 0 && IndexOf(service, "WANPPPConnection") < 0 {
            continue
        }
        control: string = TagValue(body[end:], "controlURL")
        if control == "" || len(control) > len(state.control_path) || len(service) > len(state.service) {
            return false
        }
        state.control_endpoint = endpoint
        control_path: string = control
        if control[0] != '/' {
            parsed_endpoint, parsed_path, parsed_ok := PortMapParseUrl(control)
            if parsed_ok {
                state.control_endpoint = parsed_endpoint
                control_path = parsed_path
            } else {
                // a relative path
                state.control_path[0] = '/'
                copy(state.control_path[1:], control)
                state.control_path_len = len(control) + 1
                copy(state.service[:], service)
                state.service_len = len(service)
                return len(control) + 1 <= len(state.control_path)
            }
        }
        copy(state.control_path[:], control_path)
        state.control_path_len = len(control_path)
        copy(state.service[:], service)
        state.service_len = len(service)
        return true
    }
}

// A SOAP action on the control URL. `arguments` is the inside of the action element. Returns the HTTP status and the body.
@(private)
PortMapSoap :: proc(state: ^PortMapState, action: string, arguments: string, timeout_ms: i64) -> (status: int, body: string, ok: bool) {
    envelope: [1536]byte
    service: string = string(state.service[:state.service_len])
    content: string = fmt.bprintf(envelope[:],
        "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:%s xmlns:u=\"%s\">%s</u:%s></s:Body></s:Envelope>",
        action, service, arguments, action)
    address: net.IP4_Address = state.control_endpoint.address.(net.IP4_Address)
    request: string = fmt.bprintf(state.scratch[:PORTMAP_REQUEST_AREA],
        "POST %s HTTP/1.1\r\nHOST: %d.%d.%d.%d:%d\r\nCONTENT-TYPE: text/xml; charset=\"utf-8\"\r\nSOAPACTION: \"%s#%s\"\r\nCONTENT-LENGTH: %d\r\nConnection: close\r\n\r\n%s",
        string(state.control_path[:state.control_path_len]), address[0], address[1], address[2], address[3], state.control_endpoint.port,
        service, action, len(content), content)
    return PortMapHttp(state, state.control_endpoint, len(request), timeout_ms)
}

// Describes the router at `location`, then asks for the port. `internal` is the address of this computer on that network.
PortMapTryUpnp :: proc(state: ^PortMapState, location: string, internal: net.IP4_Address, internal_port: int, timeout_ms: i64) -> bool {
    if !PortMapUpnpDescribe(state, location, timeout_ms) {
        return false
    }
    status, body, ok := PortMapSoap(state, "GetExternalIPAddress", "", timeout_ms)
    if !ok || status != 200 {
        return false
    }
    public, public_ok := net.parse_ip4_address(TagValue(body, "NewExternalIPAddress"))
    if !public_ok {
        return false
    }
    // another external port when the first is taken (718), a permanent lease when the router refuses lifetimes (725)
    lease: int = PORTMAP_LIFETIME_S
    for attempt in 0 ..< PORTMAP_PORT_TRIES {
        external_port: int = internal_port + attempt
        arguments: [512]byte
        text: string = fmt.bprintf(arguments[:],
            "<NewRemoteHost></NewRemoteHost><NewExternalPort>%d</NewExternalPort><NewProtocol>UDP</NewProtocol><NewInternalPort>%d</NewInternalPort><NewInternalClient>%d.%d.%d.%d</NewInternalClient><NewEnabled>1</NewEnabled><NewPortMappingDescription>odin p2p</NewPortMappingDescription><NewLeaseDuration>%d</NewLeaseDuration>",
            external_port, internal_port, internal[0], internal[1], internal[2], internal[3], lease)
        status, body, ok = PortMapSoap(state, "AddPortMapping", text, timeout_ms)
        if ok && status == 200 {
            state.protocol = .UPNP
            state.gateway = state.control_endpoint.address.(net.IP4_Address)
            state.external = {address = public, port = external_port}
            state.internal_port = internal_port
            state.lifetime_s = u32(lease)
            return true
        }
        code: string = TagValue(body, "errorCode")
        if code == "725" {
            lease = 0
            continue
        }
        if code != "718" && code != "" {
            return false
        }
    }
    return false
}

// ============================================================ all of it

// Tries every default gateway with PCP, NAT-PMP and UPnP. On success `state.external` is the public address and port, and the
// caller offers it as a candidate; `PortMapClose` gives it back. A mapping whose router address is private (another NAT in
// front of the router) is useless from outside: it is removed again and `state.double_nat` says so.
PortMapOpen :: proc(state: ^PortMapState, internal_port: int, timeout_ms: i64 = 1500) -> bool {
    state.protocol = .NONE
    state.double_nat = false
    gateways: [PORTMAP_MAX_GATEWAYS]net.IP4_Address
    count: int = PortMapGateways(gateways[:])
    for i in 0 ..< count {
        gateway: net.Endpoint = {address = gateways[i], port = PORTMAP_PORT}
        internal, internal_ok := PortMapLocalAddress(gateways[i])
        if !internal_ok {
            continue
        }
        if !PortMapTryUdp(state, gateway, internal, internal_port, timeout_ms) {
            url: [256]byte
            length: int = PortMapSsdpSearch(gateways[i], url[:], timeout_ms)
            if length == 0 || !PortMapTryUpnp(state, string(url[:length]), internal, internal_port, timeout_ms) {
                continue
            }
        }
        if !IsPublicAddress(state.external.address) {
            state.double_nat = true
            PortMapClose(state, timeout_ms)
            return false
        }
        return true
    }
    return false
}

// Removes the mapping at the router (a lease would end it anyway, but a game that quits should not leave a hole).
PortMapClose :: proc(state: ^PortMapState, timeout_ms: i64 = 1500) {
    protocol: PortMapProtocol = state.protocol
    state.protocol = .NONE
    switch protocol {
    case .NONE:
    case .PCP, .NAT_PMP:
        socket, ok := PortMapSocket()
        if !ok {
            return
        }
        defer net.close(socket)
        gateway: net.Endpoint = {address = state.gateway, port = PORTMAP_PORT}
        request: [PORTMAP_PCP_SIZE]byte
        reply: [128]byte
        length: int
        if protocol == .PCP {
            nonce: PortMapNonce
            crypto.rand_bytes(nonce[:])
            length = PortMapPcpRequest(request[:], {}, nonce, u16(state.internal_port), u16(state.external.port), 0)
        } else {
            length = PortMapNatPmpMapRequest(request[:], u16(state.internal_port), 0, 0)
        }
        PortMapAsk(socket, gateway, request[:length], reply[:], timeout_ms / 3)
    case .UPNP:
        arguments: [128]byte
        text: string = fmt.bprintf(arguments[:], "<NewRemoteHost></NewRemoteHost><NewExternalPort>%d</NewExternalPort><NewProtocol>UDP</NewProtocol>", state.external.port)
        PortMapSoap(state, "DeletePortMapping", text, timeout_ms)
    }
}

// ============================================================ small text helpers (no allocation)

IndexOf :: proc(text: string, pattern: string) -> int {
    for i in 0 ..< len(text) - len(pattern) + 1 {
        if text[i:i + len(pattern)] == pattern {
            return i
        }
    }
    return -1
}

// "<tag>value</tag>": the value of the first such element.
TagValue :: proc(text: string, tag: string) -> string {
    open: [48]byte
    close: [48]byte
    opening: string = fmt.bprintf(open[:], "<%s>", tag)
    closing: string = fmt.bprintf(close[:], "</%s>", tag)
    start: int = IndexOf(text, opening)
    if start < 0 {
        return ""
    }
    start += len(opening)
    end: int = IndexOf(text[start:], closing)
    if end < 0 {
        return ""
    }
    return text[start:start + end]
}

// "Name: value" of an HTTP style header, name case free, the value without its blanks.
HeaderValue :: proc(text: string, name: string) -> string {
    for line_start := 0; line_start < len(text); {
        line_end: int = IndexOf(text[line_start:], "\r\n")
        line: string = text[line_start:] if line_end < 0 else text[line_start:line_start + line_end]
        if len(line) > len(name) && line[len(name)] == ':' {
            same: bool = true
            for i in 0 ..< len(name) {
                a: byte = line[i] | 0x20
                b: byte = name[i] | 0x20
                same &&= a == b
            }
            if same {
                value: string = line[len(name) + 1:]
                for len(value) > 0 && value[0] == ' ' {
                    value = value[1:]
                }
                return value
            }
        }
        if line_end < 0 {
            break
        }
        line_start += line_end + 2
    }
    return ""
}

// ============================================================ tests

@(test)
PortMapNatPmpCodecTest :: proc(t: ^testing.T) {
    request: [PORTMAP_PCP_SIZE]byte
    testing.expect_value(t, PortMapNatPmpMapRequest(request[:], 4000, 4001, 7200), 12)
    testing.expect_value(t, GetU16BE(request[4:]), u16(4000))
    testing.expect_value(t, GetU16BE(request[6:]), u16(4001))
    testing.expect_value(t, GetU32BE(request[8:]), u32(7200))

    // what a router answers: version 0, opcode 129, result 0, epoch, ports, lifetime
    reply: [16]byte
    reply[1] = 129
    PutU16BE(reply[8:], 4000)
    PutU16BE(reply[10:], 4005)
    PutU32BE(reply[12:], 3600)
    port, lifetime, ok := PortMapNatPmpMapParse(reply[:], 4000)
    testing.expect(t, ok)
    testing.expect_value(t, port, u16(4005))
    testing.expect_value(t, lifetime, u32(3600))
    _, _, wrong_port := PortMapNatPmpMapParse(reply[:], 4001)
    testing.expect(t, !wrong_port)
    reply[2] = 0
    reply[3] = 2        // result: not authorized
    _, _, refused := PortMapNatPmpMapParse(reply[:], 4000)
    testing.expect(t, !refused)

    address: [12]byte
    address[1] = 128
    address[8], address[9], address[10], address[11] = 203, 0, 113, 7
    ip, ip_ok := PortMapNatPmpAddressParse(address[:])
    testing.expect(t, ip_ok && ip == net.IP4_Address{203, 0, 113, 7})
}

@(test)
PortMapPcpCodecTest :: proc(t: ^testing.T) {
    nonce: PortMapNonce = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
    request: [PORTMAP_PCP_SIZE]byte
    testing.expect_value(t, PortMapPcpRequest(request[:], {192, 168, 1, 20}, nonce, 4000, 4000, 7200), PORTMAP_PCP_SIZE)
    testing.expect_value(t, request[0], u8(2))
    testing.expect_value(t, request[1], u8(1))
    testing.expect_value(t, request[36], u8(17))
    testing.expect_value(t, request[20], u8(192))

    reply: [PORTMAP_PCP_SIZE]byte
    reply[0] = 2
    reply[1] = 0x81
    PutU32BE(reply[4:], 7200)
    copy(reply[24:36], nonce[:])
    PutU16BE(reply[42:], 4123)
    reply[54], reply[55] = 0xFF, 0xFF
    reply[56], reply[57], reply[58], reply[59] = 203, 0, 113, 7
    external, lifetime, ok := PortMapPcpParse(reply[:], nonce)
    testing.expect(t, ok)
    testing.expect_value(t, external, net.Endpoint{address = net.IP4_Address{203, 0, 113, 7}, port = 4123})
    testing.expect_value(t, lifetime, u32(7200))
    other: PortMapNonce = {9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9}
    _, _, wrong_nonce := PortMapPcpParse(reply[:], other)
    testing.expect(t, !wrong_nonce)
    reply[3] = 2
    _, _, refused := PortMapPcpParse(reply[:], nonce)
    testing.expect(t, !refused)
}

@(test)
PortMapTextTest :: proc(t: ^testing.T) {
    endpoint, path, ok := PortMapParseUrl("http://192.168.1.1:49152/rootDesc.xml")
    testing.expect(t, ok)
    testing.expect_value(t, endpoint, net.Endpoint{address = net.IP4_Address{192, 168, 1, 1}, port = 49152})
    testing.expect_value(t, path, "/rootDesc.xml")
    endpoint, path, ok = PortMapParseUrl("http://10.0.0.1/desc")
    testing.expect(t, ok && endpoint.port == 80 && path == "/desc")
    _, _, bad := PortMapParseUrl("https://router.local/x")
    testing.expect(t, !bad)

    testing.expect_value(t, TagValue("<a><controlURL>/ctl/IPConn</controlURL></a>", "controlURL"), "/ctl/IPConn")
    testing.expect_value(t, TagValue("<a></a>", "controlURL"), "")
    response: string = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=120\r\nLocation: http://192.168.1.1:5000/desc.xml\r\nST: x\r\n\r\n"
    testing.expect_value(t, HeaderValue(response, "location"), "http://192.168.1.1:5000/desc.xml")
    testing.expect_value(t, HeaderValue(response, "nothing"), "")
}

// A router on loopback that speaks PCP, then NAT-PMP only, over UDP.
@(private = "file")
FakeRouter :: struct {
    socket: net.UDP_Socket,
    speaks_pcp: bool,
    address: net.IP4_Address,       // the public address it reports
    done: bool,
}

@(private = "file")
FakeRouterRun :: proc(router: ^FakeRouter) {
    buffer: [128]byte
    start: i64 = LinkNow()
    for !router.done && LinkNow() - start < 5000 {
        length, from, error := net.recv_udp(router.socket, buffer[:])
        if error != nil || length <= 0 {
            time.sleep(time.Millisecond)
            continue
        }
        reply: [PORTMAP_PCP_SIZE]byte
        switch {
        case buffer[0] == 2 && length >= PORTMAP_PCP_SIZE:
            if !router.speaks_pcp {
                // NAT-PMP only: "unsupported version"
                reply[1] = 0x81
                reply[3] = 1
                net.send_udp(router.socket, reply[:8], from)
                continue
            }
            reply[0] = 2
            reply[1] = 0x81
            PutU32BE(reply[4:], 7200)
            copy(reply[24:36], buffer[24:36])
            reply[36] = 17
            PutU16BE(reply[40:], GetU16BE(buffer[40:]))
            PutU16BE(reply[42:], GetU16BE(buffer[42:]) + 100)
            reply[54], reply[55] = 0xFF, 0xFF
            copy(reply[56:60], router.address[:])
            net.send_udp(router.socket, reply[:], from)
        case buffer[0] == 0 && buffer[1] == 0:
            reply[1] = 128
            copy(reply[8:12], router.address[:])
            net.send_udp(router.socket, reply[:12], from)
        case buffer[0] == 0 && buffer[1] == 1:
            reply[1] = 129
            PutU16BE(reply[8:], GetU16BE(buffer[4:]))
            PutU16BE(reply[10:], GetU16BE(buffer[4:]) + 200)
            PutU32BE(reply[12:], GetU32BE(buffer[8:]))
            net.send_udp(router.socket, reply[:16], from)
        }
    }
}

@(private = "file")
TestRouterUdp :: proc(t: ^testing.T, speaks_pcp: bool, expected: PortMapProtocol, expected_port: int) {
    socket, make_error := net.make_unbound_udp_socket(.IP4)
    testing.expect(t, make_error == nil)
    defer net.close(socket)
    testing.expect(t, net.bind(socket, {address = net.IP4_Loopback, port = 0}) == nil)
    testing.expect(t, net.set_blocking(socket, false) == nil)
    endpoint, _ := net.bound_endpoint(socket)
    router: FakeRouter = {socket = socket, speaks_pcp = speaks_pcp, address = {203, 0, 113, 7}}
    worker: ^thread.Thread = thread.create_and_start_with_poly_data(&router, FakeRouterRun)
    defer thread.destroy(worker)

    state: ^PortMapState = new(PortMapState)
    defer free(state)
    testing.expect(t, PortMapTryUdp(state, endpoint, {192, 168, 1, 20}, 4000, 1500))
    testing.expect_value(t, state.protocol, expected)
    testing.expect_value(t, state.external, net.Endpoint{address = net.IP4_Address{203, 0, 113, 7}, port = expected_port})
    router.done = true
    thread.join(worker)
}

@(test)
PortMapPcpRouterTest :: proc(t: ^testing.T) {
    TestRouterUdp(t, true, .PCP, 4100)
}

@(test)
PortMapNatPmpRouterTest :: proc(t: ^testing.T) {
    TestRouterUdp(t, false, .NAT_PMP, 4200)
}

@(test)
PortMapSilentRouterTest :: proc(t: ^testing.T) {
    // nobody answers: the attempt ends by its own timeout and says no
    socket, _ := net.make_unbound_udp_socket(.IP4)
    defer net.close(socket)
    net.bind(socket, {address = net.IP4_Loopback, port = 0})
    endpoint, _ := net.bound_endpoint(socket)
    state: ^PortMapState = new(PortMapState)
    defer free(state)
    started: i64 = LinkNow()
    testing.expect(t, !PortMapTryUdp(state, endpoint, {192, 168, 1, 20}, 4000, 300))
    testing.expect(t, LinkNow() - started < 2000)
    testing.expect_value(t, state.protocol, PortMapProtocol.NONE)
}

// A router description and control service over TCP on loopback.
@(private = "file")
FakeIgd :: struct {
    listener: net.TCP_Socket,
    port: int,
    done: bool,
    conflicts: int,                 // answer AddPortMapping with 718 this many times
    mapped_port: int,
    deleted: bool,
}

@(private = "file")
FakeIgdRun :: proc(igd: ^FakeIgd) {
    buffer: [4096]byte
    start: i64 = LinkNow()
    for !igd.done && LinkNow() - start < 8000 {
        client, _, accept_error := net.accept_tcp(igd.listener)
        if accept_error != nil {
            time.sleep(time.Millisecond)
            continue
        }
        net.set_option(client, .Receive_Timeout, 500 * time.Millisecond)
        length, _ := net.recv_tcp(client, buffer[:])
        request: string = string(buffer[:max(length, 0)])
        answer: [1024]byte
        text: string
        switch {
        case IndexOf(request, "GET /rootDesc.xml") == 0:
            text = fmt.bprintf(answer[:], "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nConnection: close\r\n\r\n<root><device><serviceList><service><serviceType>urn:schemas-upnp-org:service:Layer3Forwarding:1</serviceType><controlURL>/ctl/L3F</controlURL></service></serviceList><deviceList><device><serviceList><service><serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType><controlURL>/ctl/IPConn</controlURL></service></serviceList></device></deviceList></device></root>")
        case IndexOf(request, "#GetExternalIPAddress") >= 0:
            text = fmt.bprintf(answer[:], "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n<s:Envelope><s:Body><u:GetExternalIPAddressResponse><NewExternalIPAddress>203.0.113.7</NewExternalIPAddress></u:GetExternalIPAddressResponse></s:Body></s:Envelope>")
        case IndexOf(request, "#AddPortMapping") >= 0:
            if igd.conflicts > 0 {
                igd.conflicts -= 1
                text = fmt.bprintf(answer[:], "HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\n<s:Envelope><s:Body><s:Fault><detail><UPnPError><errorCode>718</errorCode></UPnPError></detail></s:Fault></s:Body></s:Envelope>")
            } else {
                port_text: string = TagValue(request, "NewExternalPort")
                igd.mapped_port, _ = strconv.parse_int(port_text)
                text = fmt.bprintf(answer[:], "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n<s:Envelope><s:Body><u:AddPortMappingResponse/></s:Body></s:Envelope>")
            }
        case IndexOf(request, "#DeletePortMapping") >= 0:
            igd.deleted = true
            text = fmt.bprintf(answer[:], "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
        case:
            text = fmt.bprintf(answer[:], "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n")
        }
        net.send_tcp(client, transmute([]byte)text)
        net.close(client)
    }
}

@(test)
PortMapUpnpRouterTest :: proc(t: ^testing.T) {
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = 0})
    testing.expect(t, listen_error == nil)
    defer net.close(listener)
    net.set_blocking(listener, false)
    endpoint, _ := net.bound_endpoint(listener)
    igd: FakeIgd = {listener = listener, port = endpoint.port, conflicts = 2}
    worker: ^thread.Thread = thread.create_and_start_with_poly_data(&igd, FakeIgdRun)
    defer thread.destroy(worker)

    state: ^PortMapState = new(PortMapState)
    defer free(state)
    location: [64]byte
    url: string = fmt.bprintf(location[:], "http://127.0.0.1:%d/rootDesc.xml", endpoint.port)
    testing.expect(t, PortMapTryUpnp(state, url, {192, 168, 1, 20}, 4000, 2000))
    testing.expect_value(t, state.protocol, PortMapProtocol.UPNP)
    // two conflicts, so the third external port is the one that was granted
    testing.expect_value(t, state.external, net.Endpoint{address = net.IP4_Address{203, 0, 113, 7}, port = 4002})
    testing.expect_value(t, igd.mapped_port, 4002)
    PortMapClose(state, 2000)
    testing.expect(t, igd.deleted)
    testing.expect_value(t, state.protocol, PortMapProtocol.NONE)
    igd.done = true
    thread.join(worker)
}
