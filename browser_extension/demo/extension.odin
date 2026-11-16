// Demo extension: the popup button sends "ping", Odin counts and answers, the toolbar badge shows the count.
// A content script (when the build lists match patterns) sends "page:<title>" for every page it runs in.
package demo

import runtime "../runtime"
import "core:fmt"
import "core:strings"

// Lost when the background is stopped and started again (service worker), a real extension keeps such state in the browser storage
pings: int

// Runs once when the background starts
init :: proc() {
	runtime.Log("odin extension started")
}

// A message from the popup or a content script
on_message :: proc(message: string, reply: []u8) -> int {
	if message == "ping" {
		pings += 1
		badge: [8]u8
		runtime.SetBadge(fmt.bprintf(badge[:], "%d", pings))
		return runtime.ReplyPrint(reply, "pong %d from Odin", pings)
	}
	if strings.has_prefix(message, "page:") {
		runtime.Log(message)
		return runtime.ReplyPrint(reply, "ok")
	}
	return runtime.ReplyPrint(reply, "unknown message: %s", message)
}
