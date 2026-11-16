package options

import shorts ".."

// A background in the same process: the options page talks to the real logic (youtube_shorts.ShortsHandle) without a browser. The desktop host
// (raylib) uses it to try the page in a window, the tests to play the script.
loopback_store: shorts.Store
loopback_opened: [128]u8       // the last address OpenUrl got
loopback_opened_length: int

SAMPLE_SHORTS :: [3][2]string{
	{"aaaaaaaaaaa", "A cat that falls off a table"},
	{"bbbbbbbbbbb", "Ten second pancake"},
	{"ccccccccccc", "Why the bridge swings"},
}

// Starts a loopback background (with a few saved shorts) and gives the page its bridge
OptionsLoopbackInit :: proc(with_samples: bool) {
	shorts.StoreInit(&loopback_store)
	loopback_opened_length = 0
	if with_samples {
		samples := SAMPLE_SHORTS
		#reverse for sample in samples {
			shorts.StoreToggle(&loopback_store, sample[0], sample[1])
		}
	}
	OptionsSetBridge({send = loopbackSend, open_url = loopbackOpen})
}

OptionsLoopbackOpened :: proc() -> string {
	return string(loopback_opened[:loopback_opened_length])
}

@(private = "file")
loopbackSend :: proc(message: string) {
	reply: [16 * 1024]u8
	length, _ := shorts.ShortsHandle(&loopback_store, message, reply[:])
	OptionsOnReply(string(reply[:length]))
}

@(private = "file")
loopbackOpen :: proc(url: string) {
	loopback_opened_length = copy(loopback_opened[:], url)
}
