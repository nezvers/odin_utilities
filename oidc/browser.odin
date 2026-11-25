#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "core:os"
import "core:strings"
import "core:testing"

// A longer address is not given to `explorer` on Windows: it cuts everything after 259 characters (MAX_PATH), and the address of a login is about 300 (the PKCE challenge is at the end: the provider then
// answers `Invalid "code_challenge"`). Such an address goes into an Internet Shortcut file that is opened instead.
WINDOWS_ADDRESS_LIMIT :: 240

// The command that opens an address in the default browser: `explorer` on Windows, `open` on macOS, `xdg-open` elsewhere. (`rundll32 url.dll,FileProtocolHandler` and `cmd /c start` were tried on Windows 10 and start fine and
// exit 0 but never show the page when started from this program; `explorer` does, also with `&` in the address.) The address is one argument of its own: no shell
// reads it, so an `&` or a space in it cannot start anything else. `out` holds the arguments.
BrowserCommand :: proc(url: string, out: []string) -> []string {
    when ODIN_OS == .Windows {
        out[0], out[1] = "explorer", url
        return out[:2]
    } else when ODIN_OS == .Darwin {
        out[0], out[1] = "open", url
        return out[:2]
    } else {
        out[0], out[1] = "xdg-open", url
        return out[:2]
    }
}

// Replaces the start of the opener (a test sees the command instead of a browser window opening)
@(thread_local)
BrowserLauncher: proc(command: []string) -> bool

// Starts a command and leaves it alone: false when it cannot be started
BrowserStart :: proc(command: []string) -> bool {
    if BrowserLauncher != nil { return BrowserLauncher(command) }
    process, error := os.process_start({command = command})
    if error != nil { return false }
    _ = process
    return true
}

// An Internet Shortcut file with the address, in the temporary folder, under a name of its own (two logins, or two tests, must not write the same file: a shorter address written over a longer one would
// leave the tail of the old one). It holds an authorization request and no secret: state, nonce and the PKCE challenge are public by design. Opening the file opens the address in the default browser,
// whatever its length. The file is small and the system cleans the temporary folder; `BrowserShortcutRemove` deletes it.
BrowserShortcut :: proc(url: string) -> (path: string, ok: bool) {
    folder, folder_error := os.temp_directory(context.temp_allocator)
    if folder_error != nil { return "", false }
    random: [16]u8
    path = strings.concatenate({strings.trim_right(folder, "/\\"), "/oidc_open_browser_", RandomText(6, random[:]), ".url"}, context.temp_allocator)
    _ = os.remove(path)                       // write_entire_file does not shorten an existing file
    content: string = strings.concatenate({"[InternetShortcut]\r\nURL=", url, "\r\n"}, context.temp_allocator)
    if os.write_entire_file(path, content) != nil { return "", false }
    return path, true
}

// Deletes a shortcut made by `BrowserShortcut`; any other path is left alone
BrowserShortcutRemove :: proc(path: string) {
    if strings.has_suffix(path, ".url") && strings.contains(path, "oidc_open_browser_") { _ = os.remove(path) }
}

