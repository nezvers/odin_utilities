package demo_kit

import "core:fmt"

// Runs the demos of a library on a backend: one demo at a time, a menu on the right to switch (mouse, or PAGE_UP / PAGE_DOWN), and a
// test mode that plays the script of every demo with simulated input.
//
//     // demo_raylib/main.odin and demo_karl2d/main.odin are one line each
//     kit_raylib.Run("tween", demo_common.demos[:])
//
// A demo is plain procs over globals of its file, like the demos before it:
//
//     demo: kit.Demo = {name = "loop", init = init, update = update, draw = draw, script = script}

Demo :: struct {
    name: string,
    init: proc(ctx: ^Context),
    finit: proc(ctx: ^Context),
    update: proc(ctx: ^Context),
    draw: proc(ctx: ^Context),
    script: []Step,             // what a test plays into the input, and the checks that say it is right
}

MENU_WIDTH :: 170
MENU_BUTTON_HEIGHT :: 24
MENU_MARGIN :: 8
SMOKE_TEST_FRAMES :: 60         // a demo without a script is run this long, to see that it starts, updates and draws

Runner :: struct {
    demos: []Demo,
    backend: ^Backend,
    ctx: Context,
    current: int,
    started: bool,              // the current demo got its init
    player: Player,
    playing: bool,              // the input comes from the player
    fixed_delta: f32,           // 0: the time the backend measures. A test uses 1/60
    show_menu: bool,
    run_time: f64,
    escape_exits: bool,         // escape closes a demo in a window
}

// `demos` has to live as long as the runner. With playing = false the devices drive the demo.
RunnerInit :: proc(runner: ^Runner, demos: []Demo, backend: ^Backend, first: int = 0) {
    runner^ = {demos = demos, backend = backend, current = first, show_menu = len(demos) > 1, escape_exits = true}
    runner.ctx.backend = backend
}

// One frame. False when the window was closed (or escape was pressed in a window).
RunnerStep :: proc(runner: ^Runner) -> bool {
    backend: ^Backend = runner.backend
    ctx: ^Context = &runner.ctx

    running, delta_time := backend.begin_frame(backend, &ctx.input)
    if !running { return false }
    if runner.escape_exits && !backend.headless && KeyPressed(&ctx.input, .ESCAPE) { return false }
    if runner.fixed_delta > 0 { delta_time = runner.fixed_delta }
    ctx.delta_time = delta_time
    runner.run_time += f64(delta_time)
    ctx.time = runner.run_time
    ctx.screen = backend.screen_size(backend)
    if runner.playing { PlayerFrame(&runner.player, ctx, &ctx.input) }

    // the menu is checked first: a click on it is not for the demo
    ctx.ui_hover = runner.show_menu && !runner.playing && menuHover(runner)
    if runner.show_menu && !runner.playing { runnerMenuInput(runner) }
    if !runner.started { runnerStartDemo(runner) }
    demo: ^Demo = &runner.demos[runner.current]

    if demo.update != nil { demo.update(ctx) }

    backend.clear(backend, ctx.background)
    if demo.draw != nil { demo.draw(ctx) }
    if runner.show_menu { runnerMenuDraw(runner) }
    if runner.playing && runner.player.capture_name != "" { runnerCapture(runner) }
    backend.end_frame(backend)
    backend.stats.frames += 1
    ctx.frame += 1
    return true
}

// Switch demos: the old one gets its finit, the new one its init at the next frame
RunnerSelect :: proc(runner: ^Runner, index: int) {
    if index < 0 || index >= len(runner.demos) || index == runner.current && runner.started { return }
    runnerFinishDemo(runner)
    runner.current = index
}

RunnerShutdown :: proc(runner: ^Runner) {
    runnerFinishDemo(runner)
    if runner.backend.shutdown != nil { runner.backend.shutdown(runner.backend) }
}

// Run until the window is closed
Run :: proc(runner: ^Runner, demos: []Demo, backend: ^Backend) {
    RunnerInit(runner, demos, backend)
    for RunnerStep(runner) {
        free_all(context.temp_allocator)
    }
    RunnerShutdown(runner)
}

// ------------------------------------------------------------------------------------------------------------------------
// Tests: the scripts of the demos, played with simulated input

// Play the script of one demo from its init to its end. A demo without a script runs SMOKE_TEST_FRAMES frames. The backend can be
// a window (you watch it) or headless. `max_frames` stops a script that never ends.
TestDemo :: proc(demo: Demo, backend: ^Backend, max_frames: int = 36000) -> Report {
    demos: [1]Demo = {demo}
    runner: Runner
    RunnerInit(&runner, demos[:], backend)
    runner.show_menu = false
    runner.fixed_delta = 1.0 / 60.0
    runner.playing = true
    PlayerStart(&runner.player, demo.script)

    frames: int = 0
    limit: int = max_frames if len(demo.script) > 0 else SMOKE_TEST_FRAMES
    for frames < limit {
        if len(demo.script) > 0 && PlayerFinished(&runner.player) && frames > 0 { break }
        if !RunnerStep(&runner) { break }
        frames += 1
    }
    // the checks that were left for the last frame
    if len(demo.script) > 0 && PlayerFinished(&runner.player) {
        runner.ctx.frame = frames
        PlayerFrame(&runner.player, &runner.ctx, &runner.ctx.input)
    }
    report: Report = runner.player.report
    report.finished = len(demo.script) == 0 || PlayerFinished(&runner.player)
    report.frames = frames
    report.draw_calls = backend.stats.draw_calls
    runnerFinishDemo(&runner)
    return report
}

