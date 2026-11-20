#+private file
package demo_common

// Fifteen examples of Baldr (https://github.com/BuLEEto/Baldr, by Lee Fry and the Baldr contributors, zlib License) made again with this library, one per tab:
// 01_hello (a counter), 04_controls (check boxes, a switch and sliders bound to a state), 03_scroll (a list of cards that scrolls) and 17_toasts (cards at the top right
// that a click takes away), 02_theme_lab (a page of widgets to judge a theme by; here the theme is made from an accent that is picked on the page) 05_overlays (a select,
// a menu that opens from a button, tooltips, a card that takes a click, a dialog) 21_charts (the same numbers as a line, an area, bars and a scatter) and 09_jobs (three downloads with their progress while the page stays live; the original runs each on
// a thread that posts messages, here a download is a number that grows with the time of the frame) and 19_markdown (a text in Markdown and how it reads, side by side;
// the original is an editor that shows the styles while one types, here the source is a plain text area and ui.UiMarkdown shows it). The texts and the sample data are the ones of the originals. There a `view` builds a tree and an `update` answers messages; here the page is
// declared every frame and a widget hands back what happened: the counter is `if ui.UiButton(...) { count += 1 }`.

import "core:fmt"
import "core:math"
import "core:reflect"
import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"

@(private="package")
demo_examples: kit.Demo = {
    name = "examples",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    example: int,
    // 01_hello
    count: int,
    // 04_controls
    remember: bool,
    notify: bool,
    two_factor: bool,
    dark: bool,
    size: f32,
    volume: f32,
    // 03_scroll
    picked: int,
    messages_id: ui.Id,             // for the script: the list and the Pick button of the second card, as they were declared
    pick_id: ui.Id,
    // 17_toasts
    toasts: [3]bool,
    // 02_theme_lab
    accent: ui.Color,
    mode: int,                      // 0 dark, 1 light
    hue: f32,
    nudges: int,
    search: [48]u8,
    search_length: int,
    lab_switch: bool,
    swatch_ids: [len(ACCENTS)]ui.Id,        // for the script
    // 05_overlays
    fruit: int,
    confirm: bool,
    deleted: int,
    last: string,
    duplicate_id: ui.Id,            // for the script: the entry of the menu and the cross of the card, as they were declared
    dismiss_id: ui.Id,
    note_id: ui.Id,
    // 21_charts
    chart: ui.ChartView,
    chart_kind: ui.ChartKind,
    sales: [12]ui.ChartPoint,
    costs: [12]ui.ChartPoint,
    cloud: [40]ui.ChartPoint,
    chart_series: [2]ui.ChartSeries,        // kept here: the chart draws from them after the frame was declared
    chart_picked: [64]u8,
    chart_picked_length: int,
    chart_id: ui.Id,
    // 09_jobs
    downloads: [3]Download,
    bumps: int,
    // 19_markdown
    note: [1024]u8,
    note_length: int,
    source_id: ui.Id,
    opened: [64]u8,             // the address of the link that was clicked last
    opened_length: int,
    // 32_chat
    messages: [CHAT_MESSAGES]Message,
    message_count: int,
    draft: [MESSAGE_TEXT]u8,
    draft_length: int,
    draft_id: ui.Id,
    chat_list: ui.Id,
    chat_follow: int,           // frames the list is still moved to its end (a new message is laid out in the next frame)
    replies: int,
    // 33_reading
    paper: int,
    page: int,
    // 34_mentions
    mention: [256]u8,
    mention_length: int,
    mention_id: ui.Id,
    mentions: int,
    mentioned: int,
    // 37_custom
    ratings: [2]int,
    rating_ids: [2]ui.Id,
    // 07_code
    code: [1536]u8,
    code_length: int,
    code_id: ui.Id,
    // 20_shortcuts
    chords: [len(SHORTCUT_ACTIONS)]ui.Chord,
    chord_ids: [len(SHORTCUT_ACTIONS)]ui.Id,
    chord_changes: int,
}

Download :: struct {
    name: string,
    size: f32,                      // bytes
    got: f32,
    running: bool,
    cancelled: bool,
    seconds: f32,                   // how long it has been running, or how long it took
}

// what a download gets per second: the 96 KB every 20 ms of the original
DOWNLOAD_RATE :: f32(96 * 1024 * 50)

state: State

EXAMPLES: [15]string = {"Hello", "Controls", "Scroll", "Toasts", "Theme lab", "Overlays", "Charts", "Jobs", "Markdown", "Chat", "Reading", "Shortcuts", "Code", "Custom", "Mentions"}
NOTE :: "# Release notes\n\nThe **look** of the ui follows *Baldr*: its themes, its typeface, its icons.\n\n## What is new\n- a theme from one accent color\n- charts and a date field\n  - with a month to pick from\n1. write Markdown\n2. read it on the right\n\n> Quotes are dim, with a bar.\n\n| Block | Shown as |\n|---|---|\n| `# Title` | a title |\n| a table | **this** |\n\n```\nui.UiMarkdown(&ctx, source)\n```\n\n---\nSee [the README](ui/README.md)."
MONTHS: [12]string = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
CHART_KINDS: [4]string = {"Line", "Area", "Bar", "Scatter"}
FRUIT: [5]string = {"Apple", "Banana", "Cherry", "Dragon fruit", "Elderberry"}
MODES: [2]string = {"Dark", "Light"}
// the tiles of the original (red, amber, green, blue, violet, pink) and a grey, which gives a theme without a hue
ACCENTS: [7]ui.Color = {{229, 72, 77, 255}, {242, 181, 68, 255}, {34, 197, 94, 255}, {59, 130, 246, 255}, {139, 92, 246, 255}, {236, 72, 153, 255}, {128, 128, 128, 255}}
TOASTS: [3]string = {"Build finished", "Ada: Lunch at one?", "Backup complete"}
MESSAGES :: 40

controlsReset :: proc() {
    state.remember, state.notify, state.two_factor = false, false, false
    state.dark, state.size, state.volume = true, 15, 0.4
}

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    controlsReset()
    state.toasts = {true, true, true}
    state.accent = ACCENTS[3]
    _, _, state.hue = ui_default.ColorToOklch(state.accent)
    state.lab_switch = true
    state.fruit = 2
    state.note_length = copy(state.note[:], NOTE)
    state.paper, state.page = 1, 0
    state.ratings = {3, 0}
    state.mention_length, state.mentions, state.mentioned = 0, 0, -1
    state.code_length = copy(state.code[:], CODE_SAMPLE)
    state.chords = {{{.CTRL}, u16(kit.Key.S)}, {{.CTRL}, u16(kit.Key.O)}, {{.CTRL}, u16(kit.Key.F)}, {{.CTRL, .SHIFT}, u16(kit.Key.B)}, {}}
    state.chord_changes = 0
    state.message_count = 0
    state.replies = 0
    for seed, i in CHAT_SEED { chat_add(seed, i % 2 == 1) }
    state.downloads = {{name = "odin-nightly.tar.gz", size = 24_000_000}, {name = "fonts.zip", size = 9_500_000}, {name = "changelog.md", size = 400_000}}
    ui.ChartViewInit(&state.chart)
    // the numbers of the original
    for i in 0 ..< 12 {
        state.sales[i] = {f32(i), 40 + 30 * math.sin(f32(i) * 0.55) + f32(i) * 2.5}
        state.costs[i] = {f32(i), 28 + 12 * math.cos(f32(i) * 0.8) + f32(i) * 1.2}
    }
    for i in 0 ..< 40 {
        state.cloud[i] = {f32(i % 12), 20 + 55 * math.sin(f32(i) * 1.7) * math.cos(f32(i) * 0.3)}
    }
    ctx.background = kit.Color(state.app.painter.theme.background)
}

@(deferred_in = rowEnd)
row :: proc(c: ^ui.Context, gap: f32 = 12, align: ui.AlignX = .LEFT) -> bool {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = gap, align = {x = align, y = .CENTER}}})
    return true
}

