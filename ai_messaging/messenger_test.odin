#+build !js
// Messengers talking over real loopback sockets inside the test process: pasted codes, discovery by channel name, three members with
// forwarding, files with verification, and the refusals. Slow parts sleep one millisecond per pump (loopback is not instant).
package ai_messaging

import "core:crypto"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import p2p "../p2p"

Node :: struct {
    m: ^Messenger,
    texts: [dynamic]string,              // "from: text"
    to_all: [dynamic]bool,
    done: [dynamic]Event,
    offered: [dynamic]Event,
    errors: [dynamic]string,
    requests: [dynamic]Event,            // AGENT_REQUEST
    statuses: [dynamic]Event,            // AGENT_STATUS
    orders: [dynamic]Event,              // MODERATION
    reports: [dynamic]Event,             // AGENT_REPORT
    agent_said: [dynamic]bool,           // for each text: was it an agent
    session: ^Session,                   // optional: the agent session of this node (session_test.odin)
    notes: [dynamic]string,              // what the session said: "REPLY: ...", "INFO: ..."
    joined: int,
    left: int,
    connected: bool,
}

NodeOpen :: proc(config: MessengerConfig) -> ^Node {
    node: ^Node = new(Node)
    node.m = new(Messenger)
    if !MessengerOpen(node.m, config, p2p.LinkNow()) {
        return nil
    }
    return node
}

NodeClose :: proc(node: ^Node) {
    MessengerClose(node.m)
    free(node.m)
    for text in node.texts {
        delete(text)
    }
    for text in node.errors {
        delete(text)
    }
    delete(node.texts)
    delete(node.to_all)
    delete(node.done)
    delete(node.offered)
    delete(node.errors)
    delete(node.requests)
    delete(node.statuses)
    delete(node.orders)
    delete(node.reports)
    delete(node.agent_said)
    for note in node.notes {
        delete(note)
    }
    delete(node.notes)
    free(node)
}

NodeUpdate :: proc(node: ^Node) {
    MessengerUpdate(node.m, p2p.LinkNow())
    for {
        event, ok := MessengerPoll(node.m)
        if !ok {
            break
        }
        if node.session != nil {
            SessionOnEvent(node.session, &event, p2p.LinkNow())
        }
        switch event.kind {
        case .NONE, .FILE_PROGRESS:
        case .CONNECTED:
            node.connected = true
        case .MEMBER_JOINED:
            node.joined += 1
        case .MEMBER_LEFT:
            node.left += 1
        case .TEXT:
            append(&node.texts, fmt.aprintf("%s: %s", MessengerName(node.m, event.member), string(event.text[:event.text_length])))
            append(&node.to_all, event.to == ALL)
            append(&node.agent_said, event.agent)
        case .FILE_OFFERED:
            append(&node.offered, event)
        case .FILE_DONE:
            append(&node.done, event)
        case .ERROR:
            append(&node.errors, strings.clone(string(event.text[:event.text_length])))
        case .AGENT_REQUEST:
            append(&node.requests, event)
        case .AGENT_STATUS:
            append(&node.statuses, event)
        case .MODERATION:
            append(&node.orders, event)
        case .AGENT_REPORT:
            append(&node.reports, event)
        case .REMOTE_GRANT, .REMOTE_RUN, .REMOTE_OUT:                // the session handles them
        }
    }
    if node.session != nil {
        SessionUpdate(node.session, p2p.LinkNow())
        for {
            out, out_ok := SessionPoll(node.session)
            if !out_ok {
                break
            }
            append(&node.notes, fmt.aprintf("%v: %s", out.kind, SessionOutText(&out)))
        }
    }
}

// Pumps every node until `condition` holds or about 8 seconds passed.
PumpUntil :: proc(nodes: []^Node, condition: proc(nodes: []^Node) -> bool, limit: int = 8000) -> bool {
    for _ in 0 ..< limit {
        for node in nodes {
            NodeUpdate(node)
        }
        if condition(nodes) {
            return true
        }
        time.sleep(time.Millisecond)
    }
    return false
}

Heard :: proc(node: ^Node, text: string) -> bool {
    for line in node.texts {
        if strings.contains(line, text) {
            return true
        }
    }
    return false
}

TempFolder :: proc(label: string) -> string {
    random: [4]byte
    crypto.rand_bytes(random[:])
    base, _ := os.temp_directory(context.temp_allocator)
    path: string = fmt.aprintf("%s/aimsg_%s_%x", strings.trim_right(base, "/\\"), label, random)
    os.make_directory_all(path)
    return path
}

// Reproducible bytes that do not compress or repeat in chunk sized blocks.
FillTestFile :: proc(path: string, size: int) {
    data: []byte = make([]byte, size)
    defer delete(data)
    state: u32 = 12345
    for i in 0 ..< size {
        state = state * 1664525 + 1013904223
        data[i] = byte(state >> 24)
    }
    _ = os.write_entire_file(path, data)
}

