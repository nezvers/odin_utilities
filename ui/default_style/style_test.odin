#+build !js
package ui_default

// The style without a window: a frame with the widgets of the library is rendered into a painter that only writes down what it was asked to draw. The pictures of the
// demos check how it looks; this checks that every kind draws, with and without icons, in both themes, and leaves the painter as it found it.

import "core:math"
import "core:testing"
import ui ".."
import icons "../../icons"

@(private = "file")
Recorder :: struct {
    rects: int,
    polygons: int,
    rounded: int,
    texts: int,
    icon_count: int,
    clips: int,
    strong_texts: int,              // texts drawn in the STRONG face
    mono_texts: int,
    seen_text: [16]string,          // the texts that were looked for (wanted) and found
    wanted: [16]string,
    found: [16]bool,
    colors: [16]ui.Color,           // the color a wanted text was drawn in
    fill_colors: [8]ui.Color,       // the colors of the first rectangles that were filled
    fill_count: int,
    seen_icons: [icons.Icon]int,
    bad_rect: bool,                 // something was drawn with a size that is not a number or is negative
}

@(private = "file")
recorderOf :: proc(painter: ^Painter) -> ^Recorder {
    return cast(^Recorder)painter.user
}

@(private = "file")
checkRect :: proc(recorder: ^Recorder, rect: ui.Rect) {
    for value in rect {
        if value != value { recorder.bad_rect = true }
    }
    if rect.z < -0.01 || rect.w < -0.01 { recorder.bad_rect = true }
}

@(private = "file")
recorderPainter :: proc(painter: ^Painter, recorder: ^Recorder, theme: Theme, with_icons: bool) {
    painter^ = {
        user = recorder,
        theme = theme,
        fill_rect = proc(painter: ^Painter, rect: ui.Rect, color: ui.Color) {
            recorder: ^Recorder = recorderOf(painter)
            if recorder.fill_count < len(recorder.fill_colors) { recorder.fill_colors[recorder.fill_count] = color }
            recorder.fill_count += 1
            recorderOf(painter).rects += 1
            checkRect(recorderOf(painter), rect)
        },
        fill_polygon = proc(painter: ^Painter, points: []ui.Vec2, color: ui.Color) {
            recorderOf(painter).polygons += 1
            if len(points) < 3 { recorderOf(painter).bad_rect = true }
        },
        fill_rounded = proc(painter: ^Painter, rect: ui.Rect, radius: f32, color: ui.Color) {
            recorderOf(painter).rounded += 1
            checkRect(recorderOf(painter), rect)
            if radius != radius || radius < 0 { recorderOf(painter).bad_rect = true }
        },
        draw_text = proc(painter: ^Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color) {
            recorder: ^Recorder = recorderOf(painter)
            recorder.texts += 1
            if painter.face == .STRONG { recorder.strong_texts += 1 }
            if painter.face == .MONO || painter.face == .MONO_STRONG || painter.face == .MONO_ITALIC || painter.face == .MONO_STRONG_ITALIC { recorder.mono_texts += 1 }
            for wanted, i in recorder.wanted {
                if wanted != "" && wanted == text {
                    recorder.found[i] = true
                    recorder.colors[i] = color
                }
            }
            if size <= 0 || position.x != position.x || position.y != position.y { recorder.bad_rect = true }
        },
        measure_text = proc(painter: ^Painter, text: string, size: f32) -> ui.Vec2 {
            // the strong face is a little wider, as a real one is
            return {f32(len(text)) * size * (0.55 if painter.face == .STRONG || painter.face == .MONO_STRONG || painter.face == .STRONG_ITALIC || painter.face == .MONO_STRONG_ITALIC else 0.5), size}
        },
        clip = proc(painter: ^Painter, rect: ui.Rect, begin: bool) {
            recorderOf(painter).clips += 1
        },
    }
    if with_icons {
        painter.draw_icon = proc(painter: ^Painter, icon: icons.Icon, rect: ui.Rect, color: ui.Color) {
            recorder: ^Recorder = recorderOf(painter)
            recorder.icon_count += 1
            recorder.seen_icons[icon] += 1
            checkRect(recorder, rect)
            if rect.z != rect.w { recorder.bad_rect = true }
        }
        painter.glue_fonts[.MONO] = 1
    }
}

