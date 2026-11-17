// amsg: a terminal member of an ai_messaging channel. Humans type in it, AI agents are started by it later (not done yet): this is the
// part that talks to the channel and to the person at the keyboard.
//
//   amsg <channel> [--name N] [--dir received] [--auto-accept] [--host | --guest] [--no-lan] [--stun] [--max-mb N]
//
// The first one to open a channel hosts it; the others find it by the channel name on the same computer or network. Over the
// internet one pastes the code of the other (/code shows yours). Lines typed here:
//   hello everybody              to all members            /to bob text        to one member
//   /send bob path/to/file       send a file (bob, or all) /yes 3  /no 3       answer a file offer
//   /who                         list the members          /code               show this member's code
//   <a pasted code>              joins / accepts a reply   /quit
// Output lines are one event each, easy to parse: "<name> text", "<name> (to you) text", "* ..." for everything else.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import ai "../.."
import p2p "../../../p2p"

MAX_LINE :: 1024
LINE_QUEUE :: 32

LineQueue :: struct {
    mutex: sync.Mutex,
    lines: [LINE_QUEUE][MAX_LINE]byte,
    lengths: [LINE_QUEUE]int,
    head: int,
    count: int,
    closed: bool,
}

lines: LineQueue

main :: proc() {
    config: ai.MessengerConfig
    config.lan = true
    config.receive_dir = "received"
    config.link.no_ipv6 = false
    for i := 1; i < len(os.args); i += 1 {
        argument: string = os.args[i]
        switch argument {
        case "--name":
            i += 1
            config.name = os.args[i] if i < len(os.args) else ""
        case "--dir":
            i += 1
            config.receive_dir = os.args[i] if i < len(os.args) else "received"
        case "--auto-accept":
            config.auto_accept = true
        case "--host":
            config.role = .HOST
        case "--guest":
            config.role = .GUEST
        case "--no-lan":
            config.lan = false
        case "--stun":
            config.use_stun = true
        case "--max-mb":
            i += 1
            megabytes, ok := strconv.parse_int(os.args[i] if i < len(os.args) else "")
            if !ok || megabytes < 0 {
                fmt.eprintln("--max-mb needs a number")
                os.exit(2)
            }
            config.max_file_size = u64(megabytes) * 1024 * 1024
        case:
            if strings.has_prefix(argument, "--") || config.channel != "" {
                fmt.eprintfln("unknown argument %s", argument)
                os.exit(2)
            }
            config.channel = argument
        }
    }
    if config.channel == "" {
        fmt.eprintln("usage: amsg <channel> [--name N] [--dir received] [--auto-accept] [--host | --guest] [--no-lan] [--stun] [--max-mb N]")
        os.exit(2)
    }
    if config.name == "" {
        config.name = os.get_env("USERNAME", context.temp_allocator)
        if config.name == "" {
            config.name = os.get_env("USER", context.temp_allocator)
        }
        if config.name == "" {
            config.name = "member"
        }
    }

    m: ^ai.Messenger = new(ai.Messenger)
    if !ai.MessengerOpen(m, config, p2p.LinkNow()) {
        fmt.eprintln("cannot open the UDP socket")
        os.exit(1)
    }
    fmt.printfln("* channel \"%s\" as %s, finding addresses%s...", config.channel, config.name, " and looking for a host" if config.role != .HOST else "")
    thread.create_and_start(ReadLines, context)
    Loop(m, config)
}

Loop :: proc(m: ^ai.Messenger, config: ai.MessengerConfig) {
    announced_code: bool
    for {
        now: i64 = p2p.LinkNow()
        ai.MessengerUpdate(m, now)
        for {
            event, ok := ai.MessengerPoll(m)
            if !ok {
                break
            }
            ShowEvent(m, &event)
        }
        // the code is shown once the role is known and again on /code
        if !announced_code && m.link.role != .NONE {
            announced_code = true
            ShowCode(m, "code to paste on another network (the same network finds the channel by its name)")
        }
        input: [MAX_LINE]byte
        length, has_line := PopLine(input[:])
        if has_line {
            Command(m, strings.trim_space(string(input[:length])), now)
        }
        time.sleep(5 * time.Millisecond)
    }
}

