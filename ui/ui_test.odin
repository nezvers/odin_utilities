#+build !js
package ui

import "core:testing"

// A font where every character is half as wide as it is high: no framework needed to test a layout
@(private = "file", thread_local)
measure_calls: int          // how often the ui asked the measure proc (per test thread)

@(private = "file")
testMeasure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    measure_calls += 1
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(private = "file")
TestStorage :: Storage(64, 128, 32, 1024)

// What the styles of the tests saw
@(private = "file")
Seen :: struct {
    kinds: [StyleKind]int,
    last: [StyleKind]DrawInfo,
    clip_begin: int,
    clip_end: int,
}

@(private = "file", thread_local)
seen: Seen            // per test thread: the tests run in parallel

@(private = "file")
testStyle :: proc(ctx: ^Context, info: ^DrawInfo) {
    seen.kinds[info.kind] += 1
    seen.last[info.kind] = info^
}

@(private = "file")
testClip :: proc(ctx: ^Context, rect: Rect, begin: bool) {
    if begin { seen.clip_begin += 1 } else { seen.clip_end += 1 }
}

@(private = "file")
makeStyle :: proc() -> Style {
    style: Style = {metrics = DEFAULT_METRICS, clip = testClip}
    for &entry in style.procs {
        entry = testStyle
    }
    return style
}

@(private = "file")
Harness :: struct {
    storage: TestStorage,
    ctx: Context,
    style: Style,
}

@(private = "file")
harnessInit :: proc(harness: ^Harness) {
    harness.style = makeStyle()
    UiInit(&harness.ctx, &harness.storage, testMeasure)
    seen = {}
}

@(private = "file")
frame :: proc(harness: ^Harness, input: Input = {}, screen: Vec2 = {400, 300}) {
    UiBegin(&harness.ctx, input, 1.0 / 60, screen, &harness.style)
}

@(private = "file")
pointerAt :: proc(position: Vec2, down: bool = false, pressed: bool = false, released: bool = false) -> Input {
    return {mouse_position = position, mouse_down = down, mouse_pressed = pressed, mouse_released = released}
}

@(private = "file")
near :: proc(a: f32, b: f32) -> bool {
    return abs(a - b) < 0.01
}

@(test)
test_ids_depend_on_the_name_and_the_seed :: proc(t: ^testing.T) {
    a: Id = IdFromString("Ok")
    testing.expect(t, a != 0)
    testing.expect_value(t, IdFromString("Ok"), a)
    testing.expect(t, IdFromString("Ok", 5) != a)
    testing.expect(t, IdFromString("Cancel") != a)
    testing.expect(t, IdFromIndex(0, a) != IdFromIndex(1, a))
    testing.expect_value(t, IdSplitName("Save##slot2"), "Save")
    testing.expect_value(t, IdSplitName("Save"), "Save")
    testing.expect_value(t, IdSplitName("##hidden"), "")
}

@(test)
test_column_places_children_with_padding_and_gap :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    ElementOpen(&harness.ctx, {id = 10, layout = {padding = PaddingAll(5), gap = 3}})
    ElementOpen(&harness.ctx, {id = 11, layout = {size = {Fixed(40), Fixed(20)}}})
    ElementClose(&harness.ctx)
    ElementOpen(&harness.ctx, {id = 12, layout = {size = {Fixed(60), Fixed(10)}}})
    ElementClose(&harness.ctx)
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)

    outer, _ := UiElementRect(&harness.ctx, 10)
    first, _ := UiElementRect(&harness.ctx, 11)
    second, _ := UiElementRect(&harness.ctx, 12)
    testing.expect_value(t, outer, Rect{0, 0, 70, 43})                  // 60 wide + 2 * 5, 20 + 3 + 10 + 2 * 5 high
    testing.expect_value(t, first, Rect{5, 5, 40, 20})
    testing.expect_value(t, second, Rect{5, 28, 60, 10})
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(test)
test_grow_shares_what_is_left :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    ElementOpen(&harness.ctx, {id = 10, layout = {size = {Fixed(300), Fixed(50)}, direction = .LEFT_TO_RIGHT, gap = 10}})
    ElementOpen(&harness.ctx, {id = 11, layout = {size = {Fixed(100), Grow()}}})
    ElementClose(&harness.ctx)
    ElementOpen(&harness.ctx, {id = 12, layout = {size = {Grow(), Grow()}}})
    ElementClose(&harness.ctx)
    ElementOpen(&harness.ctx, {id = 13, layout = {size = {Grow(), Grow()}}})
    ElementClose(&harness.ctx)
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)

    fixed, _ := UiElementRect(&harness.ctx, 11)
    left, _ := UiElementRect(&harness.ctx, 12)
    right, _ := UiElementRect(&harness.ctx, 13)
    testing.expect_value(t, fixed.z, 100)
    testing.expect(t, near(left.z, 90), "the two grow elements share 300 - 100 - 2 * 10")
    testing.expect(t, near(right.z, 90))
    testing.expect_value(t, fixed.w, 50)                                // grow takes the height of the parent
    testing.expect(t, near(right.x, 210))
}

@(test)
test_percent_and_alignment :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    ElementOpen(&harness.ctx, {id = 10, layout = {size = {Fixed(200), Fixed(100)}, align = {x = .CENTER, y = .CENTER}}})
    ElementOpen(&harness.ctx, {id = 11, layout = {size = {Percent(0.5), Fixed(20)}}})
    ElementClose(&harness.ctx)
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)

    child, _ := UiElementRect(&harness.ctx, 11)
    testing.expect_value(t, child, Rect{50, 40, 100, 20})               // centered on x and on y
}

@(test)
test_text_wraps_in_the_width_it_gets :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    // 16 px font: 8 px per character. "aaaa bbbb cccc" is 14 characters = 112 px, the box is 80 px (10 characters)
    ElementOpen(&harness.ctx, {id = 10, layout = {size = {Fixed(80), Fit()}}})
    TextOpen(&harness.ctx, "aaaa bbbb cccc", {wrap = .WORDS})
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)

    box, _ := UiElementRect(&harness.ctx, 10)
    testing.expect_value(t, box.w, 32)                                  // two lines of 16
    lines: int = 0
    for command in UiCommands(&harness.ctx) {
        if command.kind == .DRAW && command.info.kind == .LABEL {
            lines += 1
            if lines == 1 { testing.expect_value(t, command.info.text, "aaaa bbbb") }
            if lines == 2 { testing.expect_value(t, command.info.text, "cccc") }
        }
    }
    testing.expect_value(t, lines, 2)
}

@(test)
test_text_without_wrap_keeps_one_line_and_newlines_break :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    ElementOpen(&harness.ctx, {id = 10, layout = {size = {Fixed(80), Fit()}}})
    TextOpen(&harness.ctx, "aaaa bbbb cccc", {wrap = .NONE})
    TextOpen(&harness.ctx, "one\ntwo", {wrap = .NEWLINES})
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)

    texts: [dynamic]string
    defer delete(texts)
    for command in UiCommands(&harness.ctx) {
        if command.kind == .DRAW && command.info.kind == .LABEL {
            append(&texts, command.info.text)
        }
    }
    testing.expect_value(t, len(texts), 3)
    if len(texts) == 3 {
        testing.expect_value(t, texts[0], "aaaa bbbb cccc")
        testing.expect_value(t, texts[1], "one")
        testing.expect_value(t, texts[2], "two")
    }
}

@(test)
test_floating_element_is_attached_under_its_parent :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    ElementOpen(&harness.ctx, {id = 10, layout = {padding = PaddingAll(20)}})
    ElementOpen(&harness.ctx, {id = 11, layout = {size = {Fixed(100), Fixed(30)}}})
    ElementClose(&harness.ctx)
    ElementOpen(&harness.ctx, {
        id = 12,
        layout = {size = {Grow(), Fixed(50)}},
        floating = {attach_to = .ELEMENT_WITH_ID, parent = 11, parent_point = .LEFT_BOTTOM, element_point = .LEFT_TOP, offset = {0, 4}},
    })
    ElementClose(&harness.ctx)
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)

    popup, found := UiElementRect(&harness.ctx, 12)
    testing.expect(t, found)
    testing.expect_value(t, popup, Rect{20, 54, 100, 50})               // under the 100 x 30 element at (20, 20), 4 px lower, as wide as it
    parent, _ := UiElementRect(&harness.ctx, 10)
    testing.expect_value(t, parent.w, 70)                               // the floating element is not part of the layout of its parent
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(test)
test_floating_without_a_parent_is_reported :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    ElementOpen(&harness.ctx, {id = 12, floating = {attach_to = .ELEMENT_WITH_ID, parent = 999}})
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)
    testing.expect(t, .PARENT_NOT_FOUND in harness.ctx.problems)
}

@(test)
test_clip_container_scrolls_and_pairs_its_clip_commands :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    ElementOpen(&harness.ctx, {id = 10, layout = {size = {Fixed(100), Fixed(50)}}, clip = {vertical = true, offset = {0, -30}}})
    for i in 0 ..< 5 {
        ElementOpen(&harness.ctx, {id = Id(100 + i), layout = {size = {Grow(), Fixed(20)}}})
        ElementClose(&harness.ctx)
    }
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)
    UiRender(&harness.ctx)

    area, _ := UiElementRect(&harness.ctx, 10)
    testing.expect_value(t, area.w, 50)                                 // the content (100 high) does not make a clipping container bigger
    second, _ := UiElementRect(&harness.ctx, 101)
    testing.expect_value(t, second.y, 20 - 30)                          // moved by the scroll offset
    testing.expect_value(t, seen.clip_begin, 1)
    testing.expect_value(t, seen.clip_end, 1)
}

@(test)
test_button_is_clicked_by_press_and_release_on_it :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    clicks: int = 0
    // frame 1 lays it out, 2 moves the pointer on it, 3 presses, 4 lets go
    inputs: [4]Input = {
        pointerAt({-100, -100}),
        pointerAt({20, 12}),
        pointerAt({20, 12}, down = true, pressed = true),
        pointerAt({20, 12}, released = true),
    }
    for input in inputs {
        frame(harness, input)
        if UiButton(&harness.ctx, "Ok") { clicks += 1 }
        UiEnd(&harness.ctx)
        UiRender(&harness.ctx)
    }
    testing.expect_value(t, clicks, 1)
    testing.expect(t, seen.kinds[.BUTTON] >= 4)
    testing.expect_value(t, seen.last[.BUTTON].name, "Ok")
    testing.expect(t, UiPointerOverUi(&harness.ctx) == false || UiPointerOverUi(&harness.ctx) == true)
}

@(test)
test_button_is_not_clicked_when_the_press_leaves_it :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    clicks: int = 0
    inputs: [4]Input = {
        pointerAt({-100, -100}),
        pointerAt({20, 12}),
        pointerAt({20, 12}, down = true, pressed = true),
        pointerAt({300, 250}, released = true),         // let go somewhere else
    }
    for input in inputs {
        frame(harness, input)
        if UiButton(&harness.ctx, "Ok") { clicks += 1 }
        UiEnd(&harness.ctx)
    }
    testing.expect_value(t, clicks, 0)
}

@(test)
test_slider_follows_the_pointer_while_dragged :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    value: f32 = 0
    // a slider 160 wide at x 0: x = 80 is half
    inputs: [4]Input = {
        pointerAt({-100, -100}),
        pointerAt({80, 12}),
        pointerAt({80, 12}, down = true, pressed = true),
        pointerAt({120, 12}, down = true),
    }
    for input in inputs {
        frame(harness, input)
        UiSlider(&harness.ctx, "Volume", &value, 0, 200)
        UiEnd(&harness.ctx)
        UiRender(&harness.ctx)
    }
    testing.expect(t, near(value, 150), "x 120 of 160 is 0.75 of 200")
    info: DrawInfo = seen.last[.SLIDER]
    testing.expect(t, near(info.value, 0.75))
    testing.expect(t, near(info.actual, 150))
    testing.expect_value(t, info.maximum, 200)
    testing.expect_value(t, info.text, "150.00")
    testing.expect(t, .PRESSED in info.flags)
}

@(test)
test_toggle_and_progress_give_the_style_their_values :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    on: bool = false
    inputs: [4]Input = {
        pointerAt({-100, -100}),
        pointerAt({10, 10}),
        pointerAt({10, 10}, down = true, pressed = true),
        pointerAt({10, 10}, released = true),
    }
    for input in inputs {
        frame(harness, input)
        UiToggle(&harness.ctx, "Music", &on)
        UiProgress(&harness.ctx, "Loading", 30, 0, 120)
        UiEnd(&harness.ctx)
        UiRender(&harness.ctx)
    }
    testing.expect(t, on)
    testing.expect(t, .ON in seen.last[.TOGGLE].flags)
    testing.expect(t, near(seen.last[.PROGRESS].value, 0.25))
    testing.expect(t, near(seen.last[.PROGRESS].actual, 30))
    testing.expect_value(t, seen.last[.PROGRESS].name, "Loading")
}

@(test)
test_text_field_edits_its_buffer :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    buffer: [16]u8
    length: int = 0
    typed: Input = pointerAt({20, 12})
    typed.text[0] = 'h'
    typed.text[1] = 'i'
    typed.text_count = 2
    backspace: Input = pointerAt({20, 12})
    backspace.keys = {.BACKSPACE}
    enter: Input = pointerAt({20, 12})
    enter.keys = {.ENTER}
    inputs: [6]Input = {
        pointerAt({-100, -100}),
        pointerAt({20, 12}),
        pointerAt({20, 12}, down = true, pressed = true),   // click: it gets the focus
        typed,
        backspace,
        enter,
    }
    submitted_seen: bool = false
    for input in inputs {
        frame(harness, input)
        _, submitted := UiTextField(&harness.ctx, "Name", buffer[:], &length)
        if submitted { submitted_seen = true }
        UiEnd(&harness.ctx)
    }
    testing.expect_value(t, string(buffer[:length]), "h")
    testing.expect(t, submitted_seen)
}

@(test)
test_dropdown_opens_and_selects :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    options: [3]string = {"Low", "Medium", "High"}
    selected: int = 0
    changed_seen: bool = false
    run :: proc(harness: ^Harness, input: Input, options: []string, selected: ^int, changed_seen: ^bool) {
        frame(harness, input)
        if UiDropdown(&harness.ctx, "Quality", options, selected) { changed_seen^ = true }
        UiEnd(&harness.ctx)
        UiRender(&harness.ctx)
    }
    // the box is 160 wide at the top left. Open it with a click, then click the third option (rows of 28 under the box, 2 px padding)
    run(harness, pointerAt({-100, -100}), options[:], &selected, &changed_seen)
    run(harness, pointerAt({20, 12}), options[:], &selected, &changed_seen)
    run(harness, pointerAt({20, 12}, down = true, pressed = true), options[:], &selected, &changed_seen)
    run(harness, pointerAt({20, 12}, released = true), options[:], &selected, &changed_seen)
    run(harness, pointerAt({20, 12}), options[:], &selected, &changed_seen)
    testing.expect(t, seen.kinds[.DROPDOWN_ITEM] > 0, "the list is shown")
    third_y: f32 = 28 + 2 + 28 * 2 + 14
    run(harness, pointerAt({20, third_y}), options[:], &selected, &changed_seen)
    run(harness, pointerAt({20, third_y}, down = true, pressed = true), options[:], &selected, &changed_seen)
    run(harness, pointerAt({20, third_y}, released = true), options[:], &selected, &changed_seen)
    testing.expect_value(t, selected, 2)
    testing.expect(t, changed_seen)
    seen.kinds[.DROPDOWN_ITEM] = 0
    run(harness, pointerAt({20, third_y}), options[:], &selected, &changed_seen)
    testing.expect_value(t, seen.kinds[.DROPDOWN_ITEM], 0)              // the list closed
}

