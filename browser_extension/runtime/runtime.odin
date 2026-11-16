// The Odin side of a browser extension: what the code of the background and of an extension page (options) can call. Build for js_wasm32.
//
// The source package of the background has three procs, the contract of the generated entry:
//     init :: proc()                                              run once when the background starts
//     on_load :: proc(state: string)                              the text of the last SaveState, or "" the first time. Runs before the first message
//     on_message :: proc(message: string, reply: []u8) -> int     a message from the popup, a content script or an options page, write the reply into `reply`, return its length
// A service worker is stopped when idle, so `init` runs again later and globals are fresh: SaveState what must stay, on_load gets it back.
//
// A page (the Karl2D options page) is a web_build package (init, step, shutdown) that talks to the background: SendMessage, the answer arrives
// in the handler of SetReplyHandler a little later (the browser answers asynchronously).
package extension_runtime

import "base:runtime"
import "core:fmt"

foreign import extension "extension"

@(default_calling_convention = "contextless")
foreign extension {
	@(link_name = "log")
	log_raw :: proc(message: string) ---
	@(link_name = "set_badge")
	set_badge_raw :: proc(text: string) ---
	@(link_name = "open_url")
	open_url_raw :: proc(url: string) ---
	@(link_name = "save_state")
	save_state_raw :: proc(state: string) ---
	@(link_name = "send_message")
	send_message_raw :: proc(message: string) ---
}

// Writes to the console of the extension (about:debugging "Inspect" in Firefox, "service worker" link in Chrome)
Log :: proc(message: string) {
	log_raw(message)
}

// The text on the toolbar button, at most about 4 characters are visible. "" clears it.
SetBadge :: proc(text: string) {
	set_badge_raw(text)
}

// Opens the address in a new tab
OpenUrl :: proc(url: string) {
	open_url_raw(url)
}

// Keeps the text in the browser storage (up to 16 KB), the next start hands it to on_load
SaveState :: proc(state: string) {
	save_state_raw(state)
}

// Formats into the reply buffer of on_message and returns the length. Text that does not fit is cut, the buffer is fixed.
ReplyPrint :: proc(reply: []u8, format: string, arguments: ..any) -> int {
	return len(fmt.bprintf(reply, format, ..arguments))
}

// --- Page side ---

ReplyHandler :: proc(reply: string)

REPLY_CAPACITY :: 16 * 1024

@(private)
reply_buffer: [REPLY_CAPACITY]u8
@(private)
reply_handler: ReplyHandler
@(private)
reply_context: runtime.Context

// Sends a message to the background. The reply goes to the handler, never inside of this call.
SendMessage :: proc(message: string) {
	send_message_raw(message)
}

// The handler gets every reply. Call it from `init`: the context of the caller is what the handler runs with.
SetReplyHandler :: proc(handler: ReplyHandler) {
	reply_handler = handler
	reply_context = context
}

// The JavaScript of the page copies the reply here and calls reply_ready
@(export)
reply_pointer :: proc "c" () -> rawptr {
	return &reply_buffer[0]
}

@(export)
reply_capacity :: proc "c" () -> int {
	return REPLY_CAPACITY
}

@(export)
reply_ready :: proc "c" (length: int) {
	if reply_handler == nil {
		return
	}
	context = reply_context
	reply_handler(string(reply_buffer[:clamp(length, 0, REPLY_CAPACITY)]))
}
