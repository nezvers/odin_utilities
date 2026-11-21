#+private file
package demo_common

// The gallery: the first page of the gallery of Baldr (https://github.com/BuLEEto/Baldr, examples/00_gallery, by Lee Fry and the Baldr contributors, zlib License) made
// again with this library. Baldr is a retained toolkit (a view builds a tree, messages change a state); here the same page is immediate mode: every frame declares the
// widgets and reads what they gave back. The cards, their order and their sample data are the ones of the original, so the two can be put next to each other; what this
// library does not do (frosted glass: the blur of what is behind a card) is left out.
//
// The second page shows every icon of the icons library with its name.

import ui ".."
import ui_default "../default_style"
import ui_kit "../kit"
import kit "../../demo_kit"
import icons "../../icons"

@(private="package")
demo_gallery: kit.Demo = {
    name = "baldr gallery",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    storage: ui.Storage(3072, 6144, 512, 49152),
    ctx: ui.Context,
    painter: ui_default.Painter,
    style: ui.Style,
    page: int,
    theme: int,                     // 0 dark, 1 light
    // buttons
    saves: int,
    bold, italic, underline: bool,
    // inputs
    name: [48]u8,
    name_length: int,
    password: [48]u8,
    password_length: int,
    filter: [48]u8,
    filter_length: int,
    copies: int,
    volume: f32,
    remember: bool,
    notifications: bool,
    // choices
    fruit: int,
    plan: int,
    density: int,
    platforms: [4]bool,
    // date, time and colour
    due: ui.Date,
    alarm: int,                     // minutes after midnight
    accent: int,                    // which of ACCENTS
    // tags
    tags: [4]bool,                  // which of TAGS are still there
    what_open: bool,
    // menus
    last_action: string,
    confirm_open: bool,
    // project
    tree: ui.Tree,
    view: ui.TreeView,
    files_selected: int,
}

state: State

PAGES: [2]string = {"Overview", "Icons"}
THEMES: [2]string = {"Dark", "Light"}
FRUITS: [4]string = {"Apple", "Banana", "Cherry", "Damson"}
DENSITIES: [3]string = {"Compact", "Comfortable", "Spacious"}
PLATFORMS: [4]string = {"Wayland", "X11", "Windows", "macOS"}
TAGS: [4]string = {"odin", "vulkan", "wayland", "retained"}
CRUMBS: [3]string = {"baldr", "examples", "00_gallery"}
ACCENTS: [5]ui.Color = {{56, 129, 243, 255}, {34, 197, 94, 255}, {242, 181, 68, 255}, {229, 72, 77, 255}, {139, 92, 246, 255}}

File :: struct {
    name: string,
    kind: string,
    size: string,
    icon: icons.Icon,
}

FILES: [6]File = {
    {"Text-00000.txt", "Text", "1 KB", .FILE_TEXT},
    {"Image-00001.bin", "Image", "38 KB", .FILE_IMAGE},
    {"Folder-00002.bin", "Folder", "75 KB", .FOLDER},
    {"Archive-00003.bin", "Archive", "112 KB", .FILE_ARCHIVE},
    {"Audio-00004.bin", "Audio", "149 KB", .FILE_MUSIC},
    {"Video-00005.bin", "Video", "186 KB", .FILE_VIDEO_CAMERA},
}

LABEL_WIDTH :: 96
// the three columns of the page and what is around them
MARGIN :: 16
COLUMN_GAP :: 12

lucide :: ui_default.LucideIcon

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_kit.PainterInit(&state.painter)
    state.style = ui_default.StyleMake()
    ui.UiInit(&state.ctx, &state.storage, ui_default.Measure, &state.painter)
    ctx.background = kit.Color(state.painter.theme.background)

    state.name_length = copy(state.name[:], "Ada Lovelace")
    state.copies = 3
    state.volume = 0.4
    state.fruit = 2
    state.plan = 1
    state.density = 1
    state.platforms = {true, false, true, false}
    state.tags = {true, true, true, true}
    state.last_action = "Nothing chosen yet."
    state.due = {2026, 11, 12}
    state.alarm = 7 * 60 + 30
    state.files_selected = -1

    ui.TreeInit(&state.tree)
    ui.TreeViewInit(&state.view)
    root, _ := ui.TreeAdd(&state.tree, {}, "baldr", branch = true, icon = .FOLDER)
    ui.TreeAdd(&state.tree, root, "baldr", branch = true, icon = .FOLDER)
    ui.TreeAdd(&state.tree, root, "docs", branch = true, icon = .FOLDER)
    examples, _ := ui.TreeAdd(&state.tree, root, "examples", branch = true, icon = .FOLDER)
    ui.TreeAdd(&state.tree, examples, "00_gallery", branch = true, icon = .FOLDER)
    ui.TreeAdd(&state.tree, examples, "06_panel", branch = true, icon = .FOLDER)
    ui.TreeAdd(&state.tree, root, "gpu", branch = true, icon = .FOLDER)
    ui.TreeAdd(&state.tree, root, "README.md", icon = .TEXT)
    ui.TreeAdd(&state.tree, root, "build.sh", icon = lucide(.TERMINAL))
    ui.TreeExpand(&state.tree, root)
    ui.TreeExpand(&state.tree, examples)
}

