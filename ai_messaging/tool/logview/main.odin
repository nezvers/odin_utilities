// logview: reads the logs of amsg instances (amsg --log DIR) and prints them as one timeline, or follows one message through all of them.
//
//   logview FILE...                       every record of all the files, sorted by time
//   logview FILE... --trace ID            only what belongs with the message or turn ID (copy it from the id column):
//                                         the message at the program that sent it, at the ones that heard it, what their agents did because of
//                                         it (their turns), the messages those sent, and so on
//   logview FILE... --kind g,p,G,P        only these kinds of records (the kinds are listed in log.odin)
//   logview FILE... --ids                 add the id column (message ids "<instance>:<seq>", turn ids "<name>/<instance>#<run>.<turn>")
//   logview FILE... --cost                what the agents cost: turns, errors, tool calls, dollars and seconds per instance and run, and the dearest turns
//                                         with what started each (the costs are what Claude Code reported for each turn)
//   logview FILE...  --raw                the text of the files as it was written (what `zcat` shows)
// The clocks of different computers are not in step: records of different files are ordered by the time each one wrote.
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import ai "../.."

main :: proc() {
    paths: [dynamic]string
    trace: string
    kinds: string
    show_ids: bool
    raw: bool
    cost: bool
    for i := 1; i < len(os.args); i += 1 {
        switch os.args[i] {
        case "--trace":
            i += 1
            trace = os.args[i] if i < len(os.args) else ""
        case "--kind":
            i += 1
            kinds = os.args[i] if i < len(os.args) else ""
        case "--ids":
            show_ids = true
        case "--raw":
            raw = true
        case "--cost":
            cost = true
        case "--help", "-h":
            fmt.println("logview FILE... [--trace ID] [--kind g,p,...] [--ids] [--raw]   (see the top of tool/logview/main.odin)")
            return
        case:
            append(&paths, os.args[i])
        }
    }
    if len(paths) == 0 {
        fmt.eprintln("logview needs the log files of amsg --log (logview --help)")
        os.exit(2)
    }
    if raw {
        for path in paths {
            data, error := os.read_entire_file(path, context.allocator)
            text, ok := ai.LogDecode(data, context.allocator)
            if error != nil || !ok {
                fmt.eprintfln("cannot read %s", path)
                os.exit(1)
            }
            fmt.print(text)
        }
        return
    }
    entries, skipped, ok := ai.LogLoad(paths[:])
    if !ok {
        fmt.eprintln("cannot read one of the files")
        os.exit(1)
    }
    if skipped > 0 {
        fmt.eprintfln("%d file(s) held nothing readable (empty: the program was killed before its first block was written, or not a log of amsg)", skipped)
    }
    if cost {
        print_cost(entries)
        return
    }
    if trace != "" {
        entries = ai.LogTrace(entries, trace)
        if len(entries) == 0 {
            fmt.eprintfln("nothing belongs with %s (ids are in the id column: --ids)", trace)
            os.exit(1)
        }
    }
    for entry in entries {
        if kinds != "" && !contains_kind(kinds, entry.kind) {
            continue
        }
        if entry.kind == "@" || entry.kind == "I" {
            continue                                       // bookkeeping of the files, the names are already in the records
        }
        moment: time.Time = time.unix(entry.time_ms / 1000, (entry.time_ms % 1000) * 1_000_000)
        year, month, day := time.date(moment)
        hour, minute, second := time.clock(moment)
        ids: string
        if show_ids || trace != "" {
            ids = fmt.tprintf("  [%s%s%s]", entry.msg, " " if entry.msg != "" && entry.turn != "" else "", entry.turn)
        }
        fmt.printfln("%04d-%02d-%02d %02d:%02d:%02d.%03d  %-14s %-3s %-16s %s%s", year, int(month), day, hour, minute, second, entry.time_ms % 1000, owner_name(entry.owner), entry.kind, entry.who, strings.trim_right(entry.text, "\n"), ids)
    }
}

// What the agents cost: a table per instance and run, then the dearest turns.
print_cost :: proc(entries: []ai.LogEntry) {
    rows, turns := ai.LogSummary(entries)
    if len(rows) == 0 {
        fmt.println("no turns of an agent in these logs")
        return
    }
    fmt.printfln("%-22s %-5s %6s %7s %6s %9s %9s %9s", "instance", "run", "turns", "errors", "tools", "cost USD", "seconds", "per turn")
    for row in rows {
        per_turn: f64 = row.cost / f64(max(row.turns, 1))
        fmt.printfln("%-22s %-5s %6d %7d %6d %9.4f %9d %9.4f", row.owner, "all" if row.run == 0 else fmt.tprintf("%d", row.run), row.turns, row.errors, row.tools, row.cost, row.seconds, per_turn)
    }
    total: f64
    for row in rows {
        if row.run != 0 { total += row.cost }
    }
    fmt.printfln("total: $%.4f", total)
    if len(turns) > 0 {
        fmt.println("the dearest turns:")
        for turn, i in turns {
            if i >= 5 { break }
            started: string = strings.trim_space(turn.started_by)
            if len(started) > 100 { started = fmt.tprintf("%s...", started[:100]) }
            fmt.printfln("  $%.4f %4ds  %-22s run %d turn %d%s  %s", turn.cost, turn.seconds, turn.owner, turn.run, turn.turn, "" if turn.ok else " (error)", started)
        }
    }
}

contains_kind :: proc(list: string, kind: string) -> bool {
    for part in strings.split(list, ",", context.temp_allocator) {
        if part == kind {
            return true
        }
    }
    return false
}

owner_name :: proc(owner: string) -> string {
    slash: int = strings.index_byte(owner, '/')
    return owner[:slash] if slash > 0 else owner
}
