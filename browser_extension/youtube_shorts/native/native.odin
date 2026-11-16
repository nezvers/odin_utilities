#+build !js
// The download helper: a program the browser starts (native messaging) because an extension cannot run youtube-dl itself.
// This package is everything it decides, native_host/main.odin only reads and writes the browser's packets.
//
// A request and a reply are one text each, wrapped as {"m": "<text>"}:
//   check               -> "ytdl:ok <program> <version>" or "ytdl:missing"
//   download:<id>       -> "job:<id>" (the program runs in a worker process), "ytdl:missing" or "invalid"
//   install             -> "job:install": downloads yt-dlp.exe (Windows) or runs pip (elsewhere)
//   status:<job>        -> "status:running", "status:done <file>", "status:failed <code>" or "status:none"
// A job is a copy of the helper started with `--job download <id>` / `--job install`. The browser starts a helper per message and stops it
// after the reply, so a job cannot be a thread of it: it reports through a file (`<temp>/shorts_helper/<job>.status`) that `status` reads.
package native

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import shorts ".."

// Both programs take the same arguments for what the helper does. yt-dlp is the maintained fork and goes first.
YTDL_COMMANDS :: [2]string{"yt-dlp", "youtube-dl"}
// What install gets: the release exe of yt-dlp on Windows (the helper looks in its folder too, no change of PATH needed), pip elsewhere
YTDL_RELEASE_URL :: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"

Config :: struct {
    ytdl_command: string,       // empty - yt-dlp, then youtube-dl from PATH, then the folder of install
    work_directory: string,     // status files and the installed youtube-dl. Empty - <temp>/shorts_helper
    downloads_directory: string,// empty - <home>/Downloads
    host_executable: string,    // what a job starts: this program. Empty - os.args[0]
}

// --- Packets of the browser ---

// {"m":"text"} -> text. False when it is not that.
NativeParseRequest :: proc(body: []byte, allocator := context.temp_allocator) -> (text: string, ok: bool) {
    value, error := json.parse(body, allocator = allocator)
    if error != nil {
        return
    }
    object, is_object := value.(json.Object)
    if !is_object {
        return
    }
    message, is_string := object["m"].(json.String)
    return string(message), is_string
}

NativeEncodeReply :: proc(text: string, allocator := context.temp_allocator) -> []byte {
    Reply :: struct {
        m: string `json:"m"`,
    }
    data, _ := json.marshal(Reply{text}, allocator = allocator)
    return data
}

// --- Places ---

@(private)
workDirectory :: proc(config: Config) -> string {
    if len(config.work_directory) > 0 {
        return config.work_directory
    }
    temp, _ := os.temp_directory(context.temp_allocator)
    return fmt.tprintf("%s/shorts_helper", temp)
}

@(private)
downloadsDirectory :: proc(config: Config) -> string {
    if len(config.downloads_directory) > 0 {
        return config.downloads_directory
    }
    home: string
    when ODIN_OS == .Windows {
        home, _ = os.lookup_env("USERPROFILE", context.temp_allocator)
    } else {
        home, _ = os.lookup_env("HOME", context.temp_allocator)
    }
    return fmt.tprintf("%s/Downloads", home)
}

@(private)
installedYtdl :: proc(config: Config) -> string {
    return fmt.tprintf("%s/bin/yt-dlp%s", workDirectory(config), ".exe" if ODIN_OS == .Windows else "")
}

@(private)
statusPath :: proc(config: Config, job: string) -> string {
    return fmt.tprintf("%s/%s.status", workDirectory(config), job)
}

// --- youtube-dl ---