// A row of a form: the name of a field in the dim color, then the field
@(deferred_in = fieldEnd)
field :: proc(c: ^ui.Context, name: string) -> bool {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 8, align = {y = .CENTER}}})
    ui.ElementOpen(c, {layout = {size = {ui.Fixed(LABEL_WIDTH), ui.Fit()}}})
    ui.UiLabelDim(c, name)
    ui.ElementClose(c)
    return true
}

fieldEnd :: proc(c: ^ui.Context, name: string) {
    ui.ElementClose(c)
}

@(deferred_in = rowEnd)
row :: proc(c: ^ui.Context, gap: f32 = 8) -> bool {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = gap, align = {y = .CENTER}}})
    return true
}

rowEnd :: proc(c: ^ui.Context, gap: f32 = 8) {
    ui.ElementClose(c)
}

@(deferred_in = columnEnd)
column :: proc(c: ^ui.Context) -> bool {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .TOP_TO_BOTTOM, gap = COLUMN_GAP}})
    return true
}

columnEnd :: proc(c: ^ui.Context) {
    ui.ElementClose(c)
}

cardButtons :: proc(c: ^ui.Context) {
    if ui.UiCard(c, "Buttons") {
        if row(c) {
            if ui.UiTagged(c, "primary") { ui.UiButton(c, "Primary") }
            if ui.UiTagged(c, "secondary") { ui.UiButton(c, "Secondary") }
            if ui.UiTagged(c, "outline") { ui.UiButton(c, "Outline") }
            if ui.UiTagged(c, "ghost") { ui.UiButton(c, "Ghost") }
            if ui.UiTagged(c, "danger") { ui.UiButton(c, "Danger") }
        }
        if row(c) {
            if ui.UiTagged(c, "primary") {
                if ui.UiButton(c, "Save", icon = lucide(.SAVE)) { state.saves += 1 }
            }
            if ui.UiTagged(c, "outline") { ui.UiButton(c, "Share", icon = lucide(.EXTERNAL_LINK)) }
            if ui.UiTagged(c, "secondary") { ui.UiButton(c, "Profile", icon = lucide(.USER)) }
            if ui.UiTagged(c, "outline") { ui.UiButton(c, "##settings", icon = lucide(.SETTINGS)) }
            if ui.UiTagged(c, "primary") { ui.UiButton(c, "Disabled", disabled = true) }
        }
        if row(c) {
            // three buttons that stay down: the tag follows the state
            marks: [3]^bool = {&state.bold, &state.italic, &state.underline}
            names: [3]string = {"##bold", "##italic", "##underline"}
            pictures: [3]icons.Icon = {.BOLD, .ITALIC, .UNDERLINE}
            for mark, i in marks {
                ui.UiPushTag(c, "primary" if mark^ else "")
                if ui.UiButton(c, names[i], icon = lucide(pictures[i])) { mark^ = !mark^ }
                ui.UiPopTag(c)
            }
        }
    }
}

cardInputs :: proc(c: ^ui.Context) {
    wide: ui.Size = {ui.Grow(), {}}
    if ui.UiCard(c, "Inputs") {
        if field(c, "Name") { ui.UiTextField(c, "Name##name", state.name[:], &state.name_length, wide) }
        if field(c, "Password") { ui.UiTextField(c, "Password##password", state.password[:], &state.password_length, wide) }
        if field(c, "Search") { ui.UiTextField(c, "Filter##filter", state.filter[:], &state.filter_length, wide) }
        if field(c, "Copies") { ui.UiInputInt(c, "##copies", &state.copies) }
        if field(c, "Volume") {
            if ui.UiTagged(c, "thin") { ui.UiSlider(c, "##volume", &state.volume, 0, 1, wide) }
        }
        if field(c, "Progress") {
            if ui.UiTagged(c, "thin") { ui.UiProgress(c, "##progress", state.volume, 0, 1, wide) }
            ui.UiSpinner(c)
        }
        ui.UiToggle(c, "Remember me on this device", &state.remember)
        ui.UiSwitch(c, "Notifications", &state.notifications)
    }
}

