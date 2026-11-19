#+build !js
// What a build of amsg can tell about itself: the version of the program and the commit of the repository it was built from, so that anybody can see whether it is the current one
// (`amsg --version`, and `amsg --version --check` asks GitHub). The commit is not known to the compiler: `odin run ai_messaging/tool/build` finds it with git and builds with
// `-define:AMSG_COMMIT=...`, a plain `odin build` says "unknown".
package ai_messaging

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

@(private)
NEWLINE :: u8(10)

VERSION :: "1.0"                                            // raise it when the behaviour or the wire format changes in a way that members of different builds should know about
VERSION_REPOSITORY :: "nezvers/odin_utilities"             // on GitHub: where `--version --check` looks
VERSION_PATHS :: [?]string{"ai_messaging", "p2p", "serial"} // the folders of the repository that make up the program
COMMIT :: #config(AMSG_COMMIT, "unknown")                   // the newest commit that touched one of those folders when it was built
DIRTY :: #config(AMSG_DIRTY, false)                         // those folders had changes that were not committed
BUILT :: #config(AMSG_BUILT, 0)                             // when it was built: seconds since 1970 (UTC), 0 when it is not known

// One line: "amsg 1.0, commit 0a1b2c3 (+ local changes), built 2026-11-19 10:15 UTC".
VersionText :: proc() -> string {
    if COMMIT == "unknown" {
        return fmt.tprintf("amsg %s, commit unknown (built without tool/build: `odin run ai_messaging/tool/build` records it)", VERSION)
    }
    built: string
    if BUILT != 0 {
        moment: time.Time = time.unix(i64(BUILT), 0)
        year, month, day := time.date(moment)
        hour, minute, _ := time.clock(moment)
        built = fmt.tprintf(", built %04d-%02d-%02d %02d:%02d UTC", year, int(month), day, hour, minute)
    }
    return fmt.tprintf("amsg %s, commit %s%s%s", VERSION, COMMIT[:min(len(COMMIT), 7)], " (+ local changes)" if DIRTY else "", built)
}

// The newest commit of the repository that touched the folders of the program, from GitHub (needs `curl` and a network: the rate limit of the unauthenticated API is 60 an hour).
// `sha` is empty and `message` says why when it could not be read.
VersionLatest :: proc() -> (sha: string, date: string, subject: string, message: string) {
    for path in VERSION_PATHS {
        url: string = fmt.tprintf("https://api.github.com/repos/%s/commits?path=%s&per_page=1", VERSION_REPOSITORY, path)
        state, stdout, _, error := os.process_exec({command = {"curl", "-s", "-m", "15", "-H", "User-Agent: amsg", url}}, context.temp_allocator)
        if error != nil || !state.success {
            return "", "", "", "could not run curl (not installed, or no network)"
        }
        body: string = string(stdout)
        found: string = jsonField(body, "\"sha\"")
        if len(found) != 40 {
            return "", "", "", "GitHub did not answer with a commit (offline, a private repository, or the hourly limit of the API)"
        }
        // the author date of the first commit in the answer is the one that follows the sha
        author: int = strings.index(body, "\"author\"")
        committed: string = jsonField(body[max(author, 0):], "\"date\"")
        if date == "" || committed > date {
            sha, date = found, committed
            subject = firstLine(jsonField(body, "\"message\""))
        }
    }
    return
}

// The text of the first `"name": "value"` in a JSON text (the escapes \" \\ and \n are undone), empty when it is not there.
@(private)
jsonField :: proc(body: string, name: string) -> string {
    at: int = strings.index(body, name)
    if at < 0 { return "" }
    rest: string = body[at + len(name):]
    start: int = strings.index_byte(rest, '"')
    if start < 0 { return "" }
    rest = rest[start + 1:]
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    for i := 0; i < len(rest); i += 1 {
        switch rest[i] {
        case '"': return strings.to_string(builder)
        case '\\':
            i += 1
            if i < len(rest) {
                switch rest[i] {
                case 'n': strings.write_byte(&builder, NEWLINE)
                case 't': strings.write_byte(&builder, ' ')
                case: strings.write_byte(&builder, rest[i])
                }
            }
        case: strings.write_byte(&builder, rest[i])
        }
    }
    return ""
}

@(private)
firstLine :: proc(text: string) -> string {
    end: int = strings.index_byte(text, NEWLINE)
    return text if end < 0 else text[:end]
}

// What `amsg --version --check` prints after the version line: whether this build has the newest commit.
VersionCheck :: proc() -> (up_to_date: bool, text: string) {
    sha, date, subject, message := VersionLatest()
    if sha == "" { return false, fmt.tprintf("cannot tell if this is the newest: %s", message) }
    day: string = date[:min(len(date), 10)]
    if COMMIT == "unknown" {
        return false, fmt.tprintf("the newest commit of the repository for this program is %s (%s): %s. This build does not know its own commit: rebuild it with `odin run ai_messaging/tool/build`", sha[:7], day, subject)
    }
    if sha == COMMIT {
        if DIRTY { return false, "the same commit as the repository, but it was built with local changes" }
        return true, "up to date with the repository"
    }
    return false, fmt.tprintf("NOT the newest: the repository has %s (%s): %s. Update with `git pull` and `odin run ai_messaging/tool/build` (if you have commits that are not pushed yet, yours may be the newer one)", sha[:7], day, subject)
}
