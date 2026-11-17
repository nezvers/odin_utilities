#+build !js
// A channel of people and programs (humans at a terminal, AI agents) that talk to each other directly over p2p, no server.
//
//   m: ^Messenger = new(Messenger)                      // ~340 KB of fixed storage, place it once
//   MessengerOpen(m, {channel = "my-project", name = "alice", receive_dir = "received", auto_accept = true})
//   every frame: MessengerUpdate(m, p2p.LinkNow()); then MessengerPoll(m) until it returns false
//   MessengerSendText(m, ALL, "hello") / (m, MessengerFindMember(m, "bob"), "hi bob")
//   MessengerSendFile(m, member, "build/game.zip")      // events report the progress and the verdict
//
// Topology: a star. One member is the host (the first to open the channel, or the one asked to be), the others are its guests, each
// joined by the normal p2p handshake. Messages between two guests are forwarded by the host, which also checks who is speaking.
// The host is the weak point: when it leaves, the channel ends (a guest could take over later, that is not done).
//
// Finding the others: on the same computer or network by the channel name alone (discovery.odin); across the internet by pasted
// codes (MessengerCode / MessengerUseCode, the same codes as tool/chat). Everything is non blocking after MessengerOpen (which may
// look up STUN servers, blocking, once).
//
// Files travel in chunks over the reliable channel, with a credit window, a sha256 check at the end and a verdict back to the
// sender. The receiver decides: `auto_accept` into `receive_dir` (names reduced to a safe file name, never overwriting), or an event
// asks the program and it calls MessengerFileAnswer.
//
// Fixed capacities, failures are returned (false) or reported as events, nothing grows.
package ai_messaging

import "base:runtime"
import "core:crypto"
import "core:crypto/sha2"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import p2p "../p2p"
import serial "../serial"

EVENTS :: 64
FORWARDS :: 96
MAX_OUT :: 4
MAX_IN :: 4
FILE_WINDOW :: 12 * FILE_CHUNK           // bytes a sender may have sent beyond what the receiver credited (the link window holds 16 frames)
CREDIT_EVERY :: 3 * FILE_CHUNK
OFFER_TIMEOUT_MS :: 30000
STALL_TIMEOUT_MS :: 30000
SEARCH_MS :: 1500                        // how long a newcomer asks around before it becomes the host (plus up to 700 ms of jitter)
ASK_INTERVAL_MS :: 400
JOIN_INTERVAL_MS :: 500
DEFAULT_MAX_FILE :: u64(1) << 30
PASSWORD_MAX :: 64
PROBE_DELAY_MS :: 4000                   // after becoming the host of a channel at the relay: is another member the host as well?
PROBE_AGAIN_MS :: 12000
PROBE_ROUNDS :: 2

Role :: enum {
    AUTO,                                // look for a host of the channel, become one when there is none
    HOST,                                // be the host, do not look
    GUEST,                               // only look (and accept a pasted code): never become the host
}

MessengerConfig :: struct {
    channel: string,
    // Optional: makes the channel private. The name alone finds a channel, so anybody who guesses "test" could join, listen to the beacon
    // or take the place of the host at the relay. With a password, everything that finds the channel (the relay key, the beacon hash, the
    // beacon contents) is made from name AND password, so a stranger cannot find it, join it, or read the session secret. Use a long
    // random one; every member needs the same. It is only for finding: the session itself is protected by the secret in the invite.
    password: string,
    name: string,
    role: Role,
    lan: bool,                           // use the discovery beacon (same computer / network)
    // Over the internet by channel name alone, through a free Tailscale DERP relay (p2p/derp.odin): the number of the relay (1 = the first
    // of p2p.DERP_SERVERS, all members must use the same one), 0 = off. The host sits at the relay under a key derived from the channel name,
    // guests ask that key and join; nothing is pasted. The relay carries the connection when no direct path works and the members move to a
    // direct path when one does. The name is the secret: anybody who knows it can join.
    // 255 (p2p.DERP_CUSTOM) with `derp_host`: any DERP server by name (a relay of your own, or one that is not in the built in list).
    derp_server: int,
    derp_host: string,
    use_stun: bool,                      // look up the public address for codes that are sent over the internet (blocking at open)
    receive_dir: string,                 // incoming files go here ("" refuses all)
    auto_accept: bool,                   // accept offers without asking (else a FILE_OFFERED event, then MessengerFileAnswer)
    max_file_size: u64,                  // 0 = DEFAULT_MAX_FILE (a folder counts its whole stream)
    keep_executable: bool,               // folders: set the executable bit on files that had it (off: received files never run by themselves)
    link: p2p.LinkConfig,
}

EventKind :: enum {
    NONE,
    CONNECTED,                           // this member is now part of the channel (guest: the host answered, `member` = own id)
    MEMBER_JOINED,                       // `member` joined (text = its name)
    MEMBER_LEFT,                         // `member` left (text = its name)
    TEXT,                                // `member` said `text`; `to` tells if it was for everybody (ALL) or for this member only
    FILE_OFFERED,                        // `member` wants to send `text` (name), `size` bytes: MessengerFileAnswer(transfer)
    FILE_PROGRESS,                       // `done` of `size` bytes, `incoming` tells the direction
    FILE_DONE,                           // finished: `ok`; text = the saved path (incoming) or the reason when not ok
    ERROR,                               // `text` says what went wrong (could not reach the host, ...)
    AGENT_REQUEST,                       // `member` asks this member to start or dismiss its agent: `action`, text = the model asked for (may be empty)
    AGENT_STATUS,                        // the agent of `member`: `ok` = running, text = its model, `note` = what happened ("started", "declined", ...)
}

Event :: struct {
    kind: EventKind,
    member: u8,
    to: u8,
    transfer: u16,
    incoming: bool,
    ok: bool,
    size: u64,
    done: u64,
    files: u32,                          // FILE_OFFERED / FILE_DONE of a folder: how many files it holds (0 for a single file)
    folder: bool,
    agent: bool,                         // TEXT: said by the agent of `member`
    action: AgentAction,                 // AGENT_REQUEST
    text: [MAX_TEXT]byte,
    text_length: int,
    note: [AGENT_NOTE_MAX]byte,          // AGENT_STATUS
    note_length: int,
}

AGENT_NOTE_MAX :: 120
AGENT_MODEL_MAX :: 64

EventText :: proc(event: ^Event) -> string {
    return string(event.text[:event.text_length])
}

EventNote :: proc(event: ^Event) -> string {
    return string(event.note[:event.note_length])
}

Member :: struct {
    used: bool,
    name: [NAME_MAX]byte,
    name_length: int,
}

OutState :: enum {
    FREE,
    OFFERED,                             // waiting for the other side to accept
    SENDING,
    FINISHING,                           // everything sent, END sent, waiting for the verdict
}

OutTransfer :: struct {
    state: OutState,
    id: u16,
    to: u8,
    file: ^os.File,
    size: u64,
    sent: u64,
    credited: u64,
    end_sent: bool,
    active_ms: i64,                      // last sign of life, for the timeouts
    progress_ms: i64,
    hash: sha2.Context_256,
    bundle: ^Bundle,                     // a folder: the stream comes from here instead of the file
    pending: [FILE_CHUNK]byte,           // the next chunk, read already, waiting for room in the window
    pending_length: int,
}

InState :: enum {
    FREE,
    PENDING,                             // offered, the program has to answer
    RECEIVING,
}

InTransfer :: struct {
    state: InState,
    from: u8,
    id: u16,
    file: ^os.File,
    size: u64,
    received: u64,
    credited: u64,
    active_ms: i64,
    progress_ms: i64,
    name: [FILE_NAME_MAX + 1]byte,
    name_length: int,
    part_path: [FILE_NAME_MAX + 256]byte,
    part_length: int,
    hash: sha2.Context_256,
    folder: bool,
    files: u32,
    reader: BundleReader,
}

Forward :: struct {
    peer: int,
    length: int,
    data: [p2p.MAX_PAYLOAD]byte,
}

