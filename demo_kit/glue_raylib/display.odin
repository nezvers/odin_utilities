package demo_kit_raylib

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import kit ".."

DISPLAY_SETTLE_FRAMES :: 300        // how long the window gets to arrive on its display and take its size (Windows sends its scaling messages after a move)
DISPLAY_STABLE_FRAMES :: 5          // how many frames in a row it has to be right

// Puts the window on the display that DEMO_MONITOR names (when it is set), then makes its drawing area `width` x `height` pixels whatever the scaling of the display is.
// Prints one line that says where the window is. False, with the reason printed, when the display is not there or the size cannot be had: the pictures would not fit
// the stored ones.
placeOnDisplay :: proc(width: i32, height: i32) -> bool {
    request: string = kit.DisplayRequest()
    count: i32 = rl.GetMonitorCount()
    target: i32 = -1
    if request != "" {
        // raylib only knows "Generic PnP Monitor": the captures tool looked the name up and says where the display is on the desktop
        if rect, has_rect := kit.DisplayRect(); has_rect {
            for i in 0 ..< count {
                position: rl.Vector2 = rl.GetMonitorPosition(i)
                if int(position.x) == rect[0] && int(position.y) == rect[1] && int(rl.GetMonitorWidth(i)) == rect[2] && int(rl.GetMonitorHeight(i)) == rect[3] {
                    target = i
                    break
                }
            }
        } else {
            for i in 0 ..< count {
                if kit.DisplayMatches(string(rl.GetMonitorName(i)), request) {
                    target = i
                    break
                }
            }
        }
        if target < 0 {
            fmt.printfln("[DEMO TEST] no display %q found by raylib. Connected: %s (raylib cannot read display names: start the demos with `odin run demo_kit/tool/captures`, it finds the display and tells raylib where it is)", request, displayNames(count))
            return false
        }
    }
    place :: proc(target: i32, width: i32, height: i32) {
        position: rl.Vector2 = rl.GetMonitorPosition(target)
        x: i32 = i32(position.x) + max((rl.GetMonitorWidth(target) - width) / 2, 0)
        y: i32 = i32(position.y) + max((rl.GetMonitorHeight(target) - height) / 2, 0)
        rl.SetWindowPosition(x, y)
    }
    if target >= 0 { place(target, width, height) }
    stable: int
    for _ in 0 ..< DISPLAY_SETTLE_FRAMES {
        rl.PollInputEvents()
        on_target: bool = target < 0 || rl.GetCurrentMonitor() == target
        if on_target && rl.GetRenderWidth() == width && rl.GetRenderHeight() == height {
            stable += 1
            if stable >= DISPLAY_STABLE_FRAMES { break }
        } else {
            stable = 0
            if target >= 0 && !on_target { place(target, width, height) }
            rl.SetWindowSize(width, height)
        }
        rl.WaitTime(0.016)
    }
    current: i32 = rl.GetCurrentMonitor()
    scale: rl.Vector2 = rl.GetWindowScaleDPI()
    name: string = string(rl.GetMonitorName(current))
    if stable < DISPLAY_STABLE_FRAMES {
        fmt.printfln("[DEMO TEST] the window on %q is %d x %d, not %d x %d (scale %.2f): the pictures cannot be compared", name, rl.GetRenderWidth(), rl.GetRenderHeight(), width, height, scale.x)
        return false
    }
    fmt.printfln("[DEMO TEST] display: %s (%d of %d), %d x %d, scale %.2f, window %d x %d", name, current + 1, count, rl.GetMonitorWidth(current), rl.GetMonitorHeight(current), scale.x, rl.GetRenderWidth(), rl.GetRenderHeight())
    return true
}

@(private)
displayNames :: proc(count: i32) -> string {
    names: [dynamic]string
    names.allocator = context.temp_allocator
    for i in 0 ..< count {
        position: rl.Vector2 = rl.GetMonitorPosition(i)
        append(&names, fmt.tprintf("%q at %d,%d %dx%d", string(rl.GetMonitorName(i)), int(position.x), int(position.y), rl.GetMonitorWidth(i), rl.GetMonitorHeight(i)))
    }
    return strings.join(names[:], ", ", context.temp_allocator)
}