rowEnd :: proc(c: ^ui.Context, gap: f32 = 12, align: ui.AlignX = .LEFT) {
    ui.ElementClose(c)
}

// The window of an example: a panel of the size the original opens with, in the middle of what is left of the screen
@(deferred_in = stageEnd)
stage :: proc(c: ^ui.Context, name: string, size: ui.Vec2, layout: ui.Layout) -> bool {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Grow()}, direction = .TOP_TO_BOTTOM, align = {x = .CENTER, y = .CENTER}}})
    inner: ui.Layout = layout
    inner.size = {ui.Fixed(size.x), ui.Fixed(size.y)}
    ui.ElementOpen(c, {id = ui.UiId(c, name), layout = inner, hit = {.BLOCKER}, draw = {kind = .PANEL, name = name}})
    return true
}

stageEnd :: proc(c: ^ui.Context, name: string, size: ui.Vec2, layout: ui.Layout) {
    ui.ElementClose(c)
    ui.ElementClose(c)
}

// 01_hello: a heading, a count, and minus, Reset and plus
hello :: proc(c: ^ui.Context) {
    if stage(c, "hello", {480, 320}, {direction = .TOP_TO_BOTTOM, gap = 16, padding = ui.PaddingAll(32), align = {x = .CENTER, y = .CENTER}}) {
        ui.UiTitle(c, "Hello, Baldr", 1.9)
        ui.UiPushTag(c, "dim")
        ui.UiTitle(c, ui.UiFormat(c, "Count: %d", state.count), 1.4)
        ui.UiPopTag(c)
        ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 12}})
        if ui.UiTagged(c, "secondary") {
            if ui.UiButton(c, "##minus", icon = ui_default.LucideIcon(.MINUS)) { state.count -= 1 }
        }
        if ui.UiTagged(c, "outline") {
            if ui.UiButton(c, "Reset", disabled = state.count == 0) { state.count = 0 }
        }
        if ui.UiTagged(c, "primary") {
            if ui.UiButton(c, "##plus", icon = ui_default.LucideIcon(.PLUS)) { state.count += 1 }
        }
        ui.ElementClose(c)
    }
}

// 04_controls: every value is the state of the program, the widgets change it in place
controls :: proc(c: ^ui.Context) {
    if stage(c, "controls", {520, 480}, {direction = .TOP_TO_BOTTOM, gap = 16, padding = ui.PaddingAll(24)}) {
        ui.UiTitle(c, "Settings", 1.6)
        if ui.UiTagged(c, "flat") {
            if ui.UiCard(c, "Account") {
                ui.UiToggle(c, "Remember me on this device", &state.remember)
                ui.UiToggle(c, "Email me about new releases", &state.notify)
                ui.UiToggle(c, "Two-factor (managed by your organisation)", &state.two_factor, disabled = true)
            }
            if ui.UiCard(c, "Appearance") {
                ui.UiSwitch(c, "Dark theme", &state.dark)
                if row(c) {
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(72), ui.Fit()}}})
                    ui.UiLabelDim(c, "Text size")
                    ui.ElementClose(c)
                    if ui.UiTagged(c, "thin") {
                        if ui.UiSlider(c, "##size", &state.size, 12, 24, {ui.Grow(), {}}) { state.size = f32(int(state.size + 0.5)) }
                    }
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(52), ui.Fit()}, direction = .LEFT_TO_RIGHT, align = {x = .RIGHT}}})
                    ui.UiLabelf(c, "%.0f px", state.size)
                    ui.ElementClose(c)
                }
                if row(c) {
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(72), ui.Fit()}}})
                    ui.UiLabelDim(c, "Volume")
                    ui.ElementClose(c)
                    if ui.UiTagged(c, "thin") { ui.UiSlider(c, "##volume", &state.volume, 0, 1, {ui.Grow(), {}}) }
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(52), ui.Fit()}, direction = .LEFT_TO_RIGHT, align = {x = .RIGHT}}})
                    ui.UiLabelf(c, "%d%%", int(state.volume * 100 + 0.5))
                    ui.ElementClose(c)
                }
            }
        }
        if ui.UiTagged(c, "outline") {
            if ui.UiButton(c, "Reset") { controlsReset() }
        }
    }
}

// 03_scroll: forty cards in a region of a fixed height
scroll :: proc(c: ^ui.Context) {
    if stage(c, "scroll", {560, 480}, {direction = .TOP_TO_BOTTOM, gap = 16, padding = ui.PaddingAll(24)}) {
        if row(c) {
            ui.UiTitle(c, "Inbox", 1.6)
            ui.UiSpacer(c, {ui.Grow(), ui.Fixed(1)})
            ui.UiLabelDim(c, ui.UiFormat(c, "%d picked", state.picked))
            if ui.UiTagged(c, "outline") {
                if ui.UiButton(c, "Clear", disabled = state.picked == 0) { state.picked = 0 }
            }
        }
        state.messages_id = ui.UiId(c, "##messages")
        if ui.UiScroll(c, "##messages", {ui.Grow(), ui.Grow()}, {direction = .TOP_TO_BOTTOM, gap = 8, padding = {0, 12, 0, 0}}) {
            theme: ^ui_default.Theme = &state.app.painter.theme
            for i in 0 ..< MESSAGES {
                ui.ElementOpen(c, {
                    id = ui.IdFromIndex(u32(i), ui.UiId(c, "message")),
                    layout = {size = {ui.Grow(), ui.Fit()}, direction = .TOP_TO_BOTTOM, gap = 4, padding = ui.PaddingAll(12)},
                    draw = {kind = .PANEL},
                })
                if row(c) {
                    // a dot: every third message is unread
                    ui.ElementOpen(c, {layout = {size = {ui.Fixed(10), ui.Fixed(10)}}, draw = {kind = .AVATAR, color = theme.accent if i % 3 == 0 else theme.border}})
                    ui.ElementClose(c)
                    ui.UiTitle(c, ui.UiFormat(c, "Message %d - build finished", i + 1), 1.1)
                    ui.UiSpacer(c, {ui.Grow(), ui.Fixed(1)})
                    if ui.UiTagged(c, "ghost") {
                        if i == 1 { state.pick_id = ui.UiId(c, "Pick##1") }
                        if ui.UiButton(c, ui.UiFormat(c, "Pick##%d", i)) { state.picked += 1 }
                    }
                }
                ui.UiLabelDim(c, "All 55 headless tests passed. The Wayland and Win32 backends both presented the counter.", .WORDS)
                ui.ElementClose(c)
            }
        }
    }
}

// 17_toasts: cards at the top right, each one gone with a click. The original closes its program with the last one; here a button brings them back.
toasts :: proc(c: ^ui.Context, screen: ui.Vec2) {
    if stage(c, "toasts", {420, 160}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(24), align = {x = .CENTER, y = .CENTER}}) {
        left: int
        for shown in state.toasts {
            if shown { left += 1 }
        }
        ui.UiLabelDim(c, ui.UiFormat(c, "%d toasts at the top right: a click takes one away", left))
        if ui.UiTagged(c, "outline") {
            if ui.UiButton(c, "Show them again", disabled = left == len(state.toasts)) { state.toasts = {true, true, true} }
        }
    }
    y: f32 = 64
    for title, i in TOASTS {
        if !state.toasts[i] { continue }
        id: ui.Id = ui.IdFromIndex(u32(i), ui.UiId(c, "toast"))
        if ui.UiInteract(c, id).clicked { state.toasts[i] = false }
        ui.UiPushTag(c, "popup")
        ui.ElementOpen(c, {
            id = id,
            layout = {size = {ui.Fixed(370), ui.Fixed(72)}, direction = .TOP_TO_BOTTOM, gap = 2, padding = ui.PaddingAll(12), align = {y = .CENTER}},
            floating = {attach_to = .ROOT, offset = {screen.x - 370 - 16, y}, z_index = 10},
            hit = {.INTERACTIVE, .BLOCKER},
            draw = {kind = .PANEL, name = title},
        })
        ui.UiPopTag(c)
        ui.UiTitle(c, title, 1)
        ui.UiLabelDim(c, "Click to dismiss")
        ui.ElementClose(c)
        y += 80
    }
}