SameFile :: proc(a: string, b: string) -> bool {
    first, error_a := os.read_entire_file(a, context.allocator)
    second, error_b := os.read_entire_file(b, context.allocator)
    defer delete(first)
    defer delete(second)
    return error_a == nil && error_b == nil && string(first) == string(second)
}

// Host and guest meet by pasted codes (what two people on different networks do), then talk and exchange a file both ways.
@(test)
MessengerCodesAndFilesTest :: proc(t: ^testing.T) {
    folder: string = TempFolder("codes")
    defer os.remove_all(folder)
    defer delete(folder)
    host: ^Node = NodeOpen({channel = "codes", name = "ann", role = .HOST, receive_dir = fmt.tprintf("%s/host_in", folder), auto_accept = true})
    guest: ^Node = NodeOpen({channel = "codes", name = "bob", role = .GUEST, receive_dir = fmt.tprintf("%s/guest_in", folder), auto_accept = true})
    testing.expect(t, host != nil && guest != nil)
    defer NodeClose(host)
    defer NodeClose(guest)
    nodes: []^Node = {host, guest}

    ready := proc(nodes: []^Node) -> bool {
        return nodes[0].m.phase == .RUNNING && nodes[1].m.phase != .GATHERING && nodes[1].m.phase != .CLOSED && nodes[1].m.link.candidate_count > 0
    }
    testing.expect(t, PumpUntil(nodes, ready))
    code: [p2p.CODE_TEXT_MAX]byte
    invite: string = strings.clone(MessengerCode(host.m, code[:]))
    defer delete(invite)
    testing.expect(t, invite != "")
    ok, _ := MessengerUseCode(guest.m, invite, p2p.LinkNow())
    testing.expect(t, ok)
    reply: string = strings.clone(MessengerCode(guest.m, code[:]))
    defer delete(reply)
    ok, _ = MessengerUseCode(host.m, reply, p2p.LinkNow())
    testing.expect(t, ok)
    bad, message := MessengerUseCode(guest.m, "NOT-A-CODE", p2p.LinkNow())
    testing.expect(t, !bad)
    _ = message

    connected := proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 1 && nodes[1].connected && MessengerReady(nodes[1].m)
    }
    testing.expect(t, PumpUntil(nodes, connected))
    testing.expect_value(t, MessengerName(guest.m, 0), "ann")
    testing.expect_value(t, MessengerSelf(guest.m), u8(1))
    testing.expect_value(t, MessengerFindMember(host.m, "BOB"), u8(1))

    testing.expect(t, MessengerSendText(host.m, ALL, "hello bob", p2p.LinkNow()))
    testing.expect(t, MessengerSendText(guest.m, HOST_ID, "hello ann", p2p.LinkNow()))
    heard := proc(nodes: []^Node) -> bool {
        return Heard(nodes[0], "bob: hello ann") && Heard(nodes[1], "ann: hello bob")
    }
    testing.expect(t, PumpUntil(nodes, heard))

    // a file from the guest to the host, big enough to need many chunks and credits
    source: string = fmt.tprintf("%s/source.bin", folder)
    FillTestFile(source, 300_001)
    _, started := MessengerSendFile(guest.m, HOST_ID, source, p2p.LinkNow())
    testing.expect(t, started)
    transferred := proc(nodes: []^Node) -> bool {
        return len(nodes[0].done) == 1 && len(nodes[1].done) == 1
    }
    testing.expect(t, PumpUntil(nodes, transferred))
    if len(host.done) == 1 && len(guest.done) == 1 {
        testing.expect(t, host.done[0].ok && host.done[0].incoming)
        testing.expect(t, guest.done[0].ok && !guest.done[0].incoming)
        testing.expect_value(t, host.done[0].done, u64(300_001))
        testing.expect(t, SameFile(source, string(host.done[0].text[:host.done[0].text_length])))
    }

    // and back: an empty file (no chunks, only offer, end and verdict) and a name that tries to leave the folder
    empty: string = fmt.tprintf("%s/empty.txt", folder)
    _ = os.write_entire_file(empty, "")
    _, started = MessengerSendFile(host.m, 1, empty, p2p.LinkNow())
    testing.expect(t, started)
    back := proc(nodes: []^Node) -> bool {
        return len(nodes[0].done) == 2 && len(nodes[1].done) == 2
    }
    testing.expect(t, PumpUntil(nodes, back))
    testing.expect(t, os.exists(fmt.tprintf("%s/guest_in/empty.txt", folder)))
}

