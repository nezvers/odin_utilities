#+build !js
package demo_kit

import "base:runtime"
import "../wait_for"

// A device that is slower than the one the scripts were written on: ODIN_SLOW=3 makes every `WaitUntil` wait three times as long (wait_for.odin has the rest of the story). Read once, when the program starts.
@(init)
time_scale_init :: proc "contextless" () {
    context = runtime.default_context()
    TimeScale = wait_for.Scale()
}
