#+build !js
package ai_messaging

import "core:crypto"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import p2p "../p2p"

// The file format: records with awkward text come back whole, the file is a series of gzip members that survives a cut end, and a long log
// goes on in the next part.
@(test)
LogFormatTest :: proc(t: ^testing.T) {
    folder: string = TempFolder("logformat")
    defer os.remove_all(folder)
    defer delete(folder)
    log: Log
    path, ok := LogOpen(&log, folder, "chan/x", "ann bob", 1000)
    testing.expect(t, ok)
    path = strings.clone(path)
    defer delete(path)
    testing.expect(t, strings.contains(path, "chan_x.ann_bob."))                // names in a file name are made safe
    log.rotate_at = 100 * 1024
    LogMember(&log, 1010, 0, "ann")
    LogRecord(&log, 1020, "g", "0", "0.1", "tab\there, newline\nhere, backslash \\ and \r more")
    LogRecord(&log, 1020, "n", "", "", "")
    LogMember(&log, 1030, 0, "ann")                                              // the same name again: nothing is written
    testing.expect_value(t, log.block_length > 0, true)
    // many records: several blocks, then one more part
    filler: string = strings.repeat("line of agent text that repeats and compresses well. ", 20, context.temp_allocator)
    for i in 0 ..< 400 {
        LogRecord(&log, 2000 + i64(i), "a", "0", "1.1", filler)
    }
    LogRecord(&log, 9000, "n", "", "", "the end")
    stem: string = strings.clone(log.stem)
    defer delete(stem)
    LogClose(&log)

    data, error := os.read_entire_file(path, context.temp_allocator)
    testing.expect(t, error == nil)
    text, decoded := LogDecode(data, context.temp_allocator)
    testing.expect(t, decoded)
    lines: []string = strings.split_lines(text, context.temp_allocator)
    testing.expect(t, strings.has_prefix(lines[0], "#amsglog\t1\t"))
    testing.expect(t, strings.has_suffix(lines[0], "\tchan/x\tann bob\t1"))
    testing.expect_value(t, lines[1], "10\t@\t0\t\tann")
    testing.expect_value(t, lines[2], "10\tg\t0\t0.1\ttab\\there, newline\\nhere, backslash \\\\ and \\r more")
    testing.expect_value(t, LogUnescape(strings.split_n(lines[2], "\t", 5, context.temp_allocator)[4], context.temp_allocator), "tab\there, newline\nhere, backslash \\ and \r more")
    testing.expect(t, os.exists(fmt.tprintf("%s.2.amsglog.gz", stem)))          // 440 KB of text with 100 KB parts: the log went on in the next ones
    testing.expect(t, !strings.contains(text, "the end"))
    last_part: int = 1
    for os.exists(fmt.tprintf("%s.%d.amsglog.gz", stem, last_part + 1)) {
        last_part += 1
    }
    testing.expect(t, last_part >= 3)
    last_data, _ := os.read_entire_file(fmt.tprintf("%s.%d.amsglog.gz", stem, last_part), context.temp_allocator)
    last_text, last_ok := LogDecode(last_data, context.temp_allocator)
    testing.expect(t, last_ok)
    testing.expect(t, strings.has_suffix(strings.split_lines(last_text, context.temp_allocator)[0], fmt.tprintf("\tann bob\t%d", last_part)))     // every part has its header
    testing.expect(t, strings.contains(last_text, "\tthe end\n"))
    testing.expect(t, len(data) < len(text) / 4)                                 // it is small: this text compresses to a fraction

    // a program that died while writing leaves a cut last member: everything before it is still readable
    cut: []byte = data[:len(data) - 7]
    cut_text, cut_ok := LogDecode(cut, context.temp_allocator)
    testing.expect(t, cut_ok)
    testing.expect(t, strings.has_prefix(cut_text, "#amsglog\t1\t"))
    testing.expect(t, len(cut_text) < len(text) && len(cut_text) > len(text) / 2)

    // rotation: the next part starts with its own header
    second: Log
    _, ok = LogOpen(&second, folder, "chan", "rot", 0)
    testing.expect(t, ok)
    second.rotate_at = 20 * 1024
    for i in 0 ..< 400 {
        LogRecord(&second, i64(i), "a", "0", "1.1", fmt.tprintf("%d %s", i, filler))
    }
    second_stem: string = strings.clone(second.stem)
    defer delete(second_stem)
    LogClose(&second)
    testing.expect(t, os.exists(fmt.tprintf("%s.2.amsglog.gz", second_stem)))
}