cardMenus :: proc(c: ^ui.Context) {
    if ui.UiCard(c, "Menus, tooltips and dialogs") {
        if row(c) {
            if ui.UiTagged(c, "outline") {
                if ui.UiButton(c, "Actions...", icon = lucide(.ELLIPSIS)) { state.last_action = "The actions were asked for." }
            }
            ui.UiTooltip(c, "A tooltip: what the button does")
            if ui.UiTagged(c, "secondary") {
                if ui.UiButton(c, "Show a toast", icon = lucide(.BELL)) { state.last_action = "A toast would say this." }
            }
            if ui.UiTagged(c, "danger") {
                if ui.UiButton(c, "Delete...", icon = lucide(.TRASH)) { state.confirm_open = true }
            }
        }
        ui.UiLabelDim(c, state.last_action, scale = 0.9)
    }
}

cardChoices :: proc(c: ^ui.Context) {
    if ui.UiCard(c, "Choices") {
        if field(c, "Fruit") { ui.UiDropdown(c, "##fruit", FRUITS[:], &state.fruit, {ui.Fixed(200), {}}) }
        if field(c, "Plan") {
            ui.UiRadio(c, "Free", &state.plan, 0)
            ui.UiRadio(c, "Pro", &state.plan, 1)
            ui.UiRadio(c, "Team", &state.plan, 2)
        }
        if field(c, "Density") { ui.UiSegmented(c, "##density", DENSITIES[:], &state.density) }
        if row(c, 6) {
            for name, i in PLATFORMS {
                if ui.UiChip(c, name, state.platforms[i]) { state.platforms[i] = !state.platforms[i] }
            }
        }
    }
}

cardDate :: proc(c: ^ui.Context) {
    if ui.UiCard(c, "Date, time and colour") {
        if field(c, "Due date") { ui.UiDateField(c, "##due", &state.due, {ui.Fixed(170), {}}) }
        if field(c, "Alarm") { ui.UiTimeField(c, "##alarm", &state.alarm, 30, {ui.Fixed(150), {}}) }
        if field(c, "Accent") {
            for accent, i in ACCENTS {
                if ui.UiColorButton(c, ui.UiFormat(c, "##accent%d", i), {f32(accent.r) / 255, f32(accent.g) / 255, f32(accent.b) / 255}, 26) { state.accent = i }
            }
            accent: ui.Color = ACCENTS[state.accent]
            ui.UiPushTag(c, "mono")
            ui.UiLabelf(c, "#%02x%02x%02x", accent.r, accent.g, accent.b)
            ui.UiPopTag(c)
        }
        ui.UiLabelDim(c, ui.UiFormat(c, "Due %d %s %d at %02d:%02d.", state.due.day, ui.DATE_MONTH_NAMES[clamp(state.due.month, 1, 12) - 1], state.due.year, state.alarm / 60, state.alarm % 60), scale = 0.9)
    }
}

cardProject :: proc(c: ^ui.Context) {
    if ui.UiCard(c, "Project") {
        ui.UiBreadcrumbs(c, "##crumbs", CRUMBS[:])
        ui.UiTree(c, "##project", &state.tree, &state.view, {ui.Grow(), ui.Fixed(264)})
    }
}

cardBadges :: proc(c: ^ui.Context) {
    if ui.UiCard(c, "Badges, avatars and tags") {
        if row(c, 6) {
            ui.UiBadge(c, "Neutral")
            ui.UiBadge(c, "12 new", .ACCENT)
            ui.UiBadge(c, "Passing", .SUCCESS)
            ui.UiBadge(c, "Slow", .WARNING)
            ui.UiBadge(c, "Failed", .DANGER)
        }
        if row(c) {
            ui.UiAvatar(c, "OU", {96, 165, 250, 255})
            ui.UiAvatar(c, "AL", {37, 99, 235, 255})
            ui.UiAvatar(c, "JS", {124, 58, 237, 255})
            ui.UiAvatar(c, "MK", {190, 18, 60, 255})
        }
        if row(c, 4) {
            for name, i in TAGS {
                if !state.tags[i] { continue }
                if _, removed := ui.UiTag(c, name, lucide(.STAR)); removed { state.tags[i] = false }
            }
        }
        if ui.UiCollapsing(c, "What these are for", tree = true) {
            ui.UiLabelDim(c, "Badges say a state in a word, avatars stand for people, tags can be taken away.", .WORDS, 0.9)
        }
    }
}

