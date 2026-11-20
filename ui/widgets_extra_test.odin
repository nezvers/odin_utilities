#+build !js
package ui

// Tests of widgets_extra.odin, of the icon of a button and of the tags of a text

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(private = "file")
Extra :: struct {
    storage: Storage(128, 256, 64, 2048),
    ctx: Context,
    style: Style,
    // what the widgets of `declare` work on and gave back
    on: bool,
    chips: [2]bool,
    tag_clicked: bool,
    tag_removed: bool,
    segment: int,
    segment_changed: int,
    crumb: int,
    saved: int,
    row_clicks: int,
}

@(private = "file")
extraInit :: proc(extra: ^Extra) {
    extra.style = {metrics = DEFAULT_METRICS}
    UiInit(&extra.ctx, &extra.storage, measure)
    extra.crumb = -1
}

// One frame with every widget of the file in a column at the top left of the screen
@(private = "file")
declare :: proc(extra: ^Extra, input: Input) {
    ctx: ^Context = &extra.ctx
    UiBegin(ctx, input, 1.0 / 60, {600, 600}, &extra.style)
    if UiWindow(ctx, "window", {0, 0}, {Fixed(500), {}}) {
        if UiButton(ctx, "Save", icon = .CHECK) { extra.saved += 1 }
        UiButton(ctx, "Plain")
        UiButton(ctx, "##only", icon = .CLOSE)
        UiSwitch(ctx, "Notify", &extra.on)
        if UiChip(ctx, "Wayland", extra.chips[0]) { extra.chips[0] = !extra.chips[0] }
        if UiChip(ctx, "Folder", extra.chips[1], .FOLDER) { extra.chips[1] = !extra.chips[1] }
        clicked, removed := UiTag(ctx, "odin")
        extra.tag_clicked = extra.tag_clicked || clicked
        extra.tag_removed = extra.tag_removed || removed
        labels: [3]string = {"Compact", "Comfortable", "Spacious"}
        if UiSegmented(ctx, "density", labels[:], &extra.segment) { extra.segment_changed += 1 }
        parts: [3]string = {"root", "folder", "here"}
        if clicked_part := UiBreadcrumbs(ctx, "path", parts[:]); clicked_part >= 0 { extra.crumb = clicked_part }
        UiBadge(ctx, "Failed", .DANGER)
        UiAvatar(ctx, "AL", {10, 20, 30, 255})
        UiSpinner(ctx)
        UiTitle(ctx, "A title")
        UiLabelDim(ctx, "a hint")
        UiLabel(ctx, "plain text")
        if UiCard(ctx, "Card") { UiLabel(ctx, "in the card") }
        // a row of the program that takes clicks
        row: Id = UiId(ctx, "row")
        if UiInteract(ctx, row).clicked { extra.row_clicks += 1 }
        ElementOpen(ctx, {id = row, layout = {size = {Grow(), Fixed(20)}}, hit = {.INTERACTIVE}, draw = {kind = .SELECTABLE}})
        ElementClose(ctx)
    }
    UiEnd(ctx)
}

@(private = "file")
idle :: proc(extra: ^Extra, frames: int = 1) {
    for _ in 0 ..< frames { declare(extra, {mouse_position = {-100, -100}}) }
}

