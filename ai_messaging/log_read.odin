// Reading the logs back (log.odin has the format): one or more files of different instances become one list of entries sorted by time, with
// global ids, so that a message can be followed from the program that sent it to the programs that heard it and on to what their agents did.
//   message id  "<instance>:<seq>"           the instance (8 hex digits) that numbered the message, and its number
//   turn id     "<name>/<instance>#<run>.<turn>"  one turn of the agent of that instance
// An entry has the ids it belongs to (`msg`, `turn`); entries that share an id belong together, and LogTrace follows that to the end.
package ai_messaging

import "base:runtime"
import "core:compress/deflate"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

LogEntry :: struct {
    time_ms: i64,                        // unix ms of the writer's clock (computers differ by what their clocks differ)
    owner: string,                       // "name/instance" of the program that wrote it
    kind: string,
    who: string,                         // a member id becomes the member's name
    ref: string,                         // as written
    text: string,
    msg: string,                         // message id, "" if none
    turn: string,                        // turn id, "" if none
}

// The text of a log file: every gzip member inflated and joined. Plain gzip tools read the same text (`zcat`).
LogDecode :: proc(data: []byte, allocator := context.allocator) -> (text: string, ok: bool) {
    all: [dynamic]byte
    all.allocator = allocator
    position: int
    for position + 18 <= len(data) {
        if data[position] != 0x1f || data[position + 1] != 0x8b || data[position + 3] & 4 == 0 || data[position + 12] != 'B' || data[position + 13] != 'C' {
            break
        }
        total: int = (int(data[position + 16]) | int(data[position + 17]) << 8) + 1
        if position + total > len(data) {
            break                                           // the last member was cut (the program died while writing)
        }
        block: [dynamic]byte
        block.allocator = context.temp_allocator
        if deflate.inflate_gzip_from_bytes(&block, data[position:position + total], allocator = context.temp_allocator) != nil {
            return "", false
        }
        append(&all, ..block[:])
        position += total
    }
    return string(all[:]), len(all) > 0
}

LogUnescape :: proc(text: string, allocator := context.allocator) -> string {
    if !strings.contains_rune(text, '\\') {
        return text
    }
    builder: strings.Builder
    strings.builder_init(&builder, allocator)
    for i := 0; i < len(text); i += 1 {
        if text[i] == '\\' && i + 1 < len(text) {
            i += 1
            switch text[i] {
            case 'n':
                strings.write_byte(&builder, '\n')
            case 'r':
                strings.write_byte(&builder, '\r')
            case 't':
                strings.write_byte(&builder, '\t')
            case:
                strings.write_byte(&builder, text[i])
            }
        } else {
            strings.write_byte(&builder, text[i])
        }
    }
    return strings.to_string(builder)
}

