package demo_kit

// A log of a test run: what the input simulator did, what the demo did in reaction, and when. The scripts of the demos (sim.odin) play it, a failed check says "frame 140: the switch did
// not turn the page light" and nothing more; with the log on you read the whole run, one line for each event:
//
//   [frame    12  t=  0.2000s  +   31.2 ms]  INPUT     step 7 MOUSE_CLICK LEFT at (78.0, 104.0)
//   [frame    12  t=  0.2000s  +   31.3 ms]  INPUT     mouse -> (78.0, 104.0)
//   [frame    12  t=  0.2000s  +   31.3 ms]  INPUT     LEFT down
//   [frame    13  t=  0.2167s  +   33.0 ms]  INPUT     LEFT up
//   [frame    15  t=  0.2500s  +   35.8 ms]  REACTION  check PASS "a click on the title selected the node" (3 frames after the last input)
//
// `frame` and `t` are the simulated frame and time (the same on every run); `+ ms` is the wall clock since the log was opened (what the run really took: added by the file sink, so a log
// of a run in a browser has none). Three kinds of lines, chosen separately:
//   INPUT      the steps of the script as they start, and the input that came of them (a position, a button, a key, a character, the wheel) when it changes
//   REACTION   the checks and the captures with their result, how many frames after the last input they were made, and the notes that a demo writes with `LogNote`
//   FRAME      one line for every frame: the draw calls it made
//
// Turning it on, without a change of code:
//   DEMO_LOG=stdout | stderr | <file>          the environment of the run (odin test, a demo executable with -define:DEMO_TEST=true)
//   DEMO_LOG_KINDS=input,reaction,frame | all  what to write (default: input and reaction); `input` alone is the trace of the simulator
// or with `-define:DEMO_LOG=...` and `-define:DEMO_LOG_KINDS=...` when the program is built, or in code with `LogOpen(&log, "run.log", {.INPUT})` and `TestDemo(demo, backend, log = &log)`.

import "core:fmt"
import "core:strings"

LogKind :: enum u8 {
    INPUT,
    REACTION,
    FRAME,
}

LogKinds :: bit_set[LogKind; u8]

LOG_DEFAULT_KINDS :: LogKinds{.INPUT, .REACTION}
LOG_ALL_KINDS :: LogKinds{.INPUT, .REACTION, .FRAME}

LOG_LINE_LENGTH :: 512

Log :: struct {
    kinds: LogKinds,                                    // empty: the log is off
    sink: proc(user: rawptr, line: string),             // where a finished line goes (a file, stdout, a buffer of a test)
    user: rawptr,
    lines: int,
    last_input_frame: int,                              // the frame of the last INPUT line: what a check reports its distance from
    last_input_time: f64,
    held: LogHeld,                                      // the input of the frame before, to write only what changed
    scratch: [LOG_LINE_LENGTH]u8,
}

@(private)
LogHeld :: struct {
    position: Vec2,
    buttons: MouseButtons,
    keys: KeySet,
    started: bool,
}

LogEnabled :: proc(log: ^Log, kind: LogKind) -> bool {
    return log != nil && log.sink != nil && kind in log.kinds
}

// Writes one line (`[frame  t=  +ms] KIND  text`) when the log is on for the kind. Used by the player, a demo may call it through `LogNote`.
Logf :: proc(log: ^Log, ctx: ^Context, kind: LogKind, format: string, args: ..any) {
    if !LogEnabled(log, kind) { return }
    text: string = fmt.bprintf(log.scratch[:], format, ..args)
    // the prefix is made in a second buffer so that the text keeps its place in the first
    head: [96]u8
    names: [LogKind]string = {.INPUT = "INPUT   ", .REACTION = "REACTION", .FRAME = "FRAME   "}
    prefix: string = fmt.bprintf(head[:], "[frame %5d  t=%8.4fs]  %s  ", ctx.frame, ctx.time, names[kind])
    line: string = strings.concatenate({prefix, text}, context.temp_allocator)
    log.sink(log.user, line)
    log.lines += 1
    if kind == .INPUT {
        log.last_input_frame, log.last_input_time = ctx.frame, ctx.time
    }
}

// A line from a demo: what it did in reaction (REACTION), for example "selected node 2" or "the menu opened". Free when no log is on.
LogNote :: proc(ctx: ^Context, format: string, args: ..any) {
    if ctx.log == nil { return }
    Logf(ctx.log, ctx, .REACTION, format, ..args)
}

// A log into a caller's buffer lines (for a test of the log itself, or a program that shows the log): every line is appended to `lines` with a newline
LogToBuffer :: proc(log: ^Log, lines: ^[dynamic]u8, kinds: LogKinds = LOG_DEFAULT_KINDS) {
    log^ = {kinds = kinds, user = lines, sink = proc(user: rawptr, line: string) {
        buffer: ^[dynamic]u8 = cast(^[dynamic]u8)user
        append(buffer, ..transmute([]u8)line)
        append(buffer, '\n')
    }}
}

// The kinds that a text names, comma separated: input, reaction, frame, all (unknown words are skipped)
LogKindsParse :: proc(text: string) -> (kinds: LogKinds) {
    rest: string = text
    for len(rest) > 0 {
        part: string
        comma: int = strings.index_byte(rest, ',')
        if comma < 0 {
            part, rest = rest, ""
        } else {
            part, rest = rest[:comma], rest[comma + 1:]
        }
        switch strings.to_lower(strings.trim_space(part), context.temp_allocator) {
        case "input": kinds += {.INPUT}
        case "reaction", "reactions": kinds += {.REACTION}
        case "frame", "frames": kinds += {.FRAME}
        case "all": kinds += LOG_ALL_KINDS
        }
    }
    return
}