Phase :: enum {
    GATHERING,                           // the link is finding its addresses
    SEARCHING,                           // asking the network for a host
    HOSTING_WAIT,                        // no host found: reconnecting to the relay under the channel key, then hosting
    RUNNING,
    CLOSED,
}

PATH_MAX :: 260

Messenger :: struct {
    config: MessengerConfig,             // its strings point into the three buffers below (copies: the caller's may be temporary)
    channel_buffer: [64]byte,
    password_buffer: [PASSWORD_MAX]byte,
    channel_id_buffer: [64 + 1 + PASSWORD_MAX]byte,
    name_buffer: [NAME_MAX]byte,
    dir_buffer: [PATH_MAX]byte,
    derp_host_buffer: [p2p.DERP_HOST_MAX]byte,
    demoted: bool,                       // hosted the channel at the same moment as another member and lost: MessengerClose and MessengerOpen again to join it as a guest
    probe: p2p.ChannelProbe,             // the check for a second host of the channel (relay hosting only)
    probe_due_ms: i64,
    probe_rounds: int,
    ended: bool,                         // a guest lost its host (or the channel was never reachable): the program may MessengerClose and MessengerOpen again
    link: p2p.Link,
    phase: Phase,
    is_host: bool,
    joined: bool,                        // guest: has a host (found or pasted)
    self_id: u8,
    members: [MAX_MEMBERS]Member,
    beacon: Beacon,
    beacon_up: bool,
    host_beacon: net.Endpoint,           // guest: where the host's beacon answers from
    host_beacon_known: bool,
    search_start_ms: i64,
    search_ms: i64,
    ask_ms: i64,
    join_ms: i64,
    stun: [p2p.STUN_MAX_SERVERS]net.Endpoint,
    stun_count: int,
    channel_private: p2p.BoxKey,         // the channel's identity at the relay (derived from its name)
    channel_public: p2p.BoxKey,
    derp_finding: bool,
    derp_was_lost: bool,
    events: [EVENTS]Event,
    event_head: int,
    event_count: int,
    forwards: [FORWARDS]Forward,
    forward_count: int,
    outs: [MAX_OUT]OutTransfer,
    ins: [MAX_IN]InTransfer,
    next_transfer: u16,
    scratch: [p2p.MAX_PAYLOAD]byte,      // frames are built here, one at a time
}

// ============================================================================================ open / close

// Opens the sockets and starts finding addresses. Blocking only for the STUN name lookup when `use_stun` is set.
MessengerOpen :: proc(m: ^Messenger, config: MessengerConfig, now_ms: i64) -> bool {
    assert(config.channel != "" && config.name != "")
    m^ = {}
    m.config = config
    m.config.channel = StringKeep(m.channel_buffer[:], config.channel)
    m.config.name = StringKeep(m.name_buffer[:], config.name)
    m.config.password = StringKeep(m.password_buffer[:], config.password)
    MessengerSetReceiveDir(m, config.receive_dir)
    m.config.derp_host = StringKeep(m.derp_host_buffer[:], config.derp_host)
    if m.config.max_file_size == 0 {
        m.config.max_file_size = DEFAULT_MAX_FILE
    }
    link_config: p2p.LinkConfig = config.link
    link_config.include_loopback = true      // agents on one computer reach each other through 127.0.0.1
    if config.derp_server != 0 {
        m.channel_private, m.channel_public = p2p.DerpChannelKey(ChannelId(m))
        if config.role == .HOST {
            link_config.derp_private = m.channel_private          // the host IS the channel key at the relay
            link_config.derp_private_set = true
        }
    }
    if !p2p.LinkInit(&m.link, link_config) {
        return false
    }
    if config.use_stun {
        m.stun_count = p2p.LinkResolveStun(m.stun[:])
    }
    if config.derp_server != 0 && !DerpStart(m, now_ms) {
        return false
    }
    p2p.LinkGatherBegin(&m.link, m.stun[:m.stun_count], now_ms)
    m.phase = .GATHERING
    return true
}

// What the relay key is made from: the name, and the password when there is one.
@(private)
ChannelId :: proc(m: ^Messenger) -> string {
    if m.config.password == "" {
        return m.config.channel
    }
    length: int = copy(m.channel_id_buffer[:], m.config.channel)
    m.channel_id_buffer[length] = 0x1f
    length += 1
    length += copy(m.channel_id_buffer[length:], m.config.password)
    return string(m.channel_id_buffer[:length])
}

@(private)
DerpStart :: proc(m: ^Messenger, now_ms: i64) -> bool {
    if m.config.derp_server == p2p.DERP_CUSTOM {
        return p2p.LinkDerpBeginHost(&m.link, m.config.derp_host, now_ms)
    }
    return p2p.LinkDerpBegin(&m.link, m.config.derp_server, now_ms)
}

@(private)
StringKeep :: proc(buffer: []byte, text: string) -> string {
    count: int = min(len(buffer), len(text))
    copy(buffer[:count], text)
    return string(buffer[:count])
}

// Where incoming files go ("" refuses them). Can change at any time.
MessengerSetReceiveDir :: proc(m: ^Messenger, directory: string) {
    m.config.receive_dir = StringKeep(m.dir_buffer[:], directory)
}

MessengerClose :: proc(m: ^Messenger) {
    for &out in m.outs {
        OutFinish(m, &out, false, "closed")
    }
    for &in_ in m.ins {
        InFinish(m, &in_, false, "closed", true)
    }
    BeaconClose(&m.beacon)
    p2p.ChannelProbeClose(&m.probe)
    p2p.LinkClose(&m.link)
    m.phase = .CLOSED
}

// ============================================================================================ queries

MessengerName :: proc(m: ^Messenger, member: u8) -> string {
    if int(member) >= MAX_MEMBERS || !m.members[member].used {
        return ""
    }
    return string(m.members[member].name[:m.members[member].name_length])
}

// The id of the member with that name (case free), or UNKNOWN_ID.
MessengerFindMember :: proc(m: ^Messenger, name: string) -> u8 {
    for i in 0 ..< MAX_MEMBERS {
        if m.members[i].used && strings.equal_fold(MessengerName(m, u8(i)), name) {
            return u8(i)
        }
    }
    return UNKNOWN_ID
}

MessengerSelf :: proc(m: ^Messenger) -> u8 {
    return m.self_id
}

// Connected: in the channel and able to send.
MessengerReady :: proc(m: ^Messenger) -> bool {
    return m.phase == .RUNNING && m.self_id != UNKNOWN_ID && (m.is_host || m.joined)
}

// The text of this member's code, for pasting on another network. Empty before the link has a role.
MessengerCode :: proc(m: ^Messenger, buffer: []byte) -> string {
    if m.link.role == .NONE {
        return ""
    }
    text, ok := p2p.InviteEncode(p2p.LinkMakeInvite(&m.link), buffer)
    return text if ok else ""
}

// A pasted code. A host's invite makes this member its guest (then MessengerCode is the reply to send back); a guest's reply
// is accepted by the host. Returns a sentence to show.
MessengerUseCode :: proc(m: ^Messenger, text: string, now_ms: i64) -> (ok: bool, message: string) {
    if m.phase != .RUNNING && m.phase != .SEARCHING {
        return false, "not ready yet (still finding addresses)"
    }
    invite, decoded := p2p.InviteDecode(text)
    if !decoded {
        return false, "that is not a valid code (copy it whole)"
    }
    switch {
    case invite.kind == .REPLY && m.is_host:
        _, accepted := p2p.LinkAcceptReply(&m.link, invite, now_ms)
        return accepted, "reply accepted, connecting..." if accepted else "that reply is not for this channel (or the room is full)"
    case invite.kind == .INVITE && !m.is_host && !m.joined && m.link.role == .NONE:
        p2p.LinkJoin(&m.link, invite, m.config.name, now_ms)
        m.joined = true
        m.phase = .RUNNING
        return true, "joined, connecting... send your reply code (MessengerCode) back to the host"
    }
    return false, "that code is not the kind needed now"
}

// ============================================================================================ events

