#+build !js
// Tests of the kit: the input player, the headless backend and the test runner, on a small demo of their own.
package demo_kit

import "core:testing"

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