@(private = "file")
Everything :: struct {
    storage: ui.Storage(1024, 2048, 256, 16384),
    ctx: ui.Context,
    style: ui.Style,
    painter: Painter,
    recorder: Recorder,
    // what the widgets work on
    on: bool,
    off: bool,
    value: f32,
    number: int,
    choice: int,
    text: [32]u8,
    text_length: int,
    area: [64]u8,
    area_length: int,
    date: ui.Date,
    minutes: int,
    chart: ui.ChartView,
    points: [5]ui.ChartPoint,
    series: [1]ui.ChartSeries,
    tree: ui.Tree,
    tree_view: ui.TreeView,
    plot: [4]f32,                   // kept here: a plot draws from its numbers when the frame is rendered
    open: bool,
    modal: bool,
    chord: ui.Chord,
    code: [64]u8,
    code_length: int,
}

OPTIONS: [3]string = {"Low", "Medium", "High"}

@(private = "file")
everythingInit :: proc(e: ^Everything, theme: Theme, with_icons: bool) {
    recorderPainter(&e.painter, &e.recorder, theme, with_icons)
    e.style = StyleMake()
    ui.UiInit(&e.ctx, &e.storage, Measure, &e.painter)
    e.on, e.value, e.number, e.choice = true, 0.4, 3, 1
    e.text_length = copy(e.text[:], "Ada")
    e.date = {2026, 11, 12}
    e.minutes = 450
    e.plot = {1, 3, 2, 5}
    e.chord = {{.CTRL}, 5}
    e.code_length = copy(e.code[:], "total: int = 42 // sum")
    ui.ChartViewInit(&e.chart)
    e.points = {{0, 10}, {1, 30}, {2, 20}, {3, 45}, {4, 25}}
    e.series = {{name = "Sales", points = e.points[:]}}
    ui.TreeInit(&e.tree)
    ui.TreeViewInit(&e.tree_view)
    folder, _ := ui.TreeAdd(&e.tree, {}, "folder", branch = true, icon = .FOLDER)
    ui.TreeAdd(&e.tree, folder, "note", icon = .TEXT)
    ui.TreeExpand(&e.tree, folder)
}