// Reads the logs (paths of files, any number of instances) into one list sorted by time. Strings live in `allocator`. `skipped`: files that held
// no readable record.
LogLoad :: proc(paths: []string, allocator := context.allocator) -> (entries: []LogEntry, skipped: int, ok: bool) {
    list: [dynamic]LogEntry
    list.allocator = allocator
    for path in paths {
        data, error := os.read_entire_file(path, context.temp_allocator)
        if error != nil {
            return nil, skipped, false
        }
        text, decoded := LogDecode(data, context.temp_allocator)
        if !decoded {
            skipped += 1                                    // empty (the program was killed before its first block) or not a log: the others are still read
            continue
        }
        instance: string
        owner: string
        names: [MAX_MEMBERS]string
        instances: [MAX_MEMBERS]string
        self_id: int = -1
        now_ms: i64
        for raw in strings.split_lines(text, context.temp_allocator) {
            if raw == "" {
                continue
            }
            if strings.has_prefix(raw, "#amsglog\t") {
                fields: []string = strings.split(raw, "\t", context.temp_allocator)
                if len(fields) < 7 {
                    skipped += 1
                    break
                }
                instance = strings.clone(fields[2], allocator)
                start, _ := strconv.parse_i64(fields[4])
                now_ms = start
                owner = fmt.aprintf("%s/%s", fields[6], instance, allocator = allocator)
                continue
            }
            fields: []string = strings.split_n(raw, "\t", 5, context.temp_allocator)
            if len(fields) < 5 {
                continue
            }
            delta, _ := strconv.parse_i64(fields[0])
            now_ms += delta
            kind: string = fields[1]
            who: string = fields[2]
            ref: string = fields[3]
            body: string = LogUnescape(fields[4], context.temp_allocator)
            id_of :: proc(text: string) -> int {
                number, parsed := strconv.parse_int(strings.trim_right(text, "a"))
                return number if parsed && number >= 0 && number < MAX_MEMBERS else -1
            }
            // "m.seq" as a global id: member m's instance and the number
            global :: proc(ref: string, own: string, self_id: int, instances: ^[MAX_MEMBERS]string, allocator: runtime.Allocator) -> string {
                dot: int = strings.index_byte(ref, '.')
                if dot < 0 {
                    return ""
                }
                member, parsed := strconv.parse_int(ref[:dot])
                if !parsed || member < 0 || member >= MAX_MEMBERS {
                    return ""
                }
                instance: string = own if member == self_id || instances[member] == "" else instances[member]
                return fmt.aprintf("%s:%s", instance, ref[dot + 1:], allocator = allocator)
            }
            entry: LogEntry = {time_ms = now_ms, owner = owner, kind = strings.clone(kind, allocator), ref = strings.clone(ref, allocator)}
            switch kind {
            case "@":
                if member := id_of(who); member >= 0 {
                    names[member] = strings.clone(body, allocator)
                }
            case "I":
                if member := id_of(who); member >= 0 {
                    instances[member] = strings.clone(body, allocator)
                }
            case "n":
                // "connected as NAME (member N)"
                if strings.has_prefix(body, "connected as ") {
                    if open := strings.last_index(body, "(member "); open >= 0 {
                        number, parsed := strconv.parse_int(body[open + len("(member "):strings.last_index_byte(body, ')')])
                        if parsed {
                            self_id = number
                        }
                    }
                }
            case "g", "p":
                entry.msg = global(ref, instance, self_id, &instances, allocator)
            case "G", "P", "GA", "PA", "u":
                if dot := strings.index_byte(ref, '.'); dot >= 0 {
                    if member, parsed := strconv.parse_int(ref[:dot]); parsed {
                        self_id = member
                    }
                }
                entry.msg = global(ref, instance, self_id, &instances, allocator)
                if kind == "GA" || kind == "PA" {
                    if at := strings.index_byte(who, '@'); at >= 0 {
                        entry.turn = fmt.aprintf("%s#%s", owner, who[at + 1:], allocator = allocator)
                        who = who[:at]
                    }
                }
            case "i":
                entry.turn = fmt.aprintf("%s#%s", owner, ref, allocator = allocator)
                if strings.has_prefix(body, "@") {
                    entry.msg = global(body[1:], instance, self_id, &instances, allocator)
                }
            case "a", "t", "e", "d":
                entry.turn = fmt.aprintf("%s#%s", owner, ref, allocator = allocator)
            }
            // who: a member id becomes a name
            if member := id_of(who); member >= 0 && names[member] != "" && kind != "@" && kind != "I" {
                entry.who = fmt.aprintf("%s%s", names[member], "'s agent" if strings.has_suffix(who, "a") else "", allocator = allocator)
            } else {
                entry.who = strings.clone(who, allocator)
            }
            entry.text = strings.clone(body, allocator)
            append(&list, entry)
        }
    }
    slice.stable_sort_by(list[:], proc(a, b: LogEntry) -> bool {
        return a.time_ms < b.time_ms
    })
    return list[:], skipped, true
}

// The entries that belong with the ones that carry `id` (a message id, a turn id): they share ids, and so do the entries that share with those.
// Message to its receivers, a receiver to its agent's turn, that turn to the messages it sent, those to their receivers, and so on.
LogTrace :: proc(entries: []LogEntry, id: string, allocator := context.allocator) -> []LogEntry {
    wanted: map[string]bool
    wanted.allocator = context.temp_allocator
    wanted[id] = true
    selected: [dynamic]bool
    selected.allocator = context.temp_allocator
    resize(&selected, len(entries))
    for changed: bool = true; changed; {
        changed = false
        for entry, i in entries {
            if selected[i] {
                continue
            }
            if entry.msg != "" && entry.msg in wanted || entry.turn != "" && entry.turn in wanted {
                selected[i] = true
                changed = true
                if entry.msg != "" {
                    wanted[entry.msg] = true
                }
                if entry.turn != "" {
                    wanted[entry.turn] = true
                }
            }
        }
    }
    result: [dynamic]LogEntry
    result.allocator = allocator
    for entry, i in entries {
        if selected[i] {
            append(&result, entry)
        }
    }
    return result[:]
}
