// The log of one amsg instance: everything it says, hears, is told and does, one line per record, small on disk, and traceable between instances.
// Each instance writes its own file, so several on one device never share anything (no locking); `tool/logview` merges files and follows a
// message from the one that sent it to the ones that heard it and on to what their agents did with it.
//
// File: a series of gzip members (the BGZF layout: a member holds the size of the member in a header field, so a reader can skip or split them,
// and plain `zcat file` reads the whole file). A member holds up to LOG_BLOCK bytes of text and is written when it is full, LOG_FLUSH_MS after
// its first record, or when the program ends: a crash loses at most the last block. After LOG_ROTATE bytes of text a new file (the next part) starts.
//
// The text: the first line of each file is the header
//     #amsglog TAB 1 TAB <instance hex> TAB <pid> TAB <start, unix ms> TAB <channel> TAB <name> TAB <part>
// and then one record per line, fields separated by a TAB:
//     <ms after the previous record> TAB <kind> TAB <who> TAB <ref> TAB <text>
// The text escapes only \ (as \\), newline (\n), carriage return (\r) and TAB (\t), so every record is one line and `split on TAB, 5 parts`
// parses it. Names are written once (kind @, who = member id, text = name), not on every line.
//
//   kind  who                ref            text
//   @     member id          -              the name of that member (again when the id gets another member)
//   I     member id          -              the instance (hex) of that member's program: what makes refs global
//   j / l member id          -              joined / left (the name is in the @ record before it)
//   g / p sender id (+"a")   sender.seq     a group / private message heard ("a": said by the sender's agent)
//   G / P * or receiver id   my.seq         a group / private message sent by the person at this keyboard
//   GA/PA * or receiver@turn my.seq         the same, sent by this instance's agent during that turn
//   c     -                  -              a command typed at this terminal (--spawn, --run, ...; messages to a member or the group are G / P)
//   u     my id              my.seq         a line typed to the private agent (text as typed)
//   i     my id              turn           a message handed to the agent that starts its turn: text "@sender.seq" when the message is logged
//                                           (g, p, u) elsewhere, else the text itself (idle report, spawn notice, command result)
//   a / t / e / d  my id     turn           the agent's reply / tool call / tool error / end of the turn (text: cost in USD, seconds, ok|error)
//   x     member id          -              a file or folder transfer: offered / done / failed
//   n     -                  -              something the program reported (agent started, remote command run, errors, ...)
// A ref "m.seq" means message number seq of the instance of member m: with the I records it becomes the global id "<instance>:<seq>".
package ai_messaging

import "core:compress/deflate"
import "core:crypto"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:strings"
import "core:time"

LOG_BLOCK :: 48 * 1024
LOG_FLUSH_MS :: 10000                    // a program that is killed (a headless device) loses what is younger than this
LOG_ROTATE :: 8 * 1024 * 1024
LOG_TEXT_MAX :: 4000                     // longer text is cut (and says by how much)
LOG_VERSION :: 1

Log :: struct {
    enabled: bool,
    file: ^os.File,
    stem: string,                        // "<dir>/<channel>.<name>.<pid>.<instance>": the part number and the extension follow
    header_tail: string,                 // "<channel> TAB <name>" for the header of every part
    instance: u32,
    seq: u32,                            // messages numbered by this instance
    part: int,
    last_ms: i64,                        // time of the last record (the records hold the difference)
    block: [LOG_BLOCK]byte,
    block_length: int,
    block_since_ms: i64,
    raw_total: int,                      // text written to the current part
    packed: [dynamic]u8,
    named: [MAX_MEMBERS][NAME_MAX]byte,
    named_length: [MAX_MEMBERS]int,
    known_instance: [MAX_MEMBERS]u32,
    turn: [24]byte,                      // see LogSetTurn
    turn_length: int,
    rotate_at: int,                      // text per part before the next one starts (0 = LOG_ROTATE)
}