@(test)
test_scroll_container_takes_the_wheel :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    wheel: Input = pointerAt({50, 50})
    wheel.wheel = {0, -1}
    inputs: [4]Input = {pointerAt({50, 50}), pointerAt({50, 50}), wheel, pointerAt({50, 50})}
    for input in inputs {
        frame(harness, input)
        if UiScroll(&harness.ctx, "List", {Fixed(100), Fixed(100)}) {
            for i in 0 ..< 10 {
                UiLabel(&harness.ctx, "item")
                _ = i
            }
        }
        UiEnd(&harness.ctx)
        UiRender(&harness.ctx)
    }
    testing.expect(t, UiScrollGet(&harness.ctx, UiIdPath("List")) > 0)
    testing.expect(t, seen.kinds[.SCROLLBAR] > 0)
    testing.expect(t, UiPointerOverUi(&harness.ctx))
}

@(test)
test_state_of_widgets_that_are_gone_is_released :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    for i in 0 ..< 3 {
        frame(harness)
        UiButton(&harness.ctx, "A")
        UiButton(&harness.ctx, "B")
        UiEnd(&harness.ctx)
        _ = i
    }
    testing.expect(t, stateFind(&harness.ctx, UiIdIn(&harness.ctx, "A")) != nil)
    // B is left out: its state is kept for a frame or two (a widget that flickers keeps what it remembers), then forgotten
    for i in 0 ..< 2 {
        frame(harness)
        UiButton(&harness.ctx, "A")
        UiEnd(&harness.ctx)
        testing.expect(t, stateFind(&harness.ctx, UiIdIn(&harness.ctx, "B")) != nil, "B is still remembered after a frame or two")
        _ = i
    }
    frame(harness)
    UiButton(&harness.ctx, "A")
    UiEnd(&harness.ctx)
    testing.expect(t, stateFind(&harness.ctx, UiIdIn(&harness.ctx, "A")) != nil)
    testing.expect(t, stateFind(&harness.ctx, UiIdIn(&harness.ctx, "B")) == nil, "B was left out for too long")
}

// The id a widget gets when it is declared directly in the root of a frame
@(private = "file")
UiIdIn :: proc(ctx: ^Context, name: string) -> Id {
    return UiId(ctx, name)
}

@(test)
test_root_id_constant_matches_the_hash :: proc(t: ^testing.T) {
    testing.expect_value(t, ROOT_ID, IdFromString("ui_root"))
}

@(test)
test_full_storage_is_reported_not_crashed :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    for i in 0 ..< 100 {
        UiLabel(&harness.ctx, "x")
        _ = i
    }
    UiEnd(&harness.ctx)
    testing.expect(t, .ELEMENTS_FULL in harness.ctx.problems)
    frame(harness)                                  // the next frame works again
    UiLabel(&harness.ctx, "ok")
    UiEnd(&harness.ctx)
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(test)
test_rounded_radius_is_a_part_of_the_shortest_side :: proc(t: ^testing.T) {
    rect: Rect = {0, 0, 200, 40}
    testing.expect_value(t, RoundedRadius(rect, 0), 0)
    testing.expect_value(t, RoundedRadius(rect, 1), 20)             // the full round: half of the shortest side
    testing.expect_value(t, RoundedRadius(rect, 0.5), 10)
    testing.expect_value(t, RoundedRadius(rect, 5), 20)             // over 1 is clamped
    testing.expect_value(t, RoundedRadius(rect, 1, 8), 8)           // and limited in pixels
    testing.expect_value(t, RoundedRadius(rect, -1), 0)
    radii: [4]f32 = RoundedRadii(rect, {100, 3, -2, 20})
    testing.expect_value(t, radii, [4]f32{20, 3, 0, 20})
}

@(test)
test_rounded_points_stay_inside_the_rectangle :: proc(t: ^testing.T) {
    rect: Rect = {10, 20, 100, 60}
    buffer: RoundedBuffer
    points: []Vec2 = RoundedPointsUniform(rect, 1, buffer[:])
    testing.expect(t, len(points) >= 8)
    for point in points {
        testing.expect(t, point.x >= rect.x - 0.01 && point.x <= rect.x + rect.z + 0.01)
        testing.expect(t, point.y >= rect.y - 0.01 && point.y <= rect.y + rect.w + 0.01)
    }
    // sharp: the four corners
    sharp: []Vec2 = RoundedPointsUniform(rect, 0, buffer[:])
    testing.expect_value(t, len(sharp), 8)                          // two points per corner, equal ones
    testing.expect_value(t, sharp[0], Vec2{10, 20})
}

@(private = "file")
navFrame :: proc(harness: ^Harness, body: proc(ctx: ^Context), direction: Maybe(Direction) = nil, activate: bool = false) {
    frame(harness, pointerAt({-100, -100}))
    if d, ok := direction.?; ok { UiNavigate(&harness.ctx, d) }
    if activate { UiActivate(&harness.ctx) }
    body(&harness.ctx)
    UiEnd(&harness.ctx)
}

@(private = "file")
navMenu :: proc(ctx: ^Context) {
    UiButton(ctx, "A")
    UiButton(ctx, "B")
    UiButton(ctx, "C")
}

@(test)
test_navigation_moves_to_the_nearest_widget_in_the_direction :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    navFrame(harness, navMenu)
    navFrame(harness, navMenu, .DOWN)                       // nothing was focused: the first one
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("A"))
    navFrame(harness, navMenu, .DOWN)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("B"))
    navFrame(harness, navMenu, .DOWN)
    navFrame(harness, navMenu, .DOWN)                       // nothing under C: stays
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("C"))
    navFrame(harness, navMenu, .UP)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("B"))
    navFrame(harness, navMenu, .LEFT)                       // nothing on the left
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("B"))
}

@(test)
test_navigation_finds_the_widget_in_a_grid :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    grid :: proc(ctx: ^Context) {
        if UiRow(ctx) { UiButton(ctx, "A", {Fixed(60), {}}); UiButton(ctx, "B", {Fixed(60), {}}) }
        if UiRow(ctx) { UiButton(ctx, "C", {Fixed(60), {}}); UiButton(ctx, "D", {Fixed(60), {}}) }
    }
    navFrame(harness, grid)
    navFrame(harness, grid, .DOWN)
    navFrame(harness, grid, .RIGHT)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("B"))
    navFrame(harness, grid, .DOWN)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("D"))
    navFrame(harness, grid, .LEFT)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("C"))
    navFrame(harness, grid, .UP)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("A"))
}

@(test)
test_navigation_links_and_blocks_override_the_nearest :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    menu :: proc(ctx: ^Context) {
        UiButton(ctx, "A")
        UiNavLink(ctx, .DOWN, UiId(ctx, "C"))               // jumps over B
        UiNavBlock(ctx, .UP)
        UiButton(ctx, "B")
        UiButton(ctx, "C")
    }
    navFrame(harness, menu)
    navFrame(harness, menu, .DOWN)
    navFrame(harness, menu, .UP)                            // blocked
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("A"))
    navFrame(harness, menu, .DOWN)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("C"))
}

@(test)
test_activate_clicks_the_focused_widget_and_slider_takes_steps :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    @(static) clicks: int
    @(static) volume: f32
    clicks = 0
    volume = 0
    menu :: proc(ctx: ^Context) {
        if UiButton(ctx, "Go") { clicks += 1 }
        UiSlider(ctx, "Volume", &volume, 0, 100)
    }
    navFrame(harness, menu)
    navFrame(harness, menu, .DOWN)
    navFrame(harness, menu, activate = true)
    testing.expect_value(t, clicks, 1)
    navFrame(harness, menu, .DOWN)                          // on the slider
    navFrame(harness, menu, .RIGHT)
    navFrame(harness, menu)
    navFrame(harness, menu, .RIGHT)
    navFrame(harness, menu)
    testing.expect(t, near(volume, 10), "two steps of a twentieth")
    navFrame(harness, menu, .LEFT)
    navFrame(harness, menu)
    testing.expect(t, near(volume, 5))
    testing.expect(t, .FOCUSED in seenFocusFlag(harness))
}

@(private = "file")
seenFocusFlag :: proc(harness: ^Harness) -> Flags {
    for command in UiCommands(&harness.ctx) {
        if command.kind == .DRAW && command.info.kind == .SLIDER { return command.info.flags }
    }
    return {}
}

@(test)
test_accept_opens_the_dropdown_on_the_chosen_option_and_cancel_closes_it :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    options: [3]string = {"Low", "Medium", "High"}
    selected: int = 1
    @(static) shared_options: [3]string
    @(static) shared_selected: ^int
    shared_options = options
    shared_selected = &selected
    defer shared_selected = nil
    run :: proc(harness: ^Harness, actions: Actions) {
        input: Input = pointerAt({-100, -100})
        input.actions = actions
        frame(harness, input)
        UiDropdown(&harness.ctx, "Quality", shared_options[:], shared_selected)
        UiEnd(&harness.ctx)
    }
    run(harness, {})
    run(harness, {.DOWN})                                        // focuses the box
    box: Id = UiIdPath("Quality")
    testing.expect_value(t, UiFocused(&harness.ctx), box)
    run(harness, {.ACCEPT})
    popup: Id = IdFromString("popup", box)
    testing.expect_value(t, UiFocused(&harness.ctx), IdFromIndex(1, popup))      // on the chosen option
    run(harness, {})
    run(harness, {.DOWN})
    testing.expect_value(t, UiFocused(&harness.ctx), IdFromIndex(2, popup))
    run(harness, {.CANCEL})                                      // closes it, nothing is chosen, the focus is back on the box
    testing.expect_value(t, UiFocused(&harness.ctx), box)
    testing.expect_value(t, selected, 1)
    run(harness, {.ACCEPT})
    run(harness, {})
    run(harness, {.DOWN})
    run(harness, {.ACCEPT})                                      // chooses the option under the focus
    testing.expect_value(t, selected, 2)
    testing.expect_value(t, UiFocused(&harness.ctx), box)
}

@(private = "file")
actionFrame :: proc(harness: ^Harness, body: proc(ctx: ^Context), actions: Actions = {}) {
    input: Input = pointerAt({-100, -100})
    input.actions = actions
    frame(harness, input)
    body(&harness.ctx)
    UiEnd(&harness.ctx)
}

@(test)
test_focus_next_and_previous_wrap_around_and_home_end_jump :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    actionFrame(harness, navMenu)
    actionFrame(harness, navMenu, {.FOCUS_NEXT})                 // nothing focused: the first
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("A"))
    actionFrame(harness, navMenu, {.FOCUS_NEXT})
    actionFrame(harness, navMenu, {.FOCUS_NEXT})
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("C"))
    actionFrame(harness, navMenu, {.FOCUS_NEXT})                 // around the end
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("A"))
    actionFrame(harness, navMenu, {.FOCUS_PREV})                 // and back
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("C"))
    actionFrame(harness, navMenu, {.HOME})
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("A"))
    actionFrame(harness, navMenu, {.END})
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("C"))
}

@(test)
test_cancel_is_taken_by_a_text_field_then_left_for_the_program :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    @(static) buffer: [8]u8
    @(static) length: int
    length = 0
    field :: proc(ctx: ^Context) { _, _ = UiTextField(ctx, "Name", buffer[:], &length) }
    actionFrame(harness, field)
    actionFrame(harness, field, {.DOWN})                         // the field has the focus
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("Name"))
    cancelled: bool
    frame(harness, Input{mouse_position = {-100, -100}, actions = {.CANCEL}})
    field(&harness.ctx)
    cancelled = UiCancelled(&harness.ctx)
    UiEnd(&harness.ctx)
    testing.expect(t, !cancelled, "the text field took it")
    testing.expect_value(t, UiFocused(&harness.ctx), Id(0))
    frame(harness, Input{mouse_position = {-100, -100}, actions = {.CANCEL}})
    field(&harness.ctx)
    cancelled = UiCancelled(&harness.ctx)
    UiEnd(&harness.ctx)
    testing.expect(t, cancelled, "nothing is left to take it: the program closes its dialog")
}

@(test)
test_keyboard_focus_scrolls_the_container_to_show_it :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    list :: proc(ctx: ^Context) {
        if UiScroll(ctx, "list", {Fixed(120), Fixed(100)}) {
            for i in 0 ..< 20 { UiButton(ctx, UiFormat(ctx, "Item %d##%d", i, i), {Grow(), {}}) }
        }
    }
    actionFrame(harness, list)
    actionFrame(harness, list, {.END})
    actionFrame(harness, list)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("list", "Item 19##19"))
    testing.expect(t, UiScrollGet(&harness.ctx, UiIdPath("list")) > 300, "the last item is shown")
    actionFrame(harness, list, {.PAGE_UP})
    actionFrame(harness, list)
    testing.expect(t, UiFocused(&harness.ctx) != UiIdPath("list", "Item 19##19") && UiFocused(&harness.ctx) != UiIdPath("list", "Item 18##18"))
    actionFrame(harness, list, {.HOME})
    actionFrame(harness, list)
    actionFrame(harness, list)
    testing.expect(t, UiScrollGet(&harness.ctx, UiIdPath("list")) < 10, "and back at the top (the first item shown with a margin)")
}

