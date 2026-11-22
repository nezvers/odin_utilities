#+build !js
// Tests of the kit: the input player, the headless backend and the test runner, on a small demo of their own.
package demo_kit

import "core:os"
import "core:slice"
import "core:sync"
import "core:strings"
import "core:testing"
import "core:time"

@(private="file")
Toy :: struct {
    taps: int,
    held_frames: int,
    clicks: int,
    last_click: Vec2,
    wheel: f32,
    typed: [32]u8,
    typed_count: int,
    started: int,
    stopped: int,
    updates: int,
    texture: Texture,
}
@(private="file")
toy: Toy
// The tests that use the toy take this: the test runner runs tests on several threads, and they would count in the same toy
toy_lock: sync.Mutex

@(private="file")
toy_init :: proc(ctx: ^Context) {
    toy = {}
    toy.started = 1
}

@(private="file")
toy_update :: proc(ctx: ^Context) {
    toy.updates += 1
    if KeyPressed(&ctx.input, .SPACE) { toy.taps += 1 }
    if KeyDown(&ctx.input, .D) { toy.held_frames += 1 }
    if MousePressed(&ctx.input) {
        toy.clicks += 1
        toy.last_click = ctx.input.mouse_position
    }
    toy.wheel += ctx.input.mouse_wheel
    for character in InputText(&ctx.input) {
        if toy.typed_count < len(toy.typed) {
            toy.typed[toy.typed_count] = u8(character)
            toy.typed_count += 1
        }
    }
}

@(private="file")
toy_draw :: proc(ctx: ^Context) {
    DrawRect(ctx, {10, 10, 50, 50}, RED)
    DrawText(ctx, "toy", {20, 20}, 16, BLACK)
}

@(private="file")
toy_finit :: proc(ctx: ^Context) {
    toy.stopped += 1
}

@(private="file")
toy_script: []Step = {
    Wait(3),
    Check(proc(ctx: ^Context) -> bool { return toy.updates >= 3 && toy.taps == 0 }, "nothing pressed yet"),
    Tap(.SPACE),
    Tap(.SPACE),
    Check(proc(ctx: ^Context) -> bool { return toy.taps == 2 }, "two taps are two presses, not one held key"),
    Hold(.D, 10),
    Check(proc(ctx: ^Context) -> bool { return toy.held_frames == 10 }, "held for 10 frames"),
    Click({400, 300}),
    Check(proc(ctx: ^Context) -> bool { return toy.clicks == 1 && toy.last_click == Vec2{400, 300} }, "one click at the point"),
    Scroll(2),
    Scroll(-0.5),
    Type("hi"),
    Wait(1),
    Check(proc(ctx: ^Context) -> bool { return toy.wheel == 1.5 && string(toy.typed[:toy.typed_count]) == "hi" }, "wheel and text"),
    Drag({100, 100}, {200, 100}, 10),
    Check(proc(ctx: ^Context) -> bool { return toy.clicks == 2 }, "a drag starts with a press"),
}

@(private="file")
toy_demo :: proc() -> Demo {
    return {name = "toy", init = toy_init, finit = toy_finit, update = toy_update, draw = toy_draw, script = toy_script}
}

@(test)
test_a_script_plays_into_the_input_and_checks_pass :: proc(t: ^testing.T) {
    sync.mutex_guard(&toy_lock)
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    report: Report = TestDemo(toy_demo(), &backend)
    for failure in report.failures[:min(report.failed, MAX_FAILURES)] {
        testing.expectf(t, false, "check failed on frame %d: %s", failure.frame, failure.message)
    }
    testing.expect_value(t, report.failed, 0)
    testing.expect_value(t, report.checks, 6)
    testing.expect(t, report.finished)
    testing.expect(t, report.draw_calls >= report.frames * 2, "a frame drew the rectangle and the text")
    testing.expect_value(t, toy.started, 1)
    testing.expect_value(t, toy.stopped, 1)
}

