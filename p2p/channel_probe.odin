package p2p

import "core:sync"

// Two members that start at the same moment can both become the host of a channel: both connect to the relay with the channel key and
// the relay hands everything to the NEWER connection, the older one never hears anything (measured on a real relay: no error, no
// closed connection). The member that believes it is the host asks, from a second short connection with a key of its own, who answers
// for the channel key, and compares the id in the answer with its own. One connection of a few KB for a few seconds, once or twice
// after it became the host.
ChannelProbeState :: enum {
    IDLE,
    WAITING,
    FOUND,                               // somebody answered: `found` is its invite
    NOBODY,                              // no answer (or the relay could not be used): inconclusive
}

ChannelProbe :: struct {
    state: ChannelProbeState,
    derp: ^Derp,
    key: BoxKey,                         // the channel key that is asked
    start_ms: i64,
    sent_ms: i64,
    tries: int,
    found: Invite,
}

CHANNEL_PROBE_TRIES :: 4
CHANNEL_PROBE_CONNECT_MS :: 12000

ChannelProbeBegin :: proc(probe: ^ChannelProbe, relay_host: string, channel_public: BoxKey, now_ms: i64) -> bool {
    private, public: BoxKey
    if probe.state != .IDLE || !BoxKeyGenerate(&private, &public) {
        return false
    }
    probe^ = {state = .WAITING, key = channel_public, start_ms = now_ms}
    probe.derp = new(Derp)
    DerpBegin(probe.derp, relay_host, private)
    return true
}

ChannelProbeUpdate :: proc(probe: ^ChannelProbe, now_ms: i64) -> ChannelProbeState {
    if probe.state != .WAITING {
        return probe.state
    }
    #partial switch DerpGetState(probe.derp) {
    case .FAILED, .CLOSED:
        probe.state = .NOBODY
    case .READY:
        packet: [PACKET_HEADER]byte
        if probe.tries < CHANNEL_PROBE_TRIES && now_ms - probe.sent_ms >= DERP_SIGNAL_MS {
            packet[0] = PACKET_MAGIC
            packet[1] = u8(PacketKind.WHO)
            DerpSend(probe.derp, probe.key, packet[:])
            probe.sent_ms = now_ms
            probe.tries += 1
        }
        buffer: [PACKET_HEADER + CODE_BINARY_MAX + 64]byte
        for _ in 0 ..< 8 {
            derp_packet, got, _ := DerpPoll(probe.derp, buffer[:])
            if !got {
                break
            }
            data: []byte = buffer[:derp_packet.length]
            if derp_packet.from == probe.key && len(data) > PACKET_HEADER && data[0] == PACKET_MAGIC && PacketKind(data[1]) == .HERE {
                invite, ok := InviteFromBinary(data[PACKET_HEADER:])
                if ok && invite.kind == .INVITE {
                    probe.found = invite
                    probe.state = .FOUND
                    break
                }
            }
        }
        if probe.state == .WAITING && probe.tries >= CHANNEL_PROBE_TRIES && now_ms - probe.sent_ms >= 2 * DERP_SIGNAL_MS {
            probe.state = .NOBODY
        }
    case:
        if now_ms - probe.start_ms >= CHANNEL_PROBE_CONNECT_MS {
            probe.state = .NOBODY
        }
    }
    return probe.state
}

// Frees the connection. A connect that still hangs is abandoned (its thread closes it), like the relay of a Link.
ChannelProbeClose :: proc(probe: ^ChannelProbe) {
    if probe.derp != nil {
        if DerpGetState(probe.derp) == .CONNECTING {
            sync.atomic_store(&probe.derp.abandoned, true)
        } else {
            DerpClose(probe.derp)
            free(probe.derp)
        }
    }
    probe^ = {}
}
