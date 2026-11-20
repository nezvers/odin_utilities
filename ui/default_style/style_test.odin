#+build !js
package ui_default

// The style without a window: a frame with the widgets of the library is rendered into a painter that only writes down what it was asked to draw. The pictures of the
// demos check how it looks; this checks that every kind draws, with and without icons, in both themes, and leaves the painter as it found it.

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
            if painter.face == .MONO { recorder.mono_texts += 1 }
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
            return {f32(len(text)) * size * (0.55 if painter.face == .STRONG else 0.5), size}
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
                testing.expect_value(t, recorder.mono_texts, 0)
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