// Every demo of a library, one after the other. The sum of the reports, and the first failures with the frame of their demo
TestAll :: proc(demos: []Demo, backend: ^Backend, max_frames: int = 36000) -> (total: Report) {
    total.finished = true
    for demo in demos {
        report: Report = TestDemo(demo, backend, max_frames)
        for failure in report.failures[:min(report.failed, MAX_FAILURES)] {
            if total.failed < MAX_FAILURES { total.failures[total.failed] = failure }
            total.failed += 1
        }
        total.failed += max(0, report.failed - MAX_FAILURES)
        total.checks += report.checks
        total.frames += report.frames
        total.draw_calls = report.draw_calls
        total.finished &&= report.finished
    }
    return
}

// ------------------------------------------------------------------------------------------------------------------------

// The pixels of the frame against the golden image; a difference is a failure of the script like a failed check
@(private)
runnerCapture :: proc(runner: ^Runner) {
    player: ^Player = &runner.player
    result, message := CaptureCompare(&runner.ctx, player.capture_file, player.capture_name)
    #partial switch result {
    case .SKIPPED: player.report.captures_skipped += 1
    case .WRITTEN:
        player.report.captures += 1
        player.report.captures_written += 1
    case .MATCH: player.report.captures += 1
    case:
        player.report.captures += 1
        if player.report.failed < MAX_FAILURES {
            player.report.failures[player.report.failed] = {message = message, frame = runner.ctx.frame}
        }
        player.report.failed += 1
    }
}

@(private)
runnerStartDemo :: proc(runner: ^Runner) {
    runner.started = true
    runner.ctx.frame = 0
    runner.ctx.background = RAY_WHITE
    demo: ^Demo = &runner.demos[runner.current]
    if demo.init != nil { demo.init(&runner.ctx) }
}

@(private)
runnerFinishDemo :: proc(runner: ^Runner) {
    if !runner.started { return }
    runner.started = false
    demo: ^Demo = &runner.demos[runner.current]
    if demo.finit != nil { demo.finit(&runner.ctx) }
}

@(private)
menuRect :: proc(runner: ^Runner, index: int) -> Rect {
    return {runner.ctx.screen.x - MENU_WIDTH - MENU_MARGIN, MENU_MARGIN + f32(index) * (MENU_BUTTON_HEIGHT + 2), MENU_WIDTH, MENU_BUTTON_HEIGHT}
}

@(private)
menuHover :: proc(runner: ^Runner) -> bool {
    for i in 0 ..< len(runner.demos) {
        if PointInRect(runner.ctx.input.mouse_position, menuRect(runner, i)) { return true }
    }
    return false
}

@(private)
runnerMenuInput :: proc(runner: ^Runner) {
    input: ^Input = &runner.ctx.input
    if KeyPressed(input, .PAGE_DOWN) { RunnerSelect(runner, (runner.current + 1) % len(runner.demos)) }
    if KeyPressed(input, .PAGE_UP) { RunnerSelect(runner, (runner.current + len(runner.demos) - 1) % len(runner.demos)) }
    if !MousePressed(input) { return }
    for i in 0 ..< len(runner.demos) {
        if PointInRect(input.mouse_position, menuRect(runner, i)) { RunnerSelect(runner, i) }
    }
}

@(private)
runnerMenuDraw :: proc(runner: ^Runner) {
    ctx: ^Context = &runner.ctx
    for demo, i in runner.demos {
        rect: Rect = menuRect(runner, i)
        DrawRect(ctx, rect, DARK_GRAY if i == runner.current else LIGHT_GRAY)
        DrawText(ctx, demo.name, {rect.x + 6, rect.y + 4}, 16, WHITE if i == runner.current else BLACK)
    }
}

// ------------------------------------------------------------------------------------------------------------------------

// `-define:DEMO_TEST=true` on a demo executable: instead of waiting for you it plays the scripts of its demos with simulated input
// in the window (so you see them), prints the report and exits with 1 when a check failed
DEMO_TEST :: #config(DEMO_TEST, false)

// Play the scripts of every demo on this backend and print what happened. Returns true when everything passed.
RunTests :: proc(demos: []Demo, backend: ^Backend) -> bool {
    all_passed: bool = true
    for demo in demos {
        report: Report = TestDemo(demo, backend)
        PrintReport(demo.name, report)
        if report.failed > 0 || !report.finished { all_passed = false }
    }
    return all_passed
}

PrintReport :: proc(name: string, report: Report) {
    report := report
    fmt.printfln("[DEMO TEST] %s: %d checks, %d failed, %d frames, %d draw calls%s", name, report.checks, report.failed, report.frames, report.draw_calls, "" if report.finished else ", the script did NOT finish")
    if report.captures + report.captures_skipped > 0 {
        fmt.printfln("[DEMO TEST]   captures: %d compared (%d new golden images), %d skipped", report.captures, report.captures_written, report.captures_skipped)
    }
    for failure in report.failures[:min(report.failed, MAX_FAILURES)] {
        fmt.printfln("[DEMO TEST]   failed on frame %d: %s", failure.frame, failure.message)
    }
}