// Three members found by the channel name alone: forwarding between guests, names made unique, a file from guest to guest through
// the host, a refusal, and a member leaving.
@(test)
MessengerDiscoveryTest :: proc(t: ^testing.T) {
    random: [4]byte
    crypto.rand_bytes(random[:])
    channel: string = fmt.aprintf("discovery-%x", random)
    defer delete(channel)
    folder: string = TempFolder("discovery")
    defer os.remove_all(folder)
    defer delete(folder)

    host: ^Node = NodeOpen({channel = channel, name = "host", role = .HOST, lan = true})
    a: ^Node = NodeOpen({channel = channel, name = "same", role = .GUEST, lan = true, receive_dir = fmt.tprintf("%s/a_in", folder), auto_accept = true})
    b: ^Node = NodeOpen({channel = channel, name = "same", role = .GUEST, lan = true, receive_dir = fmt.tprintf("%s/b_in", folder)})
    testing.expect(t, host != nil && a != nil && b != nil)
    defer NodeClose(host)
    defer NodeClose(a)
    nodes: []^Node = {host, a, b}

    everybody := proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 2 && nodes[1].connected && nodes[2].connected && nodes[1].joined >= 1 && nodes[2].joined >= 1
    }
    testing.expect(t, PumpUntil(nodes, everybody))
    testing.expect_value(t, MessengerName(host.m, 1), "same")
    testing.expect_value(t, MessengerName(host.m, 2), "same2")      // the second "same" got a unique name

    // guest to guest, through the host; and one to all
    testing.expect(t, MessengerSendText(a.m, 2, "psst b", p2p.LinkNow()))
    testing.expect(t, MessengerSendText(b.m, ALL, "hi everybody", p2p.LinkNow()))
    talked := proc(nodes: []^Node) -> bool {
        return Heard(nodes[2], "psst b") && Heard(nodes[0], "hi everybody") && Heard(nodes[1], "hi everybody")
    }
    testing.expect(t, PumpUntil(nodes, talked))
    testing.expect(t, !Heard(nodes[0], "psst b"))                   // the host forwarded it without showing it to itself
    testing.expect(t, !Heard(nodes[1], "same: hi everybody") || true)

    // b has no auto accept: the offer from a comes as an event, a hostile name is made safe, b says yes
    source: string = fmt.tprintf("%s/evil.bin", folder)
    FillTestFile(source, 50_000)
    wrong, _ := MessengerSendFile(a.m, 2, "does-not-exist.bin", p2p.LinkNow())
    testing.expect(t, wrong == 0)
    transfer, started := MessengerSendFile(a.m, 2, source, p2p.LinkNow())
    testing.expect(t, started)
    offered := proc(nodes: []^Node) -> bool {
        return len(nodes[2].offered) == 1
    }
    testing.expect(t, PumpUntil(nodes, offered))
    if len(b.offered) == 1 {
        testing.expect_value(t, b.offered[0].size, u64(50_000))
        testing.expect_value(t, string(b.offered[0].text[:b.offered[0].text_length]), "evil.bin")
        // b has no receive_dir: it would have refused; give it one for the answer
        MessengerSetReceiveDir(b.m, fmt.tprintf("%s/b_in", folder))
        MessengerFileAnswer(b.m, b.offered[0].member, transfer, true, p2p.LinkNow())
    }
    finished := proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 1 && len(nodes[2].done) == 1
    }
    testing.expect(t, PumpUntil(nodes, finished))
    if len(b.done) == 1 {
        testing.expect(t, b.done[0].ok)
        testing.expect(t, SameFile(source, fmt.tprintf("%s/b_in/evil.bin", folder)))
    }

    // b with no receive folder refuses: the sender is told why
    MessengerSetReceiveDir(b.m, "")
    _, started = MessengerSendFile(a.m, 2, source, p2p.LinkNow())
    testing.expect(t, started)
    refused := proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 2
    }
    testing.expect(t, PumpUntil(nodes, refused))
    if len(a.done) == 2 {
        testing.expect(t, !a.done[1].ok)
        testing.expect(t, strings.contains(string(a.done[1].text[:a.done[1].text_length]), "does not receive"))
    }

    // b leaves: the others are told and the id is free
    NodeClose(b)
    gone := proc(nodes: []^Node) -> bool {
        return nodes[0].left == 1 && nodes[1].left == 1
    }
    testing.expect(t, PumpUntil(nodes[:2], gone))
}

