#+build !js
package demo_kit_karl2d

import "core:fmt"
import "core:strings"
import "../../karl2d"
import kit ".."

// The monitor that DEMO_MONITOR names (when it is set): what Karl2D is started on. False, with the reason printed, when no connected display has that name.
findDisplay :: proc(request: string) -> (id: karl2d.Monitor_Id, found: bool) {
    if request == "" { return karl2d.MONITOR_NONE, true }
    monitors: []karl2d.Monitor_Info = karl2d.get_monitors(context.temp_allocator)
    for monitor in monitors {
        if kit.DisplayMatches(monitor.name, request) { return monitor.id, true }
    }
    names: [dynamic]string
    names.allocator = context.temp_allocator
    for monitor in monitors { append(&names, fmt.tprintf("%q", monitor.name)) }
    fmt.printfln("[DEMO TEST] no display of the name %q. Connected: %s", request, strings.join(names[:], ", ", context.temp_allocator))
    return karl2d.MONITOR_NONE, false
}

// After init: the drawing area has to be `width` x `height` (Karl2D asked for the size without the scaling of the display, see Init_Options.disable_auto_scale_hint); one try to
// set it when it is not. Prints one line that says where the window is. False, with the reason printed, when the pictures would not fit the stored ones.
checkDisplay :: proc(width: int, height: int) -> bool {
    if karl2d.get_screen_width() != width || karl2d.get_screen_height() != height {
        karl2d.set_screen_size(width, height)
    }
    name: string = "?"
    current: karl2d.Monitor_Id = karl2d.get_window_monitor()
    for monitor in karl2d.get_monitors(context.temp_allocator) {
        if monitor.id == current { name = monitor.name }
    }
    if karl2d.get_screen_width() != width || karl2d.get_screen_height() != height {
        fmt.printfln("[DEMO TEST] the window on %q is %d x %d, not %d x %d (scale %.2f): the pictures cannot be compared", name, karl2d.get_screen_width(), karl2d.get_screen_height(), width, height, karl2d.get_window_scale())
        return false
    }
    fmt.printfln("[DEMO TEST] display: %s, scale %.2f, window %d x %d", name, karl2d.get_window_scale(), karl2d.get_screen_width(), karl2d.get_screen_height())
    return true
}
