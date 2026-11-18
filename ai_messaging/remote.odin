#+build !js
// Remote control of a device. A person starts amsg on a device (a server, a laptop elsewhere, headless with `--headless`) and gives a member
// of the channel control of it: `--remote bob` (or `--remote bob` on the command line, any number of times). Bob can then
//   - run shell commands there: `--run alice <command>` (his agent: the run tool), one at a time, 60 s at most, the end of the output comes back;
//   - talk to the agent of that device with the authority of the person: his private messages (and those of his agent) reach it as "[remote bob] ...".
// `--remote_disable [bob]` takes it back, and bob is told. What keeps this from being a hole:
//   - only the person of the device grants it, to one named member at a time; the grant belongs to the member id, so it ends when he leaves, and
//     a member that arrives later with the same name gets nothing (the exception is `--remote NAME` on the command line, for a device without
//     a keyboard: that name is trusted whenever it joins, so the channel needs a password then, see tool/amsg);
//   - who sent a frame is checked by the host of the channel (a guest cannot speak as another), and the device checks the grant on every command;
//   - one command at a time, killed after a time limit or when its output grows too large, one line, no control characters, run in a private
//     folder, with no input (stdin is closed), and every command is shown on the device's screen before it runs;
//   - the output that comes back is cleaned of control characters (a hostile device cannot write into the terminal of the one who asked).
// The command runs with the rights of the user that started amsg: that is what is granted. Nothing here limits what the command may do.
package ai_messaging

import "core:crypto"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"
import "core:unicode/utf8"

REMOTE_NAMES :: 8                        // names that are trusted whenever they join (the command line)
REMOTE_TIMEOUT_MS :: 60000
REMOTE_FILE_MAX :: 4 * 1024 * 1024       // a command that writes more than this is stopped

RemoteJob :: struct {
    active: bool,
    member: u8,                          // who asked
    id: u32,
    process: os.Process,
    started_ms: i64,
}

Remote :: struct {
    allowed: [MAX_MEMBERS]bool,          // members that may control THIS device
    given: [MAX_MEMBERS]bool,            // members whose device I may control
    names: [REMOTE_NAMES][NAME_MAX]byte,
    name_lengths: [REMOTE_NAMES]int,
    name_count: int,
    folder: string,                      // private folder of the commands (made at the first one)
    job: RemoteJob,
    next_job: u32,
    asked_job: [MAX_MEMBERS]u32,         // the job I asked of that member and wait for (0 = none)
    by_agent: [MAX_MEMBERS]bool,         // my agent asked it: the result is passed to it
    output: [MAX_MEMBERS][REMOTE_OUT_MAX]byte,
    output_length: [MAX_MEMBERS]int,
}

// ---------------------------------------------------------------------------------------------------------------- granting

// `--remote NAME`: the member may control this device from now on, until `--remote_disable` or until he leaves. He is told.
RemoteGrant :: proc(s: ^Session, name: string, now_ms: i64) -> (message: string, ok: bool) {
    member: u8 = SessionMemberOf(s, name)
    if member == UNKNOWN_ID {
        return fmt.tprintf("no member called %s (see --who)", strings.trim_space(name)), false
    }
    who: string = MessengerName(s.m, member)
    if s.remote.allowed[member] {
        return fmt.tprintf("%s has remote access already (--remote_disable %s takes it back)", who, who), true
    }
    if !MessengerSendRemoteGrant(s.m, member, true, now_ms) {
        return "not sent (not connected yet?)", false
    }
    s.remote.allowed[member] = true
    return fmt.tprintf("%s may now run commands on this device and talk to its agent as you. --remote_disable %s takes it back", who, who), true
}

// `--remote_disable [NAME]`: takes the access back from one member, or from all, and tells them.
RemoteDisable :: proc(s: ^Session, name: string, now_ms: i64) -> (message: string, ok: bool) {
    wanted: string = strings.trim_space(name)
    if wanted == "" {
        count: int
        for id in 0 ..< MAX_MEMBERS {
            if s.remote.allowed[id] {
                RemoteRevoke(s, u8(id), now_ms)
                count += 1
            }
        }
        s.remote.name_count = 0
        if count == 0 {
            return "nobody has remote access to this device", true
        }
        return fmt.tprintf("remote access ended for %d member(s): they were told", count), true
    }
    forgot: bool = RemoteForgetName(s, wanted)
    member: u8 = SessionMemberOf(s, wanted)
    if member == UNKNOWN_ID || !s.remote.allowed[member] {
        if forgot {
            return fmt.tprintf("%s is not trusted for remote access any more", wanted), true
        }
        return fmt.tprintf("%s has no remote access", wanted), false
    }
    RemoteRevoke(s, member, now_ms)
    return fmt.tprintf("%s has no remote access any more: they were told", MessengerName(s.m, member)), true
}