@(test)
test_every_widget_leaves_the_containers_balanced :: proc(t: ^testing.T) {
    storage: ^Storage(512, 512, 128, 4096) = new(Storage(512, 512, 128, 4096))
    defer free(storage)
    big: ^Context = new(Context)
    defer free(big)
    style: Style = makeStyle()
    UiInit(big, storage, testMeasure)
    seen = {}
    c: ^Context = big
    @(static) a: bool
    @(static) number: int
    @(static) real: f32
    @(static) color: [3]f32
    @(static) buffer: [8]u8
    @(static) length: int
    @(static) open: bool
    @(static) position: Vec2
    items: [2]string = {"x", "y"}
    values: [4]f32 = {0, 1, 0.5, 0.2}
    open = true
    checks: [32]string
    UiBegin(c, {}, 1.0 / 60, {400, 300}, &style)
    base: int = c.open_count
    count: int = 0
    check :: proc(t: ^testing.T, c: ^Context, base: int, name: string) {
        testing.expectf(t, c.open_count == base, "%s left %d containers open", name, c.open_count - base)
    }
    if UiCollapsing(c, "h") { UiLabel(c, "x") }
    check(t, c, base, "collapsing")
    if UiTreeNode(c, "n", true) { UiLabel(c, "x") }
    check(t, c, base, "tree")
    UiRadio(c, "r", &number, 1); check(t, c, base, "radio")
    UiSelectable(c, "s", true); check(t, c, base, "selectable")
    selected: int
    UiListBox(c, "l", items[:], &selected); check(t, c, base, "listbox")
    UiTabBar(c, "t", items[:], &selected); check(t, c, base, "tabs")
    UiArrowButton(c, "a", .LEFT, true); check(t, c, base, "arrow")
    UiDrag(c, "d", &real); check(t, c, base, "drag")
    UiDragInt(c, "di", &number); check(t, c, base, "drag int")
    UiSliderInt(c, "si", &number, 0, 3); check(t, c, base, "slider int")
    UiSliderAngle(c, "sa", &real); check(t, c, base, "slider angle")
    UiInputInt(c, "ii", &number); check(t, c, base, "input int")
    UiInputFloat(c, "if", &real); check(t, c, base, "input float")
    UiPlotLines(c, "p", values[:]); check(t, c, base, "plot")
    UiPlotHistogram(c, "ph", values[:]); check(t, c, base, "histogram")
    UiColorEdit3(c, "c", &color); check(t, c, base, "color edit")
    UiColorButton(c, "cb", color); check(t, c, base, "color button")
    UiLabelColored(c, "x", {255, 0, 0, 255}); check(t, c, base, "colored label")
    UiBullet(c, "b"); check(t, c, base, "bullet")
    UiLabelText(c, "n", "v"); check(t, c, base, "label text")
    UiSeparatorText(c, "s"); check(t, c, base, "separator text")
    UiButton(c, "tip"); UiTooltip(c, "x"); check(t, c, base, "tooltip")
    if UiMenuBar(c) {
        if UiMenu(c, "m") { UiMenuItem(c, "i"); if UiMenu(c, "sub") { UiMenuItem(c, "j") } }
    }
    check(t, c, base, "menus")
    if UiModal(c, "dlg", &open) { UiLabel(c, "x") }
    check(t, c, base, "modal")
    open = false
    if UiModal(c, "dlg2", &open) { UiLabel(c, "x") }
    check(t, c, base, "closed modal")
    if UiWindowTitled(c, "w", &position) { UiLabel(c, "x") }
    check(t, c, base, "window")
    _ = a; _ = checks; _ = count; _ = buffer; _ = length
    UiEnd(c)
    testing.expect_value(t, c.problems, Problems{})
}

@(test)
test_opening_a_header_at_the_bottom_shows_its_body :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    list :: proc(ctx: ^Context) {
        if UiScroll(ctx, "list", {Fixed(200), Fixed(120)}) {
            for i in 0 ..< 6 { UiButton(ctx, UiFormat(ctx, "Item %d##%d", i, i), {Grow(), {}}) }
            if UiCollapsing(ctx, "More") {
                for i in 0 ..< 4 { UiLabelf(ctx, "line %d", i) }
            }
        }
    }
    actionFrame(harness, list)
    actionFrame(harness, list, {.END})                           // the last widget: the header, at the bottom of the scroll
    actionFrame(harness, list)
    focused: Id = UiFocused(&harness.ctx)
    testing.expect_value(t, focused, UiIdPath("list", "More"))
    before: f32 = UiScrollGet(&harness.ctx, UiIdPath("list"))
    actionFrame(harness, list, {.ACCEPT})
    for _ in 0 ..< 4 { actionFrame(harness, list) }
    testing.expect(t, UiIsOpen(&harness.ctx, UiIdPath("list", "More")))
    after: f32 = UiScrollGet(&harness.ctx, UiIdPath("list"))
    testing.expect(t, after > before + 20, "the list scrolled down to show what the header opened")
    // the last line of the body is inside of the view
    body, found := UiElementRect(&harness.ctx, UiBodyId(UiIdPath("list", "More")))
    view, _ := UiElementRect(&harness.ctx, UiIdPath("list"))
    header, _ := UiElementRect(&harness.ctx, UiIdPath("list", "More"))
    testing.expect(t, found && body.y + 20 < view.y + view.w, "the body starts inside of the view, with room for lines")
    testing.expect(t, header.y >= view.y - 1, "and the header stays in view (the body is taller than the view)")
}

@(test)
test_a_disabled_scope_takes_no_pointer_and_no_focus :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    clicks: int
    body :: proc(ctx: ^Context, clicks: ^int, off: bool) {
        if UiDisabled(ctx, off) {
            if UiButton(ctx, "Go") { clicks^ += 1 }
        }
    }
    inputs: [4]Input = {pointerAt({-100, -100}), pointerAt({20, 12}), pointerAt({20, 12}, down = true, pressed = true), pointerAt({20, 12}, released = true)}
    for input in inputs {
        frame(harness, input)
        body(&harness.ctx, &clicks, true)
        UiEnd(&harness.ctx)
        UiRender(&harness.ctx)
    }
    testing.expect_value(t, clicks, 0)
    testing.expect(t, .DISABLED in seen.last[.BUTTON].flags, "drawn disabled")
    testing.expect_value(t, UiCursor(&harness.ctx), Cursor.ARROW)
    // not focusable by navigation either
    harness.ctx.focus = 0
    testing.expect(t, !UiNavigate(&harness.ctx, .DOWN))
    // with the scope off it is a normal button again
    for input in inputs {
        frame(harness, input)
        body(&harness.ctx, &clicks, false)
        UiEnd(&harness.ctx)
    }
    testing.expect_value(t, clicks, 1)
    testing.expect_value(t, harness.ctx.disabled_depth, 0)
}

@(test)
test_double_click_and_cursor_and_usage :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    doubles: int
    clicked_names: int
    @(static) text: [8]u8
    @(static) length: int
    one :: proc(ctx: ^Context, doubles: ^int) {
        id: Id = UiId(ctx, "Go")
        _ = stateGet(ctx, id)
        interaction: Interaction = widgetBehavior(ctx, id)
        if interaction.double_clicked { doubles^ += 1 }
        ElementOpen(ctx, {id = id, layout = {size = {Fixed(100), Fixed(30)}}, hit = {.INTERACTIVE}, draw = {kind = .BUTTON}})
        ElementClose(ctx)
        _, _ = UiTextField(ctx, "Name", text[:], &length)
    }
    press :: proc(harness: ^Harness, doubles: ^int, input: Input) {
        frame(harness, input)
        one(&harness.ctx, doubles)
        UiEnd(&harness.ctx)
    }
    press(harness, &doubles, pointerAt({-100, -100}))
    press(harness, &doubles, pointerAt({20, 12}))
    press(harness, &doubles, pointerAt({20, 12}, down = true, pressed = true))
    press(harness, &doubles, pointerAt({20, 12}, released = true))
    press(harness, &doubles, pointerAt({20, 12}, down = true, pressed = true))        // the second press, a few frames later
    testing.expect_value(t, doubles, 1)
    // the text field gives the text cursor
    press(harness, &doubles, pointerAt({20, 45}))
    press(harness, &doubles, pointerAt({20, 45}))
    testing.expect_value(t, UiCursor(&harness.ctx), Cursor.TEXT)
    now, peak := UiUsage(&harness.ctx)
    testing.expect(t, now.elements >= 3 && peak.elements >= now.elements)
    testing.expect(t, peak.states >= 2)
    _ = clicked_names
}

@(test)
test_fades_are_frame_rate_independent_and_report_animating :: proc(t: ^testing.T) {
    // two frames of 1/120 s arrive where one of 1/60 s does
    one: f32 = animationStep(1.0 / 60, ANIMATION_RATE)
    two: f32 = 1 - (1 - animationStep(1.0 / 120, ANIMATION_RATE)) * (1 - animationStep(1.0 / 120, ANIMATION_RATE))
    testing.expect(t, abs(one - two) < 0.0001)
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    hover: Input = pointerAt({20, 12})
    for i in 0 ..< 3 {
        frame(harness, pointerAt({-100, -100}))
        UiButton(&harness.ctx, "Go")
        UiEnd(&harness.ctx)
        _ = i
    }
    testing.expect(t, !UiAnimating(&harness.ctx), "nothing moves")
    frame(harness, hover)
    UiButton(&harness.ctx, "Go")
    UiEnd(&harness.ctx)
    frame(harness, hover)
    UiButton(&harness.ctx, "Go")
    UiEnd(&harness.ctx)
    testing.expect(t, UiAnimating(&harness.ctx), "the hover fade is on its way")
    for i in 0 ..< 120 {
        frame(harness, hover)
        UiButton(&harness.ctx, "Go")
        UiEnd(&harness.ctx)
        _ = i
    }
    testing.expect(t, !UiAnimating(&harness.ctx), "and it arrived")
}

@(test)
test_a_truncated_text_ends_in_dots_and_shows_itself_in_a_tooltip :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    // 8 px per character: 15 characters are 120 px, the box is 80 px (10 characters, 7 of the text and "...")
    label :: proc(ctx: ^Context) {
        if UiBox(ctx, {layout = {size = {Fixed(80), Fit()}}}) {
            UiLabelTruncated(ctx, "abcdefghijklmno")
        }
    }
    for i in 0 ..< 3 {
        frame(harness, pointerAt({10, 8}))
        label(&harness.ctx)
        UiEnd(&harness.ctx)
        _ = i
    }
    saw_tooltip: bool
    for command in UiCommands(&harness.ctx) {
        if command.kind == .DRAW && command.info.kind == .LABEL {
            if .TRUNCATED in command.info.flags {
                testing.expect_value(t, command.info.text, "abcdefg...")
                testing.expect_value(t, command.info.name, "abcdefghijklmno")
            } else if command.info.text == "abcdefghijklmno" {
                saw_tooltip = true                              // the whole text in the tooltip
            }
        }
    }
    testing.expect(t, saw_tooltip, "the whole text is shown while the pointer is on it")
    // wide enough: the text as it is, no tooltip
    wide :: proc(ctx: ^Context) {
        if UiBox(ctx, {layout = {size = {Fixed(200), Fit()}}}) { UiLabelTruncated(ctx, "abcdefghijklmno") }
    }
    for i in 0 ..< 3 {
        frame(harness, pointerAt({10, 8}))
        wide(&harness.ctx)
        UiEnd(&harness.ctx)
        _ = i
    }
    count: int
    for command in UiCommands(&harness.ctx) {
        if command.kind == .DRAW && command.info.kind == .LABEL {
            count += 1
            testing.expect(t, .TRUNCATED not_in command.info.flags)
        }
    }
    testing.expect_value(t, count, 1)
}

@(test)
test_tags_reach_the_style_and_nest :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    UiButton(&harness.ctx, "plain")
    if UiTagged(&harness.ctx, "danger") {
        UiButton(&harness.ctx, "delete")
        if UiTagged(&harness.ctx, "flat") { UiButton(&harness.ctx, "both") }
    }
    UiButton(&harness.ctx, "after")
    UiEnd(&harness.ctx)
    found: [4]bool
    for command in UiCommands(&harness.ctx) {
        if command.kind != .DRAW || command.info.kind != .BUTTON { continue }
        info: DrawInfo = command.info
        switch info.name {
        case "plain": found[0] = !DrawInfoHasTag(&info, "danger")
        case "delete": found[1] = DrawInfoHasTag(&info, "danger") && !DrawInfoHasTag(&info, "flat")
        case "both": found[2] = DrawInfoHasTag(&info, "danger") && DrawInfoHasTag(&info, "flat")
        case "after": found[3] = !DrawInfoHasTag(&info, "danger")
        }
    }
    testing.expect_value(t, found, [4]bool{true, true, true, true})
}

@(test)
test_shrink_priority_decides_who_gives_way_first :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    // a row of 200 with two containers of a text of 6 words (136 px each, a word is 16): both have to shrink 72 together, and the one with the higher
    // shrink number only after the other is at its minimum
    ElementOpen(&harness.ctx, {id = 10, layout = {size = {Fixed(200), Fixed(30)}, direction = .LEFT_TO_RIGHT}})
    ElementOpen(&harness.ctx, {id = 11, layout = {size = {{kind = .FIT, shrink = 1}, Fit()}}})
    TextOpen(&harness.ctx, "aa aa aa aa aa aa", {wrap = .WORDS})
    ElementClose(&harness.ctx)
    ElementOpen(&harness.ctx, {id = 12, layout = {size = {{kind = .FIT, shrink = 0}, Fit()}}})
    TextOpen(&harness.ctx, "aa aa aa aa aa aa", {wrap = .WORDS})
    ElementClose(&harness.ctx)
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)
    keeps, _ := UiElementRect(&harness.ctx, 11)
    gives, _ := UiElementRect(&harness.ctx, 12)
    testing.expect(t, near(gives.z, 64), "the element with the lower number shrank until the row fits (136 - 72)")
    testing.expect(t, near(keeps.z, 136), "the one with the higher number kept its size")
}

@(test)
test_drag_and_drop_moves_a_payload_between_widgets :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    @(static) dropped_value: int
    @(static) dragging_seen: bool
    dropped_value = -1
    dragging_seen = false
    build :: proc(ctx: ^Context) {
        ElementOpen(ctx, {layout = {direction = .LEFT_TO_RIGHT, gap = 20}})
        UiButton(ctx, "Item", {Fixed(80), Fixed(30)})
        item: int = 42
        if UiDragSourceValue(ctx, "item", &item) { dragging_seen = true }
        UiButton(ctx, "Slot", {Fixed(80), Fixed(30)})
        if payload, dropped := UiDropTarget(ctx, "item"); dropped { dropped_value = (^int)(raw_data(payload))^ }
        UiButton(ctx, "Other", {Fixed(80), Fixed(30)})
        if _, dropped := UiDropTarget(ctx, "something else"); dropped { dropped_value = -2 }      // another kind: never
        ElementClose(ctx)
    }
    inputs: [8]Input = {
        pointerAt({-100, -100}),
        pointerAt({20, 12}),
        pointerAt({20, 12}, down = true, pressed = true),
        pointerAt({40, 12}, down = true),                           // 20 px away: the drag starts
        pointerAt({120, 12}, down = true),                          // over the slot
        pointerAt({120, 12}, released = true),                      // let go: dropped
        pointerAt({120, 12}),
        pointerAt({120, 12}),
    }
    for input in inputs {
        frame(harness, input)
        build(&harness.ctx)
        UiEnd(&harness.ctx)
    }
    testing.expect(t, dragging_seen, "the source knew it was dragged")
    testing.expect_value(t, dropped_value, 42)
    _, still_dragging := UiDragging(&harness.ctx)
    testing.expect(t, !still_dragging, "the drag ended with the button")
}

@(test)
test_focus_returns_to_the_remembered_widget_of_a_window :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    two_windows :: proc(ctx: ^Context) {
        if UiWindow(ctx, "A", {0, 0}, {Fixed(100), {}}) {
            UiButton(ctx, "a1")
            UiButton(ctx, "a2")
        }
        if UiWindow(ctx, "B", {200, 0}, {Fixed(100), {}}) {
            UiButton(ctx, "b1")
            UiButton(ctx, "b2")
        }
    }
    actionFrame(harness, two_windows)
    actionFrame(harness, two_windows, {.FOCUS_NEXT})            // a1
    actionFrame(harness, two_windows, {.FOCUS_NEXT})            // a2
    actionFrame(harness, two_windows, {.FOCUS_NEXT})            // b1: the first of window B (nothing remembered there)
    actionFrame(harness, two_windows, {.FOCUS_NEXT})            // b2
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("B", "b2"))
    actionFrame(harness, two_windows, {.FOCUS_NEXT})            // around the end: window A again, at the widget that had the focus there: a2
    actionFrame(harness, two_windows)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("A", "a2"))
    actionFrame(harness, two_windows, {.FOCUS_PREV})            // a1
    actionFrame(harness, two_windows, {.FOCUS_PREV})            // around the start into window B, at its b2 (the last widget that had the focus there)
    actionFrame(harness, two_windows)
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("B", "b2"))
    UiFocusRoot(&harness.ctx, UiIdPath("A"))
    testing.expect_value(t, UiFocused(&harness.ctx), UiIdPath("A", "a1"))     // window A: where its focus was last
}

