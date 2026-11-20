package main

// How fast text is measured: `odin run font/tool/measure_bench -o:speed` (a debug build says nothing). 4 KB of English text, Inter and Fira Code at 13 px, best of five, ns per character:
// the whole TextMeasure without and with a wrap width, and the pieces it is made of when asked one by one (the cmap lookup, the advance, the kerning of a pair), which is what the layout
// loops cost before the ASCII tables.

import "core:fmt"
import "core:time"
import font "../.."

INTER :: #load("../../../assets/fonts/inter/Inter-Regular.ttf")
FIRA :: #load("../../../assets/fonts/FiraCode-Regular.ttf")

nanoseconds_per_character :: proc(count: int, repeats: int, work: proc(data: rawptr), data: rawptr) -> f64 {
    best: f64 = 1e30
    for _ in 0 ..< 5 {
        start: time.Tick = time.tick_now()
        for _ in 0 ..< repeats { work(data) }
        best = min(best, f64(time.duration_nanoseconds(time.tick_since(start))) / f64(repeats) / f64(count))
    }
    return best
}

Job :: struct {
    font: ^font.Font,
    text: string,
    sink: f32,
}

run :: proc(name: string, bytes: []u8, text: string) {
    f: font.Font
    ok := font.FontInit(&f, bytes)
    job: Job = {font = &f, text = text}
    measure := nanoseconds_per_character(len(text), 100, proc(data: rawptr) {
        job: ^Job = cast(^Job)data
        job.sink += font.TextMeasure(job.font, job.text, 13).x
    }, &job)
    wrapped := nanoseconds_per_character(len(text), 100, proc(data: rawptr) {
        job: ^Job = cast(^Job)data
        job.sink += font.TextMeasure(job.font, job.text, 13, {wrap_width = 300}).x
    }, &job)
    cmap := nanoseconds_per_character(len(text), 100, proc(data: rawptr) {
        job: ^Job = cast(^Job)data
        for c in transmute([]u8)job.text { job.sink += f32(font.FontGlyph(job.font, rune(c))) }
    }, &job)
    advance := nanoseconds_per_character(len(text), 100, proc(data: rawptr) {
        job: ^Job = cast(^Job)data
        for c in transmute([]u8)job.text { job.sink += font.FontAdvance(job.font, int(c) - 31) }
    }, &job)
    kerning := nanoseconds_per_character(len(text), 100, proc(data: rawptr) {
        job: ^Job = cast(^Job)data
        bytes: []u8 = transmute([]u8)job.text
        for i in 1 ..< len(bytes) { job.sink += font.FontKerning(job.font, int(bytes[i - 1]) - 31, int(bytes[i]) - 31) }
    }, &job)
    fmt.printf("%-9s ok=%v  measure %6.2f ns/char   wrapped %6.2f   (plain pieces: cmap %5.2f, advance %5.2f, kerning of a pair %6.2f)  %v\n", name, ok, measure, wrapped, cmap, advance, kerning, job.sink != 0)
}

main :: proc() {
    text: [dynamic]u8
    defer delete(text)
    sample: string = "The quick brown fox jumps over the lazy dog, again and again. "
    for len(text) < 4096 { append(&text, ..transmute([]u8)sample) }
    run("Inter", INTER, string(text[:]))
    run("FiraCode", FIRA, string(text[:]))
}