// One frame with the widgets of the library, rendered into the recorder
@(private = "file")
everythingFrame :: proc(e: ^Everything, input: ui.Input = {mouse_position = {-100, -100}}) {
    c: ^ui.Context = &e.ctx
    e.recorder = {wanted = e.recorder.wanted}
    ui.UiBegin(c, input, 1.0 / 60, {1600, 3000}, &e.style)
    if ui.UiWindow(c, "window", {0, 0}, {ui.Fixed(900), {}}) {
        ui.UiTitle(c, "A title")
        ui.UiLabelDim(c, "a hint")
        ui.UiLabel(c, "plain text")
        for tag in ([?]string{"", "primary", "secondary", "outline", "ghost", "danger"}) {
            ui.UiPushTag(c, tag)
            ui.UiButton(c, ui.UiFormat(c, "Button##%s", tag), icon = LucideIcon(.SAVE))
            ui.UiButton(c, ui.UiFormat(c, "Off##%s", tag), disabled = true)
            ui.UiPopTag(c)
        }
        ui.UiButton(c, "##only", icon = .CLOSE)
        ui.UiToggle(c, "on", &e.on)
        ui.UiToggle(c, "off", &e.off)
        ui.UiSwitch(c, "switch on", &e.on)
        ui.UiSwitch(c, "switch off", &e.off, disabled = true)
        ui.UiSlider(c, "slider", &e.value)
        ui.UiProgress(c, "progress", e.value)
        if ui.UiTagged(c, "thin") {
            ui.UiSlider(c, "thin slider", &e.value)
            ui.UiProgress(c, "thin progress", e.value)
        }
        ui.UiTextField(c, "Name", e.text[:], &e.text_length)
        ui.UiDropdown(c, "dropdown", OPTIONS[:], &e.choice)
        ui.UiCombo(c, "combo", OPTIONS[:], &e.choice)
        ui.UiRadio(c, "radio a", &e.choice, 0)
        ui.UiRadio(c, "radio b", &e.choice, 1)
        ui.UiSelectable(c, "row", true)
        ui.UiSelectable(c, "other row", false)
        ui.UiTabBar(c, "tabs", OPTIONS[:], &e.choice)
        ui.UiSegmented(c, "segments", OPTIONS[:], &e.choice)
        ui.UiBreadcrumbs(c, "crumbs", OPTIONS[:])
        ui.UiChip(c, "chip on", true)
        ui.UiChip(c, "chip off", false, LucideIcon(.STAR))
        ui.UiTag(c, "tag", .FOLDER)
        for tone in ui.Tone { ui.UiBadge(c, ui.UiFormat(c, "badge %d", int(tone)), tone) }
        ui.UiAvatar(c, "AL", {37, 99, 235, 255})
        ui.UiAvatar(c, "OU", {250, 240, 180, 255})
        ui.UiSpinner(c)
        ui.UiSeparator(c)
        ui.UiSeparatorText(c, "section")
        ui.UiInputInt(c, "int", &e.number)
        ui.UiDrag(c, "drag", &e.value)
        ui.UiArrowButton(c, "arrow", .LEFT)
        ui.UiBullet(c, "bullet")
        ui.UiIcon(c, .FILE)
        ui.UiIcon(c, LucideIcon(.HEART))
        ui.UiIcon(c, .USER)                                 // an icon of the program: the style has no picture for it and draws nothing
        ui.UiColorButton(c, "swatch", {0.2, 0.6, 0.9})
        ui.UiPlotLines(c, "plot", e.plot[:])
        ui.UiPlotHistogram(c, "histogram", e.plot[:])
        if ui.UiCollapsing(c, "section header", true) { ui.UiLabel(c, "inside") }
        if ui.UiTreeNode(c, "tree node", true) { ui.UiLabel(c, "leaf") }
        ui.UiTree(c, "tree", &e.tree, &e.tree_view, {ui.Grow(), ui.Fixed(80)})
        ui.UiDateField(c, "date", &e.date)
        ui.UiTimeField(c, "time", &e.minutes)
        ui.UiChart(c, "line chart", &e.chart, e.series[:], .LINE, nil, {ui.Fixed(400), ui.Fixed(160)})
        if ui.UiCard(c, "Card") { ui.UiLabel(c, "in the card") }
        if ui.UiScroll(c, "scroll", {ui.Grow(), ui.Fixed(40)}) {
            for i in 0 ..< 6 { ui.UiLabel(c, ui.UiFormat(c, "line %d", i)) }
        }
        if ui.UiMenuBar(c) {
            if ui.UiMenu(c, "File") { ui.UiMenuItem(c, "New", "Ctrl+N") }
        }
        // texts with styles inside, a shortcut, code with colors, bubbles
        ui.UiMarkdown(c, "# Heading\n\nwith **strong**, *slanted*, `inline` and a [link](x)\n\n- entry\n\n> quoted\n\n| Head | Two |\n|---|---|\n| cell | 2 |\n\n```\nfenced\n```\n\n---")
        ui.UiRichText(c, "rich", "a **bold** bubble text", 1, 200)
        ui.UiShortcutField(c, "shortcut", &e.chord, {}, proc(key: u16) -> string { return "K" })
        ui.UiTextArea(c, "code", e.code[:], &e.code_length, {ui.Fixed(300), ui.Fixed(60)}, false, false, ui.HighlightCode)
        for mine in ([2]bool{false, true}) {
            ui.UiPushTag(c, "bubble")
            if mine { ui.UiPushTag(c, "mine") }
            ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, padding = ui.PaddingAll(8)}, draw = {kind = .PANEL}})
            if mine { ui.UiPopTag(c) }
            ui.UiPopTag(c)
            ui.UiLabel(c, "a message" if mine else "an answer")
            ui.ElementClose(c)
        }
    }
    if ui.UiModal(c, "dialog", &e.modal, {ui.Fixed(300), {}}) { ui.UiLabel(c, "in the dialog") }
    ui.UiEnd(c)
    ui.UiRender(c)
}

