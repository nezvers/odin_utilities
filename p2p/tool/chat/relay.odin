// --find-relay: which relay (TURN) servers answer from this network, and what to do with them. See p2p.RelayFind.
package main

import "core:fmt"
import "core:os"
import "core:strings"
import p2p "../.."

RELAY_SEARCH_MS :: 3000

// Lists the relays that answer, and lets the person type credentials for one of them (they come from a free sign-up).
// Before the keyboard reader thread starts. `turn` is filled when credentials were given.
FindRelay :: proc(turn: ^TurnOptions) {
    fmt.println("Searching for relay (TURN) servers that answer from this network (UDP, takes a few seconds)...")
    hosts: [len(p2p.RELAY_CANDIDATES)]string
    for candidate, i in p2p.RELAY_CANDIDATES {
        hosts[i] = candidate.host
    }
    infos: [len(p2p.RELAY_CANDIDATES)]p2p.RelayInfo
    alive: int = p2p.RelayFind(hosts[:], infos[:], RELAY_SEARCH_MS)
    if alive == 0 {
        fmt.println("No relay answered (offline, or UDP to them is blocked here). Going without one.")
        return
    }
    wants_login: int
    for info, i in infos {
        candidate: p2p.RelayCandidate = p2p.RELAY_CANDIDATES[i]
        switch info.state {
        case .WANTS_LOGIN:
            wants_login += 1
            fmt.printfln("  alive, wants a login  %-34s %4d ms  %s", candidate.host, info.rtt_ms, candidate.provider)
            if candidate.signup != "" {
                fmt.printfln("                        free account: %s", candidate.signup)
            }
        case .OPEN:
            fmt.printfln("  OPEN (no login)       %-34s %4d ms  %s   <- allocated without credentials", candidate.host, info.rtt_ms, candidate.provider)
        case .OTHER_ERROR:
            fmt.printfln("  alive, refused (%d)  %-34s %4d ms  %s", info.code, candidate.host, info.rtt_ms, candidate.provider)
        case .UNRESOLVED, .NO_ANSWER:
        }
    }
    fmt.println("A relay only carries the traffic when a direct connection is impossible (both behind carrier NAT, symmetric NAT).")
    if wants_login == 0 || turn.host != "" {
        return
    }
    fmt.println("If you have an account at one of them, type:  host:port username password   (or just press Enter to go without a relay)")
    line: string = ReadLine()
    parts: []string = strings.fields(line, context.temp_allocator)
    if len(parts) == 3 {
        turn.host = parts[0]
        turn.user = parts[1]
        turn.password = parts[2]
        fmt.printfln("Using the relay %s.", turn.host)
    } else if len(parts) != 0 {
        fmt.println("Expected three words: host:port username password. Going without a relay.")
    }
}

// A blocking line from the keyboard, only for use before the reader thread starts. Kept alive in the temp allocator.
ReadLine :: proc() -> string {
    line: [MAX_LINE]byte
    length: int
    for length < len(line) {
        one: [1]byte
        count, error := os.read(os.stdin, one[:])
        if error != nil || count <= 0 || one[0] == '\n' {
            break
        }
        if one[0] != '\r' {
            line[length] = one[0]
            length += 1
        }
    }
    return strings.clone(string(line[:length]), context.temp_allocator)
}