downloadStart :: proc(download: ^Download) {
    if download.running { return }
    download.got, download.seconds, download.cancelled, download.running = 0, 0, false, true
}

downloadStatus :: proc(c: ^ui.Context, download: Download) -> string {
    megabytes: f32 = download.size / 1e6
    switch {
    case download.running:
        return ui.UiFormat(c, "%.1f of %.1f MB, %.1f MB/s", download.got / 1e6, megabytes, download.got / 1e6 / max(download.seconds, 0.001))
    case download.cancelled:
        return ui.UiFormat(c, "Cancelled at %.1f of %.1f MB", download.got / 1e6, megabytes)
    case download.got == download.size && download.size > 0:
        return ui.UiFormat(c, "Done in %.1f s", download.seconds)
    }
    return ui.UiFormat(c, "%.1f MB", megabytes)
}

// 09_jobs: three downloads. The work goes on while the page is drawn and used: a button counts clicks to show it.
jobs :: proc(c: ^ui.Context, delta_time: f32) {
    for &download in state.downloads {
        if !download.running { continue }
        download.seconds += delta_time
        download.got = min(download.got + DOWNLOAD_RATE * delta_time, download.size)
        if download.got >= download.size { download.running = false }
    }
    if stage(c, "jobs", {560, 460}, {direction = .TOP_TO_BOTTOM, gap = 14, padding = ui.PaddingAll(24)}) {
        ui.UiTitle(c, "Downloads", 1.6)
        ui.UiLabelDim(c, "Each transfer goes on while the page is drawn; the page never waits.", .WORDS)
        if ui.UiTagged(c, "flat") {
            for &download, i in state.downloads {
                ui.ElementOpen(c, {
                    id = ui.IdFromIndex(u32(i), ui.UiId(c, "download")),
                    layout = {size = {ui.Grow(), ui.Fit()}, direction = .TOP_TO_BOTTOM, gap = 8, padding = ui.PaddingAll(12)},
                    draw = {kind = .PANEL},
                })
                if row(c) {
                    ui.UiTitle(c, download.name, 1.05)
                    ui.UiSpacer(c, {ui.Grow(), ui.Fixed(1)})
                    ui.UiLabelDim(c, downloadStatus(c, download), scale = 0.9)
                    if download.running {
                        if ui.UiTagged(c, "outline") {
                            if ui.UiButton(c, ui.UiFormat(c, "Cancel##%d", i)) { download.running, download.cancelled = false, true }
                        }
                    } else if ui.UiTagged(c, "secondary") {
                        if ui.UiButton(c, ui.UiFormat(c, "%s##%d", "Download" if download.got == 0 else "Again", i)) { downloadStart(&download) }
                    }
                }
                if ui.UiTagged(c, "thin") { ui.UiProgress(c, ui.UiFormat(c, "##progress%d", i), download.got, 0, download.size, {ui.Grow(), {}}) }
                ui.ElementClose(c)
            }
        }
        if row(c) {
            if ui.UiTagged(c, "primary") {
                if ui.UiButton(c, "Download all") {
                    for &download in state.downloads { downloadStart(&download) }
                }
            }
            if ui.UiTagged(c, "outline") {
                if ui.UiButton(c, ui.UiFormat(c, "Clicked %d times: still responsive##bump", state.bumps)) { state.bumps += 1 }
            }
        }
    }
}

// 19_markdown: the source on the left, how it reads on the right. Every change of the text is on the right in the same frame: the view reads the text again each time.
markdown :: proc(c: ^ui.Context) {
    if stage(c, "markdown", {960, 560}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(20)}) {
        ui.UiTitle(c, "Markdown", 1.25)
        ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Grow()}, direction = .LEFT_TO_RIGHT, gap = 16}})
        state.source_id = ui.UiId(c, "Markdown source##note")
        // the source in the code face: its lines are measured in that face too, so they wrap where they are drawn
        if ui.UiTagged(c, "mono") { ui.UiTextArea(c, "Markdown source##note", state.note[:], &state.note_length, {ui.Percent(0.45), ui.Grow()}) }
        if ui.UiScroll(c, "##preview", {ui.Grow(), ui.Grow()}, {direction = .TOP_TO_BOTTOM, padding = {0, 14, 0, 0}}) {
            // a clicked link gives its address: a program opens it, here it is shown (it is a part of the note, so it is copied before the note changes)
            address, clicked := ui.UiMarkdown(c, string(state.note[:state.note_length]))
            if clicked { state.opened_length = copy(state.opened[:], address) }
            if state.opened_length > 0 { ui.UiLabelDim(c, ui.UiFormat(c, "Link clicked: %s", string(state.opened[:state.opened_length]))) }
        }
        ui.ElementClose(c)
    }
}

// 32_chat with the bubbles of 29_styled_text: messages as bubbles that are as wide as their text, with styles inside (the marks of Markdown), in a list that
// stays at its newest message. The messages are in fixed storage: when it is full the oldest one goes.
CHAT_MESSAGES :: 24
MESSAGE_TEXT :: 160
Message :: struct {
    mine: bool,
    text: [MESSAGE_TEXT]u8,
    length: int,
}
CHAT_SEED: [7]string = {
    "Did the **charts** land?",
    "Yes, with the *color blind safe* palette. Line, area, bar and scatter.",
    "And the date field?",
    "A popup with a month to pick from, `UiDateField`. The time field is a combo over the times of a day.",
    "Nice. What is left?",
    "The editor with syntax colors. A paragraph with **strong**, *italic*, `code` and [links](ui/README.md) is done, and it wraps inside of a bubble like this one.",
    "Send me a picture when it is in.",
}
CHAT_REPLIES: [3]string = {"Noted.", "I will look at *that* tomorrow.", "**Done**, see [the list](ui/TODO.md)."}

chat_add :: proc(text: string, mine: bool) {
    if state.message_count == CHAT_MESSAGES {
        copy(state.messages[:CHAT_MESSAGES - 1], state.messages[1:])
        state.message_count -= 1
    }
    message: ^Message = &state.messages[state.message_count]
    message.mine = mine
    message.length = copy(message.text[:], text)
    state.message_count += 1
    state.chat_follow = 3
}

chat :: proc(c: ^ui.Context) {
    if stage(c, "chat", {640, 440}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(20)}) {
        ui.UiTitle(c, "Chat", 1.25)
        list: ui.Id = ui.UiId(c, "##messages")
        state.chat_list = list
        list_rect, _ := ui.UiElementRect(c, list)
        // a bubble takes up to three quarters of the list (a guess before the list was laid out once)
        widest: f32 = max(list_rect.z, 560) * 0.72
        if state.chat_follow > 0 {
            ui.UiScrollSet(c, list, 1e9)
            state.chat_follow -= 1
        }
        if ui.UiScroll(c, "##messages", {ui.Grow(), ui.Grow()}, {direction = .TOP_TO_BOTTOM, gap = 8, padding = {0, 14, 0, 0}}) {
            for &message, i in state.messages[:state.message_count] {
                ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, align = {x = .RIGHT if message.mine else .LEFT}}})
                ui.UiPushTag(c, "bubble")
                if message.mine { ui.UiPushTag(c, "mine") }
                ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, padding = {12, 12, 8, 8}}, draw = {kind = .PANEL}})
                if message.mine { ui.UiPopTag(c) }
                ui.UiPopTag(c)
                ui.UiRichText(c, ui.UiFormat(c, "##message %d", i), string(message.text[:message.length]), 1, widest - 24)
                ui.ElementClose(c)
                ui.ElementClose(c)
            }
        }
        ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 8, align = {y = .CENTER}}})
        state.draft_id = ui.UiId(c, "Message##draft")
        _, submitted := ui.UiTextField(c, "Message##draft", state.draft[:], &state.draft_length, {ui.Grow(), {}})
        if ui.UiTagged(c, "primary") { submitted |= ui.UiButton(c, "Send", {}, state.draft_length == 0, ui_default.LucideIcon(.SEND)) }
        ui.ElementClose(c)
        if submitted && state.draft_length > 0 {
            chat_add(string(state.draft[:state.draft_length]), true)
            state.draft_length = 0
            // the other side answers at once: the page has no clock, so its script and its pictures are the same on every machine
            chat_add(CHAT_REPLIES[state.replies % len(CHAT_REPLIES)], false)
            state.replies += 1
        }
    }
}