@(test)
test_the_style_draws_every_widget_in_both_themes_with_and_without_icons :: proc(t: ^testing.T) {
    for theme in ([2]Theme{THEME_DARK, THEME_LIGHT}) {
        for with_icons in ([2]bool{true, false}) {
            e: ^Everything = new(Everything)
            defer free(e)
            everythingInit(e, theme, with_icons)
            e.recorder.wanted = {"A title", "a hint", "plain text", "Button", "12/11/2026", "07:30", "Ada", "Medium", "in the card", "AL", "badge 4", "tag", "section", "File", "Sales", "note"}
            for _ in 0 ..< 3 { everythingFrame(e) }
            recorder: ^Recorder = &e.recorder
            testing.expect_value(t, ui.UiProblems(&e.ctx), ui.Problems{})
            testing.expect(t, !recorder.bad_rect, "nothing was drawn with a size that is not a number")
            testing.expect(t, recorder.rounded > 60, "controls are rounded rectangles")
            testing.expect(t, recorder.texts > 80)
            testing.expect(t, recorder.strong_texts > 20, "labels of controls and titles are in the strong face")
            // "Sales" is the legend of a chart of two series or more: this chart has one, so it is the one text that is not drawn
            for wanted, i in recorder.wanted {
                if wanted == "Sales" {
                    testing.expectf(t, !recorder.found[i], "one series has no legend")
                    continue
                }
                testing.expectf(t, recorder.found[i], "the text %q was drawn (icons %v, dark %v)", wanted, with_icons, theme.dark)
            }
            // the style leaves the painter in the regular face: a text of the program after UiRender is not strong by accident
            testing.expect_value(t, e.painter.face, Face.REGULAR)
            if with_icons {
                testing.expect(t, recorder.icon_count > 25)
                testing.expect(t, recorder.seen_icons[icons.Icon.SAVE] >= 6, "every button with an icon draws it")
                testing.expect(t, recorder.seen_icons[icons.Icon.CHECK] >= 2, "the ticked check box and the chosen chip")
                testing.expect(t, recorder.seen_icons[icons.Icon.X] >= 2, "the button with the cross and the cross of the tag")
                testing.expect(t, recorder.seen_icons[icons.Icon.CALENDAR] == 1, "the date field")
                testing.expect(t, recorder.seen_icons[icons.Icon.CHEVRON_DOWN] >= 2, "the dropdown and the combo")
                testing.expect(t, recorder.seen_icons[icons.Icon.CHEVRON_RIGHT] >= 2, "between the breadcrumbs")
                testing.expect(t, recorder.seen_icons[icons.Icon.FOLDER_OPEN] >= 1, "the open folder of the tree")
                testing.expect(t, recorder.seen_icons[icons.Icon.HEART] == 1 && recorder.seen_icons[icons.Icon.STAR] == 1)
                testing.expect_value(t, recorder.seen_icons[icons.Icon.NONE], 0)
                testing.expect(t, recorder.mono_texts > 0, "numbers are in the code face when the glue has one")
            } else {
                // without icons the style still draws: arrows as triangles, check marks as lines, the file pictures as rectangles
                testing.expect_value(t, recorder.icon_count, 0)
                testing.expect(t, recorder.polygons > 10)
                // no code face in the glue: numbers stay in the regular one, only the texts that ask for the code face by their tag are in it (the
                // inline code and the fenced block of the Markdown view)
                testing.expect_value(t, recorder.mono_texts, 2)
            }
        }
    }
}