// Opens the log of this instance in `dir`. The file is for its owner only. False: no folder, no file (the program goes on without a log).
LogOpen :: proc(l: ^Log, dir: string, channel: string, name: string, now_ms: i64) -> (path: string, ok: bool) {
    l^ = {}
    if os.make_directory_all(dir, {.Read_User, .Write_User, .Execute_User}) != nil {
        return "", false
    }
    random: [4]byte
    crypto.rand_bytes(random[:])
    l.instance = u32(random[0]) << 24 | u32(random[1]) << 16 | u32(random[2]) << 8 | u32(random[3])
    safe :: proc(text: string) -> string {
        builder: strings.Builder
        strings.builder_init(&builder, context.temp_allocator)
        for c in transmute([]byte)text {
            strings.write_byte(&builder, c if c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '-' || c == '_' else '_')
        }
        return strings.to_string(builder)
    }
    l.stem = fmt.aprintf("%s/%s.%s.%d.%08x", strings.trim_right(dir, "/\\"), safe(channel), safe(name), os.get_pid(), l.instance)
    l.header_tail = fmt.aprintf("%s\t%s", LogEscape(channel), LogEscape(name))
    l.last_ms = now_ms
    if !LogPart(l, now_ms) {
        delete(l.stem)
        delete(l.header_tail)
        l^ = {}
        return "", false
    }
    l.enabled = true
    return fmt.tprintf("%s.%d.amsglog.gz", l.stem, l.part), true
}

// Starts the next file of this instance (the first one at the open).
@(private)
LogPart :: proc(l: ^Log, now_ms: i64) -> bool {
    if l.file != nil {
        os.close(l.file)
        l.file = nil
    }
    l.part += 1
    file, error := os.open(fmt.tprintf("%s.%d.amsglog.gz", l.stem, l.part), {.Write, .Create, .Trunc}, {.Read_User, .Write_User})
    if error != nil {
        return false
    }
    l.file = file
    l.raw_total = 0
    header: string = fmt.bprintf(l.block[:], "#amsglog\t%d\t%08x\t%d\t%d\t%s\t%d\n", LOG_VERSION, l.instance, os.get_pid(), time.to_unix_nanoseconds(time.now()) / 1_000_000, l.header_tail, l.part)
    l.block_length = len(header)
    l.block_since_ms = now_ms
    return true
}

// Ends the log: the last block is written.
LogClose :: proc(l: ^Log) {
    if !l.enabled {
        return
    }
    LogFlush(l)
    os.close(l.file)
    l.file = nil
    l.enabled = false
    delete(l.stem)
    delete(l.header_tail)
    delete(l.packed)
    l.stem = ""
    l.header_tail = ""
    l.packed = nil
}

// The path of the file being written.
LogPath :: proc(l: ^Log) -> string {
    return fmt.tprintf("%s.%d.amsglog.gz", l.stem, l.part)
}

// What the agent is doing now ("<run>.<turn>"): the messages it sends carry it, so a message can be traced to the turn that made it.
LogSetTurn :: proc(l: ^Log, turn: string) {
    l.turn_length = copy(l.turn[:], turn)
}

// The number of the next message of this instance (0 when there is no log: the others then cannot trace it).
LogNewRef :: proc(l: ^Log) -> u64 {
    if l == nil || !l.enabled {
        return 0
    }
    l.seq += 1
    return u64(l.instance) << 32 | u64(l.seq)
}

// "<member>.<seq>" for the ref that came with a message of that member ("" for none).
LogRefText :: proc(member: u8, ref: u64) -> string {
    if ref == 0 {
        return ""
    }
    return fmt.tprintf("%d.%d", member, ref & 0xFFFFFFFF)
}