// The program of the default browser on Windows, from the two registry entries that name it (the choice of the person for https links, then the open command of that kind of file); "" when it cannot be
// found (the caller then uses the system opener). Only these two keys are read: nothing of the browser's own data.
browserDefaultExecutable :: proc() -> string {
    when ODIN_OS == .Windows {
        _, choice, _, error := os.process_exec({command = {"reg", "query", `HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice`, "/v", "ProgId"}}, context.temp_allocator)
        if error != nil { return "" }
        id: string = registryValue(string(choice))
        if id == "" || strings.contains_any(id, " \\\"\r\n&|<>^%") { return "" }
        _, command, _, command_error := os.process_exec({command = {"reg", "query", strings.concatenate({`HKCR\`, id, `\shell\open\command`}, context.temp_allocator), "/ve"}}, context.temp_allocator)
        if command_error != nil { return "" }
        return BrowserExecutableFrom(registryValue(string(command)))
    } else {
        return ""
    }
}

// The value of a `reg query` answer: the text after `REG_SZ` on the line that has it
@(private)
registryValue :: proc(output: string) -> string {
    rest: string = output
    for line in strings.split_lines_iterator(&rest) {
        if at := strings.index(line, "REG_SZ"); at >= 0 { return strings.trim_space(line[at + len("REG_SZ"):]) }
    }
    return ""
}

// The program of an open command (`"C:\Program Files\X\x.exe" --single-argument %1`): the quoted path, or the first word; "" unless it is an existing .exe
BrowserExecutableFrom :: proc(command_line: string) -> string {
    line: string = strings.trim_space(command_line)
    path: string
    if strings.has_prefix(line, `"`) {
        end: int = strings.index_byte(line[1:], '"')
        if end < 0 { return "" }
        path = line[1:1 + end]
    } else {
        space: int = strings.index_byte(line, ' ')
        path = line if space < 0 else line[:space]
    }
    if !strings.has_suffix(strings.to_lower(path, context.temp_allocator), ".exe") || !os.exists(path) { return "" }
    return path
}

// Opens an address in the default browser. True means that the opener was started, not that a window is there yet (a browser that starts cold takes seconds): print the address as well.
BrowserOpen :: proc(url: string) -> bool {
    // only web addresses: the opener of the system would also open a file or run a program for a path or another scheme
    if !strings.has_prefix(url, "https://") && !strings.has_prefix(url, "http://") { return false }
    arguments: [5]string
    when ODIN_OS == .Windows {
        // The default browser's program is started itself: a web address handed to the system can be taken by an app that registered for it (the Discord desktop app takes discord.com links, so the
        // login ran there and not in the browser). A test that replaces the start keeps the old commands (what is installed on the machine must not change a test).
        if BrowserLauncher == nil {
            if exe := browserDefaultExecutable(); exe != "" { return BrowserStart({exe, url}) }
        }
        if len(url) > WINDOWS_ADDRESS_LIMIT {
            shortcut, written := BrowserShortcut(url)
            if !written { return false }
            // `cmd /c start "" file.url` is what opens a shortcut file from this program (tried on Windows 10: `explorer file.url` and `rundll32 ... file.url` start and do nothing). The only argument that
            // cmd reads is the path of our own file (a folder of the system and a name of ours: no `&`, `|` or `%` in it)
            return BrowserStart({"cmd", "/c", "start", "", shortcut})
        }
    }
    return BrowserStart(BrowserCommand(url, arguments[:]))
}

@(test)
test_the_browser_command_keeps_the_address_as_one_argument :: proc(t: ^testing.T) {
    url: string = "https://example.com/auth?a=1&b=two words&c=%26 && calc"
    arguments: [3]string
    command: []string = BrowserCommand(url, arguments[:])
    testing.expect(t, len(command) >= 2)
    testing.expect_value(t, command[len(command) - 1], url)
    for argument in command[:len(command) - 1] {
        testing.expectf(t, argument != url && len(argument) > 0, "the opener %q is not the address", argument)
    }
    when ODIN_OS == .Windows {
        testing.expect_value(t, command[0], "explorer")
    }
}

@(test)
test_the_opener_can_be_replaced_and_gets_the_address :: proc(t: ^testing.T) {
    @(static) seen: [4]string
    @(static) count: int
    count = 0
    BrowserLauncher = proc(command: []string) -> bool {
        count = copy(seen[:], command)
        return true
    }
    defer BrowserLauncher = nil
    testing.expect(t, BrowserOpen("https://example.com/?a=1&b=2"))
    testing.expect(t, count >= 2)
    testing.expect_value(t, seen[count - 1], "https://example.com/?a=1&b=2")
    // only web addresses are opened: a file, a program or another scheme is refused before the launcher is asked
    count = 0
    for refused in ([]string{"C:/Windows/System32/calc.exe", "file:///C:/secret.txt", "javascript:alert(1)", "ms-settings:", "calc", ""}) {
        testing.expectf(t, !BrowserOpen(refused), "%q is not opened", refused)
    }
    testing.expect_value(t, count, 0)
    testing.expect(t, BrowserOpen("http://127.0.0.1:1/"), "plain http is a web address")
    // a launcher that fails is a failure of BrowserOpen
    BrowserLauncher = proc(command: []string) -> bool { return false }
    testing.expect(t, !BrowserOpen("https://example.com/"))
}

// The address of a login is about 300 characters, `explorer` keeps 259: on Windows the whole address must reach the browser, through the shortcut file
@(test)
test_a_long_address_reaches_the_browser_whole :: proc(t: ^testing.T) {
    @(static) last: string
    @(static) command_start: string
    @(static) command_length: int
    last = ""
    BrowserLauncher = proc(command: []string) -> bool {
        last = strings.clone(command[len(command) - 1], context.temp_allocator)
        command_start = strings.clone(command[0], context.temp_allocator)
        command_length = len(command)
        return true
    }
    defer BrowserLauncher = nil
    long: string = strings.concatenate({"https://discord.com/api/oauth2/authorize?&response_type=code&client_id=1573843506039103518&redirect_uri=http%3A%2F%2F127.0.0.1%3A48217%2Fcallback",
        "&scope=openid%20identify%20email&state=1H-7TsxPKzB2rBoty_wOtQ&nonce=xMt3ugH0PFjrlscgusLbTQ&code_challenge=OhZa0Kwq36407D3bB7VjGj6jCAGYp9ksrwIv84KP5nM&code_challenge_method=S256"}, context.temp_allocator)
    testing.expect(t, len(long) > 259, "this is longer than what explorer keeps")
    testing.expect(t, BrowserOpen(long))
    when ODIN_OS == .Windows {
        testing.expect(t, strings.has_suffix(last, ".url"), "a shortcut file is opened, not the address")
        testing.expect_value(t, command_start, "cmd")
        testing.expect_value(t, command_length, 5)       // cmd /c start "" <file>
        data, error := os.read_entire_file(last, context.temp_allocator)
        testing.expect(t, error == nil)
        testing.expect_value(t, string(data), strings.concatenate({"[InternetShortcut]\r\nURL=", long, "\r\n"}, context.temp_allocator))
        BrowserShortcutRemove(last)
        // a short address still goes directly
        testing.expect(t, BrowserOpen("https://example.com/short"))
        testing.expect_value(t, last, "https://example.com/short")
    } else {
        testing.expect_value(t, last, long)
    }
}

@(test)
test_the_shortcut_file_holds_the_address_exactly :: proc(t: ^testing.T) {
    url: string = "https://example.com/a?x=1&y=%26&z=é"
    path, ok := BrowserShortcut(url)
    testing.expect(t, ok)
    defer BrowserShortcutRemove(path)
    data, error := os.read_entire_file(path, context.temp_allocator)
    testing.expect(t, error == nil)
    testing.expect_value(t, string(data), strings.concatenate({"[InternetShortcut]\r\nURL=", url, "\r\n"}, context.temp_allocator))
    testing.expect(t, strings.contains(path, "oidc_open_browser_") && strings.has_suffix(path, ".url"))
    // two shortcuts do not share a file, and a shorter address is exactly the shorter address (nothing of an older one is left)
    other, other_ok := BrowserShortcut("https://a.b/")
    testing.expect(t, other_ok && other != path)
    defer BrowserShortcutRemove(other)
    other_data, _ := os.read_entire_file(other, context.temp_allocator)
    testing.expect_value(t, string(other_data), "[InternetShortcut]\r\nURL=https://a.b/\r\n")
    // only a shortcut of this library is removed: any other path is left alone
    BrowserShortcutRemove("C:/Windows/notepad.exe")
    testing.expect(t, ODIN_OS != .Windows || os.exists("C:/Windows/notepad.exe"))
}

@(test)
test_a_command_that_cannot_start_is_reported :: proc(t: ^testing.T) {
    testing.expect(t, !BrowserStart({"this-program-does-not-exist-oidc-test"}), "a missing program is a failure")
    when ODIN_OS == .Windows {
        testing.expect(t, BrowserStart({"cmd", "/c", "exit", "0"}), "a program that exists is started")
    } else {
        testing.expect(t, BrowserStart({"true"}), "a program that exists is started")
    }
}

@(test)
test_the_program_of_an_open_command_is_the_quoted_path :: proc(t: ^testing.T) {
    when ODIN_OS == .Windows {
        exe: string = strings.concatenate({os.get_env("SystemRoot", context.temp_allocator), `\System32\cmd.exe`}, context.temp_allocator)
        testing.expect_value(t, BrowserExecutableFrom(strings.concatenate({`"`, exe, `" --single-argument %1`}, context.temp_allocator)), exe)
        testing.expect_value(t, BrowserExecutableFrom(exe), exe)
    }
    testing.expect_value(t, BrowserExecutableFrom(`"C:\nowhere\browser.exe" %1`), "")
    testing.expect_value(t, BrowserExecutableFrom(`"unterminated`), "")
    testing.expect_value(t, BrowserExecutableFrom(`notepad.txt`), "")
}