// ------------------------------------------------------------------------------------------------------------------------
// Resizing: UiSplit (two sections and the handle between them) and the window that is resized by its edges

@(private = "file")
ResizeCase :: struct {
    vertical: bool,
    mode: int,                  // 0 a normal split, 1 only the second section, 2 only the first, 3 neither, 4 the first twice, 5 a section outside of a split, 6 a three way split
    width: f32,                 // of the container
    owned: bool,                // a window whose position and size the program keeps
    win_position: Vec2,
    win_size: Vec2,
}

@(private = "file")
caseOf :: proc(ctx: ^Context) -> ^ResizeCase {
    return cast(^ResizeCase)ctx.user
}

@(private = "file")
box :: proc(ctx: ^Context, name: string, size: Size, direction: LayoutDirection = .TOP_TO_BOTTOM) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    ElementOpen(ctx, {id = id, layout = {size = size, direction = direction}})
}

@(private = "file")
splitBody :: proc(ctx: ^Context) {
    state: ^ResizeCase = caseOf(ctx)
    direction: SplitDirection = .VERTICAL if state.vertical else .HORIZONTAL
    box(ctx, "area", {Fixed(state.width), Fixed(200)})
    switch state.mode {
    case 0:
        if UiSplit(ctx, "split", direction, 0.4, {}, 40, 30) {
            if UiSplitFirst(ctx) { UiButton(ctx, "a", {Grow(), Grow()}) }
            if UiSplitSecond(ctx) { UiButton(ctx, "b", {Grow(), Grow()}) }
        }
    case 1:
        if UiSplit(ctx, "split", direction, 0.4, {}, 40, 30) {
            if UiSplitSecond(ctx) { UiButton(ctx, "b", {Grow(), Grow()}) }
        }
    case 2:
        if UiSplit(ctx, "split", direction, 0.4, {}, 40, 30) {
            if UiSplitFirst(ctx) { UiButton(ctx, "a", {Grow(), Grow()}) }
        }
    case 3:
        if UiSplit(ctx, "split", direction, 0.4, {}, 40, 30) {}
    case 4:
        if UiSplit(ctx, "split", direction, 0.4, {}, 40, 30) {
            if UiSplitFirst(ctx) { UiButton(ctx, "a", {Grow(), Grow()}) }
            if UiSplitFirst(ctx) { UiButton(ctx, "again", {Grow(), Grow()}) }
            if UiSplitSecond(ctx) { UiButton(ctx, "b", {Grow(), Grow()}) }
        }
    case 5:
        if UiSplitFirst(ctx) { UiButton(ctx, "alone", {Grow(), Grow()}) }
    case 8:
        // a start size in pixels
        if UiSplit(ctx, "split", direction, 0.5, {}, 40, 30, 100) {
            if UiSplitFirst(ctx) { UiButton(ctx, "a", {Grow(), Grow()}) }
            if UiSplitSecond(ctx) { UiButton(ctx, "b", {Grow(), Grow()}) }
        }
    case 7:
        // content wider than its section: the sections still add up to the container
        if UiSplit(ctx, "split", direction, 0.9, {}, 40, 30) {
            if UiSplitFirst(ctx) { UiButton(ctx, "a", {Grow(), Grow()}) }
            if UiSplitSecond(ctx) {
                UiButton(ctx, "b", {Grow(), Grow()})
                ElementOpen(ctx, {layout = {size = {Fixed(500), Fixed(10)}}})       // wider than the section
                ElementClose(ctx)
            }
        }
    case 6:
        // the second section is split again: three sections side by side
        if UiSplit(ctx, "split", direction, 0.3, {}, 40, 40) {
            if UiSplitFirst(ctx) { UiButton(ctx, "a", {Grow(), Grow()}) }
            if UiSplitSecond(ctx) {
                if UiSplit(ctx, "inner", direction, 0.5, {}, 40, 40) {
                    if UiSplitFirst(ctx) { UiButton(ctx, "b", {Grow(), Grow()}) }
                    if UiSplitSecond(ctx) { UiButton(ctx, "c", {Grow(), Grow()}) }
                }
            }
        }
    }
    ElementClose(ctx)
}

@(private = "file")
dragFrames :: proc(harness: ^Harness, body: proc(ctx: ^Context), from: Vec2, to: Vec2) {
    frame(harness, pointerAt(from)); body(&harness.ctx); UiEnd(&harness.ctx)
    frame(harness, pointerAt(from, true, true)); body(&harness.ctx); UiEnd(&harness.ctx)
    for step in 1 ..= 6 {
        frame(harness, pointerAt(from + (to - from) * (f32(step) / 6), true)); body(&harness.ctx); UiEnd(&harness.ctx)
    }
    frame(harness, pointerAt(to, false, false, true)); body(&harness.ctx); UiEnd(&harness.ctx)
    frame(harness, pointerAt({-100, -100})); body(&harness.ctx); UiEnd(&harness.ctx)
}

@(private = "file")
rectOf :: proc(harness: ^Harness, path: ..string) -> Rect {
    rect, _ := UiElementRect(&harness.ctx, UiIdPath(..path))
    return rect
}

@(private = "file")
handleOf :: proc(harness: ^Harness, path: ..string) -> Rect {
    rect, _ := UiElementRect(&harness.ctx, IdFromString("handle", UiIdPath(..path)))
    return rect
}

@(test)
test_a_split_keeps_its_proportion_and_the_handle_moves_the_border :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    cs: ResizeCase = {width = 300}
    harness.ctx.user = &cs
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    a: Rect = rectOf(harness, "area", "split", "a")
    b: Rect = rectOf(harness, "area", "split", "b")
    handle: Rect = handleOf(harness, "area", "split")
    testing.expect(t, near(a.z, 120), "the first section has its part (0.4 of 300) from the very first frames")
    testing.expect(t, near(handle.x, 120) && near(handle.z, 6), "the handle sits right after it")
    testing.expect(t, near(b.x, 126) && near(b.z, 174), "the second takes the rest")

    // the pointer moves the border by what it moved
    dragFrames(harness, splitBody, RectCenter(handle), RectCenter(handle) + {50, 0})
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 170))
    testing.expect(t, near(rectOf(harness, "area", "split", "b").z, 124))

    // the container gets bigger and smaller: the proportion stays, the sections never go below their minimum
    cs.width = 600
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 600 * 170.0 / 300), "twice the container, twice the section")
    cs.width = 100
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    a = rectOf(harness, "area", "split", "a")
    b = rectOf(harness, "area", "split", "b")
    testing.expect(t, a.z >= 40 - 0.01 && b.z >= 30 - 0.01, "both keep their minimum")
    cs.width = 300
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 170), "and the proportion was not lost when the container was small")

    // pushed past the limits: the border stops where a section keeps its minimum, and follows the pointer again from there
    handle = handleOf(harness, "area", "split")
    dragFrames(harness, splitBody, RectCenter(handle), RectCenter(handle) + {500, 0})
    testing.expect(t, near(rectOf(harness, "area", "split", "b").z, 30), "the second keeps its minimum")
    handle = handleOf(harness, "area", "split")
    dragFrames(harness, splitBody, RectCenter(handle), RectCenter(handle) - {500, 0})
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 40), "the first keeps its minimum")
    handle = handleOf(harness, "area", "split")
    dragFrames(harness, splitBody, RectCenter(handle), RectCenter(handle) + {20, 0})
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 60), "it comes back with the pointer, not from where the pointer went")

    // the ratio can be read and set
    split: Id = UiIdPath("area", "split")
    testing.expect(t, near(UiSplitRatio(&harness.ctx, split), 60.0 / 300))
    UiSplitSetRatio(&harness.ctx, split, 0.5)
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 150))

    // the keyboard: the handle has the focus after a press, an arrow key is a step
    handle = handleOf(harness, "area", "split")
    dragFrames(harness, splitBody, RectCenter(handle), RectCenter(handle))
    before: f32 = rectOf(harness, "area", "split", "a").z
    actionFrame(harness, splitBody, {.RIGHT})
    actionFrame(harness, splitBody)
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, before + SPLITTER_KEY_STEP), "an arrow key moves the border by a step")
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(test)
test_a_split_of_stacked_sections_moves_up_and_down :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    cs: ResizeCase = {width = 300, vertical = true}
    harness.ctx.user = &cs
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    handle: Rect = handleOf(harness, "area", "split")
    testing.expect(t, near(handle.y, 80) && near(handle.w, 6) && near(handle.z, 300), "a bar across the container, after 0.4 of the 200 high container")
    dragFrames(harness, splitBody, RectCenter(handle), RectCenter(handle) + {0, 40})
    testing.expect(t, near(rectOf(harness, "area", "split", "a").w, 120))
    testing.expect(t, near(rectOf(harness, "area", "split", "b").w, 200 - 120 - 6))
    actionFrame(harness, splitBody, {.UP})
    actionFrame(harness, splitBody)
    testing.expect(t, near(rectOf(harness, "area", "split", "a").w, 120 - SPLITTER_KEY_STEP), "up and down move the border of stacked sections")
}

@(test)
test_a_split_stays_right_when_it_is_used_wrongly :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    cs: ResizeCase = {width = 300}
    harness.ctx.user = &cs
    // the first section left out: an empty one is made, the handle and the second are where they should be
    cs.mode = 1
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, near(handleOf(harness, "area", "split").x, 120), "the handle is after an empty first section")
    testing.expect(t, near(rectOf(harness, "area", "split", "b").x, 126))
    testing.expect_value(t, harness.ctx.problems, Problems{})
    // the second left out
    cs.mode = 2
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, near(handleOf(harness, "area", "split").x, 120) && near(rectOf(harness, "area", "split", "a").z, 120))
    testing.expect_value(t, harness.ctx.problems, Problems{})
    // both left out
    cs.mode = 3
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, near(handleOf(harness, "area", "split").x, 120) && near(handleOf(harness, "area", "split").z, 6))
    testing.expect_value(t, harness.ctx.problems, Problems{})
    // a third section: drawn in a plain box, and told
    cs.mode = 4
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, SPLIT_MISUSE_IS_SET(&harness.ctx))
    testing.expect(t, near(rectOf(harness, "area", "split", "b").z, 174), "the real second section is where it should be")
    _, again := UiElementRect(&harness.ctx, UiIdPath("area", "split", "again"))
    testing.expect(t, again, "what was declared in the extra section is still there")
    // a section outside of a split
    cs.mode = 5
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, SPLIT_MISUSE_IS_SET(&harness.ctx))
    _, alone := UiElementRect(&harness.ctx, UiIdPath("area", "alone"))
    testing.expect(t, alone)
}

@(private = "file")
SPLIT_MISUSE_IS_SET :: proc(ctx: ^Context) -> bool {
    return .SPLIT_MISUSE in ctx.problems
}

@(test)
test_a_split_can_start_with_a_size_in_pixels :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    cs: ResizeCase = {width = 300, mode = 8}
    harness.ctx.user = &cs
    actionFrame(harness, splitBody)
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 100), "the pixels are right in the very first frame")
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 100), "and after it became a proportion")
    testing.expect(t, near(UiSplitRatio(&harness.ctx, UiIdPath("area", "split")), 100.0 / 300))
    cs.width = 600
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 200), "from then on it is a proportion of the container")
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(test)
test_content_wider_than_its_section_does_not_push_the_border :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    cs: ResizeCase = {width = 300, mode = 7}
    harness.ctx.user = &cs
    for _ in 0 ..< 4 { actionFrame(harness, splitBody) }
    handle: Rect = handleOf(harness, "area", "split")
    area: Rect = rectOf(harness, "area")
    testing.expect(t, near(handle.x + handle.z, area.x + area.z - 30), "the border stops where the second section keeps its minimum")
    testing.expect(t, near(rectOf(harness, "area", "split", "b").z, 30), "the second section is as wide as the room says, not as its content")
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(test)
test_splits_inside_of_splits_make_three_sections :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    cs: ResizeCase = {width = 300, mode = 6}
    harness.ctx.user = &cs
    for _ in 0 ..< 3 { actionFrame(harness, splitBody) }
    a: Rect = rectOf(harness, "area", "split", "a")
    b: Rect = rectOf(harness, "area", "split", "inner", "b")
    c: Rect = rectOf(harness, "area", "split", "inner", "c")
    testing.expect(t, near(a.z, 90), "0.3 of 300")
    testing.expect(t, near(b.x, 96) && near(b.z + c.z + SPLITTER_THICKNESS, 204), "the rest of the container is split again")
    // the outer handle moves, the inner one is carried along and keeps its proportion
    outer: Rect = handleOf(harness, "area", "split")
    dragFrames(harness, splitBody, RectCenter(outer), RectCenter(outer) + {30, 0})
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 120))
    inner_before: f32 = UiSplitRatio(&harness.ctx, UiIdPath("area", "split", "inner"))
    testing.expect(t, near(inner_before, 0.5), "the inner split did not change")
    inner: Rect = handleOf(harness, "area", "split", "inner")
    dragFrames(harness, splitBody, RectCenter(inner), RectCenter(inner) + {20, 0})
    testing.expect(t, near(rectOf(harness, "area", "split", "a").z, 120), "the outer split did not change")
    testing.expect(t, UiSplitRatio(&harness.ctx, UiIdPath("area", "split", "inner")) > 0.5)
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(private = "file")
windowBody :: proc(ctx: ^Context) {
    state: ^ResizeCase = caseOf(ctx)
    if state.owned {
        if UiWindowResizable(ctx, "win", &state.win_position, &state.win_size, {100, 80}, {400, 0}) {
            UiButton(ctx, "fill", {Grow(), Grow()})
        }
    } else {
        if UiWindowResizable(ctx, "win", nil, nil, {100, 80}, {400, 0}, {}, 0, {40, 30}, {200, 150}) {
            UiButton(ctx, "fill", {Grow(), Grow()})
        }
    }
}

@(private = "file")
windowPosition :: proc(harness: ^Harness, cs: ^ResizeCase) -> Vec2 {
    return cs.win_position if cs.owned else UiWindowPosition(&harness.ctx, "win")
}

@(private = "file")
windowSize :: proc(harness: ^Harness, cs: ^ResizeCase) -> Vec2 {
    return cs.win_size if cs.owned else UiWindowSize(&harness.ctx, "win")
}