@(private)
EventPush :: proc(m: ^Messenger, kind: EventKind, member: u8 = 0, text: string = "") -> ^Event {
    if m.event_count >= EVENTS {
        // the oldest goes: a program that does not poll loses history, not its connection
        m.event_head = (m.event_head + 1) % EVENTS
        m.event_count -= 1
    }
    event: ^Event = &m.events[(m.event_head + m.event_count) % EVENTS]
    event^ = {kind = kind, member = member}
    event.text_length = min(len(text), MAX_TEXT)
    copy(event.text[:event.text_length], text)
    m.event_count += 1
    return event
}

MessengerPoll :: proc(m: ^Messenger) -> (event: Event, ok: bool) {
    if m.event_count == 0 {
        return
    }
    event = m.events[m.event_head]
    m.event_head = (m.event_head + 1) % EVENTS
    m.event_count -= 1
    return event, true
}

// ============================================================================================ update

MessengerUpdate :: proc(m: ^Messenger, now_ms: i64) {
    if m.phase == .CLOSED {
        return
    }
    p2p.LinkUpdate(&m.link, now_ms)
    switch m.phase {
    case .GATHERING:
        if p2p.LinkGathered(&m.link) {
            Start(m, now_ms)
        }
    case .SEARCHING:
        Search(m, now_ms)
    case .HOSTING_WAIT:
        if m.link.derp.state != .CONNECTING {
            BecomeHost(m, now_ms)
        }
    case .RUNNING:
    case .CLOSED:
    }
    if m.phase == .RUNNING && m.is_host {
        HostProbe(m, now_ms)
    }
    if m.phase == .SEARCHING || m.phase == .RUNNING {
        Beacons(m, now_ms)
        LinkEvents(m, now_ms)
        Receive(m, now_ms)
        ForwardsFlush(m, now_ms)
        TransfersPump(m, now_ms)
    }
}

// Another member may have taken the channel key at the relay at the same moment, and the relay serves the newer connection only: ask who
// answers there. An answer with another id means this member is not the one that is heard.
@(private)
HostProbe :: proc(m: ^Messenger, now_ms: i64) {
    switch m.probe.state {
    case .IDLE:
        if m.probe_due_ms != 0 && now_ms >= m.probe_due_ms && m.link.derp.state == .READY {
            m.probe_due_ms = 0
            p2p.ChannelProbeBegin(&m.probe, p2p.LinkDerpHost(&m.link), m.channel_public, now_ms)
        }
    case .WAITING:
        p2p.ChannelProbeUpdate(&m.probe, now_ms)
    case .FOUND:
        if m.probe.found.id != m.link.id {
            if p2p.LinkPeerCount(&m.link) == 0 {
                m.demoted = true
                EventPush(m, .ERROR, 0, "another member took the channel at the same moment and is the one the relay serves: joining it as a guest")
            } else {
                EventPush(m, .ERROR, 0, "another member also hosts this channel (started at the same moment): the channel is split, restart one side")
            }
            p2p.ChannelProbeClose(&m.probe)
            return
        }
        ProbeNext(m, now_ms)
    case .NOBODY:
        ProbeNext(m, now_ms)
    }
}

@(private)
ProbeNext :: proc(m: ^Messenger, now_ms: i64) {
    p2p.ChannelProbeClose(&m.probe)
    m.probe_rounds += 1
    if m.probe_rounds < PROBE_ROUNDS {
        m.probe_due_ms = now_ms + PROBE_AGAIN_MS
    }
}

@(private)
Start :: proc(m: ^Messenger, now_ms: i64) {
    m.self_id = UNKNOWN_ID
    wants_host: bool = m.config.role == .HOST || m.config.role == .AUTO && !m.config.lan && m.config.derp_server == 0
    if wants_host {
        BecomeHost(m, now_ms)
        return
    }
    if m.config.lan {
        m.beacon_up = BeaconOpen(&m.beacon, m.config.channel, false, m.config.password)
    }
    m.phase = .SEARCHING
    m.search_start_ms = now_ms
    jitter: [1]byte
    crypto.rand_bytes(jitter[:])
    m.search_ms = SEARCH_MS + i64(jitter[0]) * 700 / 255
    if m.config.derp_server != 0 {
        // the relay needs its round trips: do not take over a channel whose host just has not answered yet. The spread is wide so that,
        // when a host is lost and everybody searches again, one member finishes first and the others find it instead of all hosting.
        m.search_ms += 3000 + i64(jitter[0]) * 3000 / 255
    }
    m.ask_ms = now_ms - ASK_INTERVAL_MS
}

@(private)
BecomeHost :: proc(m: ^Messenger, now_ms: i64) {
    BeaconClose(&m.beacon)
    m.beacon_up = false
    p2p.LinkHost(&m.link, m.config.name)
    m.is_host = true
    m.self_id = HOST_ID
    MemberSet(m, HOST_ID, m.config.name)
    if m.config.lan {
        m.beacon_up = BeaconOpen(&m.beacon, m.config.channel, true, m.config.password)
        if !m.beacon_up {
            EventPush(m, .ERROR, 0, "no free discovery port: others have to paste the code")
        }
    }
    m.phase = .RUNNING
    if m.config.derp_server != 0 && m.link.derp.state == .READY && m.link.derp.public == m.channel_public {
        m.probe_due_ms = now_ms + PROBE_DELAY_MS
    }
    EventPush(m, .CONNECTED, HOST_ID, "hosting the channel")
}

@(private)
Search :: proc(m: ^Messenger, now_ms: i64) {
    if m.joined {
        m.phase = .RUNNING
        return
    }
    if m.beacon_up && now_ms - m.ask_ms >= ASK_INTERVAL_MS {
        m.ask_ms = now_ms
        BeaconAskWho(&m.beacon)
    }
    if m.config.derp_server != 0 && !m.derp_finding && m.link.derp.state == .READY && m.link.role == .NONE {
        m.derp_finding = true
        p2p.LinkDerpFind(&m.link, m.channel_public, now_ms)
    }
    if m.config.role == .AUTO && now_ms - m.search_start_ms >= m.search_ms {
        if m.config.derp_server != 0 && m.link.derp.public != m.channel_public {
            // nobody answered: this member becomes the host, which at the relay means to be the channel key
            p2p.LinkDerpClose(&m.link)
            m.link.config.derp_private = m.channel_private
            m.link.config.derp_private_set = true
            m.derp_finding = false
            if DerpStart(m, now_ms) {
                m.phase = .HOSTING_WAIT
                return
            }
        }
        BecomeHost(m, now_ms)
    }
}

// The discovery traffic of both sides.
@(private)
Beacons :: proc(m: ^Messenger, now_ms: i64) {
    if !m.beacon_up {
        return
    }
    for {
        kind, text, from, ok := BeaconReceive(&m.beacon)
        if !ok {
            break
        }
        switch {
        case kind == .WHO && m.is_host:
            code: [p2p.CODE_TEXT_MAX]byte
            BeaconSend(&m.beacon, from, .HERE, MessengerCode(m, code[:]))
        case kind == .JOIN && m.is_host:
            invite, decoded := p2p.InviteDecode(text)
            if decoded && invite.kind == .REPLY {
                p2p.LinkAcceptReply(&m.link, invite, now_ms)
            }
        case kind == .HERE && !m.is_host && !m.joined && m.link.role == .NONE:
            invite, decoded := p2p.InviteDecode(text)
            if decoded && invite.kind == .INVITE {
                p2p.LinkJoin(&m.link, invite, m.config.name, now_ms)
                m.joined = true
                m.host_beacon = from
                m.host_beacon_known = true
                m.join_ms = now_ms - JOIN_INTERVAL_MS
                m.phase = .RUNNING
            }
        }
    }
    // the guest repeats its reply until the host connected (UDP loses packets)
    if !m.is_host && m.joined && m.host_beacon_known && m.link.peers[0].state == .PUNCHING && now_ms - m.join_ms >= JOIN_INTERVAL_MS {
        m.join_ms = now_ms
        code: [p2p.CODE_TEXT_MAX]byte
        BeaconSend(&m.beacon, m.host_beacon, .JOIN, MessengerCode(m, code[:]))
    }
}

// ============================================================================================ members

