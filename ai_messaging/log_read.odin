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

// ------------------------------------------------------------------------------------------------------------------------
// What the agents cost

// The turns of the agent of one instance in one run (a run is one start of the agent; `run` 0 is all the runs of that instance together).
LogCost :: struct {
    owner: string,
    run: int,
    turns: int,
    errors: int,                         // turns that ended with an error
    tools: int,                          // tool calls
    replies: int,                        // texts the agent wrote
    cost: f64,                           // US dollars, as Claude Code reported them for each turn
    seconds: i64,
}

// One turn with what it cost and what started it.
LogTurn :: struct {
    owner: string,
    run: int,
    turn: int,
    cost: f64,
    seconds: i64,
    ok: bool,
    started_by: string,                  // the text of the message that started it, or what was handed to the agent
}

// The cost of the agents in the entries: a row per instance and run, a row for all the runs of an instance (when it has more than one), and
// the turns sorted by cost, the dearest first, with what started each. Records of turns are `d` (cost, seconds, ok / error), `t`, `a` and `i`.
LogSummary :: proc(entries: []LogEntry, allocator := context.allocator) -> (rows: []LogCost, turns: []LogTurn) {
    list: [dynamic]LogCost
    list.allocator = allocator
    dear: [dynamic]LogTurn
    dear.allocator = allocator
    text_of: map[string]string                              // message id -> text, for what started a turn
    text_of.allocator = context.temp_allocator
    started: map[string]string                              // turn id -> the message that caused it, or what was handed to the agent
    started.allocator = context.temp_allocator
    for entry in entries {
        switch entry.kind {
        case "g", "p", "u", "G", "P", "GA", "PA":
            if entry.msg != "" { text_of[entry.msg] = entry.text }
        }
    }
    for entry in entries {
        if entry.kind == "i" && entry.turn != "" {
            started[entry.turn] = text_of[entry.msg] if entry.msg != "" && entry.msg in text_of else entry.text
        }
    }
    row_of :: proc(list: ^[dynamic]LogCost, owner: string, run: int) -> ^LogCost {
        for &row in list {
            if row.owner == owner && row.run == run { return &row }
        }
        append(list, LogCost{owner = owner, run = run})
        return &list[len(list) - 1]
    }
    for entry in entries {
        switch entry.kind {
        case "t", "a", "d":
        case:
            continue
        }
        run, turn: int
        if dot := strings.index_byte(entry.ref, '.'); dot > 0 {
            run, _ = strconv.parse_int(entry.ref[:dot])
            turn, _ = strconv.parse_int(entry.ref[dot + 1:])
        }
        row: ^LogCost = row_of(&list, entry.owner, run)
        switch entry.kind {
        case "t":
            row.tools += 1
        case "a":
            row.replies += 1
        case "d":
            // "<cost> <seconds> ok|error [text]"
            fields: []string = strings.split_n(entry.text, " ", 4, context.temp_allocator)
            cost: f64
            seconds: i64
            ok: bool = true
            if len(fields) >= 1 { cost, _ = strconv.parse_f64(fields[0]) }
            if len(fields) >= 2 { seconds, _ = strconv.parse_i64(fields[1]) }
            if len(fields) >= 3 { ok = fields[2] == "ok" }
            row.turns += 1
            row.cost += cost
            row.seconds += seconds
            if !ok { row.errors += 1 }
            begin: string = started[entry.turn] if entry.turn in started else ""
            append(&dear, LogTurn{owner = entry.owner, run = run, turn = turn, cost = cost, seconds = seconds, ok = ok, started_by = strings.clone(begin, allocator)})
        }
    }
    // all the runs of an instance together, when it had several
    counted: [dynamic]string
    counted.allocator = context.temp_allocator
    for row in list[:] {
        if row.run == 0 || slice.contains(counted[:], row.owner) { continue }
        runs: int
        total: LogCost = {owner = row.owner}
        for other in list[:] {
            if other.owner == row.owner && other.run != 0 {
                runs += 1
                total.turns += other.turns
                total.errors += other.errors
                total.tools += other.tools
                total.replies += other.replies
                total.cost += other.cost
                total.seconds += other.seconds
            }
        }
        append(&counted, row.owner)
        if runs > 1 { append(&list, total) }
    }
    slice.stable_sort_by(dear[:], proc(a, b: LogTurn) -> bool {
        return a.cost > b.cost
    })
    return list[:], dear[:]
}
