#+build !js
package arena_session

// How the players of the arena get together: the generic session of `odin_utilities/spacetimedb/session` (host with a p2p invite, guest with a tunnel, codes, rooms) with the arena's module and
// database filled in. Everything else is the generic package under the same names, so the arena code reads as before:
//
//     host:   HostStart(host, {name = "Ada"})  ->  HostInvite(host) is the code to give out  ->  HostAcceptReply(host, reply code of a guest)
//     guest:  GuestJoin(guest, invite code, "Bob") -> the reply code to send back  ->  GuestConnected(guest) -> GuestEndpoint(guest) is where the game connects
//
// A game of your own uses `spacetimedb/session` directly (or its `Lobby`) with its own module and database name.

import "core:time"
import st "../.."
import base "../../session"

ARENA_DATABASE :: "arena"

SERVER_PORT :: base.SERVER_PORT
STAGE_GATHER_MS :: base.STAGE_GATHER_MS
STAGE_RELAY_MS :: base.STAGE_RELAY_MS
STAGE_FIND_MS :: base.STAGE_FIND_MS
ROOM_WORDS :: base.ROOM_WORDS

HostOptions :: base.HostOptions
GuestOptions :: base.GuestOptions
Stage :: base.Stage
Host :: base.Host
Guest :: base.Guest
CodeKind :: base.CodeKind

HostElapsedMs :: base.HostElapsedMs
HostRoom :: base.HostRoom
HostInvite :: base.HostInvite
HostAcceptReply :: base.HostAcceptReply
HostNotice :: base.HostNotice
HostGuests :: base.HostGuests
HostConnectedGuests :: base.HostConnectedGuests
HostUpdate :: base.HostUpdate
HostStop :: base.HostStop
GuestNotice :: base.GuestNotice
GuestJoin :: base.GuestJoin
GuestBegin :: base.GuestBegin
GuestBeginRoom :: base.GuestBeginRoom
GuestElapsedMs :: base.GuestElapsedMs
GuestReply :: base.GuestReply
GuestUpdate :: base.GuestUpdate
GuestConnected :: base.GuestConnected
GuestStartTunnel :: base.GuestStartTunnel
GuestEndpoint :: base.GuestEndpoint
GuestStop :: base.GuestStop
SetIdle :: base.SetIdle
ClearIdle :: base.ClearIdle
CodeInspect :: base.CodeInspect
RoomLooksLike :: base.RoomLooksLike

// The arena's database and module are the defaults of a host
@(private)
arenaOptions :: proc(options: HostOptions) -> HostOptions {
    filled: HostOptions = options
    if filled.database == "" { filled.database = ARENA_DATABASE }
    if filled.module_path == "" { filled.module_path = st.FixturePath("arena-odin") }
    return filled
}

// Starts the server, publishes the arena module, opens the p2p side and makes the invite: `HostBegin` and then the waiting. False with `host.error` set.
HostStart :: proc(host: ^Host, options: HostOptions) -> bool {
    if !HostBegin(host, options) { return false }
    for host.stage == .GATHERING || host.stage == .RELAY {
        HostUpdate(host)
        time.sleep(10 * time.Millisecond)
    }
    return host.stage == .READY
}

// The first part: the server (blocking, a second or two), the module, the link; then the stage is GATHERING and `HostUpdate` brings it to READY. False with `host.error` set.
HostBegin :: proc(host: ^Host, options: HostOptions) -> bool {
    return base.HostBegin(host, arenaOptions(options))
}
