#+build windows
package native

import "core:fmt"
import "core:strings"
import "core:sys/windows"
import "core:unicode/utf16"

// Starts a program that goes on after this one ends and shares nothing with it. os.process_start leaves the standard handles of the helper
// (the pipes of the browser) open in the child, then the browser waits for the job to end before it sees the reply. So this is CreateProcess
// without handle inheritance, detached from the console, and out of the job of the browser when that allows it.
@(private)
startDetached :: proc(command: []string) -> bool {
	line: strings.Builder
	strings.builder_init(&line, context.temp_allocator)
	for argument, i in command {
		if i > 0 {
			strings.write_byte(&line, ' ')
		}
		fmt.sbprintf(&line, "\"%s\"", argument)
	}
	wide: []u16 = make([]u16, strings.builder_len(line) + 1, context.temp_allocator)
	utf16.encode_string(wide, strings.to_string(line))

	info: windows.STARTUPINFOW = {cb = size_of(windows.STARTUPINFOW)}
	process: windows.PROCESS_INFORMATION
	DETACHED :: windows.DWORD(0x00000008) | windows.DWORD(0x00000200) | windows.DWORD(0x08000000) // detached, new group, no window
	BREAKAWAY :: windows.DWORD(0x01000000)
	// a job that forbids breakaway makes the first try fail: go without
	ok: bool = bool(windows.CreateProcessW(nil, cstring16(raw_data(wide)), nil, nil, false, DETACHED | BREAKAWAY, nil, nil, &info, &process))
	if !ok {
		ok = bool(windows.CreateProcessW(nil, cstring16(raw_data(wide)), nil, nil, false, DETACHED, nil, nil, &info, &process))
	}
	if ok {
		windows.CloseHandle(process.hProcess)
		windows.CloseHandle(process.hThread)
	}
	return ok
}
