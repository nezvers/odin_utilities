#+build windows
package demo_kit

// A window of a scripted test (`-define:DEMO_TEST=true`) must not take the computer from the person who works on it: the input is simulated, so the window needs neither the focus nor the mouse.
// PassiveWindowBegin is called before the window opens and remembers the window that has the focus; PassiveWindowEnd after it opened: the window stops being activatable and stops taking
// clicks (the mouse goes through it to what lies below), then the focus goes back to the remembered window. The window stays visible (a picture is taken from its own back buffer, so what lies
// over it does not matter).

import "core:fmt"
import win "core:sys/windows"

// The window that has the focus now
PassiveWindowBegin :: proc() -> rawptr {
    return rawptr(win.GetForegroundWindow())
}

// Make the windows of this process passive and give the focus back. Prints one line that says what happened, so a run shows that the test did not keep the focus.
PassiveWindowEnd :: proc(previous: rawptr) {
    Search :: struct {
        process: win.DWORD,
        count: int,
    }
    search: Search = {process = win.GetCurrentProcessId()}
    win.EnumWindows(proc "system" (hwnd: win.HWND, parameter: win.LPARAM) -> win.BOOL {
        search: ^Search = cast(^Search)uintptr(parameter)
        process: win.DWORD
        win.GetWindowThreadProcessId(hwnd, &process)
        if process != search.process || !win.IsWindowVisible(hwnd) { return true }
        style: win.LONG_PTR = win.GetWindowLongPtrW(hwnd, win.GWL_EXSTYLE)
        // NOACTIVATE: a click does not take the focus; LAYERED + TRANSPARENT: the mouse passes through the window (it must be layered for that)
        style |= win.LONG_PTR(win.WS_EX_NOACTIVATE | win.WS_EX_LAYERED | win.WS_EX_TRANSPARENT)
        win.SetWindowLongPtrW(hwnd, win.GWL_EXSTYLE, style)
        win.SetLayeredWindowAttributes(hwnd, 0, 255, win.LWA_ALPHA)
        win.SetWindowPos(hwnd, nil, 0, 0, 0, 0, win.SWP_NOMOVE | win.SWP_NOSIZE | win.SWP_NOZORDER | win.SWP_NOACTIVATE | win.SWP_FRAMECHANGED)
        search.count += 1
        return true
    }, win.LPARAM(uintptr(&search)))
    kept: bool = true
    if previous != nil {
        win.SetForegroundWindow(win.HWND(previous))
        kept = win.GetForegroundWindow() == win.HWND(previous)
    }
    fmt.printfln("[DEMO TEST] window made passive (%d), focus %s", search.count, "given back" if kept else "NOT given back")
}