@(private)
MemberSet :: proc(m: ^Messenger, id: u8, name: string) {
    member: ^Member = &m.members[id]
    member.used = true
    member.name_length = min(len(name), NAME_MAX)
    copy(member.name[:member.name_length], name)
}

// A free, unique name: "bob" -> "bob2" when somebody already has it.
@(private)
NameUnique :: proc(m: ^Messenger, wanted: string) -> string {
    if MessengerFindMember(m, wanted) == UNKNOWN_ID {
        return wanted
    }
    for number in 2 ..< 100 {
        candidate: string = fmt.tprintf("%s%d", wanted[:min(len(wanted), NAME_MAX - 2)], number)
        if MessengerFindMember(m, candidate) == UNKNOWN_ID {
            return candidate
        }
    }
    return wanted
}

@(private)
RosterSend :: proc(m: ^Messenger, now_ms: i64) {
    for peer in 0 ..< p2p.MAX_PEERS {
        // only members already registered: a roster that lacks the receiver itself would confuse it
        if m.link.peers[peer].state != .CONNECTED || !m.members[peer + 1].used {
            continue
        }
        writer: serial.Writer
        FrameBegin(&writer, m.scratch[:], .ROSTER, HOST_ID, u8(peer + 1))
        count: u8
        for member in m.members {
            if member.used {
                count += 1
            }
        }
        serial.WriteU8(&writer, count)
        for id in 0 ..< MAX_MEMBERS {
            if m.members[id].used {
                serial.WriteU8(&writer, u8(id))
                serial.WriteString(&writer, MessengerName(m, u8(id)))
            }
        }
        ForwardPush(m, peer, serial.WriterBytes(&writer), now_ms)
    }
}

// ============================================================================================ link events

@(private)
LinkEvents :: proc(m: ^Messenger, now_ms: i64) {
    for {
        event, ok := p2p.LinkPollEvent(&m.link)
        if !ok {
            break
        }
        #partial switch event.kind {
        case .PEER_CONNECTED:
            if m.is_host {
                id: u8 = u8(event.peer + 1)
                name: string = NameUnique(m, p2p.LinkPeerName(&m.link, event.peer))
                MemberSet(m, id, name)
                EventPush(m, .MEMBER_JOINED, id, name)
                RosterSend(m, now_ms)
            }
        case .DERP_HOST_FOUND:
            if !m.is_host && !m.joined && m.link.role == .NONE {
                p2p.LinkJoin(&m.link, m.link.derp.found, m.config.name, now_ms)
                m.joined = true
                m.phase = .RUNNING
            }
        case .DERP_FAILED:
            EventPush(m, .ERROR, 0, fmt.tprintf("the relay cannot be used: %s. %s (it keeps trying in the background)", m.link.derp.failure, p2p.DerpAdvice(m.link.derp.failure_kind)))
        case .DERP_SWITCHED:
            m.derp_was_lost = true
            EventPush(m, .ERROR, 0, fmt.tprintf("the relay stayed down, moved to %s (the others move the same way)", p2p.LinkDerpHost(&m.link)))
        case .DERP_LOST:
            m.derp_was_lost = true
            EventPush(m, .ERROR, 0, "the relay connection was lost, reconnecting by itself")
        case .DERP_READY:
            if m.derp_was_lost {
                m.derp_was_lost = false
                EventPush(m, .ERROR, 0, "the relay is back")
            }
        case .PEER_FAILED:
            if !m.is_host {
                EventPush(m, .ERROR, HOST_ID, "could not reach the host (is it still running? firewall? same network?)")
            }
        case .PEER_LOST:
            if m.is_host {
                id: u8 = u8(event.peer + 1)
                if m.members[id].used {
                    EventPush(m, .MEMBER_LEFT, id, MessengerName(m, id))
                    TransfersFailMember(m, id, "the member left")
                    m.members[id] = {}
                    RosterSend(m, now_ms)
                }
            } else {
                for id in 0 ..< MAX_MEMBERS {
                    if m.members[id].used && u8(id) != m.self_id {
                        EventPush(m, .MEMBER_LEFT, u8(id), MessengerName(m, u8(id)))
                        TransfersFailMember(m, u8(id), "the host left")
                        m.members[id] = {}
                    }
                }
                m.ended = true
                EventPush(m, .ERROR, HOST_ID, "the host is gone, the channel ended (MessengerClose and MessengerOpen again to rejoin or take over)")
            }
        }
    }
}

// ============================================================================================ sending

// Sends one built frame towards `to`. As the host this is a direct send to the guest (or all of them); as a guest it goes to the
// host, which forwards. `queue` true: a full window parks the frame (text); false: the caller gets false and tries again (chunks).
@(private)
FrameSend :: proc(m: ^Messenger, to: u8, frame: []byte, now_ms: i64, queue: bool) -> bool {
    if m.is_host {
        if to == ALL {
            for peer in 0 ..< p2p.MAX_PEERS {
                if m.link.peers[peer].state == .CONNECTED {
                    ForwardPush(m, peer, frame, now_ms)
                }
            }
            return true
        }
        if to == HOST_ID || int(to) >= MAX_MEMBERS || !m.members[to].used {
            return false
        }
        if queue {
            return ForwardPush(m, int(to) - 1, frame, now_ms)
        }
        return p2p.LinkSend(&m.link, int(to) - 1, frame, true, now_ms)
    }
    if !m.joined || m.self_id == UNKNOWN_ID {
        return false
    }
    if queue {
        return ForwardPush(m, 0, frame, now_ms)
    }
    return p2p.LinkSend(&m.link, 0, frame, true, now_ms)
}

// Text to one member or to ALL. False: too long, not ready, no such member, or the queue is full. `agent`: it is the agent of this member
// that speaks (the others see it as that).
MessengerSendText :: proc(m: ^Messenger, to: u8, text: string, now_ms: i64, agent: bool = false) -> bool {
    if len(text) > MAX_TEXT || !MessengerReady(m) {
        return false
    }
    writer: serial.Writer
    FrameBegin(&writer, m.scratch[:], .AGENT_TEXT if agent else .TEXT, m.self_id, to)
    serial.WriteBytes(&writer, transmute([]byte)text)
    return FrameSend(m, to, serial.WriterBytes(&writer), now_ms, true)
}

// Asks a member to start (SPAWN, with the model wanted, "" = its own default) or dismiss (DISMISS) its agent. The member decides: the answer
// is an AGENT_STATUS event.
MessengerSendAgentRequest :: proc(m: ^Messenger, to: u8, action: AgentAction, model: string, now_ms: i64) -> bool {
    if to == ALL || len(model) > AGENT_MODEL_MAX || !MessengerReady(m) {
        return false
    }
    writer: serial.Writer
    FrameBegin(&writer, m.scratch[:], .AGENT_REQUEST, m.self_id, to)
    serial.WriteU8(&writer, u8(action))
    serial.WriteString(&writer, model)
    return FrameSend(m, to, serial.WriterBytes(&writer), now_ms, true)
}

// Tells one member (or ALL) what the agent of this member is doing.
MessengerSendAgentStatus :: proc(m: ^Messenger, to: u8, running: bool, model: string, note: string, now_ms: i64) -> bool {
    if len(model) > AGENT_MODEL_MAX || len(note) > AGENT_NOTE_MAX || !MessengerReady(m) {
        return false
    }
    writer: serial.Writer
    FrameBegin(&writer, m.scratch[:], .AGENT_STATUS, m.self_id, to)
    serial.WriteBool(&writer, running)
    serial.WriteString(&writer, model)
    serial.WriteString(&writer, note)
    return FrameSend(m, to, serial.WriterBytes(&writer), now_ms, true)
}

// Sends the frame now when the window has room and nothing older waits for that peer, else parks it (up to FORWARDS frames).
@(private)
ForwardPush :: proc(m: ^Messenger, peer: int, frame: []byte, now_ms: i64) -> bool {
    waiting: bool
    for i in 0 ..< m.forward_count {
        waiting ||= m.forwards[i].peer == peer
    }
    if !waiting && p2p.LinkSend(&m.link, peer, frame, true, now_ms) {
        return true
    }
    if m.forward_count >= FORWARDS || len(frame) > p2p.MAX_PAYLOAD {
        return false
    }
    slot: ^Forward = &m.forwards[m.forward_count]
    slot.peer = peer
    slot.length = len(frame)
    copy(slot.data[:], frame)
    m.forward_count += 1
    return true
}