// One record. `who` and `ref` are short fields without TAB; the text is escaped and cut at LOG_TEXT_MAX.
LogRecord :: proc(l: ^Log, now_ms: i64, kind: string, who: string, ref: string, text: string) {
    if l == nil || !l.enabled {
        return
    }
    shown: string = text
    cut: int
    if len(shown) > LOG_TEXT_MAX {
        end: int = LOG_TEXT_MAX
        for end > 0 && shown[end] & 0xC0 == 0x80 {
            end -= 1
        }
        cut = len(shown) - end
        shown = shown[:end]
    }
    if l.block_length + 2 * len(shown) + len(kind) + len(who) + len(ref) + 64 > LOG_BLOCK {
        LogFlush(l)
    }
    if l.block_length == 0 {
        l.block_since_ms = now_ms
    }
    delta: i64 = max(0, now_ms - l.last_ms)
    l.last_ms = now_ms
    head: string = fmt.bprintf(l.block[l.block_length:], "%d\t%s\t%s\t%s\t", delta, kind, who, ref)
    l.block_length += len(head)
    for c in transmute([]byte)shown {
        switch c {
        case '\\':
            LogPut(l, "\\\\")
        case '\n':
            LogPut(l, "\\n")
        case '\r':
            LogPut(l, "\\r")
        case '\t':
            LogPut(l, "\\t")
        case:
            l.block[l.block_length] = c
            l.block_length += 1
        }
    }
    if cut > 0 {
        tail: string = fmt.bprintf(l.block[l.block_length:], "...(+%d bytes)", cut)
        l.block_length += len(tail)
    }
    l.block[l.block_length] = '\n'
    l.block_length += 1
}

@(private)
LogPut :: proc(l: ^Log, text: string) {
    l.block_length += copy(l.block[l.block_length:], text)
}

// For the header: no TAB or newline.
@(private)
LogEscape :: proc(text: string) -> string {
    first, _ := strings.replace_all(text, "\t", " ", context.temp_allocator)
    second, _ := strings.replace_all(first, "\n", " ", context.temp_allocator)
    return second
}

// The name of a member, written when it is new or changed.
LogMember :: proc(l: ^Log, now_ms: i64, member: u8, name: string) {
    if l == nil || !l.enabled || int(member) >= MAX_MEMBERS || name == "" {
        return
    }
    if string(l.named[member][:l.named_length[member]]) == name {
        return
    }
    l.named_length[member] = copy(l.named[member][:], name)
    LogRecord(l, now_ms, "@", fmt.tprintf("%d", member), "", name)
}

// The instance of the program of a member, learnt from the ref of its messages: written when it is new.
LogInstance :: proc(l: ^Log, now_ms: i64, member: u8, ref: u64) {
    if l == nil || !l.enabled || int(member) >= MAX_MEMBERS || ref == 0 || l.known_instance[member] == u32(ref >> 32) {
        return
    }
    l.known_instance[member] = u32(ref >> 32)
    LogRecord(l, now_ms, "I", fmt.tprintf("%d", member), "", fmt.tprintf("%08x", u32(ref >> 32)))
}

// Every frame: a block that waited LOG_FLUSH_MS is written.
LogTick :: proc(l: ^Log, now_ms: i64) {
    if l.enabled && l.block_length > 0 && now_ms - l.block_since_ms >= LOG_FLUSH_MS {
        LogFlush(l)
    }
}

// Writes the block as one gzip member: header with the size of the member (BGZF), the deflated text, crc32 and length of the text.
LogFlush :: proc(l: ^Log) {
    if !l.enabled || l.block_length == 0 || l.file == nil {
        return
    }
    input: []byte = l.block[:l.block_length]
    clear(&l.packed)
    if deflate.deflate_raw_to_dynamic(&l.packed, input, .Level_6) != nil {
        l.block_length = 0                                  // cannot compress (memory): the block is lost, the log goes on
        return
    }
    total: int = 18 + len(l.packed) + 8
    size: u16 = u16(total - 1)
    header: [18]byte = {0x1f, 0x8b, 8, 4, 0, 0, 0, 0, 0, 255, 6, 0, 'B', 'C', 2, 0, byte(size & 0xFF), byte(size >> 8)}
    crc: u32 = hash.crc32(input)
    length: u32 = u32(len(input))
    trailer: [8]byte = {byte(crc), byte(crc >> 8), byte(crc >> 16), byte(crc >> 24), byte(length), byte(length >> 8), byte(length >> 16), byte(length >> 24)}
    os.write(l.file, header[:])
    os.write(l.file, l.packed[:])
    os.write(l.file, trailer[:])
    l.raw_total += l.block_length
    l.block_length = 0
    if l.raw_total >= (l.rotate_at if l.rotate_at > 0 else LOG_ROTATE) {
        if !LogPart(l, l.last_ms) {                         // the header of the new part is the start of its first block
            l.enabled = false
        }
    }
}