// A click of the pointer at a point: over it, down, up
@(private = "file")
clickAt :: proc(extra: ^Extra, point: Vec2) {
    declare(extra, {mouse_position = point})
    declare(extra, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    declare(extra, {mouse_position = point, mouse_released = true})
    declare(extra, {mouse_position = {-100, -100}})
}

@(private = "file")
rectOf :: proc(t: ^testing.T, extra: ^Extra, id: Id) -> Rect {
    rect, found := UiElementRect(&extra.ctx, id)
    testing.expect(t, found && rect.z > 0, "the element was laid out")
    return rect
}

@(private = "file")
centerOf :: proc(t: ^testing.T, extra: ^Extra, id: Id) -> Vec2 {
    rect: Rect = rectOf(t, extra, id)
    return {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
}

// The draw info of the element with an id in the commands of the last frame
@(private = "file")
infoOf :: proc(extra: ^Extra, id: Id) -> (info: DrawInfo, found: bool) {
    for command in UiCommands(&extra.ctx) {
        if command.kind == .DRAW && command.info.id == id { return command.info, true }
    }
    return
}

// The draw info of the first text line that says `text`
@(private = "file")
textInfo :: proc(extra: ^Extra, text: string) -> (info: DrawInfo, found: bool) {
    for command in UiCommands(&extra.ctx) {
        if command.kind == .DRAW && command.info.kind == .LABEL && command.info.text == text { return command.info, true }
    }
    return
}

@(test)
test_a_button_carries_its_icon_and_makes_room_for_it :: proc(t: ^testing.T) {
    extra: ^Extra = new(Extra)
    defer free(extra)
    extraInit(extra)
    idle(extra, 2)
    metrics: Metrics = DEFAULT_METRICS
    save: Rect = rectOf(t, extra, UiIdPath("window", "Save"))
    // the name and the padding, and the picture with its gap before the name
    testing.expect_value(t, save.z, 4 * metrics.font_size * 0.5 + metrics.padding.x * 2 + metrics.font_size + 6)
    plain: Rect = rectOf(t, extra, UiIdPath("window", "Plain"))
    testing.expect_value(t, plain.z, 5 * metrics.font_size * 0.5 + metrics.padding.x * 2)
    // an icon and no name that is shown: a square
    only: Rect = rectOf(t, extra, UiIdPath("window", "##only"))
    testing.expect_value(t, only.z, metrics.control_height)
    testing.expect_value(t, only.w, metrics.control_height)
    info, found := infoOf(extra, UiIdPath("window", "Save"))
    testing.expect(t, found)
    testing.expect_value(t, info.icon, Icon.CHECK)
    testing.expect_value(t, info.name, "Save")
    info, _ = infoOf(extra, UiIdPath("window", "Plain"))
    testing.expect_value(t, info.icon, Icon.NONE)
    info, _ = infoOf(extra, UiIdPath("window", "##only"))
    testing.expect_value(t, info.icon, Icon.CLOSE)
    testing.expect_value(t, info.name, "")
    clickAt(extra, centerOf(t, extra, UiIdPath("window", "Save")))
    testing.expect_value(t, extra.saved, 1)
    testing.expect_value(t, UiProblems(&extra.ctx), Problems{})
}

@(test)
test_a_switch_flips_and_its_knob_slides :: proc(t: ^testing.T) {
    extra: ^Extra = new(Extra)
    defer free(extra)
    extraInit(extra)
    idle(extra, 2)
    id: Id = UiIdPath("window", "Notify")
    info, found := infoOf(extra, id)
    testing.expect(t, found && info.kind == .SWITCH)
    testing.expect(t, .ON not_in info.flags)
    testing.expect_value(t, info.value, 0)
    testing.expect(t, info.ratio > 20, "the style is told how wide the track is")
    clickAt(extra, centerOf(t, extra, id))
    testing.expect(t, extra.on)
    info, _ = infoOf(extra, id)
    testing.expect(t, .ON in info.flags)
    testing.expect(t, info.value > 0 && info.value < 1, "the knob is on its way a frame after the click")
    idle(extra, 120)
    info, _ = infoOf(extra, id)
    testing.expect(t, info.value > 0.99, "and arrives")
    clickAt(extra, centerOf(t, extra, id))
    testing.expect(t, !extra.on)
}

@(test)
test_chips_are_chosen_and_a_tag_is_removed_by_its_cross :: proc(t: ^testing.T) {
    extra: ^Extra = new(Extra)
    defer free(extra)
    extraInit(extra)
    idle(extra, 2)
    wayland: Id = UiIdPath("window", "Wayland")
    folder: Id = UiIdPath("window", "Folder")
    before: Rect = rectOf(t, extra, wayland)
    info, _ := infoOf(extra, wayland)
    testing.expect(t, info.kind == .CHIP && .SELECTED not_in info.flags)
    clickAt(extra, centerOf(t, extra, wayland))
    testing.expect(t, extra.chips[0] && !extra.chips[1])
    info, _ = infoOf(extra, wayland)
    testing.expect(t, .SELECTED in info.flags)
    // a chosen chip without an icon gets room for its check mark; one with an icon always has the room
    after: Rect = rectOf(t, extra, wayland)
    testing.expect(t, after.z > before.z)
    info, _ = infoOf(extra, folder)
    testing.expect_value(t, info.icon, Icon.FOLDER)

    // the tag: a click on its name is a click, a click on the cross at its right end takes it away
    tag: Id = UiIdPath("window", "odin")
    rect: Rect = rectOf(t, extra, tag)
    info, _ = infoOf(extra, tag)
    testing.expect(t, info.kind == .CHIP && info.actual == 1 && info.ratio > 0, "a tag is a chip with a cross")
    clickAt(extra, {rect.x + 12, rect.y + rect.w * 0.5})
    testing.expect(t, extra.tag_clicked && !extra.tag_removed)
    extra.tag_clicked = false
    clickAt(extra, {rect.x + rect.z - 8, rect.y + rect.w * 0.5})
    testing.expect(t, extra.tag_removed && !extra.tag_clicked)
}

@(test)
test_a_segment_is_chosen_and_breadcrumbs_tell_which_part_was_clicked :: proc(t: ^testing.T) {
    extra: ^Extra = new(Extra)
    defer free(extra)
    extraInit(extra)
    idle(extra, 2)
    track: Id = UiIdPath("window", "density")
    info, found := infoOf(extra, track)
    testing.expect(t, found && info.kind == .SEGMENTED)
    info, _ = infoOf(extra, IdFromIndex(0, track))
    testing.expect(t, info.kind == .SEGMENT && .SELECTED in info.flags && info.name == "Compact")
    clickAt(extra, centerOf(t, extra, IdFromIndex(2, track)))
    testing.expect_value(t, extra.segment, 2)
    testing.expect_value(t, extra.segment_changed, 1)
    clickAt(extra, centerOf(t, extra, IdFromIndex(2, track)))
    testing.expect_value(t, extra.segment_changed, 1)                           // the chosen one again: nothing changed
    info, _ = infoOf(extra, IdFromIndex(2, track))
    testing.expect(t, .SELECTED in info.flags)
    info, _ = infoOf(extra, IdFromIndex(0, track))
    testing.expect(t, .SELECTED not_in info.flags)

    // the last part is where the user is: it is marked and takes no click; the ones before it do
    path: Id = UiIdPath("window", "path")
    info, _ = infoOf(extra, IdFromIndex(2, path))
    testing.expect(t, info.kind == .BREADCRUMB && .SELECTED in info.flags && info.name == "here")
    clickAt(extra, centerOf(t, extra, IdFromIndex(2, path)))
    testing.expect_value(t, extra.crumb, -1)
    clickAt(extra, centerOf(t, extra, IdFromIndex(1, path)))
    testing.expect_value(t, extra.crumb, 1)
    clickAt(extra, centerOf(t, extra, IdFromIndex(0, path)))
    testing.expect_value(t, extra.crumb, 0)
    // an arrow between the parts
    arrows: int
    for command in UiCommands(&extra.ctx) {
        if command.kind == .DRAW && command.info.kind == .ICON && Icon(int(command.info.actual)) == .CHEVRON_RIGHT { arrows += 1 }
    }
    testing.expect_value(t, arrows, 2)
}

@(test)
test_badges_avatars_titles_and_cards_reach_the_style :: proc(t: ^testing.T) {
    extra: ^Extra = new(Extra)
    defer free(extra)
    extraInit(extra)
    idle(extra, 2)
    badge, avatar, spinner: DrawInfo
    panels: int
    for command in UiCommands(&extra.ctx) {
        if command.kind != .DRAW { continue }
        #partial switch command.info.kind {
        case .BADGE:
            badge = command.info
        case .AVATAR:
            avatar = command.info
        case .SPINNER:
            spinner = command.info
        case .PANEL:
            if command.info.name == "Card" { panels += 1 }
        }
    }
    testing.expect_value(t, badge.name, "Failed")
    testing.expect_value(t, Tone(int(badge.actual)), Tone.DANGER)
    testing.expect(t, badge.font_size < DEFAULT_METRICS.font_size, "a badge is small text")
    testing.expect_value(t, avatar.name, "AL")
    testing.expect_value(t, avatar.color, Color{10, 20, 30, 255})
    testing.expect(t, avatar.rect.z == avatar.rect.w && avatar.rect.z > DEFAULT_METRICS.control_height, "a disc")
    testing.expect(t, spinner.rect.z > 0)
    testing.expect_value(t, panels, 1)

    // texts carry the tags that were pushed when they were declared: a style draws a title strong and a hint dim
    title, title_found := textInfo(extra, "A title")
    hint, hint_found := textInfo(extra, "a hint")
    plain, plain_found := textInfo(extra, "plain text")
    card_title, card_title_found := textInfo(extra, "Card")
    testing.expect(t, title_found && hint_found && plain_found && card_title_found)
    testing.expect(t, DrawInfoHasTag(&title, "title") && !DrawInfoHasTag(&title, "dim"))
    testing.expect(t, title.font_size > DEFAULT_METRICS.font_size)
    testing.expect(t, DrawInfoHasTag(&hint, "dim") && !DrawInfoHasTag(&hint, "title"))
    testing.expect(t, !DrawInfoHasTag(&plain, "title") && !DrawInfoHasTag(&plain, "dim"))
    testing.expect(t, DrawInfoHasTag(&card_title, "title"), "the title of a card is a title")

    // an element of the program takes clicks through UiInteract
    clickAt(extra, centerOf(t, extra, UiIdPath("window", "row")))
    testing.expect_value(t, extra.row_clicks, 1)
    testing.expect_value(t, UiProblems(&extra.ctx), Problems{})
}

// A measure proc that knows two faces: a text inside of the tag "mono" is twice as wide
@(private = "file")
measureFaces :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    width: f32 = f32(len(text)) * font_size * 0.5
    return {width * 2 if UiMeasureHasTag(ctx, "mono") else width, font_size}
}

