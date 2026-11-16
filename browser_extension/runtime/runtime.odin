// The Odin side of a browser extension: what the code of the background can call. Build for js_wasm32 (the extension build does).
//
// The source package of an extension has two procs, the contract of the generated entry:
//     init :: proc()                                        run once when the background starts
//     on_message :: proc(message: string, reply: []u8) -> int   a message from the popup or a content script, write the reply into `reply`, return its length
// A service worker is stopped when idle, so `init` runs again later and globals are fresh: keep what must stay in the browser storage.
package extension_runtime

import "core:fmt"

foreign import extension "extension"

@(default_calling_convention = "contextless")
foreign extension {
	@(link_name = "log")
	log_raw :: proc(message: string) ---
	@(link_name = "set_badge")
	set_badge_raw :: proc(text: string) ---
}

// Writes to the console of the extension background (about:debugging "Inspect" in Firefox, "service worker" link in Chrome)
Log :: proc(message: string) {
	log_raw(message)
}

// The text on the toolbar button, at most about 4 characters are visible. "" clears it.
SetBadge :: proc(text: string) {
	set_badge_raw(text)
}

// Formats into the reply buffer of on_message and returns the length. Text that does not fit is cut, the buffer is fixed.
ReplyPrint :: proc(reply: []u8, format: string, arguments: ..any) -> int {
	return len(fmt.bprintf(reply, format, ..arguments))
}
