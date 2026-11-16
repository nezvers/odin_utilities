// Tries to open a UDP port on YOUR router with PCP, NAT-PMP and UPnP, one at a time, and says what each answered.
//
//   odin run p2p/tool/portmap [-- port]
//
// It opens the port (default 40123), prints the public address that now reaches this computer, and removes it again. Run it
// on the network you plan to play on: it tells whether the router can be asked to forward a port at all.
package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import p2p "../.."

main :: proc() {
    port: int = 40123
    if len(os.args) > 1 {
        parsed, ok := strconv.parse_int(os.args[1])
        if !ok || parsed <= 0 || parsed > 65535 {
            fmt.eprintln("usage: portmap [port]")
            os.exit(2)
        }
        port = parsed
    }
    state: ^p2p.PortMapState = new(p2p.PortMapState)
    gateways: [p2p.PORTMAP_MAX_GATEWAYS]net.IP4_Address
    count: int = p2p.PortMapGateways(gateways[:])
    if count == 0 {
        fmt.println("no default gateway found (no network?)")
        os.exit(1)
    }
    found: bool
    for i in 0 ..< count {
        gateway: net.IP4_Address = gateways[i]
        internal, internal_ok := p2p.PortMapLocalAddress(gateway)
        fmt.printfln("gateway %v, this computer on it: %v", gateway, internal if internal_ok else net.IP4_Address{})
        if !internal_ok {
            continue
        }

        start: i64 = p2p.LinkNow()
        if p2p.PortMapTryUdp(state, {address = gateway, port = p2p.PORTMAP_PORT}, internal, port, 1500) {
            Report(state, p2p.LinkNow() - start)
            found = true
            p2p.PortMapClose(state)
            continue
        }
        fmt.printfln("  PCP / NAT-PMP: no answer (%d ms)", p2p.LinkNow() - start)

        start = p2p.LinkNow()
        url: [256]byte
        length: int = p2p.PortMapSsdpSearch(gateway, url[:], 2000)
        if length == 0 {
            fmt.printfln("  UPnP: no router answered the search (%d ms)", p2p.LinkNow() - start)
            continue
        }
        fmt.printfln("  UPnP: router description at %s", string(url[:length]))
        if p2p.PortMapTryUpnp(state, string(url[:length]), internal, port, 3000) {
            Report(state, p2p.LinkNow() - start)
            found = true
            p2p.PortMapClose(state)
        } else {
            fmt.println("  UPnP: the router refused the mapping (UPnP switched off, or the port taken)")
        }
    }
    if found {
        fmt.println("RESULT: this router can forward a port on request: p2p can offer a fixed public address here.")
    } else {
        fmt.println("RESULT: no port mapping available on this network (hole punching is all there is).")
    }
}

Report :: proc(state: ^p2p.PortMapState, ms: i64) {
    fmt.printfln("  %v: mapped %v -> this computer port %d, lifetime %d s (%d ms)", state.protocol,
        net.endpoint_to_string(state.external, context.temp_allocator), state.internal_port, state.lifetime_s, ms)
    if !p2p.IsPublicAddress(state.external.address) {
        fmt.println("  but that address is private: another NAT sits in front of this router, the mapping does not reach the internet")
    }
}
