#+build !js
package demo_kit

// The sinks of the log that need a file or the environment (log.odin has the format): stdout, stderr or a file, a wall clock in front of every line, and the setting by environment variables
// or by -define. A browser build has none of this (log_js.odin).

import "core:fmt"
import "core:os"
import "core:time"

DEMO_LOG :: #config(DEMO_LOG, "")                       // "stdout", "stderr" or a file name; empty: the environment decides
DEMO_LOG_KINDS :: #config(DEMO_LOG_KINDS, "")           // see LogKindsParse; empty: the environment decides, then input and reaction

@(private)
FileSink :: struct {
    file: ^os.File,
    own: bool,                  // a file that this log opened: LogClose closes it (stdout and stderr stay open)
    start: time.Tick,
}

@(private)
file_sink: FileSink

// Opens the log on `target`: "stdout", "stderr" or the name of a file (made new). False when the file cannot be made. One log at a time uses this sink.
LogOpen :: proc(log: ^Log, target: string, kinds: LogKinds = LOG_DEFAULT_KINDS) -> bool {
    file_sink = {start = time.tick_now()}
    switch target {
    case "stdout": file_sink.file = os.stdout
    case "stderr": file_sink.file = os.stderr
    case:
        file, err := os.create(target)
        if err != nil { return false }
        file_sink.file, file_sink.own = file, true
    }
    log^ = {kinds = kinds, user = &file_sink, sink = fileSinkWrite}
    return true
}

LogClose :: proc(log: ^Log) {
    if log.user == &file_sink && file_sink.own && file_sink.file != nil { os.close(file_sink.file) }
    file_sink.file, file_sink.own = nil, false
    log^ = {}
}

@(private)
fileSinkWrite :: proc(user: rawptr, line: string) {
    sink: ^FileSink = cast(^FileSink)user
    if sink.file == nil { return }
    milliseconds: f64 = f64(time.duration_microseconds(time.tick_since(sink.start))) / 1000
    // the wall clock goes inside of the bracket: `[frame 12  t= 0.2000s  + 31.2 ms]`
    close: int = -1
    for i in 0 ..< len(line) {
        if line[i] == ']' {
            close = i
            break
        }
    }
    if close < 0 {
        fmt.fprintln(sink.file, line)
        return
    }
    fmt.fprintfln(sink.file, "%s  +%9.2f ms%s", line[:close], milliseconds, line[close:])
}

// The log that the environment or the build asks for (DEMO_LOG, DEMO_LOG_KINDS): false when none was asked for. TestDemo calls it for every demo it plays, so
// `DEMO_LOG=run.log odin test ui/demo_common` needs no change of code. The first call opens it, the next ones go on in the same file.
LogFromEnvironment :: proc(log: ^Log) -> bool {
    @(static) opened: bool
    @(static) failed: bool
    @(static) shared: Log
    if failed { return false }
    if !opened {
        target: string = DEMO_LOG
        if target == "" {
            value, found := os.lookup_env("DEMO_LOG", context.temp_allocator)
            if found { target = value }
        }
        if target == "" {
            failed = true
            return false
        }
        kinds_text: string = DEMO_LOG_KINDS
        if kinds_text == "" {
            value, found := os.lookup_env("DEMO_LOG_KINDS", context.temp_allocator)
            if found { kinds_text = value }
        }
        kinds: LogKinds = LogKindsParse(kinds_text) if kinds_text != "" else LOG_DEFAULT_KINDS
        // the target string has to outlive this call only for the open
        if !LogOpen(&shared, target, kinds) {
            failed = true
            return false
        }
        opened = true
    }
    log^ = shared
    return true
}
