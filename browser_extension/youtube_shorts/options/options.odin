// The options page of the YouTube Shorts extension, a demo of the demo kit: the same code is drawn by raylib (host_raylib, on the desktop, with a
// loopback instead of a browser) and by Karl2D (host_karl2d, inside of the extension page). It shows the two options and the saved shorts.
//
// It never decides anything. Every change is sent to the background as a text (youtube_shorts.ShortsHandle) and what comes back
// is what it shows, so what is on the screen is what the background keeps.
package options

import "core:fmt"
import "core:strings"
import kit "../../../demo_kit"
import shorts ".."

SCREEN_SIZE :: kit.Vec2{960, 600}
ROWS_PER_PAGE :: 10
ROW_HEIGHT :: 32
LIST_TOP :: 236

// What the page needs of the world around it. The extension page fills it with the browser (runtime.SendMessage, OpenUrl), the desktop
// host and the tests with a loopback.
Bridge :: struct {
	send: proc(message: string),    // the reply comes back through OptionsOnReply, possibly later
	open_url: proc(url: string),
}

// What the page shows, only ever set from replies of the background
Page :: struct {
	bridge: Bridge,
	settings: shorts.Settings,
	loaded: bool,                   // the background answered the first "get"
	count: int,
	ids: [shorts.MAX_SAVED][shorts.SHORT_ID_LENGTH]u8,
	titles: [shorts.MAX_SAVED][shorts.TITLE_CAPACITY]u8,
	title_lengths: [shorts.MAX_SAVED]int,
	first_row: int,                 // paging of the list
}

page: Page

demo: kit.Demo = {name = "YouTube Shorts options", init = init, update = update, draw = draw, script = script}

// The host calls this before the demo starts: replies of the background go to OptionsOnReply
OptionsSetBridge :: proc(bridge: Bridge) {
	page = {bridge = bridge}
}

// A reply of the background. The first line says what it is: the settings text, or "list" and then the saved shorts. The rest is not for the page.
OptionsOnReply :: proc(reply: string) {
	switch {
	case strings.has_prefix(reply, "redirect="):
		page.settings = shorts.ShortsSettingsDecode(reply, shorts.SETTINGS_DEFAULT)
		page.loaded = true
	case strings.has_prefix(reply, "list"):
		page.count = 0
		remaining: string = reply
		_, _ = strings.split_lines_iterator(&remaining) // the "list" line
		for line in strings.split_lines_iterator(&remaining) {
			tab: int = strings.index_byte(line, '\t')
			if tab != shorts.SHORT_ID_LENGTH || page.count >= shorts.MAX_SAVED {
				continue
			}
			copy(page.ids[page.count][:], line[:tab])
			page.title_lengths[page.count] = copy(page.titles[page.count][:], line[tab + 1:])
			page.count += 1
		}
		page.first_row = min(page.first_row, max(page.count - 1, 0) / ROWS_PER_PAGE * ROWS_PER_PAGE)
	}
}

init :: proc(ctx: ^kit.Context) {
	ctx.background = kit.RAY_WHITE
	page.bridge.send("get")
	page.bridge.send("list")
}

update :: proc(ctx: ^kit.Context) {
}

@(private = "file")
rowRect :: proc(row: int, x, width: f32) -> kit.Rect {
	return {x, LIST_TOP + f32(row) * ROW_HEIGHT, width, ROW_HEIGHT - 6}
}

// An option is a toggle: the page asks the background to change it and shows the settings that come back, not its own guess
@(private = "file")
optionToggle :: proc(ctx: ^kit.Context, rect: kit.Rect, text: string, value: bool, key: string) {
	shown: bool = value
	label: string = fmt.tprintf("%s   %s", "ON " if value else "OFF", text)
	if kit.Toggle(ctx, rect, label, &shown) {
		page.bridge.send(fmt.tprintf("set:%s=%d", key, int(shown)))
	}
}