@(private)
RemoteRevoke :: proc(s: ^Session, member: u8, now_ms: i64) {
    s.remote.allowed[member] = false
    RemoteForgetName(s, MessengerName(s.m, member))
    if s.remote.job.active && s.remote.job.member == member {
        RemoteKill(s)
    }
    MessengerSendRemoteGrant(s.m, member, false, now_ms)
}

// The names of the command line (`--remote NAME`): comma separated, kept by this session.
RemoteSetNames :: proc(s: ^Session, names: string) {
    for part in strings.split(names, ",", context.temp_allocator) {
        name: string = strings.trim_space(part)
        if name != "" && s.remote.name_count < REMOTE_NAMES {
            s.remote.name_lengths[s.remote.name_count] = copy(s.remote.names[s.remote.name_count][:], name)
            s.remote.name_count += 1
        }
    }
}

@(private)
RemoteNameListed :: proc(s: ^Session, name: string) -> bool {
    for i in 0 ..< s.remote.name_count {
        if strings.equal_fold(string(s.remote.names[i][:s.remote.name_lengths[i]]), name) {
            return true
        }
    }
    return false
}

@(private)
RemoteForgetName :: proc(s: ^Session, name: string) -> bool {
    for i in 0 ..< s.remote.name_count {
        if strings.equal_fold(string(s.remote.names[i][:s.remote.name_lengths[i]]), name) {
            last: int = s.remote.name_count - 1
            s.remote.names[i] = s.remote.names[last]
            s.remote.name_lengths[i] = s.remote.name_lengths[last]
            s.remote.name_count -= 1
            return true
        }
    }
    return false
}

// ---------------------------------------------------------------------------------------------------------------- events of the channel

// A member of a listed name arrived: the access is his without anybody typing anything (a device without a keyboard).
RemoteOnJoin :: proc(s: ^Session, member: u8, name: string, now_ms: i64) {
    if int(member) >= MAX_MEMBERS || member == MessengerSelf(s.m) || !RemoteNameListed(s, name) {
        return
    }
    if MessengerSendRemoteGrant(s.m, member, true, now_ms) {
        s.remote.allowed[member] = true
        SessionNote(s, .INFO, fmt.tprintf("%s joined and has remote access to this device (it was granted on the command line)", name))
    }
}

// A member left: nothing that was his stays (an id can be given to somebody else).
RemoteOnLeft :: proc(s: ^Session, member: u8) {
    if int(member) >= MAX_MEMBERS {
        return
    }
    s.remote.allowed[member] = false
    s.remote.given[member] = false
    s.remote.asked_job[member] = 0
    s.remote.output_length[member] = 0
    if s.remote.job.active && s.remote.job.member == member {
        RemoteKill(s)
    }
}

// Somebody gave me access to their device, or took it back.
RemoteOnGrant :: proc(s: ^Session, event: ^Event) {
    if int(event.member) >= MAX_MEMBERS || event.member == MessengerSelf(s.m) {
        return
    }
    name: string = MessengerName(s.m, event.member)
    s.remote.given[event.member] = event.ok
    if event.ok {
        SessionNote(s, .INFO, fmt.tprintf("%s gave you remote control of their device: --run %s <command> runs a command there, and what you send to them privately reaches their agent as an order", name, name))
        InboxAdd(s, fmt.tprintf("* %s gave you remote control of their device", name))
    } else {
        s.remote.asked_job[event.member] = 0
        SessionNote(s, .INFO, fmt.tprintf("%s took back your remote control of their device", name))
        InboxAdd(s, fmt.tprintf("* %s took back your remote control of their device", name))
    }
}

// ---------------------------------------------------------------------------------------------------------------- asking: the side that controls

// `--run NAME command` (and the run tool of the agent): the command goes to that member's device when they gave this member access.
RemoteRun :: proc(s: ^Session, name: string, command: string, by_agent: bool, now_ms: i64) -> (message: string, ok: bool) {
    member: u8 = SessionMemberOf(s, name)
    if member == UNKNOWN_ID {
        return fmt.tprintf("no member called %s (see who)", strings.trim_space(name)), false
    }
    who: string = MessengerName(s.m, member)
    if !s.remote.given[member] {
        return fmt.tprintf("%s has not given you remote control (they type --remote %s on their device)", who, MessengerName(s.m, MessengerSelf(s.m))), false
    }
    text: string = strings.trim_space(command)
    if text == "" {
        return "no command", false
    }
    if len(text) > REMOTE_COMMAND_MAX {
        return fmt.tprintf("the command is too long (%d bytes, at most %d)", len(text), REMOTE_COMMAND_MAX), false
    }
    if !RemoteCommandValid(text) {
        return "a command is one line without control characters", false
    }
    next: u32 = s.remote.next_job + 1
    if !MessengerSendRemoteRun(s.m, member, next, text, now_ms) {
        return "not sent", false
    }
    s.remote.next_job = next
    s.remote.asked_job[member] = next
    s.remote.by_agent[member] = by_agent
    s.remote.output_length[member] = 0
    return fmt.tprintf("sent to %s (job %d): the output comes back when it ends", who, next), true
}