// Two programs: what one sends is found in the log of the other under the same id, and the trace of a typed line follows it through the agent
// of its program to the message that agent sent and the member that heard it.
@(test)
LogTraceTest :: proc(t: ^testing.T) {
    fake: string = FakeAgent()
    testing.expect(t, fake != "")
    if fake == "" {
        return
    }
    random: [4]byte
    crypto.rand_bytes(random[:])
    channel: string = fmt.aprintf("logtrace-%x", random)
    defer delete(channel)
    folder: string = TempFolder("logtrace")
    defer os.remove_all(folder)
    defer delete(folder)

    names: [2]string = {"alice", "bob"}
    nodes: [2]^Node
    paths: [2]string
    for name, i in names {
        directory: string = fmt.aprintf("%s/%s", folder, name)
        defer delete(directory)
        receive: string = fmt.aprintf("%s/in", directory)
        defer delete(receive)
        agent_dir: string = fmt.aprintf("%s/agent", directory)
        defer delete(agent_dir)
        logs: string = fmt.aprintf("%s/logs", folder)
        defer delete(logs)
        nodes[i] = NodeOpen({channel = channel, name = name, role = .HOST if i == 0 else .GUEST, lan = true, receive_dir = receive})
        testing.expect(t, nodes[i] != nil)
        nodes[i].session = new(Session)
        testing.expect(t, SessionInit(nodes[i].session, nodes[i].m, {agent_command = fake, agent_dir = agent_dir, log_dir = logs}))
        testing.expect(t, nodes[i].session.log.enabled)
        paths[i] = strings.clone(LogPath(&nodes[i].session.log))
    }
    alice, bob := nodes[0], nodes[1]
    both: []^Node = nodes[:]
    testing.expect(t, PumpUntil(both, proc(nodes: []^Node) -> bool {
        return nodes[0].joined == 1 && nodes[1].connected
    }))
    message, started := SessionSpawn(alice.session, "", p2p.LinkNow())
    testing.expect(t, started, message)
    testing.expect(t, Until(both, proc(nodes: []^Node) -> bool {
        return nodes[0].session.ready
    }))
    // alice types a line for her agent; the agent says "pong" to the group; bob hears it. Bob answers privately to alice
    testing.expect(t, SessionLine(alice.session, "say:pong", p2p.LinkNow()))
    testing.expect(t, Until(both, proc(nodes: []^Node) -> bool {
        return len(nodes[1].texts) > 0
    }))
    testing.expect(t, MessengerSendText(bob.m, HOST_ID, "thanks, bob here", p2p.LinkNow()))
    testing.expect(t, Until(both, proc(nodes: []^Node) -> bool {
        return len(nodes[0].texts) > 0
    }))
    Pump(both, 300)
    for node in nodes {
        SessionClose(node.session, p2p.LinkNow())
        free(node.session)
        NodeClose(node)
    }

    entries, _, loaded := LogLoad(paths[:], context.temp_allocator)
    testing.expect(t, loaded)
    typed: LogEntry
    heard: LogEntry
    reply: LogEntry
    for entry in entries {
        switch {
        case entry.kind == "u" && entry.text == "say:pong":
            typed = entry
        case entry.kind == "g" && entry.text == "pong":
            heard = entry
        case entry.kind == "p" && strings.contains(entry.text, "bob here"):
            reply = entry
        }
    }
    testing.expect(t, typed.msg != "", "the typed line has an id")
    testing.expect(t, heard.msg != "", "bob logged the message of alice's agent with its id")
    testing.expect(t, strings.has_prefix(heard.who, "alice"), heard.who)
    testing.expect(t, strings.has_suffix(heard.who, "'s agent"), heard.who)
    testing.expect(t, reply.msg != "", "alice logged the private message of bob with its id")
    testing.expect(t, strings.has_prefix(typed.owner, "alice/") && strings.has_prefix(heard.owner, "bob/"))
    // the instance in the id is the one of the sender: the typed line of alice and the id of what bob heard come from the same program
    testing.expect_value(t, strings.split(typed.msg, ":", context.temp_allocator)[0], strings.split(heard.msg, ":", context.temp_allocator)[0])
    // bob's private message carries bob's instance
    testing.expect(t, strings.split(reply.msg, ":", context.temp_allocator)[0] != strings.split(typed.msg, ":", context.temp_allocator)[0])

    // the trace of the typed line: the line, the agent's turn that it caused, the message the agent sent, and who heard it
    traced: []LogEntry = LogTrace(entries, typed.msg, context.temp_allocator)
    seen: map[string]bool
    seen.allocator = context.temp_allocator
    for entry in traced {
        seen[fmt.tprintf("%s %s", entry.owner[:strings.index_byte(entry.owner, '/')], entry.kind)] = true
    }
    testing.expect(t, "alice u" in seen)
    testing.expect(t, "alice i" in seen)                       // handed to the agent, caused by the typed line
    testing.expect(t, "alice GA" in seen)                      // and sent a group message
    testing.expect(t, "alice d" in seen)                       // the turn ended
    testing.expect(t, "bob g" in seen)                         // bob heard it
    testing.expect(t, !("bob p" in seen))                      // what bob said afterwards has nothing to do with it
    for entry in traced {
        if entry.kind == "GA" {
            testing.expect_value(t, entry.msg, heard.msg)        // the same id on both sides
        }
    }
    // commands and the rest are in the logs too
    commands: int
    for entry in entries {
        if entry.kind == "n" && strings.contains(entry.text, "your agent is up") {
            commands += 1
        }
    }
    testing.expect_value(t, commands, 1)
    for path in paths {
        delete(path)
    }
}