ShowCode :: proc(m: ^ai.Messenger, title: string) {
    buffer: [p2p.CODE_TEXT_MAX]byte
    code: string = ai.MessengerCode(m, buffer[:])
    if code == "" {
        fmt.println("* no code yet (still looking for a host, or finding addresses)")
        return
    }
    fmt.printfln("* %s:", title)
    fmt.printfln("CODE: %s", code)
}

ShowEvent :: proc(m: ^ai.Messenger, event: ^ai.Event) {
    text: string = ai.EventText(event)
    name: string = ai.MessengerName(m, event.member)
    switch event.kind {
    case .NONE:
    case .CONNECTED:
        fmt.printfln("* connected as %s (member %d)%s", ai.MessengerName(m, ai.MessengerSelf(m)), ai.MessengerSelf(m), ", hosting" if m.is_host else "")
    case .MEMBER_JOINED:
        fmt.printfln("* %s joined", text)
    case .MEMBER_LEFT:
        fmt.printfln("* %s left", text)
    case .TEXT:
        if event.to == ai.ALL {
            fmt.printfln("<%s> %s", name, text)
        } else {
            fmt.printfln("<%s> (to you) %s", name, text)
        }
    case .FILE_OFFERED:
        fmt.printfln("* %s offers the file \"%s\" (%d bytes): /yes %d or /no %d  (from %s)", name, text, event.size, event.transfer, event.transfer, name)
    case .FILE_PROGRESS:
        fmt.printfln("* file %d %s: %d of %d bytes", event.transfer, "incoming" if event.incoming else "outgoing", event.done, event.size)
    case .FILE_DONE:
        direction: string = "from" if event.incoming else "to"
        if event.ok {
            fmt.printfln("* file %d %s %s done, %d bytes%s", event.transfer, direction, name, event.size, fmt.tprintf(", saved as %s", text) if event.incoming else "")
        } else {
            fmt.printfln("* file %d %s %s FAILED: %s", event.transfer, direction, name, text)
        }
    case .ERROR:
        fmt.printfln("* error: %s", text)
    }
}

Command :: proc(m: ^ai.Messenger, line: string, now: i64) {
    switch {
    case line == "":
    case line == "/quit":
        ai.MessengerClose(m)
        os.exit(0)
    case line == "/code":
        ShowCode(m, "your code")
    case line == "/who":
        for id in 0 ..< ai.MAX_MEMBERS {
            name: string = ai.MessengerName(m, u8(id))
            if name != "" {
                fmt.printfln("* member %d: %s%s%s", id, name, " (host)" if id == 0 else "", " (you)" if u8(id) == ai.MessengerSelf(m) else "")
            }
        }
    case strings.has_prefix(line, "/to "):
        rest: string = strings.trim_space(line[4:])
        space: int = strings.index_byte(rest, ' ')
        if space < 0 {
            fmt.println("* usage: /to <name> <text>")
            return
        }
        Say(m, ai.MessengerFindMember(m, rest[:space]), strings.trim_space(rest[space + 1:]), now)
    case strings.has_prefix(line, "/send "):
        rest: string = strings.trim_space(line[6:])
        space: int = strings.index_byte(rest, ' ')
        if space < 0 {
            fmt.println("* usage: /send <name|all> <path>")
            return
        }
        Send(m, rest[:space], strings.trim_space(rest[space + 1:]), now)
    case strings.has_prefix(line, "/yes ") || strings.has_prefix(line, "/no "):
        accept: bool = strings.has_prefix(line, "/yes ")
        number, ok := strconv.parse_int(strings.trim_space(line[5 if accept else 4:]))
        if !ok {
            fmt.println("* usage: /yes <transfer number>")
            return
        }
        // the offer is identified by number; the sender is whoever offered it
        for &in_ in m.ins {
            if in_.state == .PENDING && int(in_.id) == number {
                ai.MessengerFileAnswer(m, in_.from, in_.id, accept, now)
                fmt.printfln("* %s", "accepted" if accept else "declined")
                return
            }
        }
        fmt.println("* no such offer")
    case strings.has_prefix(line, "/"):
        fmt.println("* commands: /to name text  /send name|all path  /yes n  /no n  /who  /code  /quit")
    case len(line) > 40 && !strings.contains_rune(line, ' '):
        ok, message := ai.MessengerUseCode(m, line, now)
        _ = ok
        fmt.printfln("* %s", message)
        if ok && !m.is_host {
            ShowCode(m, "send this reply code back to the host")
        }
    case:
        Say(m, ai.ALL, line, now)
    }
}