cardFiles :: proc(c: ^ui.Context) {
    metrics: ^ui.Metrics = &c.style.metrics
    if ui.UiCard(c, "Files") {
        cell :: proc(c: ^ui.Context, text: string, width: ui.SizingAxis, dim: bool, right: bool = false) {
            ui.ElementOpen(c, {layout = {size = {width, ui.Fit()}, direction = .LEFT_TO_RIGHT, align = {x = .RIGHT if right else .LEFT}}})
            if dim {
                ui.UiLabelDim(c, text)
            } else {
                ui.UiLabel(c, text)
            }
            ui.ElementClose(c)
        }
        // a table by hand: a header on the color of a well, then a row per file that can be chosen
        ui.UiPushTag(c, "flat")
        ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(1)}, draw = {kind = .PANEL}})
        ui.UiPopTag(c)
        ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fixed(metrics.control_height)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(10, 0), gap = 8, align = {y = .CENTER}}, draw = {kind = .MENU_BAR}})
        ui.UiPushTag(c, "title")
        cell(c, "Name", ui.Grow(), true)
        cell(c, "Kind", ui.Fixed(76), true)
        cell(c, "Size", ui.Fixed(64), true, true)
        ui.UiPopTag(c)
        ui.ElementClose(c)
        for file, i in FILES {
            id: ui.Id = ui.UiId(c, file.name)
            interaction: ui.Interaction = ui.UiInteract(c, id)
            if interaction.clicked { state.files_selected = i }
            ui.ElementOpen(c, {
                id = id,
                layout = {size = {ui.Grow(), ui.Fixed(metrics.control_height)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(10, 0), gap = 8, align = {y = .CENTER}},
                hit = {.INTERACTIVE},
                draw = {kind = .SELECTABLE, flags = {.SELECTED} if state.files_selected == i else {}},
            })
            ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 6, align = {y = .CENTER}}})
            ui.UiIcon(c, lucide(file.icon))
            ui.UiLabel(c, file.name)
            ui.ElementClose(c)
            cell(c, file.kind, ui.Fixed(76), true)
            cell(c, file.size, ui.Fixed(64), false, true)
            ui.ElementClose(c)
        }
        ui.ElementClose(c)
        ui.UiLabelDim(c, "6 rows here; ui.UiTable shows 100 000 (the table demo)", scale = 0.9)
    }
}

pageOverview :: proc(c: ^ui.Context) {
    // the page is taller than a small window: it scrolls
    if !ui.UiScroll(c, "##overview", {ui.Grow(), ui.Grow()}, {direction = .TOP_TO_BOTTOM}) { return }
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingAll(MARGIN), gap = COLUMN_GAP}})
    if column(c) {
        cardButtons(c)
        cardInputs(c)
        cardMenus(c)
    }
    if column(c) {
        cardChoices(c)
        cardDate(c)
        cardProject(c)
    }
    if column(c) {
        cardBadges(c)
        cardFiles(c)
    }
    ui.ElementClose(c)
}

// Every icon of the icons library with its name, in rows of ICON_COLUMNS
ICON_COLUMNS :: 8

pageIcons :: proc(c: ^ui.Context) {
    if ui.UiScroll(c, "##icons", {ui.Grow(), ui.Grow()}, {padding = ui.PaddingAll(MARGIN), gap = 6, direction = .TOP_TO_BOTTOM}) {
        ui.UiLabelDim(c, ui.UiFormat(c, "%d icons of Lucide (lucide.dev, ISC License) in icons/lucide.ttf: ui_default.LucideIcon(.NAME) is an icon for a button, a chip, a row", len(icons.Icon) - 1))
        count: int = len(icons.Icon) - 1
        for first := 1; first <= count; first += ICON_COLUMNS {
            ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 6}})
            for number in first ..< min(first + ICON_COLUMNS, count + 1) {
                icon: icons.Icon = icons.Icon(number)
                ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fixed(34)}, direction = .LEFT_TO_RIGHT, gap = 8, padding = ui.PaddingXY(8, 0), align = {y = .CENTER}}})
                ui.UiIcon(c, lucide(icon), 20, state.painter.theme.text)
                ui.UiLabelDim(c, icons.ICON_NAMES[icon], scale = 0.85)
                ui.ElementClose(c)
            }
            ui.ElementClose(c)
        }
    }
}