// 33_reading: a page in colors of its own, its controls included. The window keeps its theme; the bar, the text and the buttons of the page are declared inside of
// a theme area (ui_default.ThemeAreaSet), so a button of the page hovers in the colors of the page.
PAPERS: [4]string = {"Paper", "Sepia", "Dusk", "Night"}
PAGES: [2]string = {
    "# On margins\n\nA page is read by its **edges** as much as by its words. The eye comes back to the left side of a line some thousands of times in an hour, and every time it has to find the next line; a margin is what it finds it by.\n\n> Sixty to seventy letters in a line: fewer and the eye turns too often, more and it loses the line.\n\nThe color of the paper is a part of it. *Sepia* takes the glare from a white page, a dark page at night keeps the room dark.",
    "# On type\n\nA text face is made to be forgotten. Its letters are a little wider and more open than the ones of a title, because at a small size the eye needs the room *inside* of the letters.\n\n- the size: what is read at an arm's length\n- the line: one and a half times the size\n- the measure: see the page before\n\nCode keeps its own face, `like this`, so that a name is seen as a name.",
}

reading_theme :: proc(paper: int) -> ui_default.Theme {
    theme: ui_default.Theme
    switch paper {
    case 0:
        theme = ui_default.ThemeFromAccent({37, 99, 235, 255}, false)
        theme.panel = {252, 252, 250, 255}
    case 1:
        theme = ui_default.ThemeFromAccent({176, 108, 44, 255}, false)
        theme.panel, theme.text, theme.text_dim = {244, 236, 216, 255}, {91, 70, 54, 255}, {138, 116, 96, 255}
    case 2:
        theme = ui_default.ThemeFromAccent({129, 140, 248, 255}, true)
        theme.panel, theme.text, theme.text_dim = {38, 40, 58, 255}, {214, 216, 236, 255}, {150, 154, 186, 255}
    case:
        theme = ui_default.ThemeFromAccent({217, 119, 6, 255}, true)
        theme.panel, theme.text, theme.text_dim = {6, 6, 8, 255}, {168, 168, 168, 255}, {110, 110, 110, 255}
    }
    return theme
}

reading :: proc(c: ^ui.Context) {
    if stage(c, "reading", {620, 520}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(20)}) {
        ui.UiTitle(c, "Reading", 1.25)
        if ui.UiTagged(c, ui_default.ThemeAreaTag(0)) {
            ui.UiPushTag(c, "flat")
            ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Grow()}, direction = .TOP_TO_BOTTOM, gap = 14, padding = {28, 28, 18, 18}}, draw = {kind = .PANEL}})
            ui.UiPopTag(c)
            ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 8, align = {y = .CENTER}}})
            ui.UiSegmented(c, "##paper", PAPERS[:], &state.paper)
            ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}}})
            ui.ElementClose(c)
            ui.UiLabelDim(c, ui.UiFormat(c, "Page %d of %d", state.page + 1, len(PAGES)))
            if ui.UiTagged(c, "ghost") {
                if ui.UiButton(c, "Previous", {}, state.page == 0) { state.page -= 1 }
                if ui.UiButton(c, "Next", {}, state.page == len(PAGES) - 1) { state.page += 1 }
            }
            ui.ElementClose(c)
            if ui.UiScroll(c, "##page", {ui.Grow(), ui.Grow()}, {direction = .TOP_TO_BOTTOM, padding = {0, 14, 0, 0}}) {
                ui.UiMarkdown(c, PAGES[state.page])
            }
            ui.ElementClose(c)
        }
    }
}

// 20_shortcuts: a shortcut is set by pressing it. A click on a row makes it listen; the next key with the modifiers that are held is written down. Escape lets
// go, Backspace takes the shortcut away. A shortcut that another action had is taken from that one: two actions never share one.
SHORTCUT_ACTIONS: [5]string = {"Save", "Open", "Find", "Toggle the sidebar", "Reload"}

shortcuts :: proc(c: ^ui.Context, input: ^kit.Input) {
    // the key that went down in this frame, in the numbers of the kit; a key that only is a modifier is no key of a shortcut
    pressed: ui.Chord = {modifiers = c.input.modifiers}
    for key in kit.Key {
        if key == .None || (key >= .LEFT_SHIFT && key <= .RIGHT_ALT) || key not_in input.keys_pressed { continue }
        pressed.key = u16(key)
        break
    }
    if stage(c, "shortcuts", {520, 400}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(24)}) {
        ui.UiTitle(c, "Shortcuts", 1.6)
        ui.UiLabelDim(c, "Click a shortcut and press the keys. Escape lets go, Backspace takes it away.", .WORDS)
        for action, i in SHORTCUT_ACTIONS {
            ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 12, align = {y = .CENTER}}})
            ui.UiLabel(c, action)
            ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}}})
            ui.ElementClose(c)
            name: string = ui.UiFormat(c, "##shortcut %d", i)
            state.chord_ids[i] = ui.UiId(c, name)
            changed, _ := ui.UiShortcutField(c, name, &state.chords[i], pressed, proc(key: u16) -> string { return reflect.enum_string(kit.Key(key)) }, {ui.Fixed(170), {}})
            if changed {
                state.chord_changes += 1
                for &other, k in state.chords {
                    if k != i && other == state.chords[i] { other = {} }
                }
            }
            ui.ElementClose(c)
        }
    }
}

// 07_code: an editor for code. It is the text area of the library with a highlighter: the words of every row in view are cut into spans and drawn in the
// colors of what they are, while the text is edited as any text.
CODE_SAMPLE :: `package counter

import "core:fmt"

/* Counts the words of a text.
   The longest one is kept. */
Counter :: struct {
    words: int,
    longest: string,
}

count :: proc(counter: ^Counter, text: string) -> int {
    start: int = -1
    for character, i in text {
        if character == ' ' {
            start = -1
            continue
        }
        if start < 0 {
            start = i
            counter.words += 1
        }
    }
    fmt.println("words:", counter.words, 0x10, 2.5)
    return counter.words
}`

code :: proc(c: ^ui.Context) {
    if stage(c, "code", {720, 560}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(20)}) {
        ui.UiTitle(c, "Code", 1.25)
        ui.UiLabelDim(c, "A text area with a highlighter for Odin. Type: the colors follow.", .WORDS)
        state.code_id = ui.UiId(c, "Source##code")
        if ui.UiTagged(c, "mono") {
            ui.UiTextArea(c, "Source##code", state.code[:], &state.code_length, {ui.Grow(), ui.Grow()}, false, false, ui.HighlightCode, &ui.HIGHLIGHT_ODIN)
        }
    }
}

// 37_custom: a widget of one's own. The library has no star rating: this one is made of what a widget of the library is made of. `UiInteract` gives it the
// pointer and the focus, an element with the draw kind CUSTOM and a proc of the program draws it with the painter in the colors of the theme, the arrows change
// it while it has the focus (UiNavBlock keeps them from moving the focus).
RATING_STAR :: 30

