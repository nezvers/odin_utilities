#+build js
package demo_kit

// A page in a browser has no displays to choose from and no environment: nothing is asked for (display.odin is the desktop side)

DisplayRequest :: proc() -> string {
    return ""
}

DisplayRect :: proc() -> (rect: [4]int, ok: bool) {
    return
}

DisplayMatches :: proc(name: string, request: string) -> bool {
    return false
}