// In order per peer; a peer whose window is full does not hold the others back.
@(private)
ForwardsFlush :: proc(m: ^Messenger, now_ms: i64) {
    blocked: [p2p.MAX_PEERS]bool
    kept: int
    for i in 0 ..< m.forward_count {
        item: ^Forward = &m.forwards[i]
        if m.link.peers[item.peer].state != .CONNECTED {
            continue                                 // the peer is gone: drop its frames
        }
        if !blocked[item.peer] && p2p.LinkSend(&m.link, item.peer, item.data[:item.length], true, now_ms) {
            continue
        }
        blocked[item.peer] = true
        if kept != i {
            m.forwards[kept] = m.forwards[i]
        }
        kept += 1
    }
    m.forward_count = kept
}

// ============================================================================================ receiving

@(private)
Receive :: proc(m: ^Messenger, now_ms: i64) {
    buffer: [p2p.MAX_PAYLOAD]byte
    for {
        peer, length, ok := p2p.LinkReceive(&m.link, buffer[:])
        if !ok {
            break
        }
        frame, parsed := FrameParse(buffer[:length])
        if !parsed {
            continue
        }
        if m.is_host {
            // the host knows who is on the other end of a link: a frame claiming another sender is dropped
            if frame.from != u8(peer + 1) {
                continue
            }
            switch {
            case frame.to == HOST_ID:
                Deliver(m, &frame, now_ms)
            case frame.to == ALL:
                for other in 0 ..< p2p.MAX_PEERS {
                    if other != peer && m.link.peers[other].state == .CONNECTED {
                        if !ForwardPush(m, other, buffer[:length], now_ms) {
                            ForwardDropped(m, &frame, now_ms)
                        }
                    }
                }
                Deliver(m, &frame, now_ms)
            case int(frame.to) < MAX_MEMBERS && m.members[frame.to].used && frame.to != frame.from:
                if !ForwardPush(m, int(frame.to) - 1, buffer[:length], now_ms) {
                    ForwardDropped(m, &frame, now_ms)
                }
            }
        } else if frame.kind == .ROSTER || frame.to == m.self_id || frame.to == ALL {
            Deliver(m, &frame, now_ms)
        }
    }
}

// The host could not pass a frame on (the receiver's queue is full). Silently losing a frame of a reliable stream would corrupt a
// file, so a file frame ends that transfer for the sender, and the host reports it.
@(private)
ForwardDropped :: proc(m: ^Messenger, frame: ^Frame, now_ms: i64) {
    EventPush(m, .ERROR, frame.from, "a message could not be passed on (queue full), dropped")
    #partial switch frame.kind {
    case .FILE_OFFER, .FILE_CHUNK, .FILE_END, .FILE_ACCEPT, .FILE_CREDIT:
        reader: serial.Reader = frame.body
        reader.offset = 0
        id: u16 = serial.ReadU16(&reader)
        writer: serial.Writer
        FrameBegin(&writer, m.scratch[:], .FILE_CANCEL, HOST_ID, frame.from)
        serial.WriteU16(&writer, id)
        serial.WriteString(&writer, "the host was overloaded and dropped a frame")
        FrameSend(m, frame.from, serial.WriterBytes(&writer), now_ms, true)
    }
}

// A frame for this member.
@(private)
Deliver :: proc(m: ^Messenger, frame: ^Frame, now_ms: i64) {
    switch frame.kind {
    case .NONE:
    case .ROSTER:
        if !m.is_host {
            RosterReceive(m, frame)
        }
    case .TEXT, .AGENT_TEXT:
        if text := serial.ReaderRemaining(&frame.body); text > 0 && text <= MAX_TEXT {
            event: ^Event = EventPush(m, .TEXT, frame.from, string(serial.ReadBytes(&frame.body, text)))
            event.to = frame.to
            event.agent = frame.kind == .AGENT_TEXT
        }
    case .AGENT_REQUEST:
        action: u8 = serial.ReadU8(&frame.body)
        model: string = serial.ReadString(&frame.body)
        if serial.ReaderOk(&frame.body) && (action == u8(AgentAction.SPAWN) || action == u8(AgentAction.DISMISS)) && len(model) <= AGENT_MODEL_MAX {
            event: ^Event = EventPush(m, .AGENT_REQUEST, frame.from, model)
            event.action = AgentAction(action)
            event.to = frame.to
        }
    case .AGENT_STATUS:
        running: bool = serial.ReadBool(&frame.body)
        model: string = serial.ReadString(&frame.body)
        note: string = serial.ReadString(&frame.body)
        if serial.ReaderOk(&frame.body) && len(model) <= AGENT_MODEL_MAX && len(note) <= AGENT_NOTE_MAX {
            event: ^Event = EventPush(m, .AGENT_STATUS, frame.from, model)
            event.ok = running
            event.to = frame.to
            event.note_length = len(note)
            copy(event.note[:], note)
        }
    case .FILE_OFFER:
        OfferReceive(m, frame, now_ms)
    case .FILE_ACCEPT, .FILE_REJECT, .FILE_CREDIT, .FILE_DONE:
        OutReceive(m, frame, now_ms)
    case .FILE_CANCEL:
        CancelReceive(m, frame)
    case .FILE_CHUNK, .FILE_END:
        InReceive(m, frame, now_ms)
    }
}

@(private)
RosterReceive :: proc(m: ^Messenger, frame: ^Frame) {
    m.self_id = frame.to
    count: int = int(serial.ReadU8(&frame.body))
    seen: [MAX_MEMBERS]bool
    names: [MAX_MEMBERS]string
    for _ in 0 ..< count {
        id: u8 = serial.ReadU8(&frame.body)
        name: string = serial.ReadString(&frame.body)
        if !serial.ReaderOk(&frame.body) || int(id) >= MAX_MEMBERS {
            return
        }
        seen[id] = true
        names[id] = name
    }
    for id in 0 ..< MAX_MEMBERS {
        if seen[id] && !m.members[id].used {
            MemberSet(m, u8(id), names[id])
            if u8(id) == m.self_id {
                EventPush(m, .CONNECTED, m.self_id, names[id])
            } else {
                EventPush(m, .MEMBER_JOINED, u8(id), names[id])
            }
        } else if !seen[id] && m.members[id].used {
            EventPush(m, .MEMBER_LEFT, u8(id), MessengerName(m, u8(id)))
            TransfersFailMember(m, u8(id), "the member left")
            m.members[id] = {}
        }
    }
}

// ============================================================================================ files: sending

@(private)
OutSlot :: proc(m: ^Messenger) -> ^OutTransfer {
    for &out in m.outs {
        if out.state == .FREE {
            return &out
        }
    }
    return nil
}

@(private)
OutOffer :: proc(m: ^Messenger, out: ^OutTransfer, name: string, folder: bool, files: u32, now_ms: i64) -> bool {
    safe: [FILE_NAME_MAX]byte
    writer: serial.Writer
    FrameBegin(&writer, m.scratch[:], .FILE_OFFER, m.self_id, out.to)
    serial.WriteU16(&writer, out.id)
    serial.WriteU64(&writer, out.size)
    serial.WriteU8(&writer, 1 if folder else 0)
    serial.WriteU32(&writer, files)
    serial.WriteString(&writer, FileNameSafe(safe[:], name))
    return FrameSend(m, out.to, serial.WriterBytes(&writer), now_ms, true)
}

@(private)
TransferTargetOk :: proc(m: ^Messenger, to: u8) -> bool {
    return MessengerReady(m) && to != ALL && to != m.self_id && int(to) < MAX_MEMBERS && m.members[to].used
}

@(private)
TransferId :: proc(m: ^Messenger) -> u16 {
    m.next_transfer += 1
    if m.next_transfer == 0 {
        m.next_transfer = 1
    }
    return m.next_transfer
}

