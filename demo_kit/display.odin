#+build !js
package demo_kit

// Which display a demo window is put on when the demos are tested in a window. The person says it with the environment variable DEMO_MONITOR: a part of the name of
// the display, without regard to case ("dell" for "DELL U2720Q"). Without it the window opens where the operating system puts it. The captures tool sets it from its
// `--monitor` option or from a local file (see tool/captures/main.odin), the backends (glue_raylib, glue_karl2d) move the window there and make its size the one the
// demo asked for, whatever the scaling of that display is (Windows can scale a window by 125 %, 150 %: a picture of a scaled window is bigger than the stored one).

import "core:os"
import "core:strconv"
import "core:strings"

DISPLAY_ENV :: "DEMO_MONITOR"
DISPLAY_RECT_ENV :: "DEMO_MONITOR_RECT"         // "x,y,width,height" of the display on the desktop, set by the captures tool for the backends that cannot read names (raylib)

// The wanted display: a part of its name, empty for no wish.
DisplayRequest :: proc() -> string {
    return strings.trim_space(os.get_env(DISPLAY_ENV, context.temp_allocator))
}

// Where the wanted display is on the desktop, when the captures tool found it out: x, y, width, height in pixels.
DisplayRect :: proc() -> (rect: [4]int, ok: bool) {
    text: string = strings.trim_space(os.get_env(DISPLAY_RECT_ENV, context.temp_allocator))
    if text == "" { return }
    parts: []string = strings.split(text, ",", context.temp_allocator)
    if len(parts) != 4 { return }
    for part, i in parts {
        value, parsed := strconv.parse_int(strings.trim_space(part))
        if !parsed { return }
        rect[i] = value
    }
    return rect, true
}

// Does the name of a display hold the request (without regard to case)?
DisplayMatches :: proc(name: string, request: string) -> bool {
    return strings.contains(strings.to_lower(name, context.temp_allocator), strings.to_lower(request, context.temp_allocator))
}
