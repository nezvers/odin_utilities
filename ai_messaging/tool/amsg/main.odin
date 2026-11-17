// amsg: a terminal member of an ai_messaging channel. Humans type in it, and each terminal can have a private AI agent (Claude Code) that
// works for the person at the keyboard: this is the part that talks to the channel, to the person and to the agent.
//
//   amsg <channel> [--name N] [--dir received] [--auto-accept] [--host | --guest] [--no-lan] [--stun] [--max-mb N]
//                  [--json] [--exclude name]... [--include-git] [--keep-exec] [--derp [N]] [--derp-host name] [--derp-only] [--auto-reconnect]
//                  [--agent [model]] [--agent-model M] [--agent-cmd claude] [--agent-tools Read,Glob] [--agent-dir agent_files]
//                  [--listen mentions|all|none] [--agent-trust ask|members|name,name] [--allow-remote-agent]
//
// The first one to open a channel hosts it; the others find it by the channel name on the same computer or network. Over the
// internet one pastes the code of the other (--code shows yours). Without --agent this is a plain chat: what you type goes to the group.
// With an agent (--agent at the start, or --spawn later) what you type goes to YOUR agent only, and the agent talks to the group by itself
// when it has something to say; to speak to the group yourself use --group_msg. Lines typed here:
//   hello                        to your agent (no agent: to all members)      --group_msg hello   to all members
//   --to bob text                to one member                                 --send bob path     a file or a whole folder (all = everybody)
//   --spawn [model]              start your agent (model: haiku, sonnet, opus or a full id)   --dismiss   end it
//   --spawn bob [model]          ask bob to start his agent  --dismiss bob   ask him to end it (bob decides: --yes agent / --no agent)
//   --agents                     who has an agent         --listen all|mentions|none   what the channel passes to your agent
//   --trust ask|members|bob,carol   how far your agent believes other members: ask (default) = it asks you first, members = it does what
//                                any member asks with its tools, a list = only those members
//   --yes 3  --no 3              answer an offer           --cancel 3          stop a transfer
//   --who  --code  --quit  --help   <a pasted code> joins or accepts a reply
// Only a line that starts with "--" and a letter is a tool command; everything else, "/" lines included, is a message (to the agent when
// there is one). A line that must start with "--" is sent with a space in front of it.
// The agent has no shell and no files, only the tools of the channel (say, tell, send from --agent-dir, inbox, who): what other members write
// reaches it only when it names it ("@<yourname>-agent", or everything with --listen all). Other members can only ask for an agent here;
// --allow-remote-agent says yes to every such request without asking you (it costs your Claude Code usage).
// --derp: find the others over the internet by the channel name alone, through a free Tailscale DERP relay (no account, nothing to paste).
// Everybody uses the same relay: N is its number (see p2p/tool/derp), without N the fastest one is looked for (so give N when members start
// at different places). --derp-only sends everything through the relay (no addresses offered): for tests and privacy.
// --derp-host name: any DERP server by name instead of the built in list (a relay of your own, or a current one from `derp -- map`).
// --reconnect (a command) closes this member and joins the channel again; --auto-reconnect does it by itself when the host is lost, so
// the channel finds a new host (whoever searches first takes over) and everybody comes back.
// A folder is sent as one new folder at the receiver, all or nothing, without .git, node_modules, __pycache__, .DS_Store and
// whatever --exclude names (a name, or *.ext); --include-git keeps .git. Received folders keep executable bits only with --keep-exec.
//
// Output: one event per line. Text mode: "<name> text", "<name> (to you) text", "* ..." for everything else. With --json every line
// is one JSON object ({"event":"text","from":"bob","to":"all","text":"..."}), for programs and agents to read.
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
MAX_EXCLUDES :: 32

LineQueue :: struct {
    mutex: sync.Mutex,
    lines: [LINE_QUEUE][MAX_LINE]byte,
    lengths: [LINE_QUEUE]int,
    head: int,
    count: int,
    closed: bool,
}

lines: LineQueue
session: ^ai.Session
autostart_agent: bool
autostart_model: string
json_mode: bool
auto_reconnect: bool
reopen_requested: bool
excludes: [MAX_EXCLUDES]string
exclude_count: int