// One line of printable text.
RemoteCommandValid :: proc(text: string) -> bool {
    for c in transmute([]byte)text {
        if c < 32 && c != '\t' || c == 127 {
            return false
        }
    }
    return true
}

// Output of a command I asked for: in pieces, the last one carries the exit code. Only the job I wait for from that member counts.
RemoteOnOutput :: proc(s: ^Session, event: ^Event) {
    member: u8 = event.member
    if int(member) >= MAX_MEMBERS || s.remote.asked_job[member] == 0 || s.remote.asked_job[member] != event.job {
        return
    }
    piece: string = RemoteClean(EventText(event))
    length: ^int = &s.remote.output_length[member]
    length^ += copy(s.remote.output[member][length^:], piece)
    if event.more {
        return
    }
    output: string = string(s.remote.output[member][:length^])
    length^ = 0
    s.remote.asked_job[member] = 0
    name: string = MessengerName(s.m, member)
    result: string = fmt.tprintf("[run %s] exit %d%s", name, event.exit_code, fmt.tprintf(":\n%s", strings.trim_right_space(output)) if strings.trim_space(output) != "" else "")
    // the screen note has a size limit: long output goes in pieces
    rest: string = result
    for rest != "" {
        cut: int = min(len(rest), SESSION_OUT_MAX - 100)
        for cut > 0 && cut < len(rest) && rest[cut] & 0xC0 == 0x80 {
            cut -= 1
        }
        SessionNote(s, .INFO, rest[:cut])
        rest = rest[cut:]
    }
    InboxAdd(s, result)
    if s.remote.by_agent[member] {
        SessionToAgent(s, result)
    }
}

// ---------------------------------------------------------------------------------------------------------------- running: the device

// A command arrived. It runs only for a member that was granted, and only when no other command is running.
RemoteOnRun :: proc(s: ^Session, event: ^Event, now_ms: i64) {
    member: u8 = event.member
    command: string = EventText(event)
    if int(member) >= MAX_MEMBERS || !s.remote.allowed[member] {
        SessionNote(s, .INFO, fmt.tprintf("%s asked to run a command here and has no remote access: refused", MessengerName(s.m, member)))
        MessengerSendRemoteOut(s.m, member, event.job, "this device did not give you remote access", -1, now_ms)
        return
    }
    if s.remote.job.active {
        MessengerSendRemoteOut(s.m, member, event.job, "busy: another command is still running on this device", -1, now_ms)
        return
    }
    if !RemoteCommandValid(command) || command == "" {
        MessengerSendRemoteOut(s.m, member, event.job, "a command is one line without control characters", -1, now_ms)
        return
    }
    reason: string = RemoteStart(s, member, event.job, command, now_ms)
    if reason != "" {
        MessengerSendRemoteOut(s.m, member, event.job, reason, -1, now_ms)
    }
}

// Starts the command with its output in a file of the private folder. "" when it runs, else why not.
@(private)
RemoteStart :: proc(s: ^Session, member: u8, job: u32, command: string, now_ms: i64) -> string {
    if !RemoteFolderMake(s) {
        return "this device cannot make a private folder for the command"
    }
    arguments: [3]string
    when ODIN_OS == .Windows {
        // a script file: cmd has its own idea of quotes, which a command line built from arguments cannot satisfy
        script: string = fmt.tprintf("%s/job.cmd", s.remote.folder)
        if os.write_entire_file(script, fmt.tprintf("@echo off\r\n%s\r\n", command)) != nil {
            return "cannot write the command to a file"
        }
        arguments = {"cmd", "/c", script}
    } else {
        arguments = {"sh", "-c", command}
    }
    SessionNote(s, .INFO, fmt.tprintf("remote: %s runs: %s", MessengerName(s.m, member), command))
    // like the agent: nobody else may start a process while this one inherits its handles (agent_spawn_mutex). The file must be inheritable
    // (on Windows a handle that is not is invalid in the child: its output would be lost)
    sync.mutex_lock(&agent_spawn_mutex)
    out, open_error := os.open(fmt.tprintf("%s/out.txt", s.remote.folder), {.Write, .Create, .Trunc, .Inheritable}, {.Read_User, .Write_User})
    if open_error != nil {
        sync.mutex_unlock(&agent_spawn_mutex)
        return "cannot make the output file"
    }
    process, start_error := os.process_start({
        working_dir = s.config.remote_dir,
        command = arguments[:],
        stdout = out,
        stderr = out,
    })
    sync.mutex_unlock(&agent_spawn_mutex)
    os.close(out)
    if start_error != nil {
        return fmt.tprintf("cannot start the command (%v)", start_error)
    }
    s.remote.job = {active = true, member = member, id = job, process = process, started_ms = now_ms}
    return ""
}