@(private = "file")
resizeWindowCase :: proc(t: ^testing.T, owned: bool) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    cs: ResizeCase = {owned = owned, win_position = {40, 30}, win_size = {200, 150}}
    harness.ctx.user = &cs
    for _ in 0 ..< 3 { actionFrame(harness, windowBody) }
    window: Id = UiIdPath("win")
    corner, found := UiElementRect(&harness.ctx, IdFromString("grip.bottom_right", window))
    testing.expect(t, found)
    testing.expect(t, near(corner.x + corner.z, 240) && near(corner.y + corner.w, 180), "the corner grip is in the corner of the window")

    dragFrames(harness, windowBody, RectCenter(corner), RectCenter(corner) + {40, 30})
    testing.expect(t, near(windowSize(harness, &cs).x, 240) && near(windowSize(harness, &cs).y, 180), "the corner took both sizes")
    testing.expect(t, near(windowPosition(harness, &cs).x, 40) && near(windowPosition(harness, &cs).y, 30), "the top left stays")
    button, _ := UiElementRect(&harness.ctx, UiIdPath("win", "fill"))
    testing.expect(t, button.z > 200, "what is Grow() inside took the room")

    // the right edge cannot take it past the largest width, the smallest stops at min_size
    right, _ := UiElementRect(&harness.ctx, IdFromString("grip.right", window))
    dragFrames(harness, windowBody, RectCenter(right), RectCenter(right) + {300, 0})
    testing.expect(t, near(windowSize(harness, &cs).x, 400), "the largest width")
    right, _ = UiElementRect(&harness.ctx, IdFromString("grip.right", window))
    dragFrames(harness, windowBody, RectCenter(right), RectCenter(right) - {900, 0})
    testing.expect(t, near(windowSize(harness, &cs).x, 100), "the smallest width")
    testing.expect(t, near(windowPosition(harness, &cs).x, 40), "the right edge never moves the left one")

    // the left edge moves the position by what the size lost: the right edge stays
    right_edge: f32 = windowPosition(harness, &cs).x + windowSize(harness, &cs).x
    left, _ := UiElementRect(&harness.ctx, IdFromString("grip.left", window))
    dragFrames(harness, windowBody, RectCenter(left), RectCenter(left) - {30, 0})
    testing.expect(t, near(windowSize(harness, &cs).x, 130) && near(windowPosition(harness, &cs).x, 10), "the left edge grew the window to the left")
    testing.expect(t, near(windowPosition(harness, &cs).x + windowSize(harness, &cs).x, right_edge), "and the right edge is where it was")

    // the top edge stops at the top of the screen
    top, _ := UiElementRect(&harness.ctx, IdFromString("grip.top", window))
    bottom_edge: f32 = windowPosition(harness, &cs).y + windowSize(harness, &cs).y
    dragFrames(harness, windowBody, RectCenter(top), RectCenter(top) - {0, 500})
    testing.expect(t, near(windowPosition(harness, &cs).y, 0), "not above the screen")
    testing.expect(t, near(windowPosition(harness, &cs).y + windowSize(harness, &cs).y, bottom_edge), "the bottom edge stays")

    // the title bar drags the window and does not change its size; it cannot be dragged off the screen
    size_before: Vec2 = windowSize(harness, &cs)
    title, _ := UiElementRect(&harness.ctx, IdFromString("title", window))
    dragFrames(harness, windowBody, RectCenter(title) + {0, 4}, RectCenter(title) + {30, 44})
    testing.expect(t, near(windowSize(harness, &cs).x, size_before.x) && near(windowSize(harness, &cs).y, size_before.y))
    title, _ = UiElementRect(&harness.ctx, IdFromString("title", window))
    dragFrames(harness, windowBody, RectCenter(title), RectCenter(title) + {2000, 2000})
    testing.expect(t, windowPosition(harness, &cs).x <= 400 - WINDOW_KEEP_VISIBLE + 0.01, "a part of the title bar stays on the screen at the right")
    testing.expect(t, windowPosition(harness, &cs).y <= 300 - 28 + 0.01, "and at the bottom")
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(test)
test_a_window_that_keeps_its_own_position_and_size_is_resized_by_its_corner_and_edges :: proc(t: ^testing.T) {
    resizeWindowCase(t, false)
}

@(test)
test_a_window_whose_position_and_size_the_program_keeps_is_resized_the_same :: proc(t: ^testing.T) {
    resizeWindowCase(t, true)
}

@(private = "file")
hugeWindow :: proc(ctx: ^Context) {
    if UiWindowResizable(ctx, "huge", nil, nil, {100, 80}, {}, {}, 0, {-500, 900}, {3000, 2000}) {}
}

@(test)
test_a_window_is_pulled_back_when_it_does_not_fit_the_screen :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    actionFrame(harness, hugeWindow)
    actionFrame(harness, hugeWindow)
    size: Vec2 = UiWindowSize(&harness.ctx, "huge")
    testing.expect(t, near(size.x, 400) && near(size.y, 300), "not bigger than the screen")
    position: Vec2 = UiWindowPosition(&harness.ctx, "huge")
    testing.expect(t, position.x >= 80 - size.x - 0.01 && position.x <= 320.01 && position.y >= 0 && position.y <= 300 - 28 + 0.01, "its title bar is on the screen")
    // the screen shrinks: the window follows
    UiBegin(&harness.ctx, {}, 1.0 / 60, {200, 150}, &harness.style)
    hugeWindow(&harness.ctx)
    UiEnd(&harness.ctx)
    testing.expect(t, near(UiWindowSize(&harness.ctx, "huge").x, 200) && near(UiWindowSize(&harness.ctx, "huge").y, 150))
}

@(test)
test_an_absolute_child_is_out_of_the_flow_and_at_its_offset :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    ElementOpen(&harness.ctx, {id = 10, layout = {padding = PaddingAll(5), gap = 3}})
    ElementOpen(&harness.ctx, {id = 11, layout = {size = {Fixed(40), Fixed(20)}}})
    ElementClose(&harness.ctx)
    // between two children of the flow: neither the gap nor the size of the parent knows it
    ElementOpen(&harness.ctx, {id = 12, layout = {size = {Fixed(300), Fixed(200)}}, absolute = {enabled = true, offset = {7, 9}}})
    ElementOpen(&harness.ctx, {id = 13, layout = {size = {Fixed(10), Fixed(10)}}})       // and it has children of its own
    ElementClose(&harness.ctx)
    ElementClose(&harness.ctx)
    ElementOpen(&harness.ctx, {id = 14, layout = {size = {Fixed(60), Fixed(10)}}})
    ElementClose(&harness.ctx)
    // grows to the size of the parent
    ElementOpen(&harness.ctx, {id = 15, layout = {size = {Grow(), Grow()}}, absolute = {enabled = true}})
    ElementClose(&harness.ctx)
    ElementClose(&harness.ctx)
    UiEnd(&harness.ctx)

    outer, _ := UiElementRect(&harness.ctx, 10)
    testing.expect_value(t, outer, Rect{0, 0, 70, 43})                  // as without the absolute children
    second, _ := UiElementRect(&harness.ctx, 14)
    testing.expect_value(t, second, Rect{5, 28, 60, 10})               // placed right after the first: no gap for the absolute one
    absolute, _ := UiElementRect(&harness.ctx, 12)
    testing.expect_value(t, absolute, Rect{7, 9, 300, 200})            // from the corner of the parent, the padding is not added, it may be bigger
    inner, _ := UiElementRect(&harness.ctx, 13)
    testing.expect_value(t, inner, Rect{7, 9, 10, 10})                 // its own children follow it
    grown, _ := UiElementRect(&harness.ctx, 15)
    testing.expect_value(t, grown, Rect{0, 0, 70, 43})
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(private = "file")
coveredGraphFrame :: proc(harness: ^Harness, graph: ^Graph, view: ^GraphView, input: Input) {
    frame(harness, input)
    ctx: ^Context = &harness.ctx
    if UiGraph(ctx, "g", graph, view, {Fixed(400), Fixed(300)}) {
        order: [4]NodeHandle
        count: int = GraphNodesByDepth(graph, order[:])
        for node in order[:count] {
            if UiGraphNode(ctx, graph, node) {
                port: ^Port = GraphPort(graph, GraphNode(graph, node).first_port)
                for port != nil {
                    UiGraphPin(ctx, graph, port.handle)
                    port = GraphPort(graph, port.next_in_node)
                }
            }
        }
    }
    UiEnd(ctx)
}

@(test)
test_a_pin_that_another_node_covers_neither_drags_nor_connects :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    graph: ^Graph = new(Graph)
    defer free(graph)
    GraphInit(graph)
    view: GraphView
    front_node, _ := GraphNodeAdd(graph, "back", {0, 0})            // declared first: below
    back_out, _ := GraphPortAdd(graph, front_node, "out", .OUTPUT, 1)
    cover, _ := GraphNodeAdd(graph, "front", {100, 0})              // declared second: above, over the right part of the first one
    cover_in, _ := GraphPortAdd(graph, cover, "in", .INPUT, 1)
    for _ in 0 ..< 4 { coveredGraphFrame(harness, graph, &view, {}) }
    pin: ^Port = GraphPort(graph, back_out)
    target: ^Port = GraphPort(graph, cover_in)
    testing.expect(t, pin.anchor_known && target.anchor_known)
    testing.expect(t, pin.anchor.x > 100, "the pin is under the second node")

    coveredGraphFrame(harness, graph, &view, pointerAt(pin.anchor))
    coveredGraphFrame(harness, graph, &view, pointerAt(pin.anchor, true, true))
    for i in 1 ..= 10 {
        position: Vec2 = pin.anchor + (target.anchor - pin.anchor) * (f32(i) / 10)
        coveredGraphFrame(harness, graph, &view, pointerAt(position, true))
        _, dragging := UiDragging(&harness.ctx)
        testing.expect(t, !dragging, "no cable is dragged from a covered pin")
    }
    coveredGraphFrame(harness, graph, &view, pointerAt(target.anchor, false, false, true))
    testing.expect_value(t, GraphLinkCount(graph), 0)

    // and a cable from a pin that is free cannot end on a pin that is covered
    free_node, _ := GraphNodeAdd(graph, "free", {0, 150})
    free_out, _ := GraphPortAdd(graph, free_node, "in", .INPUT, 1)          // an input: it fits the covered output, so only the cover can stop it
    for _ in 0 ..< 3 { coveredGraphFrame(harness, graph, &view, {}) }
    source: ^Port = GraphPort(graph, free_out)
    coveredGraphFrame(harness, graph, &view, pointerAt(source.anchor))
    coveredGraphFrame(harness, graph, &view, pointerAt(source.anchor, true, true))
    for i in 1 ..= 10 {
        position: Vec2 = source.anchor + (pin.anchor - source.anchor) * (f32(i) / 10)
        coveredGraphFrame(harness, graph, &view, pointerAt(position, true))
    }
    coveredGraphFrame(harness, graph, &view, pointerAt(pin.anchor, false, false, true))
    testing.expect_value(t, GraphLinkCount(graph), 0)
}

@(private = "file")
scrollFrame :: proc(harness: ^Harness, input: Input) {
    frame(harness, input)
    if UiScroll(&harness.ctx, "List", {Fixed(100), Fixed(100)}) {
        for _ in 0 ..< 20 { UiLabel(&harness.ctx, "item") }
    }
    UiEnd(&harness.ctx)
    UiRender(&harness.ctx)
}

@(test)
test_the_scrollbar_is_dragged_by_its_thumb :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    for _ in 0 ..< 3 { scrollFrame(harness, pointerAt({95, 5})) }
    testing.expect_value(t, UiScrollGet(&harness.ctx, UiIdPath("List")), 0)
    scrollFrame(harness, pointerAt({95, 5}, true, true))
    // the pointer goes down the track: the content follows, the thumb stays under the pointer
    for y in 10 ..= 40 { scrollFrame(harness, pointerAt({95, f32(y)}, true)) }
    middle: f32 = UiScrollGet(&harness.ctx, UiIdPath("List"))
    testing.expect(t, middle > 50, "the content moved")
    scrollFrame(harness, pointerAt({95, 40}, false, false, true))
    held: f32 = UiScrollGet(&harness.ctx, UiIdPath("List"))
    testing.expect_value(t, held, middle)                       // letting go keeps it
    // all the way down, and past the end of the track
    scrollFrame(harness, pointerAt({95, 40}, true, true))
    for y in 41 ..= 140 { scrollFrame(harness, pointerAt({95, f32(y)}, true)) }
    scrollFrame(harness, pointerAt({95, 140}, false, false, true))
    end: f32 = UiScrollGet(&harness.ctx, UiIdPath("List"))
    scrollFrame(harness, pointerAt({95, 40}))
    testing.expect(t, end > middle, "the end of the track is the end of the content")
    state: ^WidgetState = stateFind(&harness.ctx, UiIdPath("List"))
    testing.expect(t, abs(end - (state.content_size.y - state.rect.w)) < 0.5)
}

@(private = "file")
audioFrame :: proc(harness: ^Harness, input: Input, knob: ^f32, fader: ^f32) -> (knob_changed: bool, fader_changed: bool) {
    frame(harness, input)
    knob_changed = UiKnob(&harness.ctx, "Gain", knob, 0, 10, 5, {Fixed(40), Fixed(40)})
    fader_changed = UiFader(&harness.ctx, "Vol", fader, 0, 1, 0.5, {Fixed(20), Fixed(100)})
    UiMeter(&harness.ctx, "Level", 0.5, 0.8)
    UiEnd(&harness.ctx)
    UiRender(&harness.ctx)
    return
}

@(test)
test_a_knob_turns_by_dragging_up_and_resets_on_a_double_click :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    knob: f32 = 5
    fader: f32 = 0.5
    for _ in 0 ..< 3 { audioFrame(harness, pointerAt({20, 20}), &knob, &fader) }
    audioFrame(harness, pointerAt({20, 20}, true, true), &knob, &fader)
    // 80 pixels up is half of the whole drag distance: half of the range
    for i in 1 ..= 8 { audioFrame(harness, pointerAt({20, 20 - f32(i) * 10}, true), &knob, &fader) }
    audioFrame(harness, pointerAt({20, -60}, false, false, true), &knob, &fader)
    testing.expect(t, abs(knob - (5 + 10 * 80.0 / KNOB_DRAG_PIXELS)) < 0.01 || knob == 10, "dragging up turns it up")
    // down again, below the start: it stops at the minimum
    audioFrame(harness, pointerAt({20, 20}), &knob, &fader)
    audioFrame(harness, pointerAt({20, 20}, true, true), &knob, &fader)
    for i in 1 ..= 30 { audioFrame(harness, pointerAt({20, 20 + f32(i) * 10}, true), &knob, &fader) }
    audioFrame(harness, pointerAt({20, 320}, false, false, true), &knob, &fader)
    testing.expect_value(t, knob, 0)
    // a second press within the double click time sets the default
    audioFrame(harness, pointerAt({20, 20}), &knob, &fader)
    audioFrame(harness, pointerAt({20, 20}, true, true), &knob, &fader)
    audioFrame(harness, pointerAt({20, 20}, false, false, true), &knob, &fader)
    audioFrame(harness, pointerAt({20, 20}, true, true), &knob, &fader)
    audioFrame(harness, pointerAt({20, 20}, false, false, true), &knob, &fader)
    testing.expect_value(t, knob, 5)
    // what the style gets: the value 0..1 and where the default is
    testing.expect(t, near(seen.last[.KNOB].value, 0.5) && near(seen.last[.KNOB].ratio, 0.5))
}

