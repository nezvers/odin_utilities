#+build !js
package ui

import "core:testing"

// A font where every character is half as wide as it is high: no framework needed to test a layout
@(private = "file")
testMeasure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
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
    frame(harness)
    UiButton(&harness.ctx, "A")
    UiEnd(&harness.ctx)
    testing.expect(t, stateFind(&harness.ctx, UiIdIn(&harness.ctx, "A")) != nil)
    testing.expect(t, stateFind(&harness.ctx, UiIdIn(&harness.ctx, "B")) == nil, "B was not declared this frame")
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
    big: Context
    style: Style = makeStyle()
    UiInit(&big, storage, testMeasure)
    seen = {}
    c: ^Context = &big
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