@(test)
test_the_style_draws_open_popups_states_and_a_dialog :: proc(t: ^testing.T) {
    e: ^Everything = new(Everything)
    defer free(e)
    everythingInit(e, THEME_DARK, true)
    for _ in 0 ..< 3 { everythingFrame(e) }
    closed_rounded: int = e.recorder.rounded
    click :: proc(e: ^Everything, id: ui.Id) {
        rect, _ := ui.UiElementRect(&e.ctx, id)
        point: ui.Vec2 = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
        everythingFrame(e, {mouse_position = point})
        everythingFrame(e, {mouse_position = point, mouse_down = true, mouse_pressed = true})
        everythingFrame(e, {mouse_position = point, mouse_released = true})
        everythingFrame(e, {mouse_position = point})
    }
    // the month of the date field: 30 cells more, the names of the days
    e.recorder.wanted = {0 = "November 2026", 1 = "Mo", 2 = "30"}
    click(e, ui.UiIdPath("window", "date"))
    testing.expect(t, e.recorder.found[0] && e.recorder.found[1] && e.recorder.found[2], "the open month is drawn")
    testing.expect(t, e.recorder.rounded > closed_rounded, "the popup and the marked day")
    testing.expect(t, !e.recorder.bad_rect)
    // the pointer over a button and a press on it: the same shapes, no bad numbers (the colors are what changes)
    everythingFrame(e, {mouse_position = {-100, -100}, mouse_down = true, mouse_pressed = true})
    everythingFrame(e, {mouse_position = {-100, -100}, mouse_released = true})
    rect, found := ui.UiElementRect(&e.ctx, ui.UiIdPath("window", "Button##primary"))
    testing.expect(t, found)
    over: ui.Vec2 = {rect.x + 4, rect.y + 4}
    for _ in 0 ..< 4 { everythingFrame(e, {mouse_position = over, mouse_down = true}) }
    testing.expect(t, !e.recorder.bad_rect && e.recorder.texts > 80)
    // a dialog: the dimmed screen and its panel on top
    e.modal = true
    e.recorder.wanted = {0 = "in the dialog"}
    for _ in 0 ..< 2 { everythingFrame(e) }
    testing.expect(t, e.recorder.found[0])
    testing.expect_value(t, ui.UiProblems(&e.ctx), ui.Problems{})
    testing.expect_value(t, e.painter.face, Face.REGULAR)
}

@(test)
test_icons_of_the_ui_have_their_lucide_pictures :: proc(t: ^testing.T) {
    testing.expect_value(t, IconToLucide(.NONE), icons.Icon.NONE)
    testing.expect_value(t, IconToLucide(.USER), icons.Icon.NONE)
    testing.expect_value(t, IconToLucide(.FOLDER), icons.Icon.FOLDER)
    testing.expect_value(t, IconToLucide(.CLOSE), icons.Icon.X)
    testing.expect_value(t, IconToLucide(.CALENDAR), icons.Icon.CALENDAR)
    // every icon the ui names itself has a picture
    for icon in ui.Icon {
        if icon == .NONE || icon == .USER { continue }
        testing.expectf(t, IconToLucide(icon) != .NONE, "%v has a picture", icon)
    }
    // every Lucide icon goes into an icon of the ui and comes back, above the numbers of the program
    for icon in icons.Icon {
        if icon == .NONE { continue }
        number: ui.Icon = LucideIcon(icon)
        testing.expect(t, u16(number) > u16(ui.Icon.USER) + 255)
        testing.expect_value(t, IconToLucide(number), icon)
    }
    // tones and chart colors differ from each other in both themes
    for theme in ([2]Theme{THEME_DARK, THEME_LIGHT}) {
        theme := theme
        for a in ui.Tone {
            fill, ink := ToneColors(&theme, a)
            testing.expectf(t, ColorContrast(fill, ink) >= 3, "%v: a badge reads (%v)", a, ColorContrast(fill, ink))
        }
        for i in 0 ..< 8 {
            for k in i + 1 ..< 8 { testing.expect(t, ChartColor(&theme, i) != ChartColor(&theme, k)) }
        }
        testing.expect_value(t, ChartColor(&theme, 8), ChartColor(&theme, 0))
    }
}