@(test)
test_a_fader_follows_the_pointer_and_a_meter_shows_a_level_and_its_peak :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    knob: f32 = 5
    fader: f32 = 0.5
    // the fader is declared after the knob (40 high) in a column: it starts at y 40, 100 high
    for _ in 0 ..< 3 { audioFrame(harness, pointerAt({10, 60}), &knob, &fader) }
    audioFrame(harness, pointerAt({10, 60}, true, true), &knob, &fader)
    testing.expect(t, abs(fader - (1 - (60.0 - 40 - 7) / (100 - 14))) < 0.001, "the top is the maximum, the middle of the handle is at the pointer")
    audioFrame(harness, pointerAt({10, 400}, true), &knob, &fader)
    testing.expect_value(t, fader, 0)                           // past the bottom: the minimum
    audioFrame(harness, pointerAt({10, 400}, false, false, true), &knob, &fader)
    meter: DrawInfo = seen.last[.METER]
    testing.expect(t, near(meter.value, 0.5) && near(meter.ratio, 0.8) && meter.cursor == 0)
}

@(test)
test_the_delete_key_removes_the_selected_nodes_and_their_cables :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    graph: ^Graph = new(Graph)
    defer free(graph)
    GraphInit(graph)
    view: GraphView
    first, _ := GraphNodeAdd(graph, "a", {0, 0})
    out, _ := GraphPortAdd(graph, first, "out", .OUTPUT, 1)
    second, _ := GraphNodeAdd(graph, "b", {200, 0})
    input, _ := GraphPortAdd(graph, second, "in", .INPUT, 1)
    third, _ := GraphNodeAdd(graph, "c", {0, 150})
    GraphConnect(graph, out, input)
    for _ in 0 ..< 3 { coveredGraphFrame(harness, graph, &view, {}) }
    GraphNodeSelect(graph, second)
    GraphNodeSelect(graph, third)
    deleting: Input = {mouse_position = {5, 290}, keys = {.DELETE}}
    coveredGraphFrame(harness, graph, &view, deleting)
    testing.expect(t, GraphNode(graph, second) == nil && GraphNode(graph, third) == nil, "the selected nodes are gone")
    testing.expect(t, GraphNode(graph, first) != nil, "the other stays")
    testing.expect_value(t, GraphLinkCount(graph), 0)
}

@(private = "file")
zoomFrame :: proc(harness: ^Harness, input: Input) {
    frame(harness, input)
    ctx: ^Context = &harness.ctx
    ElementOpen(ctx, {id = 9, layout = {padding = {20, 0, 30, 0}}})
    ElementOpen(ctx, {id = 10, layout = {size = {Fixed(200), Fixed(100)}}, zoom = 2, clip = {horizontal = true, vertical = true, cut = true}})
    ElementOpen(ctx, {id = 11, layout = {size = {Fixed(30), Fixed(20)}}, absolute = {enabled = true, offset = {10, 10}}, hit = {.INTERACTIVE}, draw = {kind = .BUTTON}})
    ElementClose(ctx)
    ElementOpen(ctx, {id = 12, layout = {size = {Grow(), Grow()}}})
    ElementClose(ctx)
    ElementClose(ctx)
    ElementClose(ctx)
    UiEnd(ctx)
}

@(test)
test_a_zoomed_container_lays_out_in_logical_units_and_is_shown_bigger :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    for _ in 0 ..< 2 { zoomFrame(harness, pointerAt({-5, -5})) }
    container, _ := UiElementRect(&harness.ctx, 10)
    testing.expect_value(t, container, Rect{20, 30, 200, 100})          // the container itself is not zoomed
    button, _ := UiElementRect(&harness.ctx, 11)
    testing.expect_value(t, button, Rect{40, 50, 60, 40})               // 10 logical units from its corner, twice as big
    grown, _ := UiElementRect(&harness.ctx, 12)
    testing.expect_value(t, grown, Rect{20, 30, 200, 100})              // it grew to the logical size (100 x 50), shown twice as big: all of the container
    // the pointer finds it where it is shown
    zoomFrame(harness, pointerAt({50, 60}))
    testing.expect_value(t, harness.ctx.hover, Id(11))
    zoomFrame(harness, pointerAt({35, 60}))                              // 15 logical units: left of it
    testing.expect_value(t, harness.ctx.hover, Id(0))
    // the commands: the zoom is announced with its origin and factor, the draw is in logical units, the clip is the container
    zoom_begin, zoom_end, draw: int
    draw_rect: Rect
    for command in UiCommands(&harness.ctx) {
        #partial switch command.kind {
        case .ZOOM_BEGIN:
            zoom_begin += 1
            testing.expect_value(t, command.info.rect, Rect{20, 30, 2, 0})
        case .ZOOM_END: zoom_end += 1
        case .DRAW:
            draw += 1
            draw_rect = command.info.rect
        }
    }
    testing.expect(t, zoom_begin == 1 && zoom_end == 1 && draw == 1)
    testing.expect_value(t, draw_rect, Rect{30, 40, 30, 20})             // logical: corner of the container plus 10, the size it was declared with
}

@(test)
test_a_zoomed_graph_zooms_around_the_pointer_and_still_connects_and_drags :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    graph: ^Graph = new(Graph)
    defer free(graph)
    GraphInit(graph)
    view: GraphView
    left, _ := GraphNodeAdd(graph, "a", {0, 0})
    out, _ := GraphPortAdd(graph, left, "out", .OUTPUT, 1)
    right, _ := GraphNodeAdd(graph, "b", {300, 0})
    input, _ := GraphPortAdd(graph, right, "in", .INPUT, 1)
    for _ in 0 ..< 4 { coveredGraphFrame(harness, graph, &view, {}) }
    size_before: Vec2 = GraphNode(graph, left).size
    anchor_before: Vec2 = GraphPort(graph, out).anchor

    // two notches of the wheel over the empty canvas: 1.1 twice
    wheel: Input = pointerAt({250, 2})
    wheel.wheel = {0, 2}
    coveredGraphFrame(harness, graph, &view, pointerAt({250, 2}))
    coveredGraphFrame(harness, graph, &view, wheel)
    zoom: f32 = GraphViewZoom(&view)
    testing.expect(t, abs(zoom - 1.21) < 0.001)
    testing.expect(t, abs(250 / zoom + view.origin.x - 250) < 0.01 && abs(2 / zoom + view.origin.y - 2) < 0.01, "the canvas point under the pointer did not move")
    for _ in 0 ..< 3 { coveredGraphFrame(harness, graph, &view, {}) }
    // what the model knows is in canvas units, whatever the zoom
    testing.expect(t, abs(GraphNode(graph, left).size.x - size_before.x) < 0.5 && abs(GraphNode(graph, left).size.y - size_before.y) < 0.5, "a node is as big as it was in canvas units")
    testing.expect(t, abs(GraphPort(graph, out).anchor.x - anchor_before.x) < 0.5 && abs(GraphPort(graph, out).anchor.y - anchor_before.y) < 0.5)
    testing.expect(t, abs(view.viewport.x - 400 / zoom) < 0.01, "the view is as many canvas units as fit in the pixels")

    // a cable from the pin to the pin, at the places they are shown
    from: Vec2 = GraphToScreen(&view, GraphPort(graph, out).anchor)
    to: Vec2 = GraphToScreen(&view, GraphPort(graph, input).anchor)
    coveredGraphFrame(harness, graph, &view, pointerAt(from))
    coveredGraphFrame(harness, graph, &view, pointerAt(from, true, true))
    for i in 1 ..= 10 { coveredGraphFrame(harness, graph, &view, pointerAt(from + (to - from) * (f32(i) / 10), true)) }
    coveredGraphFrame(harness, graph, &view, pointerAt(to, false, false, true))
    testing.expect_value(t, GraphLinkCount(graph), 1)

    // a title that is dragged 40 pixels on the screen moves the node 40 / zoom canvas units
    corner: Vec2 = GraphToScreen(&view, GraphNode(graph, right).position)
    title: Vec2 = corner + {40, 8}
    before: f32 = GraphNode(graph, right).position.x
    coveredGraphFrame(harness, graph, &view, pointerAt(title))
    coveredGraphFrame(harness, graph, &view, pointerAt(title, true, true))
    for i in 1 ..= 8 { coveredGraphFrame(harness, graph, &view, pointerAt(title + {f32(i) * 5, 0}, true)) }
    coveredGraphFrame(harness, graph, &view, pointerAt(title + {40, 0}, false, false, true))
    testing.expect(t, abs(GraphNode(graph, right).position.x - (before + 40 / zoom)) < 0.5, "the node followed the pointer")
}

@(private = "file")
fieldFrame :: proc(harness: ^Harness, input: Input, buffer: []u8, length: ^int) -> bool {
    frame(harness, input)
    changed, _ := UiTextField(&harness.ctx, "Field", buffer, length, {Fixed(200), Fixed(28)})
    UiEnd(&harness.ctx)
    UiRender(&harness.ctx)
    return changed
}

@(private = "file")
fieldText :: proc(buffer: []u8, length: int) -> string {
    return string(buffer[:length])
}

@(test)
test_a_text_field_selects_copies_cuts_and_pastes :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    buffer: [32]u8
    length: int
    // the field is focused by a click, then "hello world" is typed
    for _ in 0 ..< 2 { fieldFrame(harness, pointerAt({20, 10}), buffer[:], &length) }
    fieldFrame(harness, pointerAt({20, 10}, true, true), buffer[:], &length)
    fieldFrame(harness, pointerAt({20, 10}, false, false, true), buffer[:], &length)
    typing: Input = pointerAt({20, 10})
    copy(typing.text[:], "hello world")
    typing.text_count = 11
    fieldFrame(harness, typing, buffer[:], &length)
    testing.expect_value(t, fieldText(buffer[:], length), "hello world")

    // shift + left: the selection grows from the cursor; ctrl + shift + left: by a word
    shift_left: Input = pointerAt({20, 10})
    shift_left.modifiers = {.SHIFT, .CTRL}
    shift_left.keys = {.LEFT}
    fieldFrame(harness, shift_left, buffer[:], &length)
    state: ^WidgetState = stateFind(&harness.ctx, UiIdPath("Field"))
    testing.expect_value(t, state.cursor, 6)                            // the start of "world"
    testing.expect_value(t, state.anchor, 11)
    // copy it, then type over it: the selection is replaced
    copy_input: Input = pointerAt({20, 10})
    copy_input.actions = {.COPY}
    fieldFrame(harness, copy_input, buffer[:], &length)
    replacement: Input = pointerAt({20, 10})
    copy(replacement.text[:], "there")
    replacement.text_count = 5
    fieldFrame(harness, replacement, buffer[:], &length)
    testing.expect_value(t, fieldText(buffer[:], length), "hello there")
    // select all, cut: the field is empty, the clipboard has it
    select_all: Input = pointerAt({20, 10})
    select_all.actions = {.SELECT_ALL, .CUT}
    fieldFrame(harness, select_all, buffer[:], &length)
    testing.expect_value(t, length, 0)
    clipboard: [32]u8
    count: int = UiClipboardGet(&harness.ctx, clipboard[:])
    testing.expect_value(t, string(clipboard[:count]), "hello there")
    // paste twice
    paste: Input = pointerAt({20, 10})
    paste.actions = {.PASTE}
    fieldFrame(harness, paste, buffer[:], &length)
    fieldFrame(harness, paste, buffer[:], &length)
    testing.expect_value(t, fieldText(buffer[:], length), "hello therehello there")
    // the buffer is full at 32 bytes: a paste that does not fit is cut, never in the middle of a rune
    for _ in 0 ..< 3 { fieldFrame(harness, paste, buffer[:], &length) }
    testing.expect_value(t, length, 32)
}

@(test)
test_a_text_field_moves_by_words_and_deletes_the_selection_with_the_keys :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    buffer: [32]u8
    text: string = "one two  three"
    copy(buffer[:], text)
    length: int = len(text)
    for _ in 0 ..< 2 { fieldFrame(harness, pointerAt({500, 10}), buffer[:], &length) }
    // the focus comes with a press on the field
    fieldFrame(harness, pointerAt({195, 10}, true, true), buffer[:], &length)
    fieldFrame(harness, pointerAt({195, 10}, false, false, true), buffer[:], &length)
    state: ^WidgetState = stateFind(&harness.ctx, UiIdPath("Field"))
    testing.expect_value(t, state.cursor, length)
    ctrl_left: Input = pointerAt({500, 10})
    ctrl_left.modifiers = {.CTRL}
    ctrl_left.keys = {.LEFT}
    fieldFrame(harness, ctrl_left, buffer[:], &length)
    testing.expect_value(t, state.cursor, 9)                            // before "three"
    fieldFrame(harness, ctrl_left, buffer[:], &length)
    testing.expect_value(t, state.cursor, 4)                            // before "two"
    // ctrl + backspace: the word before the cursor
    ctrl_backspace: Input = pointerAt({500, 10})
    ctrl_backspace.modifiers = {.CTRL}
    ctrl_backspace.keys = {.BACKSPACE}
    fieldFrame(harness, ctrl_backspace, buffer[:], &length)
    testing.expect_value(t, fieldText(buffer[:], length), "two  three")
    // shift + end selects to the end, delete removes it
    shift_end: Input = pointerAt({500, 10})
    shift_end.modifiers = {.SHIFT}
    shift_end.keys = {.END}
    fieldFrame(harness, shift_end, buffer[:], &length)
    testing.expect_value(t, state.anchor, 0)
    testing.expect_value(t, state.cursor, length)
    deleting: Input = pointerAt({500, 10})
    deleting.keys = {.DELETE}
    fieldFrame(harness, deleting, buffer[:], &length)
    testing.expect_value(t, length, 0)
}

@(test)
test_dragging_in_a_text_field_selects_and_a_double_click_takes_a_word :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    buffer: [32]u8
    text: string = "alpha beta"
    copy(buffer[:], text)
    length: int = len(text)
    for _ in 0 ..< 2 { fieldFrame(harness, pointerAt({100, 10}), buffer[:], &length) }
    // the test font is half as wide as it is high (16 px: 8 per letter), the text starts after the padding
    padding: f32 = DEFAULT_METRICS.padding.x
    fieldFrame(harness, pointerAt({padding + 8 * 2, 10}, true, true), buffer[:], &length)
    for x in 3 ..= 8 { fieldFrame(harness, pointerAt({padding + 8 * f32(x), 10}, true), buffer[:], &length) }
    fieldFrame(harness, pointerAt({padding + 8 * 8, 10}, false, false, true), buffer[:], &length)
    state: ^WidgetState = stateFind(&harness.ctx, UiIdPath("Field"))
    testing.expect_value(t, state.anchor, 2)
    testing.expect_value(t, state.cursor, 8)
    // a second press within the double click time takes the word under the pointer ("beta" is at 6 .. 10)
    fieldFrame(harness, pointerAt({padding + 8 * 7, 10}), buffer[:], &length)
    fieldFrame(harness, pointerAt({padding + 8 * 7, 10}, true, true), buffer[:], &length)
    fieldFrame(harness, pointerAt({padding + 8 * 7, 10}, false, false, true), buffer[:], &length)
    fieldFrame(harness, pointerAt({padding + 8 * 7, 10}, true, true), buffer[:], &length)
    testing.expect_value(t, state.anchor, 6)
    testing.expect_value(t, state.cursor, 10)
}

