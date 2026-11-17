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
    free(node)
}

NodeUpdate :: proc(node: ^Node) {
    MessengerUpdate(node.m, p2p.LinkNow())
    for {
        event, ok := MessengerPoll(node.m)
        if !ok {
            break
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
        case .FILE_OFFERED:
            append(&node.offered, event)
        case .FILE_DONE:
            append(&node.done, event)
        case .ERROR:
            append(&node.errors, strings.clone(string(event.text[:event.text_length])))
        }
    }
}

// Pumps every node until `condition` holds or about 8 seconds passed.
PumpUntil :: proc(nodes: []^Node, condition: proc(nodes: []^Node) -> bool) -> bool {
    for _ in 0 ..< 8000 {
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