// The program that runs and its name and version ("yt-dlp 2026.08.19"): the configured command, then yt-dlp and youtube-dl from PATH,
// then the folder install uses
NativeFindYtdl :: proc(config: Config) -> (command: string, version: string, ok: bool) {
    commands := YTDL_COMMANDS
    candidates: [4]string = {config.ytdl_command, commands[0], commands[1], installedYtdl(config)}
    for candidate in candidates {
        if len(candidate) == 0 {
            continue
        }
        state, stdout, _, error := os.process_exec({command = {candidate, "--version"}}, context.temp_allocator)
        if error == nil && state.exit_code == 0 {
            name: string = "youtube-dl" if strings.contains(candidate, "youtube-dl") else "yt-dlp"
            return candidate, fmt.tprintf("%s %s", name, strings.trim_space(string(stdout))), true
        }
        // a configured command that does not run is an answer, not a reason to look somewhere else
        if candidate == config.ytdl_command && len(config.ytdl_command) > 0 {
            return
        }
    }
    return
}

// The file youtube-dl wrote, from its output: the last "[download] Destination: <file>" or `Merging formats into "<file>"`
NativeParseOutputPath :: proc(output: string) -> string {
    path: string
    remaining: string = output
    for raw in strings.split_lines_iterator(&remaining) {
        line: string = strings.trim_space(raw)
        if strings.has_prefix(line, "[download] Destination: ") {
            path = line[len("[download] Destination: "):]
        } else if strings.has_prefix(line, "[ffmpeg] Merging formats into \"") && strings.has_suffix(line, "\"") {
            path = line[len("[ffmpeg] Merging formats into \"") : len(line) - 1]
        }
    }
    return path
}

// --- Requests ---

@(private)
writeStatus :: proc(config: Config, job: string, text: string) {
    os.make_directory_all(workDirectory(config))
    _ = os.write_entire_file(statusPath(config, job), text)
}

@(private)
startJob :: proc(config: Config, kind: string, job: string) -> bool {
    writeStatus(config, job, "running")
    executable: string = config.host_executable if len(config.host_executable) > 0 else os.args[0]
    command: [dynamic]string
    command.allocator = context.temp_allocator
    append(&command, executable, "--job", kind, job)
    if len(config.ytdl_command) > 0 {
        append(&command, config.ytdl_command)
    }
    return startDetached(command[:])
}

// The reply to a request. Allocates with the temp allocator.
NativeHandle :: proc(config: Config, request: string) -> string {
    switch {
    case request == "check":
        _, version, found := NativeFindYtdl(config)
        if !found {
            return "ytdl:missing"
        }
        return fmt.tprintf("ytdl:ok %s", version)

    case strings.has_prefix(request, "download:"):
        id: string = request[len("download:"):]
        if !shorts.ShortsIsId(id) {
            return "invalid"
        }
        if _, _, found := NativeFindYtdl(config); !found {
            return "ytdl:missing"
        }
        if !startJob(config, "download", id) {
            return "status:failed start"
        }
        return fmt.tprintf("job:%s", id)

    case request == "install":
        if !startJob(config, "install", "install") {
            return "status:failed start"
        }
        return "job:install"

    case strings.has_prefix(request, "status:"):
        job: string = request[len("status:"):]
        if job != "install" && !shorts.ShortsIsId(job) {
            return "invalid"
        }
        data, error := os.read_entire_file(statusPath(config, job), context.temp_allocator)
        if error != nil {
            return "status:none"
        }
        return fmt.tprintf("status:%s", strings.trim_space(string(data)))
    }
    return "unknown"
}

// --- Jobs (the helper started with --job) ---

// Runs youtube-dl for a short and writes the result for `status`. Returns the exit code of the program.
NativeRunDownload :: proc(config: Config, id: string) -> int {
    if !shorts.ShortsIsId(id) {
        return 2
    }
    command, _, found := NativeFindYtdl(config)
    if !found {
        writeStatus(config, id, "failed missing")
        return 1
    }
    url_buffer: [64]u8
    template: string = fmt.tprintf("%s/%%(title)s [%%(id)s].%%(ext)s", downloadsDirectory(config))
    state, stdout, _, error := os.process_exec({command = {command, "--no-playlist", "--newline", "-o", template, shorts.ShortsWatchUrl(id, url_buffer[:])}}, context.temp_allocator)
    if error != nil || state.exit_code != 0 {
        writeStatus(config, id, fmt.tprintf("failed %d", state.exit_code if error == nil else -1))
        return 1
    }
    path: string = NativeParseOutputPath(string(stdout))
    writeStatus(config, id, fmt.tprintf("done %s", path) if len(path) > 0 else "done")
    return 0
}