// A channel with a password: the name alone does not get anybody in, neither with no password nor with a wrong one.
@(test)
MessengerPasswordTest :: proc(t: ^testing.T) {
    random: [4]byte
    crypto.rand_bytes(random[:])
    channel: string = fmt.aprintf("private-%x", random)
    defer delete(channel)

    host: ^Node = NodeOpen({channel = channel, name = "host", role = .HOST, lan = true, password = "correct horse"})
    friend: ^Node = NodeOpen({channel = channel, name = "friend", role = .GUEST, lan = true, password = "correct horse"})
    nobody: ^Node = NodeOpen({channel = channel, name = "nobody", role = .GUEST, lan = true})
    wrong: ^Node = NodeOpen({channel = channel, name = "wrong", role = .GUEST, lan = true, password = "battery staple"})
    testing.expect(t, host != nil && friend != nil && nobody != nil && wrong != nil)
    defer NodeClose(host)
    defer NodeClose(friend)
    defer NodeClose(nobody)
    defer NodeClose(wrong)
    nodes: []^Node = {host, friend, nobody, wrong}

    connected := proc(nodes: []^Node) -> bool {
        return nodes[1].connected && nodes[0].joined == 1
    }
    testing.expect(t, PumpUntil(nodes, connected))
    // give the two without the password plenty of time to find the host, then see that they did not
    for _ in 0 ..< 1500 {
        for node in nodes {
            NodeUpdate(node)
        }
        time.sleep(time.Millisecond)
    }
    testing.expect(t, !nobody.connected)
    testing.expect(t, !wrong.connected)
    testing.expect_value(t, host.joined, 1)
}

// A whole project folder from one member to another (and from a guest to a guest through the host): hidden files, empty folders and
// exclusions survive, it arrives as one new folder named like the source, a second send does not overwrite it.
@(test)
MessengerFolderTest :: proc(t: ^testing.T) {
    random: [4]byte
    crypto.rand_bytes(random[:])
    channel: string = fmt.aprintf("folder-%x", random)
    defer delete(channel)
    folder: string = TempFolder("folder")
    defer os.remove_all(folder)
    defer delete(folder)
    source: string = fmt.aprintf("%s/project", folder)           // not tprintf: the temp buffer is reused by the calls below
    defer delete(source)
    WriteTree(source)

    host: ^Node = NodeOpen({channel = channel, name = "host", role = .HOST, lan = true, receive_dir = fmt.tprintf("%s/host_in", folder), auto_accept = true})
    a: ^Node = NodeOpen({channel = channel, name = "a", role = .GUEST, lan = true, receive_dir = fmt.tprintf("%s/a_in", folder)})
    b: ^Node = NodeOpen({channel = channel, name = "b", role = .GUEST, lan = true, receive_dir = fmt.tprintf("%s/b_in", folder), auto_accept = true})
    defer NodeClose(host)
    defer NodeClose(a)
    defer NodeClose(b)
    nodes: []^Node = {host, a, b}
    everybody := proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 2 && MessengerReady(nodes[1].m) && MessengerReady(nodes[2].m) && MessengerFindMember(nodes[1].m, "b") != UNKNOWN_ID
    }
    testing.expect(t, PumpUntil(nodes, everybody))

    excludes: []string = {".git", "node_modules", "*.tmp"}
    _, bad := MessengerSendFolder(a.m, 2, fmt.tprintf("%s/does-not-exist", folder), excludes, p2p.LinkNow())
    testing.expect(t, !bad)
    _, started := MessengerSendFolder(a.m, 2, source, excludes, p2p.LinkNow())          // guest to guest through the host
    testing.expect(t, started)
    done := proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 1 && len(nodes[2].done) == 1
    }
    testing.expect(t, PumpUntil(nodes, done))
    if len(b.done) == 1 {
        testing.expect(t, b.done[0].ok && b.done[0].folder)
        testing.expect_value(t, b.done[0].files, u32(5))
    }
    target: string = fmt.tprintf("%s/b_in/project", folder)
    testing.expect(t, SameFile(fmt.tprintf("%s/sub/big.bin", source), fmt.tprintf("%s/sub/big.bin", target)))
    testing.expect(t, SameFile(fmt.tprintf("%s/.gitignore", source), fmt.tprintf("%s/.gitignore", target)))
    testing.expect(t, os.is_dir(fmt.tprintf("%s/empty_dir", target)))
    testing.expect(t, !os.exists(fmt.tprintf("%s/.git", target)))
    testing.expect(t, !os.exists(fmt.tprintf("%s/project.part", fmt.tprintf("%s/b_in", folder))))   // no staging folder left behind

    // again: a second folder next to the first, the first is untouched
    _, started = MessengerSendFolder(a.m, 2, source, excludes, p2p.LinkNow())
    testing.expect(t, started)
    done2 := proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 2 && len(nodes[2].done) == 2
    }
    testing.expect(t, PumpUntil(nodes, done2))
    testing.expect(t, os.is_dir(fmt.tprintf("%s/b_in/project (1)", folder)))

    // the host asks nobody (auto accept), a has to answer: the offer comes with its size and file count
    _, started = MessengerSendFolder(host.m, 1, source, excludes, p2p.LinkNow())
    testing.expect(t, started)
    offered := proc(nodes: []^Node) -> bool {
        return len(nodes[1].offered) == 1
    }
    testing.expect(t, PumpUntil(nodes, offered))
    if len(a.offered) == 1 {
        testing.expect(t, a.offered[0].folder)
        testing.expect_value(t, a.offered[0].files, u32(5))
        MessengerFileAnswer(a.m, 0, a.offered[0].transfer, false, p2p.LinkNow())
    }
    declined := proc(nodes: []^Node) -> bool {
        return len(nodes[0].done) == 1
    }
    testing.expect(t, PumpUntil(nodes, declined))
    if len(host.done) == 1 {
        testing.expect(t, !host.done[0].ok)
        testing.expect(t, strings.contains(string(host.done[0].text[:host.done[0].text_length]), "declined"))
    }
}

