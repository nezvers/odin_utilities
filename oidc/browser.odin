#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "core:os"
import "core:testing"

// The command that opens an address in the default browser: `rundll32 url.dll,FileProtocolHandler` on Windows, `open` on macOS, `xdg-open` elsewhere. The address is one argument of its own: no shell
// reads it, so an `&` or a space in it cannot start anything else. `out` holds the arguments.
BrowserCommand :: proc(url: string, out: []string) -> []string {
    when ODIN_OS == .Windows {
        out[0], out[1], out[2] = "rundll32", "url.dll,FileProtocolHandler", url
        return out[:3]
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

// Opens an address in the default browser. True means that the opener was started, not that a window is there yet (a browser that starts cold takes seconds): print the address as well.
BrowserOpen :: proc(url: string) -> bool {
    arguments: [3]string
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
        testing.expect_value(t, command[0], "rundll32")
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
    // a launcher that fails is a failure of BrowserOpen
    BrowserLauncher = proc(command: []string) -> bool { return false }
    testing.expect(t, !BrowserOpen("https://example.com/"))
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