// Offers a file to one member. Returns the transfer id (events carry it); false when it cannot start (no such file, no free slot).
MessengerSendFile :: proc(m: ^Messenger, to: u8, path: string, now_ms: i64) -> (transfer: u16, ok: bool) {
    if !TransferTargetOk(m, to) {
        return
    }
    slot: ^OutTransfer = OutSlot(m)
    if slot == nil {
        return
    }
    file, open_error := os.open(path)
    if open_error != nil {
        return
    }
    size, size_error := os.file_size(file)
    if size_error != nil || size < 0 {
        os.close(file)
        return
    }
    slot^ = {state = .OFFERED, id = TransferId(m), to = to, file = file, size = u64(size), active_ms = now_ms, progress_ms = now_ms}
    sha2.init_256(&slot.hash)
    if !OutOffer(m, slot, path, false, 0, now_ms) {
        os.close(file)
        slot^ = {}
        return
    }
    return slot.id, true
}

// Offers a whole folder (see bundle.odin): the receiver gets it as one new folder named like this one, all or nothing. `excludes` are
// names left out anywhere in the tree (".git", "node_modules", "*.tmp"). The file list lives in `allocator` until the transfer ends.
MessengerSendFolder :: proc(m: ^Messenger, to: u8, path: string, excludes: []string, now_ms: i64, allocator := context.allocator) -> (transfer: u16, ok: bool) {
    if !TransferTargetOk(m, to) {
        return
    }
    slot: ^OutTransfer = OutSlot(m)
    if slot == nil {
        return
    }
    bundle: ^Bundle = new(Bundle, allocator)
    if !BundleScan(bundle, path, excludes, allocator) {
        free(bundle, allocator)
        return
    }
    slot^ = {state = .OFFERED, id = TransferId(m), to = to, size = bundle.total, bundle = bundle, active_ms = now_ms, progress_ms = now_ms}
    sha2.init_256(&slot.hash)
    base: string = path
    trimmed: string = strings.trim_right(path, "/\\")
    for i in 0 ..< len(trimmed) {
        if trimmed[i] == '/' || trimmed[i] == '\\' {
            base = trimmed[i + 1:]
        }
    }
    if !OutOffer(m, slot, base, true, u32(bundle.files), now_ms) {
        BundleDestroy(bundle)
        free(bundle, allocator)
        slot^ = {}
        return
    }
    return slot.id, true
}

@(private)
OutFind :: proc(m: ^Messenger, member: u8, id: u16) -> ^OutTransfer {
    for &out in m.outs {
        if out.state != .FREE && out.id == id && out.to == member {
            return &out
        }
    }
    return nil
}

@(private)
OutFinish :: proc(m: ^Messenger, out: ^OutTransfer, ok: bool, reason: string) {
    if out.state == .FREE {
        return
    }
    if out.file != nil {
        os.close(out.file)
    }
    folder: bool = out.bundle != nil
    files: u32
    if folder {
        files = u32(out.bundle.files)
        allocator: runtime.Allocator = out.bundle.allocator
        BundleDestroy(out.bundle)
        free(out.bundle, allocator)
    }
    event: ^Event = EventPush(m, .FILE_DONE, out.to, reason)
    event.transfer = out.id
    event.ok = ok
    event.size = out.size
    event.done = out.sent
    event.folder = folder
    event.files = files
    out^ = {}
}

@(private)
OutReceive :: proc(m: ^Messenger, frame: ^Frame, now_ms: i64) {
    id: u16 = serial.ReadU16(&frame.body)
    out: ^OutTransfer = OutFind(m, frame.from, id)
    if out == nil || !serial.ReaderOk(&frame.body) {
        return
    }
    out.active_ms = now_ms
    #partial switch frame.kind {
    case .FILE_ACCEPT:
        if out.state == .OFFERED {
            out.state = .SENDING
            if serial.ReaderRemaining(&frame.body) > 0 {
                OutResume(m, out, serial.ReadU64(&frame.body), serial.ReadBytes(&frame.body, HASH_SIZE), now_ms)
            }
        }
    case .FILE_REJECT:
        OutFinish(m, out, false, fmt.tprintf("rejected: %s", serial.ReadString(&frame.body)))
    case .FILE_CREDIT:
        out.credited = max(out.credited, serial.ReadU64(&frame.body))
    case .FILE_DONE:
        ok: bool = serial.ReadBool(&frame.body)
        message: string = serial.ReadString(&frame.body)
        OutFinish(m, out, ok, message)
    }
}

// The receiver kept `offset` bytes of an earlier attempt and says what they hash to. If this file (or the stream of this folder) starts with
// exactly those bytes the transfer goes on from there, else it is stopped (the receiver throws its start away: send again to start over).
@(private)
OutResume :: proc(m: ^Messenger, out: ^OutTransfer, offset: u64, theirs: []byte, now_ms: i64) {
    ok: bool = offset <= out.size && len(theirs) == HASH_SIZE
    mine: [HASH_SIZE]byte
    if ok && out.bundle != nil {
        ok = BundleSkip(out.bundle, offset, &out.hash)         // reads the stream up to there: the next chunk follows from it
    } else if ok {
        ok = PartHash(out.file, offset, &out.hash)
    }
    if ok {
        prefix: sha2.Context_256 = out.hash
        sha2.final(&prefix, mine[:])
        ok = string(mine[:]) == string(theirs)
    }
    if !ok {
        writer: serial.Writer
        FrameBegin(&writer, m.scratch[:], .FILE_CANCEL, m.self_id, out.to)
        serial.WriteU16(&writer, out.id)
        serial.WriteString(&writer, "the part that arrived before is not the start of this file or folder")
        FrameSend(m, out.to, serial.WriterBytes(&writer), now_ms, true)
        OutFinish(m, out, false, "the receiver's earlier part does not match this file: it was thrown away, send again")
        return
    }
    out.sent = offset
    out.credited = offset
}

// Stops a transfer in either direction (the other side is told). `member` is the other end.
MessengerCancel :: proc(m: ^Messenger, member: u8, transfer: u16, now_ms: i64) -> bool {
    found: bool
    if out: ^OutTransfer = OutFind(m, member, transfer); out != nil {
        OutFinish(m, out, false, "cancelled")
        found = true
    }
    for &in_ in m.ins {
        if in_.state != .FREE && in_.from == member && in_.id == transfer {
            InFinish(m, &in_, false, "cancelled")
            found = true
        }
    }
    if found {
        writer: serial.Writer
        FrameBegin(&writer, m.scratch[:], .FILE_CANCEL, m.self_id, member)
        serial.WriteU16(&writer, transfer)
        serial.WriteString(&writer, "cancelled by the other member")
        FrameSend(m, member, serial.WriterBytes(&writer), now_ms, true)
    }
    return found
}

@(private)
CancelReceive :: proc(m: ^Messenger, frame: ^Frame) {
    id: u16 = serial.ReadU16(&frame.body)
    reason: string = serial.ReadString(&frame.body)
    if !serial.ReaderOk(&frame.body) {
        return
    }
    if out: ^OutTransfer = OutFind(m, frame.from, id); out != nil {
        OutFinish(m, out, false, reason)
    }
    for &in_ in m.ins {
        if in_.state != .FREE && in_.from == frame.from && in_.id == id {
            InFinish(m, &in_, false, reason)
        }
    }
}

// ============================================================================================ files: receiving

@(private)
OfferReject :: proc(m: ^Messenger, to: u8, id: u16, reason: string, now_ms: i64) {
    writer: serial.Writer
    FrameBegin(&writer, m.scratch[:], .FILE_REJECT, m.self_id, to)
    serial.WriteU16(&writer, id)
    serial.WriteString(&writer, reason)
    FrameSend(m, to, serial.WriterBytes(&writer), now_ms, true)
}