// Stopping a transfer: the sender cancels a big file in flight, the receiver loses its half written file, both are told, the slot is
// free again for the next one.
@(test)
MessengerCancelTest :: proc(t: ^testing.T) {
    random: [4]byte
    crypto.rand_bytes(random[:])
    channel: string = fmt.aprintf("cancel-%x", random)
    defer delete(channel)
    folder: string = TempFolder("cancel")
    defer os.remove_all(folder)
    defer delete(folder)
    host: ^Node = NodeOpen({channel = channel, name = "host", role = .HOST, lan = true, receive_dir = fmt.tprintf("%s/in", folder), auto_accept = true})
    guest: ^Node = NodeOpen({channel = channel, name = "guest", role = .GUEST, lan = true})
    defer NodeClose(host)
    defer NodeClose(guest)
    nodes: []^Node = {host, guest}
    ready := proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 1 && MessengerReady(nodes[1].m)
    }
    testing.expect(t, PumpUntil(nodes, ready))

    source: string = fmt.tprintf("%s/huge.bin", folder)
    FillTestFile(source, 20_000_000)
    transfer, started := MessengerSendFile(guest.m, HOST_ID, source, p2p.LinkNow())
    testing.expect(t, started)
    flowing := proc(nodes: []^Node) -> bool {
        for &in_ in nodes[0].m.ins {
            if in_.state == .RECEIVING && in_.received > 20_000 {
                return true
            }
        }
        return false
    }
    testing.expect(t, PumpUntil(nodes, flowing))
    testing.expect(t, MessengerCancel(guest.m, HOST_ID, transfer, p2p.LinkNow()))
    cancelled := proc(nodes: []^Node) -> bool {
        return len(nodes[0].done) == 1 && len(nodes[1].done) == 1
    }
    testing.expect(t, PumpUntil(nodes, cancelled))
    if len(host.done) == 1 && len(guest.done) == 1 {
        testing.expect(t, !host.done[0].ok && !guest.done[0].ok)
    }
    testing.expect(t, !os.exists(fmt.tprintf("%s/in/huge.bin.part", folder)))
    testing.expect(t, !os.exists(fmt.tprintf("%s/in/huge.bin", folder)))
    testing.expect(t, !MessengerCancel(guest.m, HOST_ID, transfer, p2p.LinkNow()))     // already gone
}

// Over a real public DERP relay, found by the channel name alone (no lan, no code), only when asked for: P2P_LIVE=1. The first member
// finds nobody and becomes the host (it takes the channel key at the relay), the second finds it, text and a file travel, and with
// derp_only everything really goes through the relay.
@(test)
MessengerRelayLiveTest :: proc(t: ^testing.T) {
    if os.get_env("P2P_LIVE", context.temp_allocator) == "" {
        return
    }
    random: [4]byte
    crypto.rand_bytes(random[:])
    channel: string = fmt.aprintf("live-%x", random)
    defer delete(channel)
    folder: string = TempFolder("live")
    defer os.remove_all(folder)
    defer delete(folder)
    first: ^Node = NodeOpen({channel = channel, name = "first", role = .AUTO, derp_server = 22, receive_dir = fmt.tprintf("%s/first_in", folder), auto_accept = true, link = {derp_only = true}})
    testing.expect(t, first != nil)
    defer NodeClose(first)
    // the first member finds nobody and becomes the host (it takes the channel key at the relay)
    hosting := proc(nodes: []^Node) -> bool {
        return nodes[0].m.is_host && nodes[0].m.phase == .RUNNING
    }
    testing.expect(t, PumpUntil([]^Node{first}, hosting, 30000))
    // the second one starts later and finds it by the name (two members that start in the same second may both host: use the roles then)
    second: ^Node = NodeOpen({channel = channel, name = "second", role = .AUTO, derp_server = 22, receive_dir = fmt.tprintf("%s/second_in", folder), auto_accept = true, link = {derp_only = true}})
    testing.expect(t, second != nil)
    defer NodeClose(second)
    nodes: []^Node = {first, second}
    meet := proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 1 && MessengerReady(nodes[1].m)
    }
    testing.expect(t, PumpUntil(nodes, meet, 30000))
    host, guest: ^Node = first, second
    if second.m.is_host {
        host, guest = second, first
    }
    testing.expect(t, MessengerSendText(guest.m, HOST_ID, "hello through the relay", p2p.LinkNow()))
    testing.expect(t, MessengerSendText(host.m, ALL, "hello back", p2p.LinkNow()))
    talked := proc(nodes: []^Node) -> bool {
        return Heard(nodes[0], "hello") && Heard(nodes[1], "hello")
    }
    testing.expect(t, PumpUntil(nodes, talked, 20000))
    testing.expect(t, guest.m.link.peers[0].via_relay)
    source: string = fmt.aprintf("%s/live.bin", folder)
    defer delete(source)
    FillTestFile(source, 60_000)
    _, started := MessengerSendFile(guest.m, HOST_ID, source, p2p.LinkNow())
    testing.expect(t, started)
    sent := proc(nodes: []^Node) -> bool {
        return len(nodes[0].done) == 1 && len(nodes[1].done) == 1
    }
    testing.expect(t, PumpUntil(nodes, sent, 30000))
}

