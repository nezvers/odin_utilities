#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "core:os"

// Opens an address in the default browser: `rundll32 url.dll,FileProtocolHandler` on Windows, `open` on macOS, `xdg-open` elsewhere. The process is started and left alone.
BrowserOpen :: proc(url: string) -> bool {
    when ODIN_OS == .Windows {
        command: []string = {"rundll32", "url.dll,FileProtocolHandler", url}
    } else when ODIN_OS == .Darwin {
        command: []string = {"open", url}
    } else {
        command: []string = {"xdg-open", url}
    }
    process, error := os.process_start({command = command})
    if error != nil { return false }
    _ = process
    return true
}