// What the agents cost, from a log that was written by hand: two runs of one agent, an error, a turn that bob's message started and one that
// an idle report started, and the agent of another instance.
@(test)
LogCostTest :: proc(t: ^testing.T) {
    folder: string = TempFolder("logcost")
    defer os.remove_all(folder)
    defer delete(folder)
    paths: [2]string
    names: [2]string = {"alice", "carol"}
    for name, i in names {
        log: Log
        path, ok := LogOpen(&log, folder, "chan", name, 1000)
        testing.expect(t, ok)
        paths[i] = strings.clone(path)
        if i == 0 {
            LogMember(&log, 1001, 0, "alice")
            LogMember(&log, 1002, 1, "bob")
            LogInstance(&log, 1003, 1, u64(0xB0B) << 32 | 7)
            LogRecord(&log, 1100, "g", "1", "1.7", "please summarise the report")           // bob's message, as alice heard it
            LogRecord(&log, 1110, "i", "0", "1.1", "@1.7")                                   // it started turn 1 of run 1
            LogRecord(&log, 1200, "t", "0", "1.1", "Read report.txt")
            LogRecord(&log, 1300, "a", "0", "1.1", "the summary")
            LogRecord(&log, 1400, "d", "0", "1.1", "0.0100 8 ok")
            LogRecord(&log, 1500, "i", "0", "1.2", "[idle carol] all done")                  // turn 2: an idle report
            LogRecord(&log, 1600, "d", "0", "1.2", "0.0020 2 error the turn failed")
            LogRecord(&log, 2000, "i", "0", "2.1", "@1.7")                                   // a second run of the agent
            LogRecord(&log, 2100, "t", "0", "2.1", "Glob *")
            LogRecord(&log, 2200, "t", "0", "2.1", "Read a")
            LogRecord(&log, 2300, "d", "0", "2.1", "0.0300 20 ok")
        } else {
            LogRecord(&log, 1100, "i", "0", "1.1", "[amsg] you are online")
            LogRecord(&log, 1200, "d", "0", "1.1", "0.0005 1 ok")
        }
        LogClose(&log)
    }
    entries, _, loaded := LogLoad(paths[:], context.temp_allocator)
    testing.expect(t, loaded)
    rows, turns := LogSummary(entries, context.temp_allocator)
    find :: proc(rows: []LogCost, name: string, run: int) -> LogCost {
        for row in rows {
            if strings.has_prefix(row.owner, name) && row.run == run { return row }
        }
        return {}
    }
    first: LogCost = find(rows, "alice/", 1)
    testing.expect_value(t, first.turns, 2)
    testing.expect_value(t, first.errors, 1)
    testing.expect_value(t, first.tools, 1)
    testing.expect_value(t, first.replies, 1)
    testing.expect_value(t, first.seconds, 10)
    testing.expect(t, abs(first.cost - 0.0120) < 1e-9)
    second: LogCost = find(rows, "alice/", 2)
    testing.expect_value(t, second.turns, 1)
    testing.expect_value(t, second.tools, 2)
    all: LogCost = find(rows, "alice/", 0)                                                  // an instance with two runs also gets a row for both
    testing.expect_value(t, all.turns, 3)
    testing.expect(t, abs(all.cost - 0.0420) < 1e-9)
    testing.expect_value(t, find(rows, "carol/", 0).turns, 0)                               // one run: no row for "all"
    testing.expect_value(t, find(rows, "carol/", 1).turns, 1)

    // the dearest turn first, with what started it: the message of bob, the idle report, the intro
    testing.expect_value(t, len(turns), 4)
    testing.expect(t, abs(turns[0].cost - 0.0300) < 1e-9 && turns[0].run == 2)
    testing.expect_value(t, turns[0].started_by, "please summarise the report")           // the same message started the second run's turn
    testing.expect(t, abs(turns[1].cost - 0.0100) < 1e-9)
    testing.expect_value(t, turns[1].started_by, "please summarise the report")
    testing.expect(t, abs(turns[2].cost - 0.0020) < 1e-9 && !turns[2].ok)
    testing.expect_value(t, turns[2].started_by, "[idle carol] all done")
    testing.expect_value(t, turns[3].started_by, "[amsg] you are online")
    for path in paths {
        delete(path)
    }
}