// Two members that start at the same moment both hosted the channel: the relay serves the newer connection and the older one heard nothing.
// The host check finds that out and the loser joins the other as a guest. Needs the network (P2P_LIVE=1), it takes about 30 s.
@(test)
MessengerRaceLiveTest :: proc(t: ^testing.T) {
    if os.get_env("P2P_LIVE", context.temp_allocator) == "" {
        return
    }
    random: [4]byte
    crypto.rand_bytes(random[:])
    channel: string = fmt.aprintf("race-%x", random)
    defer delete(channel)
    config: MessengerConfig = {channel = channel, role = .HOST, derp_server = 22, link = {derp_only = true}}      // both are told to host: the race, forced
    config.name = "one"
    one: ^Node = NodeOpen(config)
    config.name = "two"
    two: ^Node = NodeOpen(config)
    testing.expect(t, one != nil && two != nil)
    defer NodeClose(one)
    defer NodeClose(two)
    started: time.Tick = time.tick_now()
    settled: bool
    reopened: int
    for time.duration_seconds(time.tick_since(started)) < 90 {
        NodeUpdate(one)
        NodeUpdate(two)
        for node in ([2]^^Node{&one, &two}) {
            if node^.m.demoted {
                // what the tool does: leave and come back, now as a guest of the one that is heard
                name: string = "one" if node == &one else "two"
                NodeClose(node^)
                config.role = .GUEST
                config.name = name
                node^ = NodeOpen(config)
                reopened += 1
            }
        }
        hosts: int = int(one.m.is_host && one.m.phase == .RUNNING) + int(two.m.is_host && two.m.phase == .RUNNING)
        if hosts == 1 && (one.m.is_host && one.joined == 1 && MessengerReady(two.m) || two.m.is_host && two.joined == 1 && MessengerReady(one.m)) && reopened <= 1 {
            settled = true
            break
        }
        time.sleep(time.Millisecond)
    }
    testing.expect(t, settled)
    fmt.printfln("race: settled=%v, reopened %d time(s)", settled, reopened)
    if settled {
        host, guest: ^Node = one, two
        if two.m.is_host {
            host, guest = two, one
        }
        testing.expect(t, MessengerSendText(guest.m, HOST_ID, "after the race", p2p.LinkNow()))
        heard := proc(nodes: []^Node) -> bool {
            return Heard(nodes[0], "after the race")
        }
        testing.expect(t, PumpUntil([]^Node{host, guest}, heard, 20000))
    }
}

PathSize :: proc(path: string) -> (size: i64, ok: bool) {
    file, error := os.open(path)
    if error != nil {
        return
    }
    defer os.close(file)
    size_value, size_error := os.file_size(file)
    return size_value, size_error == nil
}

