// The background of the YouTube Shorts extension: keeps the Store (shorts.odin) and answers the content script and the options page.
// All decisions are in youtube_shorts, this file only moves the state between the browser storage and the Store.
package background

import runtime "../../runtime"
import shorts ".."

store: shorts.Store
// the text form of the state, rewritten whenever the state changes
state_buffer: [shorts.STATE_CAPACITY]u8

// Runs every time the browser starts the background (a service worker is stopped when idle), on_load follows with the kept state
init :: proc() {
	shorts.StoreInit(&store)
}

// The state of the last SaveState, "" the first time
on_load :: proc(state: string) {
	shorts.StoreDecode(&store, state)
}

on_message :: proc(message: string, reply: []u8) -> int {
	length, changed := shorts.ShortsHandle(&store, message, reply)
	if changed {
		runtime.SaveState(shorts.StoreEncode(&store, state_buffer[:]))
	}
	return length
}
