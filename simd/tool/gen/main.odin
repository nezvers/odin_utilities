package main

// Writes the inputs of the text benchmarks to files, with a fixed seed: `odin run simd/tool/gen -- <folder> [megabytes]`. A comparison of two revisions runs the same bytes
// (`odin run simd/tool/info -o:speed -- --bench --data <folder>`) and the generator is not part of the measurement (the rule of ghostty's benchmarks: generate first, measure later,
// reuse the exact files). Keep big corpora outside the repository.
//
//   ascii.txt     English sentences, ASCII only
//   mixed.txt     English, accents, Greek, Cyrillic, Chinese, Japanese, emoji: what a chat or a log of a program in many languages looks like
//   damaged.txt   mixed.txt with one byte in 2000 broken (a stray byte, a cut sequence), for the validator's error path

import "core:fmt"
import "core:os"
import "core:strconv"

PIECES :: [?]string{
    "The quick brown fox jumps over the lazy dog. ", "Pack my box with five dozen liquor jugs. ", "Numbers 0123456789 and symbols ~!@#$%^&*() fill a line. ", "A short one. ",
    "café naïve façade über ñ ", "αβγδ Ωσ ", "Привет, мир! ", "日本語のテキストと中文 ",
    "\U0001F600 \U0001F44D\U0001F3FD \U0001F1E9\U0001F1EA ", "€ £ ¥ ✓ → ", "\n", "\n\n",
}

Random :: struct { state: u32 }

next :: proc(random: ^Random) -> u32 {
    random.state = random.state * 1664525 + 1013904223
    return random.state >> 8
}

main :: proc() {
    if len(os.args) < 2 {
        fmt.eprintln("usage: gen <folder> [megabytes]")
        os.exit(2)
    }
    folder: string = os.args[1]
    megabytes: int = 1
    if len(os.args) > 2 { megabytes = strconv.parse_int(os.args[2]) or_else 1 }
    size: int = megabytes << 20
    random: Random = {2026}
    pieces := PIECES
    ascii: [dynamic]u8
    mixed: [dynamic]u8
    for len(ascii) < size {
        append(&ascii, ..transmute([]u8)pieces[next(&random) % 4])
    }
    for len(mixed) < size {
        append(&mixed, ..transmute([]u8)pieces[next(&random) % len(pieces)])
    }
    damaged: [dynamic]u8 = make([dynamic]u8, len(mixed))
    copy(damaged[:], mixed[:])
    for _ in 0 ..< len(damaged) / 2000 {
        at: int = int(next(&random)) % len(damaged)
        damaged[at] = u8(next(&random))
    }
    write :: proc(folder: string, name: string, data: []u8) {
        path: string = fmt.tprintf("%s/%s", folder, name)
        if os.write_entire_file(path, data) != nil {
            fmt.eprintln("cannot write", path)
            os.exit(1)
        }
        fmt.printf("%s: %d bytes\n", path, len(data))
    }
    os.make_directory(folder)
    write(folder, "ascii.txt", ascii[:])
    write(folder, "mixed.txt", mixed[:])
    write(folder, "damaged.txt", damaged[:])
}