@(private)
OfferReceive :: proc(m: ^Messenger, frame: ^Frame, now_ms: i64) {
    id: u16 = serial.ReadU16(&frame.body)
    size: u64 = serial.ReadU64(&frame.body)
    kind: u8 = serial.ReadU8(&frame.body)
    files: u32 = serial.ReadU32(&frame.body)
    wanted: string = serial.ReadString(&frame.body)
    if !serial.ReaderOk(&frame.body) || kind > 1 {
        return
    }
    slot: ^InTransfer
    for &in_ in m.ins {
        if in_.state != .FREE && in_.from == frame.from && in_.id == id {
            return                                   // a repeated offer
        }
        if in_.state == .FREE && slot == nil {
            slot = &in_
        }
    }
    switch {
    case m.config.receive_dir == "":
        OfferReject(m, frame.from, id, "this member does not receive files", now_ms)
        return
    case size > m.config.max_file_size:
        OfferReject(m, frame.from, id, fmt.tprintf("too big (limit %d bytes)", m.config.max_file_size), now_ms)
        return
    case kind == 1 && files > BUNDLE_MAX_FILES:
        OfferReject(m, frame.from, id, "too many files in the folder", now_ms)
        return
    case slot == nil:
        OfferReject(m, frame.from, id, "too many transfers at once", now_ms)
        return
    }
    slot^ = {state = .PENDING, from = frame.from, id = id, size = size, active_ms = now_ms, progress_ms = now_ms, folder = kind == 1, files = files}
    name: [FILE_NAME_MAX]byte
    safe: string = FileNameSafe(name[:], wanted)
    slot.name_length = len(safe)
    copy(slot.name[:], safe)
    if m.config.auto_accept {
        InAccept(m, slot, now_ms)
        return
    }
    event: ^Event = EventPush(m, .FILE_OFFERED, frame.from, safe)
    event.transfer = id
    event.size = size
    event.incoming = true
    event.folder = slot.folder
    event.files = files
}

// The program's answer to a FILE_OFFERED event.
MessengerFileAnswer :: proc(m: ^Messenger, member: u8, transfer: u16, accept: bool, now_ms: i64) {
    for &in_ in m.ins {
        if in_.state == .PENDING && in_.from == member && in_.id == transfer {
            if accept {
                InAccept(m, &in_, now_ms)
            } else {
                OfferReject(m, member, transfer, "declined", now_ms)
                in_ = {}
            }
            return
        }
    }
}

// Is another transfer already writing to this part file?
@(private)
PartInUse :: proc(m: ^Messenger, except: ^InTransfer, path: string) -> bool {
    for &other in m.ins {
        if &other != except && other.state == .RECEIVING && string(other.part_path[:other.part_length]) == path {
            return true
        }
    }
    return false
}

// Feeds the first `count` bytes of a file into a hash (the start of a file that is being continued). The file position ends at `count`.
@(private)
PartHash :: proc(file: ^os.File, count: u64, hash: ^sha2.Context_256) -> bool {
    buffer: [16 * 1024]byte
    done: u64
    for done < count {
        want: int = int(min(u64(len(buffer)), count - done))
        read, error := os.read_at(file, buffer[:want], i64(done))
        if error != nil || read != want {
            return false
        }
        sha2.update(hash, buffer[:want])
        done += u64(want)
    }
    return true
}

@(private)
InAccept :: proc(m: ^Messenger, in_: ^InTransfer, now_ms: i64) {
    os.make_directory_all(m.config.receive_dir)
    path: string = FileUniquePath(m.config.receive_dir, string(in_.name[:in_.name_length]), ".part")
    if in_.folder {
        // the leftover of an interrupted transfer of this folder: its staging folder and the manifest of the headers that came
        stage: string = fmt.tprintf("%s/%s.part", m.config.receive_dir, string(in_.name[:in_.name_length]))
        manifest: string = fmt.tprintf("%s.manifest", stage)
        resumed: bool
        if os.is_dir(stage) && os.is_file(manifest) && !PartInUse(m, in_, stage) {
            sha2.init_256(&in_.hash)
            offset, resume_ok := BundleReaderResume(&in_.reader, stage, m.config.keep_executable, manifest, &in_.hash)
            if resume_ok && offset > 0 && offset <= in_.size {
                in_.received = offset
                in_.credited = offset
                path = stage
                resumed = true
            } else {
                BundleReaderClose(&in_.reader)
                in_.reader = {}
                os.remove_all(stage)
                os.remove(manifest)
            }
        }
        if !resumed {
            path = FileUniquePath(m.config.receive_dir, string(in_.name[:in_.name_length]), ".part")
            BundleReaderInit(&in_.reader, path, m.config.keep_executable, fmt.tprintf("%s.manifest", path))
            if !os.is_dir(path) {
                OfferReject(m, in_.from, in_.id, "cannot write the folder here", now_ms)
                in_^ = {}
                return
            }
        }
    } else {
        // the leftover of an interrupted transfer of this name: continue it (the sender checks the start against its own file)
        resume: string = fmt.tprintf("%s/%s.part", m.config.receive_dir, string(in_.name[:in_.name_length]))
        resumed: bool
        if os.is_file(resume) && !PartInUse(m, in_, resume) {
            if file, error := os.open(resume, {.Read, .Write}); error == nil {
                size, size_error := os.file_size(file)
                sha2.init_256(&in_.hash)
                if size_error == nil && size > 0 && u64(size) <= in_.size && PartHash(file, u64(size), &in_.hash) {
                    in_.file = file
                    in_.received = u64(size)
                    in_.credited = u64(size)
                    path = resume
                    resumed = true
                    os.seek(file, 0, .End)
                } else {
                    os.close(file)
                }
            }
        }
        if !resumed {
            file, error := os.open(path, {.Write, .Create, .Trunc})
            if error != nil {
                OfferReject(m, in_.from, in_.id, "cannot write the file here", now_ms)
                in_^ = {}
                return
            }
            in_.file = file
            sha2.init_256(&in_.hash)
        }
    }
    in_.part_length = min(len(path), len(in_.part_path))
    copy(in_.part_path[:in_.part_length], path)
    in_.state = .RECEIVING
    in_.active_ms = now_ms
    if in_.folder && in_.received == 0 {
        sha2.init_256(&in_.hash)
    }
    writer: serial.Writer
    FrameBegin(&writer, m.scratch[:], .FILE_ACCEPT, m.self_id, in_.from)
    serial.WriteU16(&writer, in_.id)
    if in_.received > 0 {
        prefix: sha2.Context_256 = in_.hash
        digest: [HASH_SIZE]byte
        sha2.final(&prefix, digest[:])
        serial.WriteU64(&writer, in_.received)
        serial.WriteBytes(&writer, digest[:])
        EventPush(m, .ERROR, in_.from, fmt.tprintf("continuing an interrupted transfer of %s from %d bytes", string(in_.name[:in_.name_length]), in_.received))
    }
    FrameSend(m, in_.from, serial.WriterBytes(&writer), now_ms, true)
}

@(private)
InFinish :: proc(m: ^Messenger, in_: ^InTransfer, ok: bool, text: string, keep_part: bool = false) {
    if in_.state == .FREE {
        return
    }
    if in_.file != nil {
        os.close(in_.file)
        in_.file = nil
    }
    if in_.folder {
        BundleReaderClose(&in_.reader)
    }
    // an interrupted file or folder (the link was lost, the program closed) keeps what arrived: sending the same one again continues there
    if !ok && in_.part_length > 0 && !keep_part {
        part: string = string(in_.part_path[:in_.part_length])
        if in_.folder {
            os.remove_all(part)
            os.remove(fmt.tprintf("%s.manifest", part))
        } else {
            os.remove(part)
        }
    }
    if in_.state == .RECEIVING || ok {
        event: ^Event = EventPush(m, .FILE_DONE, in_.from, text)
        event.transfer = in_.id
        event.incoming = true
        event.ok = ok
        event.size = in_.size
        event.done = in_.received
        event.folder = in_.folder
        event.files = u32(in_.reader.files) if in_.folder else 0
    }
    in_^ = {}
}

@(private)
InVerdict :: proc(m: ^Messenger, in_: ^InTransfer, ok: bool, message: string, now_ms: i64) {
    writer: serial.Writer
    FrameBegin(&writer, m.scratch[:], .FILE_DONE, m.self_id, in_.from)
    serial.WriteU16(&writer, in_.id)
    serial.WriteBool(&writer, ok)
    serial.WriteString(&writer, message)
    FrameSend(m, in_.from, serial.WriterBytes(&writer), now_ms, true)
}

