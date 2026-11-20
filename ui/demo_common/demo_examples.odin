#+private file
package demo_common

// Nine examples of Baldr (https://github.com/BuLEEto/Baldr, by Lee Fry and the Baldr contributors, zlib License) made again with this library, one per tab:
// 01_hello (a counter), 04_controls (check boxes, a switch and sliders bound to a state), 03_scroll (a list of cards that scrolls) and 17_toasts (cards at the top right
// that a click takes away), 02_theme_lab (a page of widgets to judge a theme by; here the theme is made from an accent that is picked on the page) 05_overlays (a select,
// a menu that opens from a button, tooltips, a card that takes a click, a dialog) 21_charts (the same numbers as a line, an area, bars and a scatter) and 09_jobs (three downloads with their progress while the page stays live; the original runs each on
// a thread that posts messages, here a download is a number that grows with the time of the frame) and 19_markdown (a text in Markdown and how it reads, side by side;
// the original is an editor that shows the styles while one types, here the source is a plain text area and ui.UiMarkdown shows it). The texts and the sample data are the ones of the originals. There a `view` builds a tree and an `update` answers messages; here the page is
// declared every frame and a widget hands back what happened: the counter is `if ui.UiButton(...) { count += 1 }`.

import "core:fmt"
import "core:math"
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

EXAMPLES: [9]string = {"Hello", "Controls", "Scroll", "Toasts", "Theme lab", "Overlays", "Charts", "Jobs", "Markdown"}
NOTE :: "# Release notes\n\nThe **look** of the ui follows *Baldr*: its themes, its typeface, its icons.\n\n## What is new\n- a theme from one accent color\n- charts and a date field\n  - with a month to pick from\n1. write Markdown\n2. read it on the right\n\n> Quotes are dim, with a bar.\n\n```\nui.UiMarkdown(&ctx, source)\n```\n\n---\nSee [the README](ui/README.md)."
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
            ui.UiMarkdown(c, string(state.note[:state.note_length]))
        }
        ui.ElementClose(c)
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
    }
    ui.ElementClose(c)
    ui_demo_end(&state.app)
}

// The script finds the widgets by where they were in the last frame: the pages are laid out by the widths of their texts
target: ui.Vec2

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
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