@(test)
test_a_failing_check_is_reported_with_its_message :: proc(t: ^testing.T) {
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    script: []Step = {
        Wait(2),
        Check(proc(ctx: ^Context) -> bool { return false }, "this one is wrong"),
        Check(proc(ctx: ^Context) -> bool { return true }, "this one is right"),
    }
    report: Report = TestDemo({name = "x", script = script}, &backend)
    testing.expect_value(t, report.checks, 2)
    testing.expect_value(t, report.failed, 1)
    testing.expect_value(t, report.failures[0].message, "this one is wrong")
}

@(test)
test_a_demo_without_a_script_is_a_smoke_test :: proc(t: ^testing.T) {
    sync.mutex_guard(&toy_lock)
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    toy = {}
    report: Report = TestDemo({name = "smoke", update = toy_update, draw = toy_draw}, &backend)
    testing.expect_value(t, report.frames, SMOKE_TEST_FRAMES)
    testing.expect_value(t, toy.updates, SMOKE_TEST_FRAMES)
}

@(test)
test_a_script_that_never_ends_is_stopped :: proc(t: ^testing.T) {
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    report: Report = TestDemo({name = "long", script = {Wait(1000)}}, &backend, 20)
    testing.expect(t, !report.finished)
    testing.expect_value(t, report.frames, 20)
}

@(test)
test_the_menu_switches_demos_by_click :: proc(t: ^testing.T) {
    sync.mutex_guard(&toy_lock)
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    toy = {}
    demos: [2]Demo = {{name = "first", init = toy_init, finit = toy_finit}, {name = "second", update = toy_update}}
    runner: Runner
    RunnerInit(&runner, demos[:], &backend)
    runner.fixed_delta = 1.0 / 60.0
    testing.expect(t, runner.show_menu)
    RunnerStep(&runner)
    testing.expect_value(t, toy.started, 1)
    RunnerSelect(&runner, 1)
    testing.expect_value(t, toy.stopped, 1)
    RunnerStep(&runner)
    testing.expect_value(t, runner.current, 1)
    testing.expect_value(t, toy.updates, 1)
    RunnerShutdown(&runner)
}

@(test)
test_the_menu_is_a_dropdown_that_opens_selects_and_closes :: proc(t: ^testing.T) {
    sync.mutex_guard(&toy_lock)
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    toy = {}
    demos: [3]Demo = {{name = "first"}, {name = "second"}, {name = "third"}}
    runner: Runner
    RunnerInit(&runner, demos[:], &backend)
    runner.fixed_delta = 1.0 / 60.0
    RunnerStep(&runner)
    click :: proc(runner: ^Runner, rect: Rect) {
        runner.ctx.input.mouse_position = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
        runner.ctx.input.mouse_pressed = {.LEFT}
        runnerMenuInput(runner)
        runner.ctx.input.mouse_pressed = {}
    }
    testing.expect(t, !runner.menu_open, "closed: one box")
    runner.ctx.input.mouse_position = {runner.ctx.screen.x - 20, 20}
    testing.expect(t, menuHover(&runner), "the box takes the pointer")
    runner.ctx.input.mouse_position = {runner.ctx.screen.x - 20, 20 + 2 * (MENU_BUTTON_HEIGHT + 2)}
    testing.expect(t, !menuHover(&runner), "the rows are not there while it is closed")
    click(&runner, menuRect(&runner, -1))
    testing.expect(t, runner.menu_open)
    testing.expect(t, menuHover(&runner), "the open list takes the pointer")
    click(&runner, menuRect(&runner, 2))
    testing.expect(t, !runner.menu_open, "a choice closes the list")
    testing.expect_value(t, runner.current, 2)
    click(&runner, menuRect(&runner, -1))
    click(&runner, {10, 400, 10, 10})
    testing.expect(t, !runner.menu_open, "a click elsewhere closes it")
    testing.expect_value(t, runner.current, 2)
    RunnerShutdown(&runner)
}