rating :: proc(c: ^ui.Context, name: string, value: ^int, stars: int = 5) -> (changed: bool) {
    id: ui.Id = ui.UiId(c, name)
    interaction: ui.Interaction = ui.UiInteract(c, id)
    // the stars up to the pointer are a preview of what a click gives
    preview: int
    if interaction.hovered { preview = clamp(int((c.input.mouse_position.x - interaction.rect.x) / RATING_STAR) + 1, 1, stars) }
    before: int = value^
    if interaction.clicked && preview > 0 { value^ = 0 if value^ == preview else preview }       // the same star again takes the rating away
    focused: bool = ui.UiIsFocused(c, id)
    if focused {
        if .LEFT in c.input.actions { value^ = max(value^ - 1, 0) }
        if .RIGHT in c.input.actions { value^ = min(value^ + 1, stars) }
    }
    ui.ElementOpen(c, {
        id = id,
        layout = {size = {ui.Fixed(f32(RATING_STAR * stars)), ui.Fixed(RATING_STAR)}},
        hit = {.INTERACTIVE},
        cursor = .HAND,
        draw = {kind = .CUSTOM, custom = rating_draw, name = ui.IdSplitName(name), actual = f32(value^), maximum = f32(stars), cursor = preview, flags = {.FOCUSED} if focused else {}},
    })
    ui.ElementClose(c)
    ui.UiNavBlock(c, .LEFT)
    ui.UiNavBlock(c, .RIGHT)
    return value^ != before
}

// The draw proc of the rating: `actual` stars are full, the ones up to `cursor` (the preview) are faint, the rest is the color of a track
rating_draw :: proc(c: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^ui_default.Painter = ui_default.PainterOf(c)
    theme: ^ui_default.Theme = &painter.theme
    for star in 0 ..< int(info.maximum) {
        color: ui.Color = theme.track_strong
        if star < int(info.actual) {
            color = theme.warning
        } else if star < info.cursor {
            color = ui.ColorLerp(theme.track_strong, theme.warning, 0.45)
        }
        // a star is ten triangles around its middle: a painter fills polygons that have no dents
        center: ui.Vec2 = {info.rect.x + (f32(star) + 0.5) * RATING_STAR, info.rect.y + info.rect.w * 0.5}
        corner :: proc(center: ui.Vec2, index: int) -> ui.Vec2 {
            radius: f32 = RATING_STAR * (0.42 if index % 2 == 0 else 0.18)
            angle: f32 = f32(index) * math.PI / 5 - math.PI / 2
            return {center.x + math.cos(angle) * radius, center.y + math.sin(angle) * radius}
        }
        for index in 0 ..< 10 {
            triangle: [3]ui.Vec2 = {center, corner(center, index), corner(center, index + 1)}
            painter.fill_polygon(painter, triangle[:], color)
        }
    }
    ui_default.FocusRing(painter, info)
}

custom :: proc(c: ^ui.Context) {
    if stage(c, "custom", {460, 300}, {direction = .TOP_TO_BOTTOM, gap = 14, padding = ui.PaddingAll(24)}) {
        ui.UiTitle(c, "A widget of your own", 1.6)
        ui.UiLabelDim(c, "A star rating that the library does not have: click a star, or use the arrows while it has the focus.", .WORDS)
        for label, i in ([2]string{"The food", "The service"}) {
            ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 12, align = {y = .CENTER}}})
            ui.ElementOpen(c, {layout = {size = {ui.Fixed(110), ui.Fit()}}})
            ui.UiLabel(c, label)
            ui.ElementClose(c)
            name: string = ui.UiFormat(c, "%s##rating", label)
            state.rating_ids[i] = ui.UiId(c, name)
            rating(c, name, &state.ratings[i])
            ui.UiLabelDim(c, ui.UiFormat(c, "%d of 5", state.ratings[i]) if state.ratings[i] > 0 else "not rated")
            ui.ElementClose(c)
        }
    }
}

// 34_mentions: a text whose @ offers the files of a project. The list opens under the caret, the letters after the @ narrow it, the arrows choose, Enter or a
// click writes the name in.
PROJECT_FILES: [8]string = {"context.odin", "layout.odin", "markdown.odin", "render.odin", "richtext.odin", "style.odin", "widgets.odin", "README.md"}

mentions :: proc(c: ^ui.Context) {
    if stage(c, "mentions", {560, 380}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(24)}) {
        ui.UiTitle(c, "Mentions", 1.6)
        ui.UiLabelDim(c, "Type @ and some letters of a file of the project.", .WORDS)
        state.mention_id = ui.UiId(c, "Message##mention")
        // before the area: the keys of the open list are its own
        inserted, item := ui.UiComplete(c, "Message##mention", state.mention[:], &state.mention_length, PROJECT_FILES[:])
        if inserted {
            state.mentions += 1
            state.mentioned = item
        }
        ui.UiTextArea(c, "Message##mention", state.mention[:], &state.mention_length, {ui.Grow(), ui.Fixed(140)})
        if state.mentioned >= 0 {
            ui.UiLabelDim(c, ui.UiFormat(c, "%d mentioned, the last one: %s", state.mentions, PROJECT_FILES[state.mentioned]))
        } else {
            ui.UiLabelDim(c, "Nothing is mentioned yet.")
        }
    }
}

// 21_charts: the same numbers as a line, an area, bars and a scatter. A click picks a point, the arrows walk the points when the chart has the focus; the value is read out.
charts :: proc(c: ^ui.Context) {
    if stage(c, "charts", {820, 520}, {direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(16)}) {
        ui.UiTitle(c, "Charts", 1.25)
        if row(c, 8) {
            for name, i in CHART_KINDS {
                ui.UiPushTag(c, "primary" if int(state.chart_kind) == i else "outline")
                if ui.UiButton(c, name) {
                    state.chart_kind = ui.ChartKind(i)
                    state.chart.picked.series = ui.CHART_NONE
                    state.chart_picked_length = 0
                }
                ui.UiPopTag(c)
            }
        }
        count: int = 2
        state.chart_series = {{name = "Sales", points = state.sales[:]}, {name = "Costs", points = state.costs[:]}}
        if state.chart_kind == .SCATTER {
            state.chart_series[0] = {name = "Orders", points = state.cloud[:]}
            count = 1
        }
        ui.UiPushTag(c, "flat")
        ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, padding = ui.PaddingAll(12)}, draw = {kind = .PANEL}})
        ui.UiPopTag(c)
        state.chart_id = ui.UiId(c, "Sales and costs by month")
        if hit, picked := ui.UiChart(c, "Sales and costs by month", &state.chart, state.chart_series[:count], state.chart_kind, MONTHS[:], {ui.Grow(), ui.Fixed(300)}); picked {
            text: string = fmt.bprintf(state.chart_picked[:], "%s: %.1f at %s", state.chart_series[hit.series].name, hit.value.y, MONTHS[int(hit.value.x) % 12])
            state.chart_picked_length = len(text)
        }
        ui.ElementClose(c)
        ui.UiLabelDim(c, string(state.chart_picked[:state.chart_picked_length]) if state.chart_picked_length > 0 else "Click a point, or focus the chart and use the arrow keys.")
    }
}