@(private = "file")
areaFrame :: proc(harness: ^Harness, input: Input, buffer: []u8, length: ^int) -> bool {
    frame(harness, input)
    UiButton(&harness.ctx, "Above")
    changed := UiTextArea(&harness.ctx, "Notes", buffer, length, {Fixed(100), Fixed(60)})
    UiEnd(&harness.ctx)
    UiRender(&harness.ctx)
    return changed
}

@(private = "file")
areaType :: proc(harness: ^Harness, text: string, buffer: []u8, length: ^int) {
    input: Input = pointerAt({50, 60})
    copy(input.text[:], text)
    input.text_count = u8(len(text))
    areaFrame(harness, input, buffer, length)
}

@(private = "file")
areaKey :: proc(harness: ^Harness, buffer: []u8, length: ^int, keys: Keys = {}, actions: Actions = {}, modifiers: Modifiers = {}) {
    input: Input = pointerAt({50, 60})
    input.keys, input.actions, input.modifiers = keys, actions, modifiers
    areaFrame(harness, input, buffer, length)
}

@(test)
test_the_rows_of_a_text_break_at_words_new_lines_and_too_long_words :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    frame(harness)
    ctx: ^Context = &harness.ctx
    // the test font: 8 pixels a letter. 80 pixels hold ten letters
    count: int = areaLines(ctx, "hello world foo", 80, true)
    testing.expect_value(t, count, 2)
    testing.expect(t, ctx.area_lines[0].start == 0 && ctx.area_lines[0].end == 6 && !ctx.area_lines[0].hard, "the space after a word stays on its row")
    testing.expect(t, ctx.area_lines[1].start == 6 && ctx.area_lines[1].end == 15 && !ctx.area_lines[1].hard)
    count = areaLines(ctx, "a\n\nb", 80, true)
    testing.expect_value(t, count, 3)
    testing.expect(t, ctx.area_lines[0].hard && ctx.area_lines[1].start == 2 && ctx.area_lines[1].end == 2 && ctx.area_lines[2].start == 3)
    count = areaLines(ctx, "abcdefghijklmnop", 80, true)
    testing.expect_value(t, count, 2)
    testing.expect(t, ctx.area_lines[0].end == 10 && ctx.area_lines[1].start == 10 && ctx.area_lines[1].end == 16, "a word wider than the room is cut where it stops fitting")
    testing.expect_value(t, areaLines(ctx, "hello world foo", 80, false), 1)
    testing.expect_value(t, areaLines(ctx, "ends with a line\n", 400, true), 2)             // an empty last row where the cursor can be
    testing.expect_value(t, areaLines(ctx, "", 80, true), 1)
    // where a byte offset is: the end of a row that wrapped is the start of the next
    count = areaLines(ctx, "hello world foo", 80, true)
    testing.expect_value(t, areaLineOf(ctx.area_lines[:], count, 6), 1)
    testing.expect_value(t, areaLineOf(ctx.area_lines[:], count, 5), 0)
    testing.expect_value(t, areaLineOf(ctx.area_lines[:], count, 15), 1)
}

@(test)
test_a_text_area_takes_new_lines_and_up_and_down_keep_the_column :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    buffer: [128]u8
    length: int
    for _ in 0 ..< 2 { areaFrame(harness, pointerAt({50, 60}), buffer[:], &length) }
    areaFrame(harness, pointerAt({50, 60}, true, true), buffer[:], &length)
    areaFrame(harness, pointerAt({50, 60}, false, false, true), buffer[:], &length)
    areaType(harness, "one", buffer[:], &length)
    areaKey(harness, buffer[:], &length, keys = {.ENTER})
    areaType(harness, "two", buffer[:], &length)
    testing.expect_value(t, string(buffer[:length]), "one\ntwo")
    state: ^WidgetState = stateFind(&harness.ctx, UiIdPath("Notes"))
    testing.expect_value(t, state.cursor, 7)
    // up: the same column on the row above, and the focus stays in the area (the button above it does not take it)
    areaKey(harness, buffer[:], &length, actions = {.UP})
    testing.expect_value(t, state.cursor, 3)
    testing.expect_value(t, harness.ctx.focus, UiIdPath("Notes"))
    areaType(harness, "X", buffer[:], &length)
    testing.expect_value(t, string(buffer[:length]), "oneX\ntwo")
    areaKey(harness, buffer[:], &length, actions = {.DOWN})
    testing.expect_value(t, state.cursor, 8)                            // the end of "two": it is shorter than the column
    areaKey(harness, buffer[:], &length, keys = {.HOME})
    testing.expect_value(t, state.cursor, 5)
    areaKey(harness, buffer[:], &length, keys = {.END})
    testing.expect_value(t, state.cursor, 8)
    areaKey(harness, buffer[:], &length, keys = {.HOME}, modifiers = {.CTRL})
    testing.expect_value(t, state.cursor, 0)
    // shift + down selects over the line break: "oneX\n" is what is copied
    areaKey(harness, buffer[:], &length, actions = {.DOWN}, modifiers = {.SHIFT})
    testing.expect_value(t, state.anchor, 0)
    testing.expect_value(t, state.cursor, 5)
    areaKey(harness, buffer[:], &length, actions = {.COPY})
    clipboard: [16]u8
    count: int = UiClipboardGet(&harness.ctx, clipboard[:])
    testing.expect_value(t, string(clipboard[:count]), "oneX\n")
    // paste keeps the new line (a text field would make a space of it)
    areaKey(harness, buffer[:], &length, keys = {.END}, modifiers = {.CTRL})
    areaKey(harness, buffer[:], &length, actions = {.PASTE})
    testing.expect_value(t, string(buffer[:length]), "oneX\ntwooneX\n")
}

@(test)
test_a_text_area_scrolls_to_the_cursor_and_wraps_to_its_width :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    buffer: [256]u8
    length: int
    for _ in 0 ..< 2 { areaFrame(harness, pointerAt({50, 60}), buffer[:], &length) }
    areaFrame(harness, pointerAt({50, 60}, true, true), buffer[:], &length)
    areaFrame(harness, pointerAt({50, 60}, false, false, true), buffer[:], &length)
    // ten rows in a box of 60 pixels: the view follows the cursor down
    for i in 0 ..< 10 {
        areaType(harness, "row", buffer[:], &length)
        _ = i
        areaKey(harness, buffer[:], &length, keys = {.ENTER})
    }
    state: ^WidgetState = stateFind(&harness.ctx, UiIdPath("Notes"))
    testing.expect(t, state.scroll.y < -50, "the view went down with the cursor")
    areaKey(harness, buffer[:], &length, keys = {.HOME}, modifiers = {.CTRL})
    testing.expect_value(t, state.scroll.y, 0)                           // and back up when the cursor does
    // a scrollbar is declared while the text is longer than the box
    areaKey(harness, buffer[:], &length)
    testing.expect(t, seen.kinds[.SCROLLBAR] > 0)
    // the text is cut into rows by the width: the words of a long line wrap
    length = 0
    areaType(harness, "alpha beta gamma delta ", buffer[:], &length)
    areaType(harness, "epsilon zeta", buffer[:], &length)
    areaKey(harness, buffer[:], &length)
    areaFrame(harness, pointerAt({50, 60}), buffer[:], &length)
    testing.expect(t, areaLines(&harness.ctx, string(buffer[:length]), 100 - 2 * DEFAULT_METRICS.padding.x - DEFAULT_METRICS.scrollbar_width, true) > 2)
}

@(private = "file")
measureFrame :: proc(harness: ^Harness, label: string) {
    frame(harness)
    UiLabel(&harness.ctx, label)
    UiButton(&harness.ctx, "A button")
    UiLabel(&harness.ctx, "some words that are measured one by one")
    UiEnd(&harness.ctx)
}

@(test)
test_texts_are_measured_once_and_the_answer_is_kept_between_frames :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    measure_calls = 0
    measureFrame(harness, "first")
    first: int = measure_calls
    testing.expect(t, first > 0, "the first frame measures")
    hits_before, misses_before := UiMeasureCacheStats(&harness.ctx)
    measure_calls = 0
    measureFrame(harness, "first")
    testing.expect_value(t, measure_calls, 0)                           // the same texts: nothing is measured again
    hits_after, misses_after := UiMeasureCacheStats(&harness.ctx)
    testing.expect(t, hits_after > hits_before && misses_after == misses_before)
    // a text that changed is measured, the others are not
    measure_calls = 0
    measureFrame(harness, "second")
    testing.expect(t, measure_calls > 0 && measure_calls < first, "only the new text goes to the measure proc")
    // after the clear everything is measured again
    UiMeasureCacheClear(&harness.ctx)
    measure_calls = 0
    measureFrame(harness, "second")
    testing.expect_value(t, measure_calls, first)
    // the same text at another size is another answer
    big: Vec2 = measureText(&harness.ctx, "word", 32)
    small: Vec2 = measureText(&harness.ctx, "word", 16)
    testing.expect(t, big.x == 2 * small.x && big.y == 32 && small.y == 16)
}

@(test)
test_a_new_ui_scale_clears_the_measure_cache :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    UiMeasureCacheScale(&harness.ctx, 1)
    measure_calls = 0
    measureFrame(harness, "x")
    first: int = measure_calls
    measure_calls = 0
    UiMeasureCacheScale(&harness.ctx, 1)
    measureFrame(harness, "x")
    testing.expect_value(t, measure_calls, 0)                           // the same scale: kept
    UiMeasureCacheScale(&harness.ctx, 2)
    measure_calls = 0
    measureFrame(harness, "x")
    testing.expect_value(t, measure_calls, first)                       // another scale: measured again
}

@(private = "file")
timelineFrame :: proc(harness: ^Harness, timeline: ^Timeline, view: ^TimelineView, input: Input) -> bool {
    frame(harness, input)
    changed := UiTimeline(&harness.ctx, "T", timeline, view, {Fixed(400), Fixed(200)})
    UiEnd(&harness.ctx)
    UiRender(&harness.ctx)
    return changed
}

@(private = "file")
timelineDrag :: proc(harness: ^Harness, timeline: ^Timeline, view: ^TimelineView, from: Vec2, to: Vec2, modifiers: Modifiers = {}) {
    start: Input = pointerAt(from)
    start.modifiers = modifiers
    timelineFrame(harness, timeline, view, start)
    press: Input = pointerAt(from, true, true)
    press.modifiers = modifiers
    timelineFrame(harness, timeline, view, press)
    for i in 1 ..= 8 {
        step: Input = pointerAt(from + (to - from) * (f32(i) / 8), true)
        step.modifiers = modifiers
        timelineFrame(harness, timeline, view, step)
    }
    timelineFrame(harness, timeline, view, pointerAt(to, false, false, true))
}

@(private = "file")
timelineClick :: proc(harness: ^Harness, timeline: ^Timeline, view: ^TimelineView, at: Vec2, modifiers: Modifiers) {
    move: Input = pointerAt(at)
    move.modifiers = modifiers
    timelineFrame(harness, timeline, view, move)
    press: Input = pointerAt(at, true, true)
    press.modifiers = modifiers
    timelineFrame(harness, timeline, view, press)
    release: Input = pointerAt(at, false, false, true)
    release.modifiers = modifiers
    timelineFrame(harness, timeline, view, release)
}

@(private = "file")
timelineDrain :: proc(timeline: ^Timeline) {
    for {
        _, has := TimelinePollEvent(timeline)
        if !has { break }
    }
}

@(private = "file")
timelineSetup :: proc(harness: ^Harness) -> (timeline: ^Timeline, view: ^TimelineView, first: TrackHandle, second: TrackHandle, clip: ClipHandle) {
    harnessInit(harness)
    timeline = new(Timeline)
    TimelineInit(timeline)
    view = new(TimelineView)
    view.zoom = 100
    view.snap = 0.5
    first, _ = TimelineTrackAdd(timeline, "one")
    second, _ = TimelineTrackAdd(timeline, "two")
    clip, _ = TimelineClipAdd(timeline, first, 1, 2, "clip")
    for _ in 0 ..< 3 { timelineFrame(harness, timeline, view, pointerAt({-10, -10})) }
    timelineDrain(timeline)
    return
}

@(test)
test_a_clip_is_dragged_to_another_start_and_another_track_with_the_pointer :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    timeline, view, first, second, clip := timelineSetup(harness)
    defer { free(timeline); free(view); free(harness) }
    timelineDrag(harness, timeline, view, {200, 40}, {300, 88})
    moved: ^TimelineClip = TimelineClipGet(timeline, clip)
    testing.expect_value(t, moved.start, 2)
    testing.expect_value(t, moved.track, second)
    testing.expect(t, moved.selected, "a press selects it")
    changed_track: bool
    for {
        event, has := TimelinePollEvent(timeline)
        if !has { break }
        testing.expect_value(t, event.kind, TimelineEventKind.CLIP_MOVED)
        if event.previous_track == first && event.track == second { changed_track = true }
    }
    testing.expect(t, changed_track, "one of the moves went from the first track to the second")
    timelineDrag(harness, timeline, view, {300, 88}, {-300, 88})
    testing.expect_value(t, TimelineClipGet(timeline, clip).start, 0)
}

@(test)
test_the_edges_of_a_clip_resize_it_and_the_playhead_follows_the_ruler :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    timeline, view, _, _, clip := timelineSetup(harness)
    defer { free(timeline); free(view); free(harness) }
    timelineDrag(harness, timeline, view, {297, 40}, {397, 40})
    testing.expect_value(t, TimelineClipGet(timeline, clip).length, 3)
    event, _ := TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.CLIP_RESIZED)
    timelineDrag(harness, timeline, view, {103, 40}, {153, 40})
    resized: ^TimelineClip = TimelineClipGet(timeline, clip)
    testing.expect(t, resized.start == 1.5 && resized.start + resized.length == 4)
    timelineDrain(timeline)
    timelineDrag(harness, timeline, view, {250, 10}, {350, 10})
    testing.expect_value(t, view.playhead, 3.5)
    seen_playhead: bool
    for {
        e, has := TimelinePollEvent(timeline)
        if !has { break }
        if e.kind == .PLAYHEAD { seen_playhead = true }
    }
    testing.expect(t, seen_playhead)
}

@(test)
test_the_wheel_zooms_around_the_pointer_and_an_empty_lane_pans :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    timeline, view, _, _, _ := timelineSetup(harness)
    defer { free(timeline); free(view); free(harness) }
    wheel: Input = pointerAt({200, 150})
    wheel.wheel = {0, 1}
    timelineFrame(harness, timeline, view, pointerAt({200, 150}))
    timelineFrame(harness, timeline, view, wheel)
    zoom: f32 = TimelineViewZoom(view)
    testing.expect(t, abs(zoom - 100 * TIMELINE_ZOOM_STEP) < 0.01)
    testing.expect(t, abs(TimelineTime(view, 200) - 2) < 0.001, "the time under the pointer did not move")
    TimelineClipSelect(timeline, TimelineClipAt(timeline, timeline.order[0], 1.5))
    timelineDrag(harness, timeline, view, {350, 150}, {250, 150})
    testing.expect(t, view.origin > 0.5)
    testing.expect_value(t, TimelineSelectedCount(timeline), 0)
}