@(test)
test_an_area_is_drawn_in_its_own_theme :: proc(t: ^testing.T) {
    Test :: struct {
        storage: ui.Storage(128, 256, 64, 2048),
        ctx: ui.Context,
        style: ui.Style,
        painter: Painter,
        recorder: Recorder,
    }
    test: ^Test = new(Test)
    defer free(test)
    recorderPainter(&test.painter, &test.recorder, THEME_DARK, false)
    test.style = StyleMake()
    ui.UiInit(&test.ctx, &test.storage, Measure, &test.painter)
    frame :: proc(test: ^Test) {
        test.recorder = {wanted = {0 = "before", 1 = "inside", 2 = "deeper", 3 = "after", 4 = "other"}}
        ui.UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 600}, &test.style)
        if ui.UiWindow(&test.ctx, "window", {0, 0}, {ui.Fixed(400), {}}) {
            ui.UiLabel(&test.ctx, "before")
            if ui.UiTagged(&test.ctx, ThemeAreaTag(0)) {
                ui.UiLabel(&test.ctx, "inside")
                if ui.UiTagged(&test.ctx, "flat") {
                    if ui.UiPanel(&test.ctx, "panel") { ui.UiLabel(&test.ctx, "deeper") }
                }
            }
            ui.UiLabel(&test.ctx, "after")
            if ui.UiTagged(&test.ctx, ThemeAreaTag(2)) { ui.UiLabelDim(&test.ctx, "other") }
        }
        ui.UiEnd(&test.ctx)
        ui.UiRender(&test.ctx)
    }
    // no area is set: the tags mean nothing
    for _ in 0 ..< 2 { frame(test) }
    for i in 0 ..< 4 { testing.expect_value(t, test.recorder.colors[i], THEME_DARK.text) }
    sepia: Theme = THEME_LIGHT
    sepia.text, sepia.text_dim = {91, 70, 54, 255}, {140, 120, 100, 255}
    ThemeAreaSet(&test.painter, 0, sepia)
    ThemeAreaSet(&test.painter, 2, THEME_LIGHT)
    frame(test)
    testing.expect_value(t, test.recorder.colors[0], THEME_DARK.text)
    testing.expect_value(t, test.recorder.colors[1], sepia.text)
    testing.expect_value(t, test.recorder.colors[2], sepia.text)
    testing.expect_value(t, test.recorder.colors[3], THEME_DARK.text)
    testing.expect_value(t, test.recorder.colors[4], THEME_LIGHT.text_dim)
    // after the frame the painter has its own theme again
    testing.expect_value(t, test.painter.theme.text, THEME_DARK.text)
    testing.expect_value(t, test.painter.area_now, 0)
    ThemeAreaClear(&test.painter, 0)
    frame(test)
    testing.expect_value(t, test.recorder.colors[1], THEME_DARK.text)
    testing.expect_value(t, test.recorder.colors[4], THEME_LIGHT.text_dim)
    testing.expect_value(t, ui.UiProblems(&test.ctx), ui.Problems{})
}

@(test)
test_the_style_draws_the_texts_with_styles_inside :: proc(t: ^testing.T) {
    for theme in ([2]Theme{THEME_DARK, THEME_LIGHT}) {
        e: ^Everything = new(Everything)
        defer free(e)
        everythingInit(e, theme, true)
        e.recorder.wanted = {"Heading", "strong", "slanted", "inline", "link", "entry", "quoted", "Head", "cell", "fenced", "bold", "Ctrl+K", "total: ", "42", "// sum", "a message"}
        for _ in 0 ..< 3 { everythingFrame(e) }
        recorder: ^Recorder = &e.recorder
        testing.expect_value(t, ui.UiProblems(&e.ctx), ui.Problems{})
        testing.expect(t, !recorder.bad_rect)
        for wanted, i in recorder.wanted { testing.expectf(t, recorder.found[i], "%q is drawn", wanted) }
        // a link in the accent, the words of code in their colors, a comment dim
        testing.expect_value(t, recorder.colors[4], theme.accent)
        testing.expect_value(t, recorder.colors[13], theme.warning)
        testing.expect_value(t, recorder.colors[14], theme.text_dim)
        testing.expect_value(t, recorder.colors[12], theme.text)
        testing.expect_value(t, e.painter.face, Face.REGULAR)
        testing.expect_value(t, e.painter.theme.text, theme.text)
    }
}