draw :: proc(ctx: ^kit.Context) {
	kit.DrawText(ctx, "YouTube Shorts", {30, 20}, 28, kit.BLACK)
	if !page.loaded {
		kit.DrawText(ctx, "waiting for the extension...", {30, 60}, 16, kit.GRAY)
	}

	optionToggle(ctx, {30, 80, 460, 36}, "Open Shorts as a full video (watch page)", page.settings.redirect, "redirect")
	optionToggle(ctx, {30, 126, 460, 36}, "Save button next to the Shorts buttons", page.settings.show_save, "save")
	kit.DrawText(ctx, "A short opens in the normal player, with the timeline and the recommendations.", {510, 90}, 14, kit.DARK_GRAY)
	kit.DrawText(ctx, "The Save button keeps the short in the list below.", {510, 136}, 14, kit.DARK_GRAY)

	kit.DrawText(ctx, fmt.tprintf("Saved shorts (%d of %d)", page.count, shorts.MAX_SAVED), {30, 190}, 20, kit.BLACK)
	if page.count == 0 {
		kit.DrawText(ctx, "Nothing saved yet. Open a short and press Save.", {30, LIST_TOP + 4}, 16, kit.GRAY)
	}

	last: int = min(page.first_row + ROWS_PER_PAGE, page.count)
	for index in page.first_row ..< last {
		row: int = index - page.first_row
		title: string = string(page.titles[index][:page.title_lengths[index]])
		text_rect: kit.Rect = rowRect(row, 30, 640)
		kit.DrawRect(ctx, text_rect, kit.WHITE)
		kit.DrawText(ctx, title if len(title) > 0 else string(page.ids[index][:]), {text_rect.x + 8, text_rect.y + 5}, 16, kit.BLACK)
		if kit.Button(ctx, rowRect(row, 690, 100), "Open") {
			page.bridge.open_url(fmt.tprintf("https://www.youtube.com/shorts/%s", string(page.ids[index][:])))
		}
		if kit.Button(ctx, rowRect(row, 800, 100), "Remove") {
			page.bridge.send(fmt.tprintf("remove:%s", string(page.ids[index][:])))
			page.bridge.send("list")
		}
	}

	if page.count > ROWS_PER_PAGE {
		if kit.Button(ctx, {30, 566, 100, 26}, "Previous") {
			page.first_row = max(page.first_row - ROWS_PER_PAGE, 0)
		}
		if kit.Button(ctx, {140, 566, 100, 26}, "Next") && page.first_row + ROWS_PER_PAGE < page.count {
			page.first_row += ROWS_PER_PAGE
		}
		kit.DrawText(ctx, fmt.tprintf("%d - %d", page.first_row + 1, last), {250, 570}, 16, kit.DARK_GRAY)
	}
}

// The script is the runtime test (odin test youtube_shorts/options) and plays in the raylib window with -define:DEMO_TEST=true.
// It runs against the loopback, so the checks look at what the page shows and at what the background kept.
script: []kit.Step = {
	kit.Wait(3),
	kit.Check(proc(ctx: ^kit.Context) -> bool {
		return page.loaded && !page.settings.redirect && page.settings.show_save && page.count == 3
	}, "the page shows the defaults and the three saved shorts"),

	// the toggle only asks: the background decides, then the page shows what it kept
	kit.Click({260, 98}),
	kit.Wait(2),
	kit.Check(proc(ctx: ^kit.Context) -> bool {
		return page.settings.redirect && loopback_store.settings.redirect
	}, "the redirect option is on in the page and in the background"),
	kit.Click({260, 144}),
	kit.Wait(2),
	kit.Check(proc(ctx: ^kit.Context) -> bool {
		return !page.settings.show_save && !loopback_store.settings.show_save
	}, "the Save button option is off"),

	kit.Click({850, 249}), // Remove, first row
	kit.Wait(2),
	kit.Check(proc(ctx: ^kit.Context) -> bool {
		return page.count == 2 && loopback_store.count == 2 && string(page.ids[0][:]) == "bbbbbbbbbbb"
	}, "the first saved short is gone and the next one moved up"),

	kit.Click({740, 249}), // Open, first row
	kit.Wait(2),
	kit.Check(proc(ctx: ^kit.Context) -> bool {
		return OptionsLoopbackOpened() == "https://www.youtube.com/shorts/bbbbbbbbbbb"
	}, "Open asks the host to open the short"),
}
