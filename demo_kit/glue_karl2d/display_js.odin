#+build js
package demo_kit_karl2d

// In a browser the canvas is where the page puts it: there is no display to find and none to check (display.odin is the desktop side)

import "../../karl2d"

@(private)
findDisplay :: proc(request: string) -> (id: karl2d.Monitor_Id, found: bool) {
    return karl2d.MONITOR_NONE, true
}

@(private)
checkDisplay :: proc(width: int, height: int) -> bool {
    return true
}