// Gets yt-dlp: on Windows the release exe into the work folder (curl.exe comes with Windows 10), elsewhere pip for the user
NativeRunInstall :: proc(config: Config) -> int {
    command: []string
    when ODIN_OS == .Windows {
        os.make_directory_all(fmt.tprintf("%s/bin", workDirectory(config)))
        command = {"curl", "-L", "--fail", "-s", "-o", installedYtdl(config), YTDL_RELEASE_URL}
    } else {
        command = {"python3", "-m", "pip", "install", "--user", "-U", "yt-dlp"}
    }
    state, _, _, error := os.process_exec({command = command}, context.temp_allocator)
    if error != nil || state.exit_code != 0 {
        writeStatus(config, "install", fmt.tprintf("failed %d", state.exit_code if error == nil else -1))
        return 1
    }
    if _, _, found := NativeFindYtdl(config); !found {
        writeStatus(config, "install", "failed not-found")
        return 1
    }
    writeStatus(config, "install", "done")
    return 0
}

// --- Tests ---

@(test)
test_packets :: proc(t: ^testing.T) {
    text, ok := NativeParseRequest(transmute([]byte)string(`{"m":"download:dQw4w9WgXcQ"}`))
    testing.expect(t, ok)
    testing.expect_value(t, text, "download:dQw4w9WgXcQ")
    _, ok = NativeParseRequest(transmute([]byte)string(`[1]`))
    testing.expect(t, !ok)
    _, ok = NativeParseRequest(transmute([]byte)string(`{"x":1}`))
    testing.expect(t, !ok)
    _, ok = NativeParseRequest(transmute([]byte)string(`not json`))
    testing.expect(t, !ok)
    testing.expect_value(t, string(NativeEncodeReply("status:done a \"b\"")), `{"m":"status:done a \"b\""}`)
}

@(test)
test_output_path :: proc(t: ^testing.T) {
    testing.expect_value(t, NativeParseOutputPath("[youtube] x: Downloading\n[download] Destination: C:/d/a [x].mp4\n[download] 100% of 1MiB\n"), "C:/d/a [x].mp4")
    testing.expect_value(t, NativeParseOutputPath("[download] Destination: a.f137.mp4\n[ffmpeg] Merging formats into \"a.mp4\"\n"), "a.mp4")
    testing.expect_value(t, NativeParseOutputPath("nothing"), "")
}

@(test)
test_requests_without_youtube_dl :: proc(t: ^testing.T) {
    temp, _ := os.temp_directory(context.temp_allocator)
    config: Config = {ytdl_command = "definitely-not-a-program-xyz", work_directory = fmt.tprintf("%s/shorts_helper_test", temp)}
    defer os.remove_all(config.work_directory)
    testing.expect_value(t, NativeHandle(config, "check"), "ytdl:missing")
    testing.expect_value(t, NativeHandle(config, "download:dQw4w9WgXcQ"), "ytdl:missing")
    testing.expect_value(t, NativeHandle(config, "download:../../x"), "invalid")
    testing.expect_value(t, NativeHandle(config, "status:dQw4w9WgXcQ"), "status:none")
    testing.expect_value(t, NativeHandle(config, "status:../x"), "invalid")
    testing.expect_value(t, NativeHandle(config, "what"), "unknown")
    writeStatus(config, "dQw4w9WgXcQ", "done a.mp4\n")
    testing.expect_value(t, NativeHandle(config, "status:dQw4w9WgXcQ"), "status:done a.mp4")
}