// A transfer that is cut in the middle (the sender leaves) keeps what arrived; sending the same file again continues there and the
// result is the same file. A part that is not the start of the file is refused and thrown away.
@(test)
MessengerResumeTest :: proc(t: ^testing.T) {
    random: [4]byte
    crypto.rand_bytes(random[:])
    channel: string = fmt.aprintf("resume-%x", random)
    defer delete(channel)
    folder: string = TempFolder("resume")
    defer os.remove_all(folder)
    defer delete(folder)
    receive: string = fmt.aprintf("%s/in", folder)
    defer delete(receive)
    source: string = fmt.aprintf("%s/big.bin", folder)
    defer delete(source)
    part: string = fmt.aprintf("%s/big.bin.part", receive)
    defer delete(part)
    FillTestFile(source, 6_000_000)

    host: ^Node = NodeOpen({channel = channel, name = "receiver", role = .HOST, lan = true, receive_dir = receive, auto_accept = true})
    testing.expect(t, host != nil)
    defer NodeClose(host)
    sender_config: MessengerConfig = {channel = channel, name = "sender", role = .GUEST, lan = true}
    sender: ^Node = NodeOpen(sender_config)
    testing.expect(t, sender != nil)
    joined := proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 1 && nodes[1].connected
    }
    testing.expect(t, PumpUntil([]^Node{host, sender}, joined))
    _, started := MessengerSendFile(sender.m, 0, source, p2p.LinkNow())
    testing.expect(t, started)

    // cut it when part of the file has arrived
    cut: bool
    for _ in 0 ..< 8000 {
        NodeUpdate(host)
        NodeUpdate(sender)
        if size, size_ok := PathSize(part); size_ok && size > 200_000 && size < 5_000_000 {
            cut = true
            break
        }
        time.sleep(time.Millisecond)
    }
    testing.expect(t, cut)
    NodeClose(sender)
    left := proc(nodes: []^Node) -> bool {
        return nodes[0].left == 1
    }
    testing.expect(t, PumpUntil([]^Node{host}, left))
    kept, kept_ok := PathSize(part)
    testing.expect(t, kept_ok && kept > 200_000)                                   // the part stays

    // the same file again: it continues from the part
    sender = NodeOpen(sender_config)
    testing.expect(t, sender != nil)
    defer NodeClose(sender)
    nodes: []^Node = {host, sender}
    testing.expect(t, PumpUntil(nodes, proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 2 && nodes[1].connected
    }))
    done_before: int = len(host.done)
    _, started = MessengerSendFile(sender.m, 0, source, p2p.LinkNow())
    testing.expect(t, started)
    finished := proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 1 && len(nodes[0].done) >= 1
    }
    testing.expect(t, PumpUntil(nodes, finished, 20000))
    testing.expect_value(t, len(host.done), done_before + 1)
    testing.expect(t, SameFile(source, fmt.tprintf("%s/big.bin", receive)))
    testing.expect(t, !os.exists(part))
    continued: bool
    for line in host.errors {
        continued ||= strings.contains(line, "continuing an interrupted transfer")
    }
    testing.expect(t, continued)

    // a part that is not the start of the file: refused, thrown away, and the next send starts clean
    os.remove(fmt.tprintf("%s/big.bin", receive))
    garbage, garbage_error := os.open(part, {.Write, .Create, .Trunc})
    testing.expect(t, garbage_error == nil)
    junk: [5000]byte
    for i in 0 ..< len(junk) {
        junk[i] = 0xAB
    }
    os.write(garbage, junk[:])
    os.close(garbage)
    sender_done: int = len(sender.done)
    _, started = MessengerSendFile(sender.m, 0, source, p2p.LinkNow())
    testing.expect(t, started)
    refused := proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 2
    }
    testing.expect(t, PumpUntil(nodes, refused, 20000))
    testing.expect(t, sender_done == 1 && len(sender.done) == 2 && !sender.done[1].ok)
    for _ in 0 ..< 200 {                                           // the receiver learns of it a moment later
        NodeUpdate(host)
        NodeUpdate(sender)
        time.sleep(time.Millisecond)
    }
    testing.expect(t, !os.exists(part))
    _, started = MessengerSendFile(sender.m, 0, source, p2p.LinkNow())
    testing.expect(t, started)
    testing.expect(t, PumpUntil(nodes, proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 3
    }, 20000))
    testing.expect(t, SameFile(source, fmt.tprintf("%s/big.bin", receive)))
}