// 05_overlays: what lies over the page. The select, the tooltips and the menu keep their own state; the dialog is open while the program says so.
overlays :: proc(c: ^ui.Context) {
    if stage(c, "overlays", {640, 560}, {direction = .TOP_TO_BOTTOM, gap = 14, padding = ui.PaddingAll(24)}) {
        ui.UiTitle(c, "Overlays", 1.6)
        if ui.UiTagged(c, "flat") {
            if ui.UiCard(c, "Select") {
                if row(c) {
                    ui.UiLabelDim(c, "Favourite fruit")
                    ui.UiDropdown(c, "##fruit", FRUIT[:], &state.fruit, {ui.Fixed(220), {}})
                }
                ui.UiLabelDim(c, ui.UiFormat(c, "You picked %s.", FRUIT[state.fruit]), scale = 0.9)
            }
            if ui.UiCard(c, "Popover menu") {
                if row(c) {
                    ui.UiPushTag(c, "outline")
                    if ui.UiMenu(c, "Actions...") {
                        if ui.UiMenuItem(c, "Rename", "F2") { state.last = "Rename" }
                        state.duplicate_id = ui.UiId(c, "Duplicate")
                        if ui.UiMenuItem(c, "Duplicate", "Ctrl+D") { state.last = "Duplicate" }
                        ui.UiSeparator(c)
                        if ui.UiMenuItem(c, "Delete...", "Del") { state.confirm = true }
                    }
                    ui.UiPopTag(c)
                    ui.UiLabelDim(c, "Nothing chosen yet." if state.last == "" else ui.UiFormat(c, "Last: %s", state.last))
                }
            }
            if ui.UiCard(c, "Dialog") {
                if row(c) {
                    if ui.UiTagged(c, "danger") {
                        if ui.UiButton(c, "Delete file...") { state.confirm = true }
                    }
                    ui.UiTooltip(c, "Asks first: nothing is deleted without confirming")
                    ui.UiLabelDim(c, ui.UiFormat(c, "Deleted %d file(s).", state.deleted))
                }
            }
            if ui.UiCard(c, "Clickable card") {
                // the whole note takes a click, the cross in it keeps its own
                state.note_id = ui.UiId(c, "note")
                if ui.UiInteract(c, state.note_id).clicked { state.last = "Opened the message" }
                ui.ElementOpen(c, {
                    id = state.note_id,
                    layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 8, padding = ui.PaddingAll(12), align = {y = .CENTER}},
                    hit = {.INTERACTIVE},
                    draw = {kind = .SELECTABLE},
                })
                ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .TOP_TO_BOTTOM, gap = 2}})
                ui.UiTitle(c, "Ada", 1)
                ui.UiLabelDim(c, "Lunch at one?")
                ui.ElementClose(c)
                state.dismiss_id = ui.UiId(c, "##dismiss")
                if ui.UiTagged(c, "ghost") {
                    if ui.UiButton(c, "##dismiss", icon = .CLOSE) { state.last = "Dismissed the message" }
                }
                ui.ElementClose(c)
            }
        }
    }
    if ui.UiModal(c, "Delete this file?", &state.confirm, {ui.Fixed(380), {}}) {
        ui.UiTitle(c, "Delete this file?")
        ui.UiLabel(c, "The file is moved to the bin. You can restore it from there for 30 days.", .WORDS)
        if row(c, 8, .RIGHT) {
            if ui.UiTagged(c, "outline") {
                if ui.UiButton(c, "Cancel") { state.confirm = false }
            }
            if ui.UiTagged(c, "danger") {
                if ui.UiButton(c, "Delete") {
                    state.deleted += 1
                    state.confirm = false
                }
            }
        }
    }
}

// 02_theme_lab: the accent is picked by a tile or by its hue, the theme of the page is made from it (ui_default.ThemeFromAccent); a side bar, a card with every kind of
// button, chips, a field and a disabled button show what the theme does with them
themeLab :: proc(c: ^ui.Context) {
    theme: ^ui_default.Theme = &state.app.painter.theme
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Grow()}, direction = .LEFT_TO_RIGHT}})
    // the side bar: a well with the places of an app, the first one chosen
    ui.ElementOpen(c, {layout = {size = {ui.Fixed(200), ui.Grow()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(16), gap = 4}, draw = {kind = .MENU_BAR}})
    ui.UiTitle(c, "Baldr", 1.25)
    ui.UiSpacer(c, {ui.Grow(), ui.Fixed(12)})
    places: [4]string = {"Overview", "Projects", "Activity", "Settings"}
    for place, i in places { ui.UiSelectable(c, place, i == 0) }
    ui.ElementClose(c)

    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Grow()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(24), gap = 16}})
    ui.UiTitle(c, "Good evening, Alex", 1.6)
    ui.UiLabelDim(c, "Three builds finished while you were away. Everything is green.")
    if ui.UiCard(c, "Accent") {
        if row(c, 8) {
            for accent, i in ACCENTS {
                name: string = ui.UiFormat(c, "##accent%d", i)
                state.swatch_ids[i] = ui.UiId(c, name)
                if ui.UiColorButton(c, name, {f32(accent.r) / 255, f32(accent.g) / 255, f32(accent.b) / 255}, 32) {
                    state.accent = accent
                    _, _, state.hue = ui_default.ColorToOklch(accent)
                }
            }
            ui.UiSpacer(c, {ui.Grow(), ui.Fixed(1)})
            ui.UiSegmented(c, "##mode", MODES[:], &state.mode)
        }
        if row(c) {
            ui.UiLabelDim(c, "Hue")
            if ui.UiTagged(c, "thin") {
                // any hue: the accent is a vivid color of that hue, the theme gives it the lightness of its mode
                if ui.UiSlider(c, "##hue", &state.hue, 0, 360, {ui.Grow(), {}}) { state.accent = ui_default.ColorFromOklch(0.62, 0.19, state.hue) }
            }
            ui.ElementOpen(c, {layout = {size = {ui.Fixed(48), ui.Fit()}, direction = .LEFT_TO_RIGHT, align = {x = .RIGHT}}})
            ui.UiLabelf(c, "%.0f", state.hue)
            ui.ElementClose(c)
        }
    }
    if ui.UiCard(c, "Project Baldr") {
        ui.UiLabelDim(c, ui.UiFormat(c, "Retained-mode GUI for Odin. %d nudges so far.", state.nudges))
        if row(c, 8) {
            if ui.UiTagged(c, "primary") {
                if ui.UiButton(c, "Continue") { state.nudges += 1 }
            }
            if ui.UiTagged(c, "secondary") { ui.UiButton(c, "Preview") }
            if ui.UiTagged(c, "outline") { ui.UiButton(c, "Settings") }
            if ui.UiTagged(c, "ghost") { ui.UiButton(c, "Skip") }
            if ui.UiTagged(c, "danger") { ui.UiButton(c, "Delete project", disabled = true) }
        }
    }
    if row(c, 8) {
        ui.UiBadge(c, "Wayland")
        ui.UiBadge(c, "Vulkan", .ACCENT)
        ui.UiBadge(c, "Pure Odin", .SUCCESS)
        ui.UiChip(c, "Chosen", true)
        ui.UiChip(c, "Not chosen", false)
    }
    if row(c) {
        ui.UiTextField(c, "Search projects##search", state.search[:], &state.search_length, {ui.Fixed(280), {}})
        ui.UiSwitch(c, "##lab switch", &state.lab_switch)
        ui.UiSpinner(c)
        // what the generator made, to read off
        ui.UiSpacer(c, {ui.Grow(), ui.Fixed(1)})
        ui.UiPushTag(c, "mono")
        ui.UiLabelf(c, "accent %d %d %d", theme.accent.r, theme.accent.g, theme.accent.b)
        ui.UiPopTag(c)
    }
    ui.ElementClose(c)
    ui.ElementClose(c)
}

draw :: proc(ctx: ^kit.Context) {
    state.app.painter.theme = ui_default.THEME_DARK if state.dark else ui_default.THEME_LIGHT
    if state.example == 4 { state.app.painter.theme = ui_default.ThemeFromAccent(state.accent, state.mode == 0) }
    ui_default.ThemeAreaSet(&state.app.painter, 0, reading_theme(state.paper))
    ctx.background = kit.Color(state.app.painter.theme.background)
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    metrics: ^ui.Metrics = &c.style.metrics
    ui.ElementOpen(c, {layout = {size = {ui.Fixed(ctx.screen.x), ui.Fixed(ctx.screen.y)}, direction = .TOP_TO_BOTTOM}})
    ui.ElementOpen(c, {
        layout = {size = {ui.Grow(), ui.Fixed(metrics.control_height + 24)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(16, 0), gap = 16, align = {y = .CENTER}},
        draw = {kind = .MENU_BAR},
    })
    ui.UiTitle(c, "Baldr examples", 1.3)
    ui.UiTabBar(c, "##examples", EXAMPLES[:], &state.example)
    ui.ElementClose(c)
    switch state.example {
    case 0:
        hello(c)
    case 1:
        controls(c)
    case 2:
        scroll(c)
    case 3:
        toasts(c, ctx.screen)
    case 4:
        themeLab(c)
    case 5:
        overlays(c)
    case 6:
        charts(c)
    case 7:
        jobs(c, ctx.delta_time)
    case 8:
        markdown(c)
    case 9:
        chat(c)
    case 10:
        reading(c)
    case 11:
        shortcuts(c, &ctx.input)
    case 12:
        code(c)
    case 13:
        custom(c)
    case 14:
        mentions(c)
    }
    ui.ElementClose(c)
    ui_demo_end(&state.app)
}

// The script finds the widgets by where they were in the last frame: the pages are laid out by the widths of their texts
target: ui.Vec2

// `target` is the middle of the shortcut field of a row
chord_target :: proc(row: int) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, state.chord_ids[row])
    target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return found
}

