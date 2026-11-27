#+build !windows
package demo_kit

// Only Windows has a passive test window so far (see passive_windows.odin): elsewhere these do nothing.

PassiveWindowBegin :: proc() -> rawptr {
    return nil
}

PassiveWindowEnd :: proc(previous: rawptr) {
}