Say :: proc(m: ^ai.Messenger, to: u8, text: string, now: i64) {
    if to == ai.UNKNOWN_ID {
        fmt.println("* no such member (see /who)")
        return
    }
    if !ai.MessengerReady(m) {
        fmt.println("* not in a channel yet, nobody got that")
        return
    }
    if !ai.MessengerSendText(m, to, text, now) {
        fmt.println("* not sent (too long, nobody there, or too many messages waiting)")
    }
}

Send :: proc(m: ^ai.Messenger, target: string, path: string, now: i64) {
    if !os.exists(path) {
        fmt.printfln("* no such file: %s", path)
        return
    }
    sent: int
    for id in 0 ..< ai.MAX_MEMBERS {
        name: string = ai.MessengerName(m, u8(id))
        if name == "" || u8(id) == ai.MessengerSelf(m) {
            continue
        }
        if strings.equal_fold(target, "all") || strings.equal_fold(target, name) {
            transfer, ok := ai.MessengerSendFile(m, u8(id), path, now)
            if ok {
                fmt.printfln("* offering %s to %s (file %d)", path, name, transfer)
                sent += 1
            } else {
                fmt.printfln("* could not start sending to %s (no free slot, or not connected)", name)
            }
        }
    }
    if sent == 0 {
        fmt.println("* nobody to send it to (see /who)")
    }
}

// ============================================================ stdin thread: a blocked read must not stop the network

ReadLines :: proc() {
    pending: [MAX_LINE]byte
    count: int
    chunk: [256]byte
    for {
        length, error := os.read(os.stdin, chunk[:])
        if error != nil || length <= 0 {
            break
        }
        for b in chunk[:length] {
            switch b {
            case '\n':
                PushLine(pending[:count])
                count = 0
            case '\r':
            case:
                if count < MAX_LINE {
                    pending[count] = b
                    count += 1
                }
            }
        }
    }
    sync.mutex_guard(&lines.mutex)
    lines.closed = true
}

PushLine :: proc(line: []byte) {
    for {
        sync.mutex_lock(&lines.mutex)
        if lines.count < LINE_QUEUE {
            slot: int = (lines.head + lines.count) % LINE_QUEUE
            copy(lines.lines[slot][:], line)
            lines.lengths[slot] = len(line)
            lines.count += 1
            sync.mutex_unlock(&lines.mutex)
            return
        }
        sync.mutex_unlock(&lines.mutex)
        time.sleep(time.Millisecond)
    }
}

PopLine :: proc(out: []byte) -> (length: int, ok: bool) {
    sync.mutex_guard(&lines.mutex)
    if lines.count == 0 {
        if lines.closed {
            os.exit(0)                   // a pipe that ended: nothing left to wait for
        }
        return
    }
    length = lines.lengths[lines.head]
    copy(out, lines.lines[lines.head][:length])
    lines.head = (lines.head + 1) % LINE_QUEUE
    lines.count -= 1
    return length, true
}