@(test)
test_a_text_is_measured_with_the_tags_it_is_drawn_with :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(64, 128, 32, 1024),
        ctx: Context,
        style: Style,
        area: [64]u8,
        area_length: int,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measureFaces)
    test.area_length = copy(test.area[:], "aaaa bbbb cccc dddd")
    for _ in 0 ..< 2 {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(600), {}}) {
            UiLabel(&test.ctx, "same text")
            if UiTagged(&test.ctx, "mono") { UiLabel(&test.ctx, "same text") }
            UiLabel(&test.ctx, "same text")
            // a wrapped text breaks by the widths of its face: 19 characters are 152 wide in the plain face and 304 in the other
            ElementOpen(&test.ctx, {id = UiId(&test.ctx, "narrow"), layout = {size = {Fixed(200), Fit()}, direction = .TOP_TO_BOTTOM}})
            UiLabel(&test.ctx, "aaaa bbbb cccc dddd##plain", .WORDS)
            if UiTagged(&test.ctx, "mono") { UiLabel(&test.ctx, "aaaa bbbb cccc dddd##wide", .WORDS) }
            ElementClose(&test.ctx)
            if UiTagged(&test.ctx, "mono") { UiTextArea(&test.ctx, "area", test.area[:], &test.area_length, {Fixed(200), Fixed(120)}) }
        }
        UiEnd(&test.ctx)
    }
    widths: [3]f32
    count: int
    plain_lines, wide_lines: int
    for command in UiCommands(&test.ctx) {
        if command.kind != .DRAW || command.info.kind != .LABEL { continue }
        info: DrawInfo = command.info
        if info.text == "same text" && count < 3 {
            widths[count] = info.rect.z
            count += 1
        }
        if info.name == "aaaa bbbb cccc dddd" {
            if DrawInfoHasTag(&info, "mono") { wide_lines += 1 } else { plain_lines += 1 }
        }
    }
    testing.expect_value(t, count, 3)
    testing.expect_value(t, widths[0], 72)
    testing.expect_value(t, widths[1], 144)                     // the tagged one: measured in its face
    testing.expect_value(t, widths[2], 72)                      // and the tags do not stay for the next text (nor in the cache)
    testing.expect_value(t, plain_lines, 1)
    testing.expect(t, wide_lines >= 2, "the same words wrap in the wider face")
    // outside of a measure there are no tags
    testing.expect(t, !UiMeasureHasTag(&test.ctx, "mono"))
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_code_is_cut_into_spans :: proc(t: ^testing.T) {
    Expected :: struct { text: string, tag: string }
    check :: proc(t: ^testing.T, source: string, expected: []Expected, language: ^HighlightLanguage = nil) {
        spans: [16]TextSpan
        count: int = HighlightCode(source, 0, len(source), spans[:], language)
        testing.expectf(t, count == len(expected), "%q: %d spans, expected %d", source, count, len(expected))
        at: int
        for want, i in expected {
            if i >= count { break }
            testing.expectf(t, source[at:at + spans[i].length] == want.text && spans[i].tag == want.tag, "%q: span %d is %q %q", source, i, source[at:at + spans[i].length], spans[i].tag)
            at += spans[i].length
        }
    }
    check(t, "", {})
    check(t, "main :: proc() {", {{"main :: ", ""}, {"proc", SYNTAX_KEYWORD}, {"() {", ""}})
    check(t, "count: int = 0x1F // a number", {{"count: ", ""}, {"int", SYNTAX_TYPE}, {" = ", ""}, {"0x1F", SYNTAX_NUMBER}, {" ", ""}, {"// a number", SYNTAX_COMMENT}})
    check(t, "x := 1.5e3 + y.z", {{"x := ", ""}, {"1.5e3", SYNTAX_NUMBER}, {" + y.z", ""}})
    check(t, "say(\"a \\\" b // not\", 'c')", {{"say(", ""}, {"\"a \\\" b // not\"", SYNTAX_STRING}, {", ", ""}, {"'c'", SYNTAX_STRING}, {")", ""}})
    check(t, "s := `raw \\` + \"open", {{"s := ", ""}, {"`raw \\`", SYNTAX_STRING}, {" + ", ""}, {"\"open", SYNTAX_STRING}})
    // a word that only starts like a keyword is a name
    check(t, "format if_ready process", {{"format if_ready process", ""}})
    python: HighlightLanguage = {keywords = {"def", "return"}, line_comment = "#"}
    check(t, "def f(): # go", {{"def", SYNTAX_KEYWORD}, {" f(): ", ""}, {"# go", SYNTAX_COMMENT}}, &python)
    check(t, "x // y", {{"x // y", ""}}, &python)
    // a row of a longer text, and room for fewer spans than the row has: the rest is left to the caller
    text: string = "a := 1\nreturn a"
    spans: [2]TextSpan
    testing.expect_value(t, HighlightCode(text, 7, len(text), spans[:], nil), 2)
    testing.expect(t, spans[0] == TextSpan{6, SYNTAX_KEYWORD} && spans[1] == TextSpan{2, ""})
    testing.expect_value(t, HighlightCode("a = 1 + 2 + 3", 0, 13, spans[:], nil), 2)
}