@(private)
logStepName :: proc(step: ^Step) -> string {
    names: [StepKind]string = {
        .WAIT = "WAIT", .WAIT_UNTIL = "WAIT_UNTIL", .KEY_DOWN = "KEY_DOWN", .KEY_UP = "KEY_UP", .KEY_TAP = "KEY_TAP", .KEY_HOLD = "KEY_HOLD", .PAD_TAP = "PAD_TAP", .MOUSE_MOVE = "MOUSE_MOVE",
        .MOUSE_DOWN = "MOUSE_DOWN", .MOUSE_UP = "MOUSE_UP", .MOUSE_CLICK = "MOUSE_CLICK", .MOUSE_DRAG = "MOUSE_DRAG", .WHEEL = "WHEEL", .MOUSE_DELTA = "MOUSE_DELTA",
        .TEXT = "TEXT", .CHECK = "CHECK", .CAPTURE = "CAPTURE",
    }
    return names[step.kind]
}

// The step that is starting, in words with its numbers (a target that is read when the step runs shows the place it has now)
@(private)
logStep :: proc(log: ^Log, ctx: ^Context, step: ^Step, index: int) {
    if !LogEnabled(log, .INPUT) { return }
    name: string = logStepName(step)
    place: Vec2 = step.target^ if step.target != nil else step.position
    #partial switch step.kind {
    case .WAIT: Logf(log, ctx, .INPUT, "step %d %s %d frames", index, name, step.frames)
    case .WAIT_UNTIL: Logf(log, ctx, .INPUT, "step %d %s %q for at most %d frames", index, name, step.text, step.frames)
    case .KEY_DOWN, .KEY_UP, .KEY_TAP: Logf(log, ctx, .INPUT, "step %d %s %v", index, name, step.key)
    case .KEY_HOLD: Logf(log, ctx, .INPUT, "step %d %s %v for %d frames", index, name, step.key, step.frames)
    case .PAD_TAP: Logf(log, ctx, .INPUT, "step %d %s %v", index, name, step.pad)
    case .MOUSE_MOVE: Logf(log, ctx, .INPUT, "step %d %s to (%.1f, %.1f)", index, name, place.x, place.y)
    case .MOUSE_DOWN, .MOUSE_UP: Logf(log, ctx, .INPUT, "step %d %s %v", index, name, step.button)
    case .MOUSE_CLICK: Logf(log, ctx, .INPUT, "step %d %s %v at (%.1f, %.1f)", index, name, step.button, place.x, place.y)
    case .MOUSE_DRAG: Logf(log, ctx, .INPUT, "step %d %s %v from (%.1f, %.1f) to (%.1f, %.1f) in %d frames", index, name, step.button, step.from.x, step.from.y, step.position.x, step.position.y, step.frames)
    case .WHEEL: Logf(log, ctx, .INPUT, "step %d %s %.2f", index, name, step.amount)
    case .MOUSE_DELTA: Logf(log, ctx, .INPUT, "step %d %s (%.1f, %.1f)", index, name, step.position.x, step.position.y)
    case .TEXT: Logf(log, ctx, .INPUT, "step %d %s %q", index, name, step.text)
    }
}

// What the input of this frame has that the one before did not: a position, a button or a key that went down or up, characters, the wheel, a pad button
@(private)
logInput :: proc(log: ^Log, ctx: ^Context, input: ^Input) {
    if !LogEnabled(log, .INPUT) { return }
    held: ^LogHeld = &log.held
    if !held.started || input.mouse_position != held.position {
        Logf(log, ctx, .INPUT, "mouse -> (%.1f, %.1f)", input.mouse_position.x, input.mouse_position.y)
    }
    for button in MouseButton {
        if button in input.mouse_down && button not_in held.buttons { Logf(log, ctx, .INPUT, "%v down", button) }
        if button not_in input.mouse_down && button in held.buttons { Logf(log, ctx, .INPUT, "%v up", button) }
    }
    for key in Key {
        if key in input.keys_down && key not_in held.keys { Logf(log, ctx, .INPUT, "key %v down", key) }
        if key not_in input.keys_down && key in held.keys { Logf(log, ctx, .INPUT, "key %v up", key) }
    }
    if input.text_count > 0 { Logf(log, ctx, .INPUT, "text %q", string(input.text[:input.text_count])) }
    if input.mouse_wheel != 0 { Logf(log, ctx, .INPUT, "wheel %.2f", input.mouse_wheel) }
    if input.pad_pressed != {} { Logf(log, ctx, .INPUT, "pad %v pressed", input.pad_pressed) }
    held^ = {position = input.mouse_position, buttons = input.mouse_down, keys = input.keys_down, started = true}
}

// A check: its result and how long after the last input it was made (the reaction time in frames and in simulated seconds)
@(private)
logCheck :: proc(log: ^Log, ctx: ^Context, message: string, passed: bool) {
    if !LogEnabled(log, .REACTION) { return }
    Logf(log, ctx, .REACTION, "check %s %q (%d frames, %.4f s after the last input)", "PASS" if passed else "FAIL", message, ctx.frame - log.last_input_frame, ctx.time - log.last_input_time)
}