@(test)
test_headless_backend_measures_text_and_reads_png_sizes :: proc(t: ^testing.T) {
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    ctx: Context = {backend = &backend}
    testing.expect_value(t, MeasureText(&ctx, "abcd", 10), Vec2{20, 10})
    png_header: [24]u8 = {0x89, 'P', 'N', 'G', 13, 10, 26, 10, 0, 0, 0, 13, 'I', 'H', 'D', 'R', 0, 0, 1, 0, 0, 0, 0, 128}
    texture: Texture = TextureLoad(&ctx, png_header[:])
    testing.expect_value(t, TextureSize(&ctx, texture), Vec2{256, 128})
    testing.expect_value(t, TextureSize(&ctx, TEXTURE_NONE), Vec2{})
}

@(test)
test_axis_keys_and_camera_helpers :: proc(t: ^testing.T) {
    input: Input = {keys_down = {.D}}
    testing.expect_value(t, AxisKeys(&input, .A, .D), 1)
    input.keys_down = {.A, .D}
    testing.expect_value(t, AxisKeys(&input, .A, .D), 0)
    camera: Camera = {target = {100, 100}, offset = {400, 300}, zoom = 2}
    testing.expect_value(t, CameraScreenToWorld(camera, {400, 300}), Vec2{100, 100})
    testing.expect_value(t, CameraWorldToScreen(camera, {110, 100}), Vec2{420, 300})
}

@(test)
test_png_round_trip_and_image_difference :: proc(t: ^testing.T) {
    width, height: int = 37, 5
    pixels: []u8 = make([]u8, width * height * 4)
    defer delete(pixels)
    for i in 0 ..< len(pixels) { pixels[i] = u8(i * 7) }
    path: string = "demo_kit_test_round_trip.png"
    defer os.remove(path)
    testing.expect(t, PngWrite(path, width, height, pixels))
    back, back_width, back_height, ok := PngRead(path)
    defer delete(back)
    testing.expect(t, ok)
    testing.expect_value(t, back_width, width)
    testing.expect_value(t, back_height, height)
    testing.expect(t, ok && slice.equal(back, pixels), "the pixels come back as they went in")

    other: []u8 = make([]u8, len(pixels))
    defer delete(other)
    copy(other, pixels)
    different, biggest := ImageDifference(pixels, other)
    testing.expect_value(t, different, 0)
    other[0] += 3                                   // under the tolerance
    other[8] += 100                                 // a pixel that differs
    different, biggest = ImageDifference(pixels, other)
    testing.expect_value(t, different, 1)
    testing.expect_value(t, biggest, 100)
}

@(test)
test_capture_is_skipped_on_the_headless_backend :: proc(t: ^testing.T) {
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    ctx: Context = {backend = &backend}
    _, _, _, ok := CaptureFrame(&ctx)
    testing.expect(t, !ok)
}

@(test)
test_a_display_is_found_by_a_part_of_its_name_without_regard_to_case :: proc(t: ^testing.T) {
    testing.expect(t, DisplayMatches("BenQ DL2215", "dl22"))
    testing.expect(t, DisplayMatches("BenQ DL2215", "BENQ"))
    testing.expect(t, DisplayMatches("LU28R55", "lu28r55"))
    testing.expect(t, !DisplayMatches("LU28R55", "benq"))
    testing.expect(t, DisplayMatches("anything", ""), "an empty request matches")
}

@(test)
test_the_rectangle_of_a_display_comes_from_the_environment :: proc(t: ^testing.T) {
    os.set_env(DISPLAY_RECT_ENV, "3840,1065,1920,1080")
    rect, ok := DisplayRect()
    testing.expect(t, ok)
    testing.expect_value(t, rect, [4]int{3840, 1065, 1920, 1080})
    os.set_env(DISPLAY_RECT_ENV, "3840, 1065, 1920")
    _, ok = DisplayRect()
    testing.expect(t, !ok, "three numbers are not a rectangle")
    os.set_env(DISPLAY_RECT_ENV, "a,b,c,d")
    _, ok = DisplayRect()
    testing.expect(t, !ok)
    os.unset_env(DISPLAY_RECT_ENV)
    _, ok = DisplayRect()
    testing.expect(t, !ok)
}