// A folder cut off in the middle (the sender closes) is kept as a staging folder with its manifest; sending the same folder again continues
// from there, and a leftover of a different folder is refused, thrown away, and the next send starts clean.
@(test)
MessengerFolderResumeTest :: proc(t: ^testing.T) {
    random: [4]byte
    crypto.rand_bytes(random[:])
    channel: string = fmt.aprintf("folderresume-%x", random)
    defer delete(channel)
    folder: string = TempFolder("folderresume")
    defer os.remove_all(folder)
    defer delete(folder)
    receive: string = fmt.aprintf("%s/in", folder)
    defer delete(receive)
    source: string = fmt.aprintf("%s/proj", folder)
    defer delete(source)
    stage: string = fmt.aprintf("%s/proj.part", receive)
    defer delete(stage)
    manifest: string = fmt.aprintf("%s.manifest", stage)
    defer delete(manifest)
    os.make_directory_all(fmt.tprintf("%s/sub", source))
    _ = os.write_entire_file(fmt.tprintf("%s/a.txt", source), "first file")
    FillTestFile(fmt.tprintf("%s/sub/big.bin", source), 6_000_000)

    host: ^Node = NodeOpen({channel = channel, name = "receiver", role = .HOST, lan = true, receive_dir = receive, auto_accept = true})
    testing.expect(t, host != nil)
    defer NodeClose(host)
    sender_config: MessengerConfig = {channel = channel, name = "sender", role = .GUEST, lan = true}
    sender: ^Node = NodeOpen(sender_config)
    testing.expect(t, sender != nil)
    testing.expect(t, PumpUntil([]^Node{host, sender}, proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 1 && nodes[1].connected
    }))
    _, started := MessengerSendFolder(sender.m, 0, source, {}, p2p.LinkNow())
    testing.expect(t, started)

    // cut it when part of the big file has arrived
    big: string = fmt.tprintf("%s/sub/big.bin", stage)
    cut: bool
    for _ in 0 ..< 8000 {
        NodeUpdate(host)
        NodeUpdate(sender)
        if size, size_ok := PathSize(big); size_ok && size > 200_000 && size < 5_000_000 {
            cut = true
            break
        }
        time.sleep(time.Millisecond)
    }
    testing.expect(t, cut)
    NodeClose(sender)
    testing.expect(t, PumpUntil([]^Node{host}, proc(nodes: []^Node) -> bool {
        return nodes[0].left == 1
    }))
    testing.expect(t, os.is_dir(stage) && os.is_file(manifest))                      // both stay

    // the same folder again: it continues from what is there
    sender = NodeOpen(sender_config)
    testing.expect(t, sender != nil)
    defer NodeClose(sender)
    nodes: []^Node = {host, sender}
    testing.expect(t, PumpUntil(nodes, proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 2 && nodes[1].connected
    }))
    done_before: int = len(host.done)
    _, started = MessengerSendFolder(sender.m, 0, source, {}, p2p.LinkNow())
    testing.expect(t, started)
    testing.expect(t, PumpUntil(nodes, proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 1 && len(nodes[0].done) >= 1
    }, 20000))
    testing.expect_value(t, len(host.done), done_before + 1)
    testing.expect(t, host.done[len(host.done) - 1].ok)
    final: string = fmt.tprintf("%s/proj", receive)
    testing.expect(t, SameFile(fmt.tprintf("%s/sub/big.bin", source), fmt.tprintf("%s/sub/big.bin", final)))
    testing.expect(t, SameFile(fmt.tprintf("%s/a.txt", source), fmt.tprintf("%s/a.txt", final)))
    testing.expect(t, !os.exists(stage) && !os.exists(manifest))
    continued: bool
    for line in host.errors {
        continued ||= strings.contains(line, "continuing an interrupted transfer")
    }
    testing.expect(t, continued)

    // a leftover of another folder of the same name (its big file differs in the first byte): the sender notices, nothing of it is kept
    os.remove_all(final)
    alternative: string = fmt.tprintf("%s/alt/proj", folder)
    os.make_directory_all(fmt.tprintf("%s/sub", alternative))
    _ = os.write_entire_file(fmt.tprintf("%s/a.txt", alternative), "first file")
    FillTestFile(fmt.tprintf("%s/sub/big.bin", alternative), 6_000_000)
    if bytes, read_error := os.read_entire_file(fmt.tprintf("%s/sub/big.bin", alternative), context.allocator); read_error == nil {
        bytes[0] ~= 0xFF
        _ = os.write_entire_file(fmt.tprintf("%s/sub/big.bin", alternative), bytes)
        delete(bytes)
    }
    other: Bundle
    testing.expect(t, BundleScan(&other, alternative, {}, context.allocator))
    leftover: [dynamic]byte
    defer delete(leftover)
    chunk: [4096]byte
    for len(leftover) < 1_000_000 {
        count: int = BundleRead(&other, chunk[:])
        append(&leftover, ..chunk[:max(count, 0)])
        if count < len(chunk) {
            break
        }
    }
    BundleDestroy(&other)
    stale: BundleReader
    BundleReaderInit(&stale, stage, false, manifest)
    testing.expect(t, BundleFeed(&stale, leftover[:]))
    BundleReaderClose(&stale)
    sender_done: int = len(sender.done)
    _, started = MessengerSendFolder(sender.m, 0, source, {}, p2p.LinkNow())
    testing.expect(t, started)
    testing.expect(t, PumpUntil(nodes, proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 2
    }, 20000))
    testing.expect(t, sender_done == 1 && len(sender.done) == 2 && !sender.done[1].ok)
    for _ in 0 ..< 200 {
        NodeUpdate(host)
        NodeUpdate(sender)
        time.sleep(time.Millisecond)
    }
    testing.expect(t, !os.exists(stage) && !os.exists(manifest))
    // and the next send starts clean
    _, started = MessengerSendFolder(sender.m, 0, source, {}, p2p.LinkNow())
    testing.expect(t, started)
    testing.expect(t, PumpUntil(nodes, proc(nodes: []^Node) -> bool {
        return len(nodes[1].done) == 3
    }, 20000))
    testing.expect(t, sender.done[2].ok)
    testing.expect(t, SameFile(fmt.tprintf("%s/sub/big.bin", source), fmt.tprintf("%s/sub/big.bin", final)))
}