@(private)
RemoteFolderMake :: proc(s: ^Session) -> bool {
    if s.remote.folder != "" {
        return true
    }
    base, _ := os.temp_directory(context.temp_allocator)
    random: [4]byte
    crypto.rand_bytes(random[:])
    folder: string = fmt.aprintf("%s/amsg_remote_%x", strings.trim_right(base, "/\\"), random)
    if os.make_directory_all(folder, {.Read_User, .Write_User, .Execute_User}) != nil {
        delete(folder)
        return false
    }
    s.remote.folder = folder
    return true
}

// Stops the running command and forgets it.
@(private)
RemoteKill :: proc(s: ^Session) {
    if !s.remote.job.active {
        return
    }
    _ = os.process_kill(s.remote.job.process)
    _, _ = os.process_wait(s.remote.job.process, 3000 * time.Millisecond)
    s.remote.job.active = false
    os.remove(fmt.tprintf("%s/out.txt", s.remote.folder))
}

// Every frame: has the command ended, run too long, or written too much?
RemoteUpdate :: proc(s: ^Session, now_ms: i64) {
    job: ^RemoteJob = &s.remote.job
    if !job.active {
        return
    }
    output_path: string = fmt.tprintf("%s/out.txt", s.remote.folder)
    state, wait_error := os.process_wait(job.process, 0)
    exit_code: i32
    stopped: string
    if wait_error == nil && state.exited {
        exit_code = i32(state.exit_code)
    } else {
        limit: i64 = s.config.remote_timeout_ms if s.config.remote_timeout_ms > 0 else REMOTE_TIMEOUT_MS
        info, stat_error := os.stat(output_path, context.temp_allocator)
        switch {
        case now_ms - job.started_ms > limit:
            stopped = fmt.tprintf("(stopped: it ran longer than %d s)", limit / 1000)
        case stat_error == nil && info.size > REMOTE_FILE_MAX:
            stopped = "(stopped: it wrote too much)"
        case:
            return
        }
        _ = os.process_kill(job.process)
        _, _ = os.process_wait(job.process, 3000 * time.Millisecond)
        exit_code = -1
    }
    job.active = false
    // the end of the output is what counts
    text: string
    if file, open_error := os.open(output_path, {.Read}); open_error == nil {
        size, _ := os.file_size(file)
        take: i64 = min(size, i64(REMOTE_OUT_MAX))
        buffer: []byte = make([]byte, int(take), context.temp_allocator)
        count, _ := os.read_at(file, buffer, size - take)
        os.close(file)
        text = RemoteClean(string(buffer[:count]))
        if size > take {
            text = fmt.tprintf("(output cut: only the end follows)\n%s", text)
        }
    }
    os.remove(output_path)
    if stopped != "" {
        text = fmt.tprintf("%s\n%s", strings.trim_right_space(text), stopped)
    }
    SessionNote(s, .INFO, fmt.tprintf("remote: the command of %s ended (exit %d)", MessengerName(s.m, job.member), exit_code))
    MessengerSendRemoteOut(s.m, job.member, job.id, text, exit_code, now_ms)
}

// The program ends: nothing keeps running, the folder goes, those who had access are told.
RemoteShutdown :: proc(s: ^Session, now_ms: i64) {
    RemoteKill(s)
    for id in 0 ..< MAX_MEMBERS {
        if s.remote.allowed[id] {
            MessengerSendRemoteGrant(s.m, u8(id), false, now_ms)
            s.remote.allowed[id] = false
        }
    }
    if s.remote.folder != "" {
        os.remove_all(s.remote.folder)
        delete(s.remote.folder)
        s.remote.folder = ""
    }
}

// Text that is safe to show: control characters (escape sequences of a terminal, ...) and bytes that are not UTF-8 become "?" (temp allocator).
RemoteClean :: proc(text: string) -> string {
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    rest: string = text
    for len(rest) > 0 {
        r, width := utf8.decode_rune_in_string(rest)
        switch {
        case r == utf8.RUNE_ERROR && width <= 1:
            strings.write_byte(&builder, '?')
        case r == '\n' || r == '\t':
            strings.write_rune(&builder, r)
        case r == '\r':
        case r < 32 || r == 127 || r >= 0x80 && r < 0xA0 || r == 0x2028 || r == 0x2029 || r >= 0x202A && r <= 0x202E || r >= 0x2066 && r <= 0x2069:
            strings.write_byte(&builder, '?')            // controls, and the characters that reorder text on a screen
        case:
            strings.write_rune(&builder, r)
        }
        rest = rest[width:]
    }
    return strings.to_string(builder)
}