@(test)
test_a_text_area_draws_its_rows_in_spans :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 2048),
        ctx: Context,
        style: Style,
        text: [128]u8,
        length: int,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measureFaces)
    test.length = copy(test.text[:], "x: int = 42 // answer\nplain line\n\nreturn \"done\"")
    for _ in 0 ..< 2 {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {1200, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(1000), {}}) {
            // in the code face (twice as wide in this test): every span is placed by the widths of that face, not only the first of the area
            if UiTagged(&test.ctx, "mono") { UiTextArea(&test.ctx, "code", test.text[:], &test.length, {Fixed(900), Fixed(200)}, false, false, HighlightCode) }
        }
        UiEnd(&test.ctx)
    }
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
    find :: proc(ctx: ^Context, text: string) -> (info: DrawInfo, found: bool) {
        for command in UiCommands(ctx) {
            if command.kind == .DRAW && command.info.kind == .LABEL && command.info.text == text { return command.info, true }
        }
        return
    }
    size: f32 = DEFAULT_METRICS.font_size
    name, name_found := find(&test.ctx, "x: ")
    type, type_found := find(&test.ctx, "int")
    number, number_found := find(&test.ctx, "42")
    comment, comment_found := find(&test.ctx, "// answer")
    plain, plain_found := find(&test.ctx, "plain line")
    keyword, keyword_found := find(&test.ctx, "return")
    text, text_found := find(&test.ctx, "\"done\"")
    testing.expect(t, name_found && type_found && number_found && comment_found && plain_found && keyword_found && text_found, "every span is a text")
    testing.expect(t, DrawInfoHasTag(&type, SYNTAX_TYPE) && DrawInfoHasTag(&number, SYNTAX_NUMBER) && DrawInfoHasTag(&comment, SYNTAX_COMMENT) && DrawInfoHasTag(&keyword, SYNTAX_KEYWORD) && DrawInfoHasTag(&text, SYNTAX_STRING))
    testing.expect(t, !DrawInfoHasTag(&name, SYNTAX_TYPE) && !DrawInfoHasTag(&plain, SYNTAX_KEYWORD))
    // a span starts where the text before it ends: a size per letter in this face
    testing.expect_value(t, type.rect.x - name.rect.x, size * 3)
    testing.expect_value(t, number.rect.x - name.rect.x, size * 9)
    testing.expect_value(t, comment.rect.x - name.rect.x, size * 12)
    testing.expect_value(t, text.rect.x - keyword.rect.x, size * 7)
    testing.expect(t, type.rect.y == name.rect.y && plain.rect.y > name.rect.y && keyword.rect.y > plain.rect.y)
}