draw :: proc(ctx: ^kit.Context) {
    state.painter.theme = ui_default.THEME_LIGHT if state.theme == 1 else ui_default.THEME_DARK
    ctx.background = kit.Color(state.painter.theme.background)
    ui_kit.Begin(&state.ctx, &state.painter, &state.style, ctx)
    c: ^ui.Context = &state.ctx
    metrics: ^ui.Metrics = &c.style.metrics

    // the whole screen: a bar with the name, the pages and the theme, then the page
    ui.ElementOpen(c, {layout = {size = {ui.Fixed(ctx.screen.x), ui.Fixed(ctx.screen.y)}, direction = .TOP_TO_BOTTOM}})
    ui.ElementOpen(c, {
        layout = {size = {ui.Grow(), ui.Fixed(metrics.control_height + 24)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(MARGIN, 0), gap = 16, align = {y = .CENTER}},
        draw = {kind = .MENU_BAR},
    })
    ui.UiTitle(c, "Gallery", 1.3)
    ui.UiTabBar(c, "##pages", PAGES[:], &state.page)
    ui.UiLabelDim(c, "Theme")
    ui.UiDropdown(c, "##theme", THEMES[:], &state.theme, {ui.Fixed(140), {}})
    ui.ElementClose(c)
    if state.page == 0 {
        pageOverview(c)
    } else {
        pageIcons(c)
    }
    ui.ElementClose(c)

    if ui.UiModal(c, "Delete the file?", &state.confirm_open, {ui.Fixed(340), {}}) {
        ui.UiTitle(c, "Delete the file?")
        ui.UiLabelDim(c, "This is a dialog: the page behind it is dimmed and does not take the pointer.", .WORDS)
        if row(c) {
            ui.UiSpacer(c, {ui.Grow(), ui.Fixed(1)})
            if ui.UiTagged(c, "outline") {
                if ui.UiButton(c, "Cancel") { state.confirm_open = false }
            }
            if ui.UiTagged(c, "danger") {
                if ui.UiButton(c, "Delete") {
                    state.confirm_open = false
                    state.last_action = "The file was deleted (not really)."
                }
            }
        }
    }
    ui.UiEnd(c)
    ui.UiRender(c)
}

// The script finds the widgets by where they were in the last frame (ui.UiElementRect), not by numbers: the page is laid out by the texts, and their widths are those of the font
target: ui.Vec2

// the middle of an element, into `target`
aim :: proc(id: ui.Id) -> bool {
    rect, found := ui.UiElementRect(&state.ctx, id)
    target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return found && rect.z > 0
}

script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the page fits into the storage"),
    kit.Capture("gallery_dark"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("Buttons", "Save")) }, "the Save button is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.saves == 1 }, "a click on Save was counted"),
    // a chip flips, a segment is chosen, a tag is taken away by its cross
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("Choices", "X11")) }, "the X11 chip is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.platforms[1] }, "the chip was switched on"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.ctx, ui.IdFromIndex(2, ui.UiIdPath("Choices", "##density")))
        target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
        return found
    }, "the third segment is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.density == 2 }, "the third segment was chosen"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.ctx, ui.UiIdPath("Badges, avatars and tags", "vulkan"))
        target = {rect.x + rect.z - 12, rect.y + rect.w * 0.5}
        return found
    }, "the vulkan tag is on the page"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.tags[1] && state.tags[0] && state.tags[2] }, "the cross of a tag took that tag away"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("Inputs", "Notifications")) }, "the switch is on the page"),
    kit.ClickAt(&target),
    kit.Wait(12),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.notifications }, "the switch was flipped"),
    // the date field: its month opens, a click on a day takes it
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui.UiIdPath("Date, time and colour", "##due")) }, "the date field is on the page"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return aim(ui.IdFromIndex(24, ui.IdFromString("popup", ui.UiIdPath("Date, time and colour", "##due"))))
    }, "the month is open: the 24th is on the screen"),
    kit.MoveTo({1000, 690}),
    kit.Wait(3),
    kit.Capture("gallery_date_open"),
    kit.Wait(2),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.due == ui.Date{2026, 11, 24} }, "a click on a day sets the date"),
    // the light theme, then the page of the icons
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        state.theme = 1
        return true
    }, "the light theme"),
    kit.MoveTo({640, 700}),
    kit.Wait(4),
    kit.Capture("gallery_light"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.ctx, ui.IdFromIndex(1, ui.UiId(&state.ctx, "##pages")))
        target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
        return found
    }, "the tab of the icons is in the bar"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.page == 1 }, "the page of the icons is shown"),
    kit.Capture("gallery_icons"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