@(test)
test_dashed_lines_keep_their_pattern_around_corners :: proc(t: ^testing.T) {
    painter: Painter
    recorder: Recorder
    recorderPainter(&painter, &recorder, THEME_DARK, false)
    // 100 long, dashes of 6 with gaps of 4: ten dashes
    after: f32 = LineDashed(&painter, {0, 0}, {100, 0}, 1, 6, 4, {255, 255, 255, 255})
    testing.expect_value(t, recorder.polygons, 10)
    testing.expect_value(t, after, 100)
    // moved by half a period: a part of a dash at the start, ten whole ones... the last one is cut by the end
    recorder.polygons = 0
    LineDashed(&painter, {0, 0}, {100, 0}, 1, 6, 4, {255, 255, 255, 255}, 5)
    testing.expect_value(t, recorder.polygons, 11)
    // a phase the other way moves the pattern back: by half of its period it is the same picture
    recorder.polygons = 0
    LineDashed(&painter, {0, 0}, {100, 0}, 1, 6, 4, {255, 255, 255, 255}, -5)
    testing.expect_value(t, recorder.polygons, 11)
    // nothing to draw: no length, no dash
    recorder.polygons = 0
    testing.expect_value(t, LineDashed(&painter, {5, 5}, {5, 5}, 1, 6, 4, {255, 255, 255, 255}, 3), 3)
    LineDashed(&painter, {0, 0}, {100, 0}, 1, 0, 4, {255, 255, 255, 255})
    testing.expect_value(t, recorder.polygons, 0)
    // a square of 4 x 25: the pattern goes around the corners, as many dashes as the line of 100 (a dash that is cut by a corner is two pieces)
    square: [4]ui.Vec2 = {{0, 0}, {25, 0}, {25, 25}, {0, 25}}
    PathDashed(&painter, square[:], true, 1, 6, 4, {255, 255, 255, 255})
    testing.expect(t, recorder.polygons >= 10 && recorder.polygons <= 13)
    recorder.polygons = 0
    PathDashed(&painter, square[:], false, 1, 6, 4, {255, 255, 255, 255})
    testing.expect(t, recorder.polygons >= 7 && recorder.polygons <= 10)
    testing.expect(t, !recorder.bad_rect)
    // the corners of a turned rectangle: a quarter turn puts the top left at the top right
    corners: [4]ui.Vec2 = RectCorners({0, 0, 20, 10}, 0)
    testing.expect(t, corners[0] == ui.Vec2{0, 0} && corners[2] == ui.Vec2{20, 10})
    corners = RectCorners({0, 0, 20, 20}, math.PI / 2)
    testing.expect(t, abs(corners[0].x - 20) < 0.001 && abs(corners[0].y) < 0.001)
    recorder.polygons = 0
    PathLines(&painter, corners[:], true, 1, {255, 255, 255, 255})
    testing.expect_value(t, recorder.polygons, 4)
}