@(test)
test_a_mask_keeps_the_pixels_inside_of_the_frames_and_clears_the_rest :: proc(t: ^testing.T) {
    width, height: int = 8, 6
    picture: []u8 = make([]u8, width * height * 4)
    defer delete(picture)
    for i in 0 ..< len(picture) { picture[i] = u8(1 + i % 200) }
    frames: [2]Rect = {{1, 1, 2, 2}, {6.5, 4.2, 10, 10}}                  // the second one reaches past the picture and starts between pixels
    masked: []u8 = CaptureMask(picture, width, height, frames[:])
    defer delete(masked)
    inside :: proc(x: int, y: int) -> bool {
        return (x >= 1 && x < 3 && y >= 1 && y < 3) || (x >= 6 && x < 8 && y >= 4 && y < 6)
    }
    for y in 0 ..< height {
        for x in 0 ..< width {
            at: int = (y * width + x) * 4
            same: bool = masked[at] == picture[at] && masked[at + 3] == picture[at + 3]
            cleared: bool = masked[at] == 0 && masked[at + 1] == 0 && masked[at + 2] == 0 && masked[at + 3] == 0
            testing.expectf(t, same if inside(x, y) else cleared, "pixel %d, %d", x, y)
        }
    }
    // a pixel that differs outside of the frames does not count, one inside does, however small the part of the picture
    changed: []u8 = make([]u8, len(picture))
    defer delete(changed)
    copy(changed, picture)
    changed[(0 * width + 0) * 4] += 100
    other: []u8 = CaptureMask(changed, width, height, frames[:])
    defer delete(other)
    different, _ := ImageDifference(masked, other)
    testing.expect_value(t, different, 0)
    changed[(1 * width + 1) * 4] += 100
    other = CaptureMask(changed, width, height, frames[:])
    different, _ = ImageDifference(masked, other)
    testing.expect_value(t, different, 1)
    // the step takes at most CAPTURE_FRAMES of them
    step: Step = CaptureIn("x", {{0, 0, 1, 1}, {1, 1, 1, 1}, {2, 2, 1, 1}, {3, 3, 1, 1}, {4, 4, 1, 1}})
    testing.expect_value(t, step.mask_count, CAPTURE_FRAMES)
}