main :: proc() {
    if len(os.args) == 2 && os.args[1] == "--mcp-bridge" {
        ai.McpServe()                                  // started by the agent's Claude Code: the channel as tools, nothing else on stdout
        return
    }
    config: ai.MessengerConfig
    session_config: ai.SessionConfig = {agent_command = "claude", agent_dir = "agent_files"}
    config.lan = true
    config.receive_dir = "received"
    include_git: bool
    use_derp: bool
    for name in ([?]string{".git", "node_modules", "__pycache__", ".DS_Store"}) {
        excludes[exclude_count] = name
        exclude_count += 1
    }
    for i := 1; i < len(os.args); i += 1 {
        argument: string = os.args[i]
        switch argument {
        case "--name":
            i += 1
            config.name = os.args[i] if i < len(os.args) else ""
        case "--password":
            i += 1
            config.password = os.args[i] if i < len(os.args) else ""
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
        case "--derp":
            use_derp = true
            if i + 1 < len(os.args) {
                number, is_number := strconv.parse_int(os.args[i + 1])
                if is_number {
                    config.derp_server = number
                    i += 1
                }
            }
        case "--derp-host":
            i += 1
            if i >= len(os.args) {
                fmt.eprintln("--derp-host needs a name, for example derp.example.com or derp.example.com:8443")
                os.exit(2)
            }
            use_derp = true
            config.derp_server = p2p.DERP_CUSTOM
            config.derp_host = os.args[i]
        case "--auto-reconnect":
            auto_reconnect = true
        case "--derp-only":
            use_derp = true
            config.link.derp_only = true
        case "--json":
            json_mode = true
        case "--keep-exec":
            config.keep_executable = true
        case "--include-git":
            include_git = true
        case "--exclude":
            i += 1
            if i >= len(os.args) || exclude_count >= MAX_EXCLUDES {
                fmt.eprintln("--exclude needs a name (or *.ext), at most 28 of them")
                os.exit(2)
            }
            excludes[exclude_count] = os.args[i]
            exclude_count += 1
        case "--agent":
            autostart_agent = true
            if i + 1 < len(os.args) && !strings.has_prefix(os.args[i + 1], "--") {
                i += 1
                autostart_model = os.args[i]
            }
        case "--agent-model":
            i += 1
            session_config.agent_model = os.args[i] if i < len(os.args) else ""
        case "--agent-cmd":
            i += 1
            session_config.agent_command = os.args[i] if i < len(os.args) else "claude"
        case "--agent-tools":
            i += 1
            session_config.agent_tools = os.args[i] if i < len(os.args) else ""
        case "--agent-dir":
            i += 1
            session_config.agent_dir = os.args[i] if i < len(os.args) else "agent_files"
        case "--allow-remote-agent":
            session_config.allow_remote = true
        case "--agent-trust":
            i += 1
            mode, trusted, trust_message, trust_ok := ai.SessionParseTrust(os.args[i] if i < len(os.args) else "")
            if !trust_ok {
                fmt.eprintln(trust_message)
                os.exit(2)
            }
            session_config.trust = mode
            session_config.trusted = strings.clone(trusted)
        case "--listen":
            i += 1
            mode, mode_ok := ListenFromText(os.args[i] if i < len(os.args) else "")
            if !mode_ok {
                fmt.eprintln("--listen needs mentions, all or none")
                os.exit(2)
            }
            session_config.listen = mode
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
    if config.password == "" {
        // the environment keeps it out of the process list and the shell history
        config.password = os.get_env("AMSG_PASSWORD", context.allocator)
    }
    if config.channel == "" {
        fmt.eprintln("usage: amsg <channel> [--name N] [--dir received] [--auto-accept] [--host | --guest] [--no-lan] [--stun] [--max-mb N] [--json] [--exclude name] [--include-git] [--keep-exec] [--derp [N] | --derp-host name] [--derp-only] [--auto-reconnect] [--password P] [--agent [model]] [--agent-model M] [--agent-cmd claude] [--agent-tools Read,Glob] [--agent-dir agent_files] [--listen mentions|all|none] [--agent-trust ask|members|name,name] [--allow-remote-agent]")
        os.exit(2)
    }
    if include_git {
        for i in 0 ..< exclude_count {
            if excludes[i] == ".git" {
                excludes[i] = excludes[exclude_count - 1]
                exclude_count -= 1
                break
            }
        }
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

    if use_derp && config.derp_server == 0 {
        Info("looking for the fastest DERP relay (free Tailscale relays, no account)...")
        candidates: [6]int = {4, 8, 1, 14, 22, 2}
        config.derp_server = p2p.DerpRace(candidates[:], 6000)
        if config.derp_server == 0 {
            Info("no DERP relay answered (offline, or TCP 443 to them is blocked): only the same network can be found")
        } else {
            Info(fmt.tprintf("using the relay %s (%s); other members must pass --derp %d", p2p.DERP_SERVERS[config.derp_server - 1].host, p2p.DERP_SERVERS[config.derp_server - 1].place, config.derp_server))
        }
    } else if use_derp && config.derp_server != p2p.DERP_CUSTOM && (config.derp_server < 1 || config.derp_server > len(p2p.DERP_SERVERS)) {
        fmt.eprintfln("--derp N: N is 1..%d", len(p2p.DERP_SERVERS))
        os.exit(2)
    }
    m: ^ai.Messenger = new(ai.Messenger)
    if !ai.MessengerOpen(m, config, p2p.LinkNow()) {
        fmt.eprintln("cannot open the UDP socket")
        os.exit(1)
    }
    Info(fmt.tprintf("channel \"%s\" as %s, finding addresses%s...", config.channel, config.name, " and looking for a host" if config.role != .HOST else ""))
    session_config.excludes = excludes[:exclude_count]
    session = new(ai.Session)
    if !ai.SessionInit(session, m, session_config) {
        Info("cannot open the local door for the agent: --agent will not work")
    }
    thread.create_and_start(ReadLines, context)
    Loop(m, config)
}

// ============================================================ output: text lines or JSON objects

// A string as a JSON string literal (temp allocator).
Json :: proc(text: string) -> string {
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    strings.write_byte(&builder, '"')
    for i in 0 ..< len(text) {
        c: u8 = text[i]
        switch c {
        case '"':
            strings.write_string(&builder, `\"`)
        case '\\':
            strings.write_string(&builder, `\\`)
        case '\n':
            strings.write_string(&builder, `\n`)
        case '\r':
            strings.write_string(&builder, `\r`)
        case '\t':
            strings.write_string(&builder, `\t`)
        case:
            if c < 32 {
                fmt.sbprintf(&builder, `\u%04x`, int(c))
            } else {
                strings.write_byte(&builder, c)
            }
        }
    }
    strings.write_byte(&builder, '"')
    return strings.to_string(builder)
}

// Something the tool says (not a message from a member).
Info :: proc(text: string) {
    if json_mode {
        fmt.printfln(`{{"event":"info","text":%s}}`, Json(text))
    } else {
        fmt.printfln("* %s", text)
    }
}

ShowCode :: proc(m: ^ai.Messenger, title: string) {
    buffer: [p2p.CODE_TEXT_MAX]byte
    code: string = ai.MessengerCode(m, buffer[:])
    if code == "" {
        Info("no code yet (still looking for a host, or finding addresses)")
        return
    }
    if json_mode {
        fmt.printfln(`{{"event":"code","code":%s,"note":%s}}`, Json(code), Json(title))
    } else {
        fmt.printfln("* %s:", title)
        fmt.printfln("CODE: %s", code)
    }
}

ShowEvent :: proc(m: ^ai.Messenger, event: ^ai.Event) {
    text: string = ai.EventText(event)
    name: string = ai.MessengerName(m, event.member)
    if json_mode {
        ShowEventJson(m, event, text, name)
        return
    }
    switch event.kind {
    case .NONE:
    case .CONNECTED:
        fmt.printfln("* connected as %s (member %d)%s", ai.MessengerName(m, ai.MessengerSelf(m)), ai.MessengerSelf(m), ", hosting" if m.is_host else "")
    case .MEMBER_JOINED:
        fmt.printfln("* %s joined", text)
    case .MEMBER_LEFT:
        fmt.printfln("* %s left", text)
    case .TEXT:
        speaker: string = fmt.tprintf("%s's agent", name) if event.agent else name
        if event.to == ai.ALL {
            fmt.printfln("<%s> %s", speaker, text)
        } else {
            fmt.printfln("<%s> (to you) %s", speaker, text)
        }
    case .AGENT_REQUEST, .AGENT_STATUS:                    // the session says what it means (ShowSession)
    case .FILE_OFFERED:
        what: string = fmt.tprintf("the folder \"%s\" (%d files, %d bytes)", text, event.files, event.size) if event.folder else fmt.tprintf("the file \"%s\" (%d bytes)", text, event.size)
        fmt.printfln("* %s offers %s: --yes %d or --no %d", name, what, event.transfer, event.transfer)
    case .FILE_PROGRESS:
        fmt.printfln("* transfer %d %s: %d of %d bytes", event.transfer, "incoming" if event.incoming else "outgoing", event.done, event.size)
    case .FILE_DONE:
        direction: string = "from" if event.incoming else "to"
        kind: string = "folder" if event.folder else "file"
        if event.ok {
            saved: string = fmt.tprintf(", saved as %s", text) if event.incoming else ""
            fmt.printfln("* %s transfer %d %s %s done, %d bytes%s", kind, event.transfer, direction, name, event.size, saved)
        } else {
            fmt.printfln("* %s transfer %d %s %s FAILED: %s", kind, event.transfer, direction, name, text)
        }
    case .ERROR:
        fmt.printfln("* error: %s", text)
    }
}

ShowEventJson :: proc(m: ^ai.Messenger, event: ^ai.Event, text: string, name: string) {
    switch event.kind {
    case .NONE:
    case .CONNECTED:
        fmt.printfln(`{{"event":"connected","id":%d,"name":%s,"host":%v}}`, ai.MessengerSelf(m), Json(ai.MessengerName(m, ai.MessengerSelf(m))), m.is_host)
    case .MEMBER_JOINED:
        fmt.printfln(`{{"event":"joined","id":%d,"name":%s}}`, event.member, Json(text))
    case .MEMBER_LEFT:
        fmt.printfln(`{{"event":"left","id":%d,"name":%s}}`, event.member, Json(text))
    case .TEXT:
        fmt.printfln(`{{"event":"text","from":%s,"from_id":%d,"to":%s,"agent":%v,"text":%s}}`, Json(name), event.member, `"all"` if event.to == ai.ALL else `"you"`, event.agent, Json(text))
    case .AGENT_REQUEST, .AGENT_STATUS:
    case .FILE_OFFERED:
        fmt.printfln(`{{"event":"file_offered","from":%s,"from_id":%d,"transfer":%d,"name":%s,"size":%d,"folder":%v,"files":%d}}`, Json(name), event.member, event.transfer, Json(text), event.size, event.folder, event.files)
    case .FILE_PROGRESS:
        fmt.printfln(`{{"event":"file_progress","member":%s,"transfer":%d,"incoming":%v,"done":%d,"size":%d}}`, Json(name), event.transfer, event.incoming, event.done, event.size)
    case .FILE_DONE:
        path: string = text if event.ok && event.incoming else ""
        message: string = "" if event.ok else text
        fmt.printfln(`{{"event":"file_done","member":%s,"transfer":%d,"incoming":%v,"ok":%v,"folder":%v,"files":%d,"size":%d,"path":%s,"message":%s}}`, Json(name), event.transfer, event.incoming, event.ok, event.folder, event.files, event.size, Json(path), Json(message))
    case .ERROR:
        fmt.printfln(`{{"event":"error","text":%s}}`, Json(text))
    }
}

// ============================================================ the loop and the commands

Loop :: proc(m: ^ai.Messenger, config: ai.MessengerConfig) {
    announced_code: bool
    reconnect_at: i64
    for {
        now: i64 = p2p.LinkNow()
        if m.demoted && reconnect_at == 0 {
            reconnect_at = now + 500
            Info("another member started hosting this channel at the same moment: joining it as a guest")
        }
        if m.ended && auto_reconnect && reconnect_at == 0 {
            // a little time and a spread, so that not everybody tries to take over the channel at the same instant
            reconnect_at = now + 1500 + i64(os.get_pid() % 7) * 400
            Info("the host is gone: rejoining the channel by itself in a moment (whoever is first takes over as the host)")
        }
        if reopen_requested || reconnect_at != 0 && now >= reconnect_at {
            reopen_requested = false
            reconnect_at = 0
            Info("reconnecting to the channel...")
            ai.MessengerClose(m)
            if !ai.MessengerOpen(m, config, now) {
                Info("cannot reopen the socket")
                os.exit(1)
            }
            announced_code = false
        }
        ai.MessengerUpdate(m, now)
        for {
            event, ok := ai.MessengerPoll(m)
            if !ok {
                break
            }
            ai.SessionOnEvent(session, &event, now)
            ShowEvent(m, &event)
        }
        if autostart_agent && ai.MessengerReady(m) {
            autostart_agent = false
            message, _ := ai.SessionSpawn(session, autostart_model, now)
            Info(message)
        }
        ai.SessionUpdate(session, now)
        for {
            out, ok := ai.SessionPoll(session)
            if !ok {
                break
            }
            ShowSession(&out)
        }
        // the code is shown once the role is known and again on --code
        if !announced_code && m.link.role != .NONE {
            announced_code = true
            ShowCode(m, "code to paste on another network (the same network finds the channel by its name)")
        }
        input: [MAX_LINE]byte
        length, has_line := PopLine(input[:])
        if has_line {
            Command(m, string(input[:length]), now)             // raw: a leading space is the escape
        }
        time.sleep(5 * time.Millisecond)
    }
}

// A tool command is "--" and a letter ("--send"); "---", "-- note", "/help" and a leading space are ordinary text.
IsToolCommand :: proc(raw: string) -> bool {
    if len(raw) < 3 || raw[0] != '-' || raw[1] != '-' {
        return false
    }
    c: u8 = raw[2]
    return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
}

Command :: proc(m: ^ai.Messenger, raw: string, now: i64) {
    if strings.has_prefix(raw, " ") {
        Plain(m, raw[1:], now)                        // the escape: a leading space makes any line a plain message
        return
    }
    line: string = strings.trim_space(raw)
    if line != "" && !IsToolCommand(line) && !LooksLikeCode(line) {
        Plain(m, line, now)
        return
    }
    switch {
    case line == "":
    case line == "--quit":
        ai.SessionClose(session, now)
        ai.MessengerClose(m)
        os.exit(0)
    case strings.has_prefix(line, "--group_msg ") || strings.has_prefix(line, "--group "):
        Say(m, ai.ALL, strings.trim_space(line[strings.index_byte(line, ' ') + 1:]), now)
    case line == "--group_msg" || line == "--group":
        Info("usage: --group_msg <text>   (a message to everybody in the channel)")
    case line == "--spawn" || strings.has_prefix(line, "--spawn "):
        AgentCommand(m, strings.trim_space(line[len("--spawn"):]), true, now)
    case line == "--dismiss" || strings.has_prefix(line, "--dismiss "):
        AgentCommand(m, strings.trim_space(line[len("--dismiss"):]), false, now)
    case line == "--agents":
        for text in strings.split_lines(ai.SessionStatus(session), context.temp_allocator) {
            Info(text)
        }
    case line == "--trust" || strings.has_prefix(line, "--trust "):
        message, _ := ai.SessionSetTrust(session, strings.trim_space(line[len("--trust"):]))
        Info(message)
    case strings.has_prefix(line, "--listen "):
        mode, mode_ok := ListenFromText(strings.trim_space(line[len("--listen "):]))
        if mode_ok {
            session.config.listen = mode
            Info(fmt.tprintf("your agent now hears: %s", strings.to_lower(strings.trim_space(line[len("--listen "):]), context.temp_allocator)))
        } else {
            Info("usage: --listen mentions|all|none")
        }
    case line == "--yes agent" || line == "--no agent":
        if !ai.SessionAnswer(session, line == "--yes agent", now) {
            Info("no request about your agent is waiting")
        }
    case line == "--code":
        ShowCode(m, "your code")
    case line == "--reconnect":
        reopen_requested = true
    case line == "--who":
        for id in 0 ..< ai.MAX_MEMBERS {
            name: string = ai.MessengerName(m, u8(id))
            if name == "" {
                continue
            }
            has_agent: bool = ai.AgentRunning(&session.agent) if u8(id) == ai.MessengerSelf(m) else session.members[id].running
            if json_mode {
                fmt.printfln(`{{"event":"member","id":%d,"name":%s,"host":%v,"you":%v,"agent":%v}}`, id, Json(name), id == 0, u8(id) == ai.MessengerSelf(m), has_agent)
            } else {
                fmt.printfln("* member %d: %s%s%s%s", id, name, " (host)" if id == 0 else "", " (you)" if u8(id) == ai.MessengerSelf(m) else "", " (with an agent)" if has_agent else "")
            }
        }
    case strings.has_prefix(line, "--to "):
        rest: string = strings.trim_space(line[5:])
        space: int = strings.index_byte(rest, ' ')
        if space < 0 {
            Info("usage: --to <name> <text>")
            return
        }
        Say(m, ai.MessengerFindMember(m, rest[:space]), strings.trim_space(rest[space + 1:]), now)
    case strings.has_prefix(line, "--send "):
        rest: string = strings.trim_space(line[7:])
        space: int = strings.index_byte(rest, ' ')
        if space < 0 {
            Info("usage: --send <name|all> <path to a file or a folder>")
            return
        }
        Send(m, rest[:space], strings.trim_space(rest[space + 1:]), now)
    case strings.has_prefix(line, "--yes ") || strings.has_prefix(line, "--no "):
        accept: bool = strings.has_prefix(line, "--yes ")
        number, ok := strconv.parse_int(strings.trim_space(line[6 if accept else 5:]))
        if !ok {
            Info("usage: --yes <transfer number>")
            return
        }
        // the offer is identified by its number; the sender is whoever offered it
        for &in_ in m.ins {
            if in_.state == .PENDING && int(in_.id) == number {
                ai.MessengerFileAnswer(m, in_.from, in_.id, accept, now)
                Info("accepted" if accept else "declined")
                return
            }
        }
        Info("no such offer")
    case strings.has_prefix(line, "--cancel "):
        number, ok := strconv.parse_int(strings.trim_space(line[9:]))
        cancelled: bool
        if ok {
            // the transfer number is looked up on both directions; the other end is whoever it is with
            for &out in m.outs {
                if out.state != .FREE && int(out.id) == number {
                    cancelled = ai.MessengerCancel(m, out.to, out.id, now) || cancelled
                }
            }
            for &in_ in m.ins {
                if in_.state != .FREE && int(in_.id) == number {
                    cancelled = ai.MessengerCancel(m, in_.from, in_.id, now) || cancelled
                }
            }
        }
        if !cancelled {
            Info("no such transfer")
        }
    case IsToolCommand(line):
        Info("commands: --group_msg text  --to name text  --send name|all path  --spawn [bob] [model]  --dismiss [bob]  --agents  --listen all|mentions|none  --trust ask|members|name,name  --yes n|agent  --no n|agent  --cancel n  --who  --code  --reconnect  --quit   (a line starting with a space is always a message; with an agent a plain line goes to it, without one to the group)")
    case LooksLikeCode(line):
        ok, message := ai.MessengerUseCode(m, line, now)
        _ = ok
        Info(message)
        if ok && !m.is_host {
            ShowCode(m, "send this reply code back to the host")
        }
    }
}

// A pasted session code: one long word.
LooksLikeCode :: proc(line: string) -> bool {
    return len(line) > 40 && !strings.contains_rune(line, ' ') && !strings.has_prefix(line, "-") && !strings.has_prefix(line, "/")
}

Say :: proc(m: ^ai.Messenger, to: u8, text: string, now: i64) {
    if to == ai.UNKNOWN_ID {
        Info("no such member (see --who)")
        return
    }
    if !ai.MessengerReady(m) {
        Info("not in a channel yet, nobody got that")
        return
    }
    if !ai.MessengerSendText(m, to, text, now) {
        Info("not sent (too long, nobody there, or too many messages waiting)")
    }
}

Send :: proc(m: ^ai.Messenger, target: string, path: string, now: i64) {
    is_folder: bool = os.is_dir(path)
    if !is_folder && !os.exists(path) {
        Info(fmt.tprintf("no such file or folder: %s", path))
        return
    }
    sent: int
    for id in 0 ..< ai.MAX_MEMBERS {
        name: string = ai.MessengerName(m, u8(id))
        if name == "" || u8(id) == ai.MessengerSelf(m) {
            continue
        }
        if !strings.equal_fold(target, "all") && !strings.equal_fold(target, name) {
            continue
        }
        transfer: u16
        ok: bool
        if is_folder {
            transfer, ok = ai.MessengerSendFolder(m, u8(id), path, excludes[:exclude_count], now)
        } else {
            transfer, ok = ai.MessengerSendFile(m, u8(id), path, now)
        }
        if ok {
            Info(fmt.tprintf("offering %s %s to %s (transfer %d)", "the folder" if is_folder else "the file", path, name, transfer))
            sent += 1
        } else {
            Info(fmt.tprintf("could not start sending to %s (no free slot, too many files, or not connected)", name))
        }
    }
    if sent == 0 {
        Info("nobody to send it to (see --who)")
    }
}

ListenFromText :: proc(text: string) -> (mode: ai.ListenMode, ok: bool) {
    switch strings.to_lower(text, context.temp_allocator) {
    case "mentions":
        return .MENTIONS, true
    case "all":
        return .ALL, true
    case "none":
        return .NONE, true
    }
    return
}

// What the agent and the session say, on the screen.
ShowSession :: proc(out: ^ai.SessionOut) {
    text: string = ai.SessionOutText(out)
    if json_mode {
        kind: string
        switch out.kind {
        case .INFO:
            Info(text)
            return
        case .REPLY:
            kind = "agent_text"
        case .TOOL:
            kind = "agent_tool"
        case .SAID:
            kind = "agent_said"
        }
        fmt.printfln(`{{"event":"%s","text":%s}}`, kind, Json(text))
        return
    }
    switch out.kind {
    case .INFO:
        fmt.printfln("* %s", text)
    case .REPLY:
        fmt.printfln("<agent> %s", text)
    case .TOOL:
        fmt.printfln("* agent uses %s", text)
    case .SAID:
        fmt.printfln("* agent says %s", text)
    }
}

// A line for your agent, or for the group when there is none.
Plain :: proc(m: ^ai.Messenger, text: string, now: i64) {
    if !ai.SessionLine(session, text, now) {
        Say(m, ai.ALL, text, now)
    }
}

// --spawn [member] [model] and --dismiss [member]
AgentCommand :: proc(m: ^ai.Messenger, line: string, spawn: bool, now: i64) {
    words: []string = strings.fields(line, context.temp_allocator)
    action: ai.AgentAction = .SPAWN if spawn else .DISMISS
    if len(words) > 0 {
        member: u8 = ai.MessengerFindMember(m, words[0])
        if member != ai.UNKNOWN_ID && member != ai.MessengerSelf(m) {
            model: string = words[1] if spawn && len(words) > 1 else ""
            if !ai.AgentModelValid(model) || strings.has_prefix(model, "-") {
                Info("that is not a model name (haiku, sonnet, opus or a full id)")
                return
            }
            if ai.SessionAsk(session, member, action, model, now) {
                Info(fmt.tprintf("asked %s to %s its agent%s, waiting for the answer", ai.MessengerName(m, member), "start" if spawn else "dismiss", fmt.tprintf(" (model %s)", model) if model != "" else ""))
            } else {
                Info("not sent (not connected yet?)")
            }
            return
        }
    }
    if spawn {
        message, ok := ai.SessionSpawn(session, words[0] if len(words) > 0 else "", now)
        _ = ok
        Info(message)
    } else {
        message, ok := ai.SessionDismiss(session, now)
        _ = ok
        Info(message)
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