@(test)
test_a_reversed_run_is_drawn_in_the_colors_of_the_theme_swapped :: proc(t: ^testing.T) {
    for theme in ([2]Theme{THEME_DARK, THEME_LIGHT}) {
        test: ^struct {
            storage: ui.Storage(128, 256, 64, 2048),
            ctx: ui.Context,
            style: ui.Style,
            painter: Painter,
            recorder: Recorder,
        } = new(struct {
            storage: ui.Storage(128, 256, 64, 2048),
            ctx: ui.Context,
            style: ui.Style,
            painter: Painter,
            recorder: Recorder,
        })
        defer free(test)
        recorderPainter(&test.painter, &test.recorder, theme, false)
        test.style = StyleMake()
        ui.UiInit(&test.ctx, &test.storage, Measure, &test.painter)
        for _ in 0 ..< 2 {
            test.recorder = {wanted = {0 = "plain", 1 = "green", 2 = "red"}}
            ui.UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 600}, &test.style)
            if ui.UiWindow(&test.ctx, "window", {0, 0}, {ui.Fixed(500), {}}) { ui.UiAnsiText(&test.ctx, "\x1b[7mplain\x1b[0m \x1b[32;7mgreen\x1b[0m \x1b[41mred\x1b[0m") }
            ui.UiEnd(&test.ctx)
            ui.UiRender(&test.ctx)
        }
        dark: [16]ui.Color = ui.ANSI_COLORS_DARK
        // the reversed run without colors: its text in the panel color on a ground in the text color
        testing.expect_value(t, test.recorder.colors[0], theme.panel)
        testing.expect_value(t, test.recorder.colors[1], theme.panel)
        testing.expect_value(t, test.recorder.colors[2], theme.text)
        // the first rectangle is that ground, the second the green one, the third the red ground that is not reversed
        testing.expect_value(t, test.recorder.fill_colors[0], theme.text)
        testing.expect_value(t, test.recorder.fill_colors[1], dark[2])
        testing.expect_value(t, test.recorder.fill_colors[2], dark[1])
        testing.expect_value(t, test.painter.theme.text, theme.text)
    }
}

@(test)
test_a_dropdown_item_draws_the_part_that_matched_in_the_strong_face :: proc(t: ^testing.T) {
    for theme in ([2]Theme{THEME_DARK, THEME_LIGHT}) {
        test: ^struct {
            storage: ui.Storage(16, 16, 8, 256),
            ctx: ui.Context,
            style: ui.Style,
            painter: Painter,
            recorder: Recorder,
        } = new(struct {
            storage: ui.Storage(16, 16, 8, 256),
            ctx: ui.Context,
            style: ui.Style,
            painter: Painter,
            recorder: Recorder,
        })
        defer free(test)
        recorderPainter(&test.painter, &test.recorder, theme, false)
        test.style = StyleMake()
        ui.UiInit(&test.ctx, &test.storage, Measure, &test.painter)
        ui.UiBegin(&test.ctx, {}, 1.0 / 60, {800, 600}, &test.style)                 // the style of the context is set by a frame
        ui.UiEnd(&test.ctx)
        info: ui.DrawInfo = {kind = .DROPDOWN_ITEM, name = "main.odin", rect = {0, 0, 200, 28}, font_size = 16, cursor = 0, anchor = 2}
        test.recorder = {wanted = {0 = "ma", 1 = "in.odin", 2 = "main.odin"}}
        DrawDropdownItem(&test.ctx, &info)
        testing.expect(t, test.recorder.found[0] && test.recorder.found[1] && !test.recorder.found[2], "drawn in two parts")
        testing.expect_value(t, test.recorder.strong_texts, 1)
        testing.expect_value(t, test.recorder.colors[0], theme.accent)
        // the chosen row is in the soft accent: the part keeps the ink of the row, in the strong face
        test.recorder = {wanted = {0 = "ma", 1 = "in.odin"}}
        info.flags = {.SELECTED}
        DrawDropdownItem(&test.ctx, &info)
        testing.expect(t, test.recorder.colors[0] != theme.accent && test.recorder.colors[0] == test.recorder.colors[1])
        // a range in the middle: three parts; a range that is empty or out of the name is not a range
        test.recorder = {wanted = {0 = "ma", 1 = "in", 2 = ".odin", 3 = "main.odin"}}
        info.flags = {}
        info.cursor, info.anchor = 2, 4
        info.name = "format"
        DrawDropdownItem(&test.ctx, &info)
        test.recorder = {wanted = {0 = "format"}}
        info.cursor, info.anchor = 3, 3
        DrawDropdownItem(&test.ctx, &info)
        testing.expect(t, test.recorder.found[0])
        test.recorder = {wanted = {0 = "format"}}
        info.cursor, info.anchor = 3, 30
        DrawDropdownItem(&test.ctx, &info)
        testing.expect(t, test.recorder.found[0] && test.recorder.strong_texts == 0)
        testing.expect_value(t, test.painter.face, Face.REGULAR)
    }
}