@(test)
test_the_log_of_a_run_has_the_steps_the_input_and_the_reactions_with_their_timing :: proc(t: ^testing.T) {
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    target: Vec2 = {50, 60}
    script: []Step = {
        Wait(2),
        MoveTo({10, 20}),
        ClickAt(&target),
        Wait(3),
        Check(proc(ctx: ^Context) -> bool { return true }, "the click happened"),
        Check(proc(ctx: ^Context) -> bool { return false }, "this one fails"),
        Tap(.SPACE),
        Type("ab"),
        Wait(1),
    }
    demo: Demo = {name = "logged", script = script, draw = proc(ctx: ^Context) { LogNote(ctx, "drew frame %d", ctx.frame) }}
    lines: [dynamic]u8
    defer delete(lines)
    log: Log
    LogToBuffer(&log, &lines, LOG_ALL_KINDS)
    report: Report = TestDemo(demo, &backend, log = &log)
    text: string = string(lines[:])
    testing.expect_value(t, report.failed, 1)
    contains :: proc(t: ^testing.T, text: string, part: string) {
        testing.expectf(t, strings.contains(text, part), "the log has %q", part)
    }
    contains(t, text, "demo \"logged\" starts: 9 steps")
    contains(t, text, "INPUT     step 1 MOUSE_MOVE to (10.0, 20.0)")
    contains(t, text, "step 2 MOUSE_CLICK LEFT at (50.0, 60.0)")      // the target is read when the step runs
    contains(t, text, "mouse -> (50.0, 60.0)")
    contains(t, text, "LEFT down")
    contains(t, text, "LEFT up")
    contains(t, text, "REACTION  check PASS \"the click happened\"")
    contains(t, text, "REACTION  check FAIL \"this one fails\"")
    contains(t, text, "frames, ")                                      // the distance from the last input, in frames and in seconds
    contains(t, text, "key SPACE down")
    contains(t, text, "text \"ab\"")
    contains(t, text, "drew frame 0")                                  // a note of the demo
    contains(t, text, "FRAME     drew ")
    contains(t, text, "demo \"logged\" ends: 2 checks, 1 failed")
    // only the trace of the simulator: no reactions, no frames
    clear(&lines)
    LogToBuffer(&log, &lines, {.INPUT})
    TestDemo(demo, &backend, log = &log)
    text = string(lines[:])
    contains(t, text, "MOUSE_CLICK")
    testing.expect(t, !strings.contains(text, "REACTION") && !strings.contains(text, "FRAME  "), "input only")
    // the time of the lines is the simulated one: the same on every run
    first_run: string = strings.clone(text)
    defer delete(first_run)
    clear(&lines)
    LogToBuffer(&log, &lines, {.INPUT})
    TestDemo(demo, &backend, log = &log)
    testing.expect_value(t, string(lines[:]), first_run)
    // the kinds are read from a text
    testing.expect_value(t, LogKindsParse("input, Reaction"), LogKinds{.INPUT, .REACTION})
    testing.expect_value(t, LogKindsParse("all"), LOG_ALL_KINDS)
    testing.expect_value(t, LogKindsParse("nothing"), LogKinds{})
}

@(test)
test_the_log_goes_to_a_file_with_the_wall_clock_in_every_line :: proc(t: ^testing.T) {
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    path: string = "demo_kit_log_test.log"
    defer os.remove(path)
    log: Log
    testing.expect(t, LogOpen(&log, path, {.INPUT, .REACTION}))
    script: []Step = {MoveTo({1, 2}), Wait(1), Check(proc(ctx: ^Context) -> bool { return true }, "fine")}
    TestDemo({name = "to file", script = script}, &backend, log = &log)
    LogClose(&log)
    data, err := os.read_entire_file(path, context.temp_allocator)
    testing.expect(t, err == nil)
    text: string = string(data)
    testing.expect(t, strings.contains(text, " ms]  INPUT") && strings.contains(text, "+"), "the wall clock is in the bracket")
    testing.expect(t, strings.contains(text, "check PASS \"fine\""))
    testing.expect(t, !LogOpen(&log, "no_such_folder_for_the_log/x.log"), "a file that cannot be made is refused")
}

// ---- the text field and the clipboard ----------------------------------------------------------------------------------------------------------------------

@(private = "file")
Field :: struct {
    buffer: [32]u8,
    length: int,
    focused: bool,
    submitted: int,
}
@(private = "file")
field: Field
field_lock: sync.Mutex