@(private)
InFail :: proc(m: ^Messenger, in_: ^InTransfer, message: string, now_ms: i64) {
    InVerdict(m, in_, false, message, now_ms)
    InFinish(m, in_, false, message)
}

@(private)
InReceive :: proc(m: ^Messenger, frame: ^Frame, now_ms: i64) {
    id: u16 = serial.ReadU16(&frame.body)
    in_: ^InTransfer
    for &candidate in m.ins {
        if candidate.state == .RECEIVING && candidate.from == frame.from && candidate.id == id {
            in_ = &candidate
        }
    }
    if in_ == nil || !serial.ReaderOk(&frame.body) {
        return
    }
    in_.active_ms = now_ms
    #partial switch frame.kind {
    case .FILE_CHUNK:
        offset: u64 = serial.ReadU64(&frame.body)
        bytes: []byte = serial.ReadBytes(&frame.body, serial.ReaderRemaining(&frame.body))
        if !serial.ReaderOk(&frame.body) || offset != in_.received || in_.received + u64(len(bytes)) > in_.size {
            InFail(m, in_, "chunk out of order or too much data", now_ms)
            return
        }
        if in_.folder {
            if !BundleFeed(&in_.reader, bytes) {
                InFail(m, in_, in_.reader.failure, now_ms)
                return
            }
        } else if _, error := os.write(in_.file, bytes); error != nil {
            InFail(m, in_, "cannot write the file", now_ms)
            return
        }
        sha2.update(&in_.hash, bytes)
        in_.received += u64(len(bytes))
        if in_.received - in_.credited >= CREDIT_EVERY {
            in_.credited = in_.received
            writer: serial.Writer
            FrameBegin(&writer, m.scratch[:], .FILE_CREDIT, m.self_id, in_.from)
            serial.WriteU16(&writer, in_.id)
            serial.WriteU64(&writer, in_.received)
            FrameSend(m, in_.from, serial.WriterBytes(&writer), now_ms, true)
        }
        Progress(m, in_.from, in_.id, true, in_.received, in_.size, &in_.progress_ms, now_ms)
    case .FILE_END:
        expected: []byte = serial.ReadBytes(&frame.body, HASH_SIZE)
        if !serial.ReaderOk(&frame.body) {
            return
        }
        actual: [HASH_SIZE]byte
        sha2.final(&in_.hash, actual[:])
        if in_.received != in_.size || string(actual[:]) != string(expected) || in_.folder && !in_.reader.ended {
            InFail(m, in_, "arrived damaged (size or sha256 differ)", now_ms)
            return
        }
        if in_.file != nil {
            os.close(in_.file)
            in_.file = nil
        }
        BundleReaderClose(&in_.reader)
        final: string = FileUniquePath(m.config.receive_dir, string(in_.name[:in_.name_length]))
        part: string = string(in_.part_path[:in_.part_length])
        if os.rename(part, final) != nil {
            InFail(m, in_, "cannot save it", now_ms)
            return
        }
        if in_.folder {
            os.remove(fmt.tprintf("%s.manifest", part))
        }
        in_.part_length = 0
        InVerdict(m, in_, true, "received and verified", now_ms)
        InFinish(m, in_, true, final)
    }
}

// A progress event at most once a second (and at the end), so a big file does not flood the queue.
@(private)
Progress :: proc(m: ^Messenger, member: u8, id: u16, incoming: bool, done: u64, size: u64, last_ms: ^i64, now_ms: i64) {
    if now_ms - last_ms^ < 1000 && done < size {
        return
    }
    last_ms^ = now_ms
    event: ^Event = EventPush(m, .FILE_PROGRESS, member)
    event.transfer = id
    event.incoming = incoming
    event.size = size
    event.done = done
}

// ============================================================================================ files: pumping and timeouts

@(private)
TransfersPump :: proc(m: ^Messenger, now_ms: i64) {
    for &out in m.outs {
        switch out.state {
        case .FREE:
        case .OFFERED:
            if now_ms - out.active_ms > OFFER_TIMEOUT_MS {
                OutFinish(m, &out, false, "nobody answered the offer")
            }
        case .SENDING:
            OutPump(m, &out, now_ms)
            if out.state == .SENDING && now_ms - out.active_ms > STALL_TIMEOUT_MS && out.sent - out.credited >= FILE_WINDOW {
                OutFinish(m, &out, false, "the receiver stopped answering")
            }
        case .FINISHING:
            if !out.end_sent {
                OutEnd(m, &out, now_ms)
            }
            if now_ms - out.active_ms > STALL_TIMEOUT_MS {
                OutFinish(m, &out, false, "no verdict from the receiver")
            }
        }
    }
    for &in_ in m.ins {
        if in_.state == .PENDING && now_ms - in_.active_ms > OFFER_TIMEOUT_MS * 2 {
            OfferReject(m, in_.from, in_.id, "nobody answered the offer in time", now_ms)
            in_ = {}
        } else if in_.state == .RECEIVING && now_ms - in_.active_ms > STALL_TIMEOUT_MS {
            InFail(m, &in_, "the sender stopped sending", now_ms)
        }
    }
}

// The next chunk of the file or folder stream, read once: it stays in `pending` until the link took it.
@(private)
OutFill :: proc(m: ^Messenger, out: ^OutTransfer) -> bool {
    if out.pending_length > 0 {
        return true
    }
    count: int = int(min(u64(FILE_CHUNK), out.size - out.sent))
    if out.bundle != nil {
        read: int = BundleRead(out.bundle, out.pending[:count])
        if read != count {
            return false
        }
    } else {
        read, error := os.read_at(out.file, out.pending[:count], i64(out.sent))
        if error != nil || read != count {
            return false
        }
    }
    out.pending_length = count
    return true
}

// Chunks while the credit window has room and the link takes them.
@(private)
OutPump :: proc(m: ^Messenger, out: ^OutTransfer, now_ms: i64) {
    for out.sent < out.size && out.sent - out.credited < FILE_WINDOW {
        if !OutFill(m, out) {
            OutFinish(m, out, false, "cannot read the file (changed while sending?)")
            return
        }
        writer: serial.Writer
        FrameBegin(&writer, m.scratch[:], .FILE_CHUNK, m.self_id, out.to)
        serial.WriteU16(&writer, out.id)
        serial.WriteU64(&writer, out.sent)
        serial.WriteBytes(&writer, out.pending[:out.pending_length])
        if !FrameSend(m, out.to, serial.WriterBytes(&writer), now_ms, false) {
            return                                   // window full, the chunk waits in `pending`
        }
        sha2.update(&out.hash, out.pending[:out.pending_length])
        out.sent += u64(out.pending_length)
        out.pending_length = 0
        Progress(m, out.to, out.id, false, out.sent, out.size, &out.progress_ms, now_ms)
    }
    if out.sent == out.size {
        out.state = .FINISHING
        OutEnd(m, out, now_ms)
    }
}

@(private)
OutEnd :: proc(m: ^Messenger, out: ^OutTransfer, now_ms: i64) {
    hash: [HASH_SIZE]byte
    copy_hash: sha2.Context_256 = out.hash
    sha2.final(&copy_hash, hash[:])
    writer: serial.Writer
    FrameBegin(&writer, m.scratch[:], .FILE_END, m.self_id, out.to)
    serial.WriteU16(&writer, out.id)
    serial.WriteBytes(&writer, hash[:])
    if FrameSend(m, out.to, serial.WriterBytes(&writer), now_ms, true) {
        out.end_sent = true
        out.active_ms = now_ms
    }
}

@(private)
TransfersFailMember :: proc(m: ^Messenger, member: u8, reason: string) {
    for &out in m.outs {
        if out.state != .FREE && out.to == member {
            OutFinish(m, &out, false, reason)
        }
    }
    for &in_ in m.ins {
        if in_.state != .FREE && in_.from == member {
            InFinish(m, &in_, false, reason, true)
        }
    }
}