@(test)
test_comments_and_raw_strings_go_over_rows :: proc(t: ^testing.T) {
    // the rows of a text, each highlighted with the state the one before left
    Row :: struct { text: string, tags: [3]string, pieces: [3]string }
    check :: proc(t: ^testing.T, rows: []Row, language: ^HighlightLanguage = nil) {
        state: u32
        for row, r in rows {
            spans: [8]TextSpan
            count: int = HighlightCode(row.text, 0, len(row.text), spans[:], language, &state)
            at: int
            for i in 0 ..< 3 {
                if row.pieces[i] == "" {
                    testing.expectf(t, count <= i, "row %d %q has %d spans", r, row.text, count)
                    break
                }
                testing.expectf(t, i < count && row.text[at:at + spans[i].length] == row.pieces[i] && spans[i].tag == row.tags[i], "row %d %q: span %d", r, row.text, i)
                if i < count { at += spans[i].length }
            }
        }
        testing.expect_value(t, state, 0)
    }
    check(t, {
        {"a /* one", {"", SYNTAX_COMMENT, ""}, {"a ", "/* one", ""}},
        {"still /* deeper */ in", {SYNTAX_COMMENT, "", ""}, {"still /* deeper */ in", "", ""}},
        {"", {}, {}},
        {"end */ b := 1", {SYNTAX_COMMENT, "", SYNTAX_NUMBER}, {"end */", " b := ", "1"}},
        {"s := `raw", {"", SYNTAX_STRING, ""}, {"s := ", "`raw", ""}},
        {"// not a comment \\", {SYNTAX_STRING, "", ""}, {"// not a comment \\", "", ""}},
        {"end` + 2", {SYNTAX_STRING, "", SYNTAX_NUMBER}, {"end`", " + ", "2"}},
        {"/* a */ /* b */ x", {SYNTAX_COMMENT, "", SYNTAX_COMMENT}, {"/* a */", " ", "/* b */"}},
    })
    // C: the first end closes the comment, a backtick is nothing
    c: HighlightLanguage = {keywords = {"int"}, line_comment = "//", block_open = "/*", block_close = "*/"}
    check(t, {
        {"/* a /* b", {SYNTAX_COMMENT, "", ""}, {"/* a /* b", "", ""}},
        {"c */ int x", {SYNTAX_COMMENT, "", SYNTAX_KEYWORD}, {"c */", " ", "int"}},
        {"` int", {"", SYNTAX_KEYWORD, ""}, {"` ", "int", ""}},
    }, &c)
    // the state is right also when the spans have no room
    state: u32
    none: [1]TextSpan
    HighlightCode("a b 1 2 /* open", 0, 15, none[:], nil, &state)
    testing.expect_value(t, state, 1)
    HighlightCode("x", 0, 1, nil, nil, &state)
    testing.expect_value(t, state, 1)
}

