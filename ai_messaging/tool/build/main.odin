// Builds amsg and records in it which commit of the repository it is: `amsg --version` then tells, and `amsg --version --check` asks GitHub if it is the newest.
//
//   odin run ai_messaging/tool/build                 from the odin_utilities folder: builds amsg.exe (amsg on Linux and macOS) there
//   odin run ai_messaging/tool/build -- --out C:/tools/amsg.exe     somewhere else (a folder that is on the PATH)
//   odin run ai_messaging/tool/build -- --debug      without -o:speed
//
// The commit is the newest one that touched ai_messaging, p2p or serial (the folders the program is made of); "+ local changes" when those folders have changes that are not
// committed. Needs git in the PATH. A plain `odin build ai_messaging/tool/amsg` works too, its version says "commit unknown".
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import ai "../.."

main :: proc() {
    out: string = "amsg.exe" when ODIN_OS == .Windows else "amsg"
    optimize: bool = true
    for i := 1; i < len(os.args); i += 1 {
        switch os.args[i] {
        case "--out":
            i += 1
            if i >= len(os.args) {
                fmt.eprintln("--out needs the path of the program")
                os.exit(2)
            }
            out = os.args[i]
        case "--debug":
            optimize = false
        case:
            fmt.eprintfln("unknown argument %s (--out PATH, --debug)", os.args[i])
            os.exit(2)
        }
    }
    if !os.exists("ai_messaging/tool/amsg") {
        fmt.eprintln("run this from the odin_utilities folder: odin run ai_messaging/tool/build")
        os.exit(2)
    }
    paths: [3]string = {"ai_messaging", "p2p", "serial"}
    commit: string = git("log", "-1", "--format=%H", "--", paths[0], paths[1], paths[2])
    dirty: bool = git("status", "--porcelain", "--", paths[0], paths[1], paths[2]) != ""
    if len(commit) != 40 {
        fmt.eprintln("git did not give a commit (is git in the PATH, and is this a clone of the repository?): building with commit unknown")
        commit = "unknown"
    }
    built: i64 = time.to_unix_seconds(time.now())
    command: [dynamic]string
    append(&command, "odin", "build", "ai_messaging/tool/amsg", fmt.tprintf("-out:%s", out), "-strict-style", "-vet")
    if optimize { append(&command, "-o:speed") }
    append(&command, fmt.tprintf("-define:AMSG_COMMIT=%s", commit), fmt.tprintf("-define:AMSG_DIRTY=%v", dirty), fmt.tprintf("-define:AMSG_BUILT=%d", built))
    state, stdout, stderr, error := os.process_exec({command = command[:]}, context.temp_allocator)
    if error != nil || !state.success {
        fmt.eprintln(string(stderr), string(stdout))
        fmt.eprintln("the build failed")
        os.exit(1)
    }
    fmt.printfln("built %s: version %s, commit %s%s", out, ai.VERSION, commit[:min(len(commit), 7)], " (+ local changes)" if dirty else "")
    fmt.println("`amsg --version --check` asks GitHub if it is the newest")
}

git :: proc(arguments: ..string) -> string {
    command: [dynamic]string
    append(&command, "git")
    for argument in arguments { append(&command, argument) }
    state, stdout, _, error := os.process_exec({command = command[:]}, context.temp_allocator)
    if error != nil || !state.success { return "" }
    return strings.trim_space(string(stdout))
}
