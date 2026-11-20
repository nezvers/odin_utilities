package main

// How fast the cell screen takes output: `odin run ui/tool/ansi_bench -o:speed` (a debug build says nothing). Fixed data (no random numbers: two revisions run the same bytes), a
// screen of 200 x 50 with a history, best of five runs, MB per second and ns per byte. `-- --bytewise` runs the same data through the byte at a time state machine (the reference path
// of the fast one) to show what the run fill gains.

import "core:fmt"
import "core:os"
import "core:time"
import ui "../.."

SIZE :: 1 << 20

run :: proc(name: string, screen: ^ui.AnsiScreen, data: []u8) {
    best: f64 = 1e30
    for _ in 0 ..< 5 {
        start: time.Tick = time.tick_now()
        for _ in 0 ..< 5 { ui.AnsiScreenWrite(screen, data) }
        best = min(best, f64(time.duration_nanoseconds(time.tick_since(start))) / 5)
    }
    fmt.printf("%-26s %8.1f MB/s   %6.2f ns/byte\n", name, f64(len(data)) / best * 1000, best / f64(len(data)))
}

fill :: proc(parts: []string, limit: int) -> [dynamic]u8 {
    data: [dynamic]u8
    for i := 0; len(data) < limit; i += 1 { append(&data, ..transmute([]u8)parts[i % len(parts)]) }
    return data
}

main :: proc() {
    cells: []ui.AnsiCell = make([]ui.AnsiCell, 200 * 50)
    history: []ui.AnsiCell = make([]ui.AnsiCell, 200 * 1000)
    alternate: []ui.AnsiCell = make([]ui.AnsiCell, 200 * 50)
    screen: ui.AnsiScreen = ui.AnsiScreenMake(cells, 200, 50, history, alternate)
    for argument in os.args[1:] {
        if argument == "--bytewise" { screen.bytewise = true }
    }
    fmt.println(len(os.args) > 1 && os.args[1] == "--bytewise" ? "byte at a time (the reference path)" : "run fill")

    lines: [dynamic]u8 = fill({"The quick brown fox jumps over the lazy dog 0123456789 and again and again and again until the line is long enough to wrap\r\n"}, SIZE)
    short: [dynamic]u8 = fill({"ls\r\n", "total 48\r\n", "drwxr-xr-x  2 user user 4096 Nov 20 22:00 src\r\n", "-rw-r--r--  1 user user  812 Nov 20 22:01 README.md\r\n"}, SIZE)
    colored: [dynamic]u8 = fill({"\x1b[32mgreen\x1b[0m plain text with some words in it, ", "\x1b[1;31mred\x1b[0m\r\n"}, SIZE)
    cursor: [dynamic]u8 = fill({"\x1b[2;1Hprogress [", "##########", "          ", "]  50%\x1b[K", "\x1b[10;20Hstatus line\x1b[K\r"}, SIZE)
    wide: [dynamic]u8 = fill({"日本語のテキスト and some latin text with é accents ", "😀 emoji and 🇩🇪 flags\r\n"}, SIZE)
    defer { delete(lines); delete(short); delete(colored); delete(cursor); delete(wide) }

    run("long ASCII lines", &screen, lines[:])
    run("short lines (ls like)", &screen, short[:])
    run("colors every 25 bytes", &screen, colored[:])
    run("cursor moves and erase", &screen, cursor[:])
    run("wide letters and emoji", &screen, wide[:])
}
