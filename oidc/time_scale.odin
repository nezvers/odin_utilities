#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "base:runtime"
import "../wait_for"

// A device that is slower than the one the timeouts were chosen on: ODIN_SLOW=3 makes them three times as long. Read once, when the program starts.
@(init)
time_scale_init :: proc "contextless" () {
    context = runtime.default_context()
    TimeScale = wait_for.Scale()
}