@(test)
test_a_text_area_keeps_the_state_of_its_rows :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(128, 256, 64, 2048),
        ctx: Context,
        style: Style,
        text: [128]u8,
        length: int,
        calls: int,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measureFaces)
    test.length = copy(test.text[:], "a := 1 /* note\nreturn inside\nend */ return b")
    // a highlighter that counts how often it is asked
    counting :: proc(text: string, row_start: int, row_end: int, spans: []TextSpan, user: rawptr, state: ^u32) -> int {
        (cast(^int)user)^ += 1
        return HighlightCode(text, row_start, row_end, spans, nil, state)
    }
    frame :: proc(test: ^Test) {
        UiBegin(&test.ctx, {mouse_position = {-100, -100}}, 1.0 / 60, {1200, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(1000), {}}) {
            UiTextArea(&test.ctx, "code", test.text[:], &test.length, {Fixed(900), Fixed(200)}, false, false, counting, &test.calls)
        }
        UiEnd(&test.ctx)
    }
    find :: proc(ctx: ^Context, text: string) -> (info: DrawInfo, found: bool) {
        for command in UiCommands(ctx) {
            if command.kind == .DRAW && command.info.kind == .LABEL && command.info.text == text { return command.info, true }
        }
        return
    }
    frame(test)
    frame(test)
    inside, inside_found := find(&test.ctx, "return inside")
    testing.expect(t, inside_found && DrawInfoHasTag(&inside, SYNTAX_COMMENT), "the row inside of the comment is a comment, its keyword too")
    end, end_found := find(&test.ctx, "end */")
    keyword, keyword_found := find(&test.ctx, "return")
    testing.expect(t, end_found && DrawInfoHasTag(&end, SYNTAX_COMMENT) && keyword_found && DrawInfoHasTag(&keyword, SYNTAX_KEYWORD), "after the end of the comment it is code again")
    // while the text is the same a frame only asks for the rows in view (3), the states are kept
    before: int = test.calls
    frame(test)
    testing.expect_value(t, test.calls - before, 3)
    // the text changes: the comment is closed in its first row, the second row is code
    test.length = copy(test.text[:], "a := 1 /* note */\nreturn inside\nend")
    frame(test)
    testing.expect_value(t, test.calls - before, 3 + 6)         // all rows for the states, then the rows in view
    _, inside_found = find(&test.ctx, "return inside")
    testing.expect(t, !inside_found)
    keyword, keyword_found = find(&test.ctx, "return")
    testing.expect(t, keyword_found && DrawInfoHasTag(&keyword, SYNTAX_KEYWORD))
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_a_drag_that_rests_over_a_widget_fires_once :: proc(t: ^testing.T) {
    Test :: struct {
        storage: Storage(64, 128, 32, 1024),
        ctx: Context,
        style: Style,
        source, folder, other: Id,
        fired: int,
        fired_other: int,
        payload: int,
    }
    test: ^Test = new(Test)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measureFaces)
    frame :: proc(test: ^Test, input: Input, delta_time: f32 = 0.1) {
        UiBegin(&test.ctx, input, delta_time, {800, 600}, &test.style)
        if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(400), {}}) {
            test.source = UiId(&test.ctx, "file")
            UiButton(&test.ctx, "file", {Fixed(300), {}})
            UiDragSourceValue(&test.ctx, "file", &test.payload)
            test.folder = UiId(&test.ctx, "folder")
            UiButton(&test.ctx, "folder", {Fixed(300), {}})
            if UiDragRest(&test.ctx, "file", 0.5) { test.fired += 1 }
            test.other = UiId(&test.ctx, "other")
            UiButton(&test.ctx, "other", {Fixed(300), {}})
            if UiDragRest(&test.ctx, "picture", 0.5) { test.fired_other += 1 }
        }
        UiEnd(&test.ctx)
    }
    center :: proc(test: ^Test, id: Id) -> Vec2 {
        rect, _ := UiElementRect(&test.ctx, id)
        return {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    }
    for _ in 0 ..< 2 { frame(test, {mouse_position = {-100, -100}}) }
    from: Vec2 = center(test, test.source)
    over: Vec2 = center(test, test.folder)
    // the pointer rests over the folder without a drag: nothing
    for _ in 0 ..< 10 { frame(test, {mouse_position = over}) }
    testing.expect_value(t, test.fired, 0)
    // a drag from the file to the folder
    frame(test, {mouse_position = from})
    frame(test, {mouse_position = from, mouse_down = true, mouse_pressed = true})
    frame(test, {mouse_position = from + {20, 0}, mouse_down = true})
    _, dragging := UiDragging(&test.ctx)
    testing.expect(t, dragging)
    // it moves over the folder: no rest while it moves
    for i in 0 ..< 10 { frame(test, {mouse_position = over + {f32(i % 2) * 30, 0}, mouse_down = true}) }
    testing.expect_value(t, test.fired, 0)
    // it stands: after half a second it fires, once
    for _ in 0 ..< 4 { frame(test, {mouse_position = over, mouse_down = true}) }
    testing.expect_value(t, test.fired, 0)
    for _ in 0 ..< 4 { frame(test, {mouse_position = over, mouse_down = true}) }
    testing.expect_value(t, test.fired, 1)
    for _ in 0 ..< 20 { frame(test, {mouse_position = over + {1, 1}, mouse_down = true}) }
    testing.expect_value(t, test.fired, 1)
    // it moves and stands again: again
    frame(test, {mouse_position = over + {40, 0}, mouse_down = true})
    for _ in 0 ..< 10 { frame(test, {mouse_position = over + {40, 0}, mouse_down = true}) }
    testing.expect_value(t, test.fired, 2)
    // over a widget that waits for another kind: nothing
    for _ in 0 ..< 12 { frame(test, {mouse_position = center(test, test.other), mouse_down = true}) }
    testing.expect_value(t, test.fired_other, 0)
    testing.expect_value(t, test.fired, 2)
    frame(test, {mouse_position = {-100, -100}, mouse_released = true})
    frame(test, {mouse_position = {-100, -100}})
    _, dragging = UiDragging(&test.ctx)
    testing.expect(t, !dragging)
}