@(private = "file")
field_script: []Step = {
    Wait(2),
    Type("ab"),                                         // not focused yet: nothing is typed into the field
    Wait(2),
    Check(proc(ctx: ^Context) -> bool { return field.length == 0 && !field.focused }, "a field that is not focused takes no text"),
    Click({100, 34}),
    Type("hello"),
    Wait(2),
    Check(proc(ctx: ^Context) -> bool { return field.focused && string(field.buffer[:field.length]) == "hello" }, "a click focuses it and typing adds the letters"),
    Tap(.BACKSPACE),
    Wait(2),
    Check(proc(ctx: ^Context) -> bool { return string(field.buffer[:field.length]) == "hell" }, "backspace removes the last one"),
    Check(proc(ctx: ^Context) -> bool { ClipboardSet(ctx, "XY\nsecond line"); return true }, "the clipboard takes text"),
    KeyDownStep(.LEFT_CTRL),
    Tap(.V),
    KeyUpStep(.LEFT_CTRL),
    Wait(2),
    Check(proc(ctx: ^Context) -> bool { return string(field.buffer[:field.length]) == "hellXY" }, "ctrl+v pastes the first line of the clipboard"),
    Tap(.ENTER),
    Wait(2),
    Check(proc(ctx: ^Context) -> bool { return field.submitted == 1 }, "enter submits"),
    Click({600, 300}),
    Wait(2),
    Check(proc(ctx: ^Context) -> bool { return !field.focused }, "a click elsewhere takes the focus away"),
}

@(private = "file")
field_demo: Demo = {
    name = "field",
    init = proc(ctx: ^Context) { field = {} },
    draw = proc(ctx: ^Context) {
        if TextField(ctx, {20, 20, 200, 28}, field.buffer[:], &field.length, &field.focused, "name") { field.submitted += 1 }
    },
    script = field_script,
}

@(test)
test_a_text_field_takes_typing_and_pastes :: proc(t: ^testing.T) {
    sync.mutex_lock(&field_lock)
    defer sync.mutex_unlock(&field_lock)
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    report: Report = TestDemo(field_demo, &backend)
    for failure in report.failures[:min(report.failed, MAX_FAILURES)] {
        testing.expectf(t, false, "frame %d: %s", failure.frame, failure.message)
    }
    testing.expect(t, report.finished)
}

@(test)
test_a_held_key_repeats_after_a_delay_like_a_keyboard :: proc(t: ^testing.T) {
    state: KeyRepeatState
    input: Input
    dt: f32 = 1.0 / 60.0
    repeats: int
    first_repeat_at: f32 = -1
    elapsed: f32
    // frame 0: the key goes down
    input.keys_down, input.keys_pressed = {.BACKSPACE}, {.BACKSPACE}
    InputRepeat(&input, &state, dt)
    testing.expect(t, .BACKSPACE in input.keys_repeat, "the press counts")
    // held for 2 seconds
    input.keys_pressed = {}
    for _ in 0 ..< 120 {
        elapsed += dt
        InputRepeat(&input, &state, dt)
        if .BACKSPACE in input.keys_repeat {
            repeats += 1
            if first_repeat_at < 0 { first_repeat_at = elapsed }
        }
    }
    testing.expect(t, first_repeat_at >= KEY_REPEAT_DELAY - dt && first_repeat_at <= KEY_REPEAT_DELAY + 2 * dt, "nothing before the delay, then the first repeat")
    // (2 - 0.4) s at 25 a second: about 40, the frames are 1/60 so the rate is a little under
    testing.expect(t, repeats >= 30 && repeats <= 42, "the repeats come at the rate of a keyboard")
    // letting go stops it and the next press starts the delay again
    input.keys_down = {}
    InputRepeat(&input, &state, dt)
    testing.expect(t, input.keys_repeat == {}, "no repeat after release")
    input.keys_down, input.keys_pressed = {.BACKSPACE}, {.BACKSPACE}
    InputRepeat(&input, &state, dt)
    input.keys_pressed = {}
    for _ in 0 ..< 20 { InputRepeat(&input, &state, dt) }             // 0.33 s
    testing.expect(t, .BACKSPACE not_in input.keys_repeat, "a new press waits for the delay again")
}