@(test)
test_the_rules_the_lock_shift_and_delete_decide_what_the_pointer_may_do :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    timeline, view, first, second, clip := timelineSetup(harness)
    defer { free(timeline); free(view); free(harness) }
    timeline.rules.can_place = TimelineRuleNoOverlap
    other, _ := TimelineClipAdd(timeline, first, 3, 2, "other")
    for _ in 0 ..< 3 { timelineFrame(harness, timeline, view, pointerAt({-10, -10})) }
    timelineDrag(harness, timeline, view, {200, 40}, {350, 40})
    testing.expect(t, TimelineClipGet(timeline, clip).start + TimelineClipGet(timeline, clip).length <= 3, "it did not overlap")
    TimelineTrackGet(timeline, second).flags += {.LOCKED}
    TimelineClipPlace(timeline, other, second, 3, 2)
    for _ in 0 ..< 3 { timelineFrame(harness, timeline, view, pointerAt({-10, -10})) }
    before: f64 = TimelineClipGet(timeline, other).start
    timelineDrag(harness, timeline, view, {390, 88}, {500, 88})
    testing.expect_value(t, TimelineClipGet(timeline, other).start, before)
    TimelineTrackGet(timeline, second).flags -= {.LOCKED}
    TimelineSelectClear(timeline)
    timelineClick(harness, timeline, view, {200, 40}, {})
    testing.expect_value(t, TimelineSelectedCount(timeline), 1)
    timelineClick(harness, timeline, view, {390, 88}, {.SHIFT})
    testing.expect_value(t, TimelineSelectedCount(timeline), 2)
    timelineClick(harness, timeline, view, {390, 88}, {.SHIFT})
    testing.expect_value(t, TimelineSelectedCount(timeline), 1)
    deleting: Input = pointerAt({-10, -10})
    deleting.keys = {.DELETE}
    timelineDrain(timeline)
    changed: bool = timelineFrame(harness, timeline, view, deleting)
    testing.expect(t, changed, "the widget says that the person changed something")
    testing.expect_value(t, TimelineClipCount(timeline), 1)
    event, _ := TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.CLIP_REMOVED)
}

@(test)
test_a_double_click_on_an_empty_lane_is_told_to_the_program :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    timeline, view, _, second, _ := timelineSetup(harness)
    defer { free(timeline); free(view); free(harness) }
    at: Vec2 = {230, 100}
    timelineFrame(harness, timeline, view, pointerAt(at))
    timelineFrame(harness, timeline, view, pointerAt(at, true, true))
    timelineFrame(harness, timeline, view, pointerAt(at, false, false, true))
    timelineFrame(harness, timeline, view, pointerAt(at, true, true))
    event, has := TimelinePollEvent(timeline)
    testing.expect(t, has)
    testing.expect_value(t, event.kind, TimelineEventKind.EMPTY_DOUBLE_CLICK)
    testing.expect_value(t, event.track, second)
    testing.expect_value(t, event.time, 2.5)
}

@(test)
test_the_ruler_step_is_one_two_or_five_times_a_power_of_ten :: proc(t: ^testing.T) {
    testing.expect_value(t, TimelineRulerStep(100), 1)
    testing.expect_value(t, TimelineRulerStep(10), 10)
    testing.expect_value(t, TimelineRulerStep(30), 5)
    testing.expect_value(t, TimelineRulerStep(1000), 0.1)
    testing.expect_value(t, TimelineRulerStep(0.5), 200)
}

@(private = "file")
LIST_ROWS :: 10000

@(private = "file")
listFrame :: proc(harness: ^Harness, list: ^VirtualList, input: Input) {
    frame(harness, input)
    UiButton(&harness.ctx, "Above")
    if UiVirtual(&harness.ctx, "L", list, LIST_ROWS, 20, {Fixed(200), Fixed(100)}) {
        for row in list.first ..< list.last {
            if UiVirtualRow(&harness.ctx, list, row) { UiLabel(&harness.ctx, "row") }
        }
    }
    UiEnd(&harness.ctx)
    UiRender(&harness.ctx)
}

@(private = "file")
listClick :: proc(harness: ^Harness, list: ^VirtualList, at: Vec2) {
    listFrame(harness, list, pointerAt(at))
    listFrame(harness, list, pointerAt(at, true, true))
    listFrame(harness, list, pointerAt(at, false, false, true))
}

@(private = "file")
listKey :: proc(harness: ^Harness, list: ^VirtualList, actions: Actions) {
    input: Input = pointerAt({-10, -10})
    input.actions = actions
    listFrame(harness, list, input)
}

@(test)
test_a_list_of_ten_thousand_rows_declares_only_the_rows_in_view :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    list: VirtualList = {selected = VIRTUAL_NONE}
    for _ in 0 ..< 3 { listFrame(harness, &list, pointerAt({-10, -10})) }
    testing.expect_value(t, harness.ctx.problems, Problems{})            // the storage holds 64 elements: all the rows would not fit
    testing.expect_value(t, list.first, 0)
    testing.expect(t, list.last >= 5 && list.last <= 8, "a hundred pixels of twenty pixel rows, and one more")
    // the wheel scrolls: the rows in view are others
    wheel: Input = pointerAt({100, 60})
    wheel.wheel = {0, -1}
    listFrame(harness, &list, pointerAt({100, 60}))
    for _ in 0 ..< 10 { listFrame(harness, &list, wheel) }
    testing.expect(t, list.first > 0 && list.last > list.first)
    testing.expect_value(t, harness.ctx.problems, Problems{})
}

@(test)
test_a_click_selects_a_row_a_double_click_and_enter_activate_it_and_the_keys_move_the_selection :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    list: VirtualList = {selected = VIRTUAL_NONE}
    for _ in 0 ..< 3 { listFrame(harness, &list, pointerAt({-10, -10})) }
    // the list is under the button (28 high): its first row is at y 28 .. 48, the fourth at 88 .. 108
    listClick(harness, &list, {100, 100})
    testing.expect_value(t, list.selected, 3)
    listFrame(harness, &list, pointerAt({100, 100}, true, true))
    listFrame(harness, &list, pointerAt({100, 100}, false, false, true))
    listFrame(harness, &list, pointerAt({100, 100}, true, true))
    testing.expect(t, list.activated, "a second press within the double click time")
    // the keys move the selection while the list has the focus, and the focus does not leave for the button above
    listKey(harness, &list, {.DOWN})
    testing.expect_value(t, list.selected, 4)
    testing.expect(t, list.changed)
    listKey(harness, &list, {.UP})
    listKey(harness, &list, {.UP})
    testing.expect_value(t, list.selected, 2)
    testing.expect_value(t, harness.ctx.focus, UiIdPath("L"))
    listKey(harness, &list, {.ACCEPT})
    testing.expect(t, list.activated && !list.changed)
    // the end and the home: the view follows the selection
    listKey(harness, &list, {.END})
    testing.expect_value(t, list.selected, LIST_ROWS - 1)
    listFrame(harness, &list, pointerAt({-10, -10}))
    testing.expect(t, list.first > LIST_ROWS - 10 && list.last == LIST_ROWS, "the last rows are in view")
    listKey(harness, &list, {.HOME})
    listFrame(harness, &list, pointerAt({-10, -10}))
    testing.expect_value(t, list.selected, 0)
    testing.expect_value(t, list.first, 0)
    listKey(harness, &list, {.PAGE_DOWN})
    testing.expect_value(t, list.selected, 4)                           // a page is the rows in view, less one
}

@(private = "file")
tableFrame :: proc(harness: ^Harness, table: ^Table, input: Input) {
    frame(harness, input)
    if UiTable(&harness.ctx, "T", table, 1000, 20, {Fixed(300), Fixed(120)}) {
        for row in table.list.first ..< table.list.last {
            if UiTableRow(&harness.ctx, table, row) {
                UiTableText(&harness.ctx, table, 0, "name")
                UiTableText(&harness.ctx, table, 1, "size")
            }
        }
    }
    UiEnd(&harness.ctx)
    UiRender(&harness.ctx)
}

@(private = "file")
tableClick :: proc(harness: ^Harness, table: ^Table, at: Vec2) {
    tableFrame(harness, table, pointerAt(at))
    tableFrame(harness, table, pointerAt(at, true, true))
    tableFrame(harness, table, pointerAt(at, false, false, true))
}

@(test)
test_a_table_sorts_by_a_click_on_a_header_and_resizes_a_column_by_its_edge :: proc(t: ^testing.T) {
    harness: ^Harness = new(Harness)
    defer free(harness)
    harnessInit(harness)
    table: Table
    TableInit(&table, {{name = "Name", width = 100}, {name = "Size", width = 80}})
    for _ in 0 ..< 3 { tableFrame(harness, &table, pointerAt({-10, -10})) }
    testing.expect_value(t, harness.ctx.problems, Problems{})
    // the header is 28 high; "Size" is at x 100 .. 174
    tableClick(harness, &table, {130, 14})
    testing.expect(t, table.sort_changed && table.sort_column == 1 && !table.sort_descending, "the first click: ascending")
    tableFrame(harness, &table, pointerAt({-10, -10}))
    testing.expect(t, !table.sort_changed, "it is told once")
    tableClick(harness, &table, {130, 14})
    testing.expect(t, table.sort_column == 1 && table.sort_descending, "the second: descending")
    tableClick(harness, &table, {130, 14})
    testing.expect_value(t, table.sort_column, VIRTUAL_NONE)               // the third: back to the order of the data
    tableClick(harness, &table, {30, 14})
    testing.expect_value(t, table.sort_column, 0)
    // the edge of the first column (its last 6 pixels) is dragged 40 pixels to the right
    tableFrame(harness, &table, pointerAt({97, 14}))
    tableFrame(harness, &table, pointerAt({97, 14}, true, true))
    for i in 1 ..= 4 { tableFrame(harness, &table, pointerAt({97 + f32(i) * 10, 14}, true)) }
    tableFrame(harness, &table, pointerAt({137, 14}, false, false, true))
    testing.expect_value(t, table.columns[0].width, 140)
    testing.expect_value(t, table.columns[1].width, 80)
    // never narrower than the minimum
    tableFrame(harness, &table, pointerAt({137, 14}))
    tableFrame(harness, &table, pointerAt({137, 14}, true, true))
    for i in 1 ..= 10 { tableFrame(harness, &table, pointerAt({137 - f32(i) * 20, 14}, true)) }
    tableFrame(harness, &table, pointerAt({-63, 14}, false, false, true))
    testing.expect_value(t, table.columns[0].width, TABLE_MIN_COLUMN)
    // a row is selected by a click in the body
    tableClick(harness, &table, {50, 28 + 20 * 2 + 5})
    testing.expect_value(t, table.list.selected, 2)
    // the cells of a row are side by side: the same y, the next one a column further
    tableFrame(harness, &table, pointerAt({-10, -10}))
    labels: [4]Rect
    count: int
    for command in UiCommands(&harness.ctx) {
        if command.kind == .DRAW && command.info.kind == .LABEL && count < len(labels) {
            labels[count] = command.info.rect
            count += 1
        }
    }
    testing.expect(t, count == 4)
    testing.expect(t, abs(labels[0].y - labels[1].y) < 0.5 && labels[1].x - labels[0].x > 20, "two cells of one row: one line, one after the other")
    testing.expect(t, labels[2].y - labels[0].y > 15 && labels[2].y - labels[0].y < 25, "the next row is one row height below")
}

@(private = "file")
InspectorStorage :: Storage(512, 512, 128, 8192)

@(private = "file")
inspectorFrame :: proc(ctx: ^Context, style: ^Style, input: Input) {
    UiBegin(ctx, input, 1.0 / 60, {800, 600}, style)
    if ElementOpen(ctx, {layout = {direction = .LEFT_TO_RIGHT}}) {
        UiInspector(ctx, "Inspector", {Fixed(300), Fixed(300)})
        UiButton(ctx, "Target", {Fixed(100), Fixed(28)})
        UiLabel(ctx, "a note")
        ElementClose(ctx)
    }
    UiEnd(ctx)
    UiRender(ctx)
}

@(test)
test_the_inspector_lists_the_elements_of_the_last_frame_without_its_own_and_picks_by_the_pointer :: proc(t: ^testing.T) {
    storage: ^InspectorStorage = new(InspectorStorage)
    defer free(storage)
    ctx: ^Context = new(Context)
    defer free(ctx)
    style: Style = makeStyle()
    UiInit(ctx, storage, testMeasure)
    seen = {}
    for _ in 0 ..< 4 { inspectorFrame(ctx, &style, pointerAt({-10, -10})) }
    testing.expect_value(t, ctx.problems, Problems{})
    rows: []InspectorRow = InspectorRows(ctx)
    testing.expect(t, len(rows) > 0)
    target: int = -1
    for row, i in rows {
        testing.expect(t, row.id != UiIdPath("Inspector"), "its own elements are not in the list")
        testing.expect(t, !row.is_text, "texts are left out until asked for")
        if row.id == UiIdPath("Target") { target = i }
    }
    testing.expect(t, target >= 0, "the button is in the list")
    testing.expect_value(t, rows[target].kind, StyleKind.BUTTON)
    testing.expect_value(t, rows[target].rect, Rect{300, 0, 100, 28})
    testing.expect(t, rows[target].depth >= 1, "it is inside of the row that holds it")
    testing.expect_value(t, inspectorRowAt(ctx, {350, 14}), target)
    testing.expect_value(t, inspectorRowAt(ctx, {750, 500}), VIRTUAL_NONE)

    // picking: the pointer inside of the panel picks nothing, outside a press selects what is under it and ends the picking
    ctx.inspector.pick = true
    inspectorFrame(ctx, &style, pointerAt({100, 100}, true, true))
    testing.expect(t, ctx.inspector.pick, "a press on the panel is for the panel")
    inspectorFrame(ctx, &style, pointerAt({350, 14}))
    inspectorFrame(ctx, &style, pointerAt({350, 14}, true, true))
    testing.expect(t, !ctx.inspector.pick)
    selected: int = ctx.inspector.list.selected
    testing.expect(t, selected != VIRTUAL_NONE && InspectorRows(ctx)[selected].id == UiIdPath("Target"), "the button is selected in the tree")
    testing.expect(t, ctx.inspector.list.reveal || ctx.inspector.list.selected >= 0)
    // the texts come in when asked for
    ctx.inspector.show_text = true
    inspectorFrame(ctx, &style, pointerAt({-10, -10}))
    texts: int
    for row in InspectorRows(ctx) {
        if row.is_text { texts += 1 }
    }
    testing.expect(t, texts > 0)
    // a frame without the inspector takes no snapshot
    UiBegin(ctx, pointerAt({-10, -10}), 1.0 / 60, {800, 600}, &style)
    UiButton(ctx, "Only")
    UiEnd(ctx)
    previous: int = len(InspectorRows(ctx))
    UiBegin(ctx, pointerAt({-10, -10}), 1.0 / 60, {800, 600}, &style)
    UiButton(ctx, "Only")
    UiEnd(ctx)
    testing.expect_value(t, len(InspectorRows(ctx)), previous)
}