// Something of a kind with a name was drawn in the last frame: `target` is its middle
drawn :: proc(kind: ui.StyleKind, name: string) -> bool {
    for command in ui.UiCommands(&state.app.ctx) {
        info: ui.DrawInfo = command.info
        if command.kind == .DRAW && info.kind == kind && (info.name == name || info.text == name) {
            target = {info.rect.x + info.rect.z * 0.5, info.rect.y + info.rect.w * 0.5}
            return true
        }
    }
    return false
}

// A line of text was drawn in the last frame, with a tag ("" for any)
shown :: proc(text: string, tag: string) -> bool {
    for command in ui.UiCommands(&state.app.ctx) {
        info: ui.DrawInfo = command.info
        if command.kind == .DRAW && info.kind == .LABEL && info.text == text && (tag == "" || ui.DrawInfoHasTag(&info, tag)) { return true }
    }
    return false
}

aim :: proc(id: ui.Id) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, id)
    target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return found && rect.z > 0
}

tab :: proc(index: u32) -> bool {
    return aim(ui.IdFromIndex(index, ui.UiId(&state.app.ctx, "##examples")))
}

script: []kit.Step = {
    kit.Wait(4),
    // hello: plus twice, minus once, reset
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("hello", "##plus")) }, "the plus button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.count == 2 }, "two clicks on plus count to 2"),
    kit.MoveTo({640, 700}),
    kit.Wait(3),
    kit.Capture("examples_hello"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("hello", "##minus")) }, "the minus button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.count == 1 }, "minus takes one away"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("hello", "Reset")) }, "the Reset button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.count == 0 }, "Reset sets the count to 0"),

    // controls: a check box, the switch (the theme of the page follows it), a slider, Reset
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(1) }, "the Controls tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("controls", "Account", "Remember me on this device")) }, "the first check box is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.remember }, "the check box was ticked"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("controls", "Account", "Two-factor (managed by your organisation)")) }, "the disabled check box is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.two_factor }, "a disabled check box does not take a click"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, ui.UiIdPath("controls", "Appearance", "##volume"))
        target = {rect.x + rect.z * 0.75, rect.y + rect.w * 0.5}
        return found
    }, "the volume slider is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(state.volume - 0.75) < 0.06 }, "a click at three quarters of the slider sets it there"),
    kit.MoveTo({640, 700}),
    kit.Wait(3),
    kit.Capture("examples_controls"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("controls", "Appearance", "Dark theme")) }, "the switch is on the page"),
    kit.ClickAt(&target),
    kit.Wait(12),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.dark && !state.app.painter.theme.dark }, "the switch turned the page to the light theme"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("controls", "Reset")) }, "the Reset button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.dark && !state.remember && state.volume == 0.4 }, "Reset puts every value back"),

    // scroll: a pick, then the wheel
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(2) }, "the Scroll tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(state.pick_id) }, "the Pick button of the second card is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.picked == 1 }, "a pick was counted"),
    kit.Scroll(-3),
    kit.Wait(6),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiScrollGet(&state.app.ctx, state.messages_id) > 10 }, "the wheel scrolls the list"),
    kit.MoveTo({640, 700}),
    kit.Wait(3),
    kit.Capture("examples_scroll"),
    kit.Wait(2),

    // toasts: one goes with a click, the button brings it back
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(3) }, "the Toasts tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Capture("examples_toasts"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.IdFromIndex(1, ui.UiId(&state.app.ctx, "toast"))) }, "the second toast is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.toasts == [3]bool{true, false, true} }, "a click took the second toast away"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("toasts", "Show them again")) }, "the button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.toasts == [3]bool{true, true, true} }, "the toasts are back"),

    // theme lab: the page is in the blue of the style, a tile makes it green, the other mode makes it light
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(4) }, "the Theme lab tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.app.painter.theme.accent == ui_default.THEME_DARK.accent }, "the blue tile gives the dark theme of the style"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(state.swatch_ids[2]) }, "the green tile is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        accent: ui.Color = state.app.painter.theme.accent
        _, _, hue := ui_default.ColorToOklch(accent)
        return accent.g > accent.r && accent.g > accent.b && abs(hue - state.hue) < 12 && state.app.painter.theme.dark
    }, "the green tile makes a green dark theme"),
    kit.MoveTo({640, 700}),
    kit.Wait(3),
    kit.Capture("examples_theme_green"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.IdFromIndex(1, ui.UiIdPath("Accent", "##mode"))) }, "the Light segment is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.app.painter.theme.dark && state.app.painter.theme.panel.r > 240 }, "the other segment makes the theme light"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(state.swatch_ids[4]) }, "the violet tile is on the page"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(4),
    kit.Capture("examples_theme_violet_light"),
    kit.Wait(2),

    // overlays: the menu from its button, the card and its cross, the dialog
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        state.mode, state.accent = 0, ACCENTS[3]
        return tab(5)
    }, "the Overlays tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("overlays", "Popover menu", "Actions...")) }, "the button of the menu is on the page"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(state.duplicate_id) }, "the menu is open: its Duplicate entry is on the screen"),
    kit.MoveTo({900, 650}),
    kit.Wait(3),
    kit.Capture("examples_overlays_menu"),
    kit.Wait(2),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.last == "Duplicate" }, "the entry of the menu was used"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        _, open := ui.UiElementRect(&state.app.ctx, state.duplicate_id)
        return !open
    }, "using an entry closes the menu"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, state.note_id)
        target = {rect.x + 40, rect.y + rect.w * 0.5}
        return found
    }, "the note is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.last == "Opened the message" }, "a click on the note opens the message"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(state.dismiss_id) }, "the cross of the note is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.last == "Dismissed the message" }, "the cross keeps its own click"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("overlays", "Dialog", "Delete file...")) }, "the Delete file button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.confirm && state.deleted == 0 }, "the dialog asks first"),
    kit.MoveTo({900, 650}),
    kit.Wait(3),
    kit.Capture("examples_overlays_dialog"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("Delete this file?", "Delete")) }, "the Delete button of the dialog is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.confirm && state.deleted == 1 }, "Delete in the dialog deletes and closes it"),

    // charts: a point of the line is picked by a click and the arrows walk on, then the bars
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(6) }, "the Charts tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, state.chart_id)
        plot: ui.Rect = ui.ChartPlotRect(&state.chart, rect, state.app.ctx.style.metrics.font_size)
        target = ui.ChartPosition(&state.chart, plot, state.sales[5])
        return found && rect.w == 300
    }, "the chart is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return state.chart.picked.series == 0 && state.chart.picked.point == 5 && string(state.chart_picked[:state.chart_picked_length]) == fmt.tprintf("Sales: %.1f at Jun", state.sales[5].y)
    }, "a click on the June point of Sales picks it and its value is read out"),
    kit.Tap(.RIGHT),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.chart.picked.point == 6 }, "the right arrow walks to July"),
    kit.MoveTo({640, 700}),
    kit.Wait(3),
    kit.Capture("examples_charts_line"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("charts", "Bar")) }, "the Bar button is on the page"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.chart_kind == .BAR && state.chart.low.y == 0 }, "the bars stand on 0"),
    kit.Capture("examples_charts_bar"),
    kit.Wait(2),

    // jobs: all three start, the small one is done at once, the page takes clicks meanwhile, the big one is cancelled
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(7) }, "the Jobs tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("jobs", "Download all")) }, "the Download all button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.downloads[0].running && state.downloads[1].running }, "the downloads are running"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("jobs", "Clicked 0 times: still responsive##bump")) }, "the counting button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(8),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        small: Download = state.downloads[2]
        return state.bumps == 1 && !small.running && small.got == small.size && state.downloads[0].got > 0
    }, "the page took a click while the downloads went on, and the small file is done"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        // the Cancel button of the first download, found by its place in the last frame
        return aim(ui.IdFromString("Cancel##0", ui.IdFromIndex(0, ui.IdFromString("download", ui.UiIdPath("jobs")))))
    }, "the first download has a Cancel button while it runs"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        first: Download = state.downloads[0]
        return !first.running && first.cancelled && first.got > 0 && first.got < first.size
    }, "Cancel stops the first download where it was"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        // the pictures are taken with the same numbers on every machine: the second download is put at a half
        state.downloads[1].got, state.downloads[1].seconds, state.downloads[1].running = 4_750_000, 1, false
        state.downloads[1].cancelled = true
        state.downloads[0].got = 6_000_000
        state.downloads[2].seconds = 0.1          // how long the small file took depends on the frames of the machine
        return true
    }, "fixed numbers for the picture"),
    kit.MoveTo({640, 700}),
    kit.Wait(3),
    kit.Capture("examples_jobs"),
    kit.Wait(2),

    // markdown: the note is shown as titles, a list and a code block; what is typed into the source is on the right at once
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(8) }, "the Markdown tab is in the bar"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shown("Release notes", "title") && shown("write Markdown", "") && shown("ui.UiMarkdown(&ctx, source)", "mono") }, "the note is shown as a title, a list and code"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shown("Shown as", "strong") && shown("# Title", "mono") && shown("a table", "") }, "the table has its header and its cells"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shown("look", "strong") && shown("Baldr", "italic") && shown("the README", "link") }, "the marks inside of a paragraph are styles"),
    kit.Capture("examples_markdown"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, state.source_id)
        target = {rect.x + rect.z * 0.5, rect.y + rect.w - 12}
        return found
    }, "the source is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Tap(.END),
    kit.Type(" Typed."),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shown(". Typed.", "") }, "what is typed into the source is read on the right"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        for command in ui.UiCommands(&state.app.ctx) {
            info: ui.DrawInfo = command.info
            if command.kind == .DRAW && info.kind == .LABEL && info.text == "the README" && ui.DrawInfoHasTag(&info, "link") {
                target = {info.rect.x + info.rect.z * 0.5, info.rect.y + info.rect.w * 0.5}
                return true
            }
        }
        return false
    }, "the link is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.opened[:state.opened_length]) == "ui/README.md" && shown("Link clicked: ui/README.md", "dim") }, "a clicked link gives its address"),

    // chat: bubbles with styles inside, the list at its newest message; a sent message and its answer are added and the list follows
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(9) }, "the Chat tab is in the bar"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shown("Send me a picture when it is in.", "") && shown("links", "link") }, "the newest message is in view, with the styles of the one before"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiScrollGet(&state.app.ctx, state.chat_list) > 0 }, "the list is at its end"),
    kit.Capture("examples_chat"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, state.draft_id)
        target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
        return found
    }, "the field is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Type("On *it*."),
    kit.Tap(.ENTER),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.message_count == len(CHAT_SEED) + 2 && state.draft_length == 0 }, "the message and its answer are added, the field is empty"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shown("it", "italic") && shown("Noted.", "") }, "both are in view: the list followed"),

    // reading: the page has a theme of its own inside of the window; another paper and the next page
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(10) }, "the Reading tab is in the bar"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shown("On margins", "title") && shown("Page 1 of 2", "dim") }, "the first page is shown"),
    kit.Capture("examples_reading"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return drawn(.SEGMENT, "Night") }, "the papers are in the bar of the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.paper == 3 && state.app.painter.areas[0].panel.r < 20 && !state.app.painter.theme.dark == !state.dark }, "the page is dark, the window kept its theme"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return drawn(.BUTTON, "Next") }, "the buttons of the page"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.page == 1 && shown("On type", "title") && shown("like this", "mono") }, "the next page is shown"),
    kit.Capture("examples_reading_night"),
    kit.Wait(2),

    // shortcuts: a row listens after a click and takes the next key; a shortcut another row had is taken from it; Backspace takes one away
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(11) }, "the Shortcuts tab is in the bar"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return drawn(.BUTTON, "Ctrl+S") && drawn(.BUTTON, "Ctrl+Shift+B") && drawn(.BUTTON, ui.SHORTCUT_NONE) }, "the shortcuts are written as their keys"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return chord_target(4) }, "the row of Reload"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return drawn(.BUTTON, ui.SHORTCUT_LISTENING) }, "the row listens"),
    kit.Capture("examples_shortcuts"),
    kit.Wait(2),
    kit.Tap(.F5),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.chords[4] == ui.Chord{{}, u16(kit.Key.F5)} && drawn(.BUTTON, "F5") }, "the key that was pressed is the shortcut"),
    // the same key for another action: the first one loses it
    kit.Check(proc(ctx: ^kit.Context) -> bool { return chord_target(2) }, "the row of Find"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Tap(.F5),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.chords[2].key == u16(kit.Key.F5) && state.chords[4] == ui.Chord{} }, "a shortcut belongs to one action"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return chord_target(0) }, "the row of Save"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Tap(.BACKSPACE),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.chords[0] == ui.Chord{} && state.chord_changes == 3 }, "Backspace takes the shortcut away"),

    // code: the words of the rows are drawn by what they are; what is typed is colored in the same frame
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(12) }, "the Code tab is in the bar"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return shown("package", ui.SYNTAX_KEYWORD) && shown("   The longest one is kept. */", ui.SYNTAX_COMMENT) && shown("\"core:fmt\"", ui.SYNTAX_STRING) && shown("0x10", ui.SYNTAX_NUMBER) && shown("string", ui.SYNTAX_TYPE)
    }, "keywords, comments, strings, numbers and types have their tags"),
    kit.Capture("examples_code"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, state.code_id)
        target = {rect.x + rect.z * 0.5, rect.y + rect.w - 12}
        return found
    }, "the editor is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Tap(.END),
    kit.Type(" // typed"),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shown("// typed", ui.SYNTAX_COMMENT) }, "what is typed is a comment at once"),

    // custom: a star rating made in the demo; a click on a star rates, the arrows change it while it has the focus
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(13) }, "the Custom tab is in the bar"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shown("3 of 5", "dim") && shown("not rated", "dim") }, "the ratings are shown"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, state.rating_ids[1])
        target = {rect.x + RATING_STAR * 3.5, rect.y + rect.w * 0.5}
        return found
    }, "the rating of the service is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.ratings[1] == 4 }, "a click on the fourth star rates four"),
    kit.MoveTo({640, 700}),
    kit.Tap(.RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.ratings[1] == 5 && ui.UiIsFocused(&state.app.ctx, state.rating_ids[1]) }, "the arrow adds a star and the focus stays"),
    kit.Capture("examples_custom"),
    kit.Wait(2),
    kit.Tap(.LEFT),
    kit.Tap(.LEFT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.ratings[1] == 3 && state.ratings[0] == 3 }, "the other arrow takes stars away"),

    // mentions: the list opens at the @, the letters narrow it, the arrow chooses, Enter writes the name in
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab(14) }, "the Mentions tab is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, state.mention_id)
        target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
        return found
    }, "the text is on the page"),
    kit.ClickAt(&target),
    kit.MoveTo({640, 700}),
    kit.Wait(2),
    kit.Type("Look at @r"),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return drawn(.DROPDOWN_ITEM, "render.odin") && drawn(.DROPDOWN_ITEM, "README.md") && !drawn(.DROPDOWN_ITEM, "layout.odin") }, "the files with the letter are offered"),
    kit.Tap(.DOWN),
    kit.Wait(2),
    kit.Capture("examples_mentions"),
    kit.Wait(2),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.mention[:state.mention_length]) == "Look at @render.odin " && state.mentions == 1 }, "Enter writes the chosen name in"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !drawn(.DROPDOWN_ITEM, "render.odin") && shown("1 mentioned, the last one: render.odin", "dim") }, "the list is closed"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