@(test)
test_keys_repeat_on_their_own_and_a_long_frame_does_not_burst :: proc(t: ^testing.T) {
    state: KeyRepeatState
    input: Input
    input.keys_down, input.keys_pressed = {.LEFT, .A}, {.LEFT, .A}
    InputRepeat(&input, &state, 0.016)
    input.keys_pressed = {}
    // A is let go, LEFT goes on: separate timers
    input.keys_down = {.LEFT}
    InputRepeat(&input, &state, 0.5)                                   // one frame of half a second (the window was dragged)
    testing.expect(t, .LEFT in input.keys_repeat, "it repeats after the delay")
    testing.expect(t, .A not_in input.keys_repeat, "the key that was let go does not")
    InputRepeat(&input, &state, 0.016)
    testing.expect(t, .LEFT not_in input.keys_repeat, "and the next frame is not another repeat: one repeat per frame at most, no burst")
    // the game's own sets are not changed by the repeat
    input.keys_pressed = {}
    testing.expect(t, KeyRepeated(&input, .LEFT) == (.LEFT in input.keys_repeat))
}

@(private = "file")
until_frame: int                  // the frame of the last step that noted it (a test reads it)

@(test)
test_wait_until_goes_on_when_the_condition_is_true_and_reports_when_it_is_not :: proc(t: ^testing.T) {
    sync.mutex_guard(&toy_lock)
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    toy = {}
    script: []Step = {
        Wait(2),
        // true after 40 updates: the script waits for it, however long that takes in frames
        WaitUntil(proc(ctx: ^Context) -> bool { return toy.updates >= 40 }, "forty updates came", 500),
        Check(proc(ctx: ^Context) -> bool { until_frame = ctx.frame; return toy.updates >= 40 }, "and the script went on after it"),
        // already true: no frame is spent on it (the next check is in the same frame)
        WaitUntil(proc(ctx: ^Context) -> bool { return true }, "true already", 500),
        Check(proc(ctx: ^Context) -> bool { return ctx.frame == until_frame }, "no frame was used"),
        // never true: the report says what was waited for, after the frames it was given, and the script goes on
        WaitUntil(proc(ctx: ^Context) -> bool { return false }, "this never happens", 30),
        Check(proc(ctx: ^Context) -> bool { return ctx.frame >= until_frame + 30 }, "it waited the frames it was given"),
        Check(proc(ctx: ^Context) -> bool { return true }, "the script went on after the timeout"),
    }
    report: Report = TestDemo({name = "until", init = toy_init, update = toy_update, draw = toy_draw, script = script}, &backend)
    testing.expect_value(t, report.failed, 1)
    testing.expect_value(t, report.failures[0].message, "this never happens")
    testing.expect_value(t, report.checks, 7)                 // every step that decides counts: 4 checks and the 3 waits for a condition
    testing.expect(t, report.finished)
}

// The thing waited for happens on another clock than the frames: a thread that sets a flag after some real time. A fixed Wait is right or wrong by luck, WaitUntil is right.
@(private = "file", thread_local)
other_clock_done: bool

@(test)
test_wait_until_waits_for_something_that_happens_on_another_clock :: proc(t: ^testing.T) {
    sync.mutex_guard(&toy_lock)
    state: HeadlessState
    backend: Backend
    HeadlessInit(&backend, &state)
    toy = {}
    other_clock_done = false
    start: time.Tick = time.tick_now()
    script: []Step = {
        // the "server": ready 150 ms of real time after the first frame (each frame of the toy is fast, so this is many frames or few depending on the computer)
        WaitUntil(proc(ctx: ^Context) -> bool {
            @(static) started: time.Tick
            if started == {} { started = time.tick_now() }
            time.sleep(time.Millisecond)                            // a frame that takes real time, as a demo that talks to a network does
            return time.duration_milliseconds(time.tick_since(started)) >= 150
        }, "the other clock ran out", 100000),
        Check(proc(ctx: ^Context) -> bool { return true }, "and the script went on"),
    }
    report: Report = TestDemo({name = "clock", init = toy_init, update = toy_update, draw = toy_draw, script = script}, &backend)
    testing.expect_value(t, report.failed, 0)
    testing.expect(t, report.finished)
    testing.expect(t, time.duration_milliseconds(time.tick_since(start)) >= 150, "it really waited for the real time")
}
