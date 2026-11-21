#+build windows
package demo_kit_karl2d

// The clipboard of Windows for the Karl2D backend (Karl2D has none): text in and out as UTF-16 through user32.

import win "core:sys/windows"

systemClipboardGet :: proc(buffer: []u8) -> int {
    if !win.OpenClipboard(nil) { return 0 }
    defer win.CloseClipboard()
    handle: win.HANDLE = win.GetClipboardData(win.CF_UNICODETEXT)
    if handle == nil { return 0 }
    memory: rawptr = win.GlobalLock(win.HGLOBAL(handle))
    if memory == nil { return 0 }
    defer win.GlobalUnlock(win.HGLOBAL(handle))
    text: string = win.wstring_to_utf8(buffer, cast(win.wstring)memory)
    return len(text)
}

systemClipboardSet :: proc(text: string) {
    if !win.OpenClipboard(nil) { return }
    defer win.CloseClipboard()
    wide: [dynamic]u16
    wide.allocator = context.temp_allocator
    resize(&wide, len(text) + 1)
    converted: []u16 = win.utf8_to_utf16(wide[:], text)
    bytes: int = (len(converted) + 1) * 2
    handle: win.HGLOBAL = cast(win.HGLOBAL)win.GlobalAlloc(win.GMEM_MOVEABLE, win.SIZE_T(bytes))
    if handle == nil { return }
    memory: [^]u16 = cast([^]u16)win.GlobalLock(handle)
    copy(memory[:len(converted)], converted)
    memory[len(converted)] = 0
    win.GlobalUnlock(handle)
    win.EmptyClipboard()
    win.SetClipboardData(win.CF_UNICODETEXT, win.HANDLE(handle))
}
