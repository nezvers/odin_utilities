package demo_kit

// Simulated user input and runtime checks, as data: a script is an array of Steps that a Player plays frame by frame into the
// Input of the demo. The same script drives a demo in a window (watch it) and headless (a test).
//
//     script: []Step = {
//         Wait(5),
//         Tap(.SPACE),                                        // pressed for one frame
//         Hold(.D, 30),                                       // held for 30 frames
//         Click({400, 300}),                                  // move the mouse there and press the left button
//         Check(proc(ctx: ^kit.Context) -> bool { return state.value == 3 }, "space added 3"),
//     }
//
// The constructors are contextless so a script can be a global (a package level array).
// A step that takes time (Wait, Tap, Hold, Click, Drag) holds the steps behind it; the others happen at once, in the same frame.
// A Check runs at the start of a frame, so it sees what the last frame's update did.

StepKind :: enum u8 {
    WAIT,
    WAIT_UNTIL,
    KEY_DOWN,
    KEY_UP,
    KEY_TAP,
    KEY_HOLD,
    PAD_TAP,
    MOUSE_MOVE,
    MOUSE_DOWN,
    MOUSE_UP,
    MOUSE_CLICK,
    MOUSE_DRAG,
    WHEEL,
    MOUSE_DELTA,
    TEXT,
    CHECK,
    CAPTURE,
}

Step :: struct {
    kind: StepKind,
    frames: u32,                // Wait, Hold, Drag, and the most that WaitUntil waits
    key: Key,
    button: MouseButton,
    pad: PadButton,             // PadTap
    position: Vec2,             // MoveTo, Click, Drag: where it goes
    from: Vec2,                 // Drag: where it starts
    amount: f32,                // Scroll
    text: string,               // Type, and the message of a Check
    check: proc(ctx: ^Context) -> bool,
    file: string,               // Capture: the file of the script, the golden images are next to it
    mask: [CAPTURE_FRAMES]Rect,     // CaptureIn: the masking frames (the rest of the picture is not looked at)
    mask_count: int,
    frame_target: ^Rect,        // CaptureAt: one frame that is read when the step runs
    target: ^Vec2,              // ClickAt: where the click goes is read when the step runs
}

Wait :: proc "contextless" (frames: u32) -> Step { return {kind = .WAIT, frames = frames} }
KeyDownStep :: proc "contextless" (key: Key) -> Step { return {kind = .KEY_DOWN, key = key} }
KeyUpStep :: proc "contextless" (key: Key) -> Step { return {kind = .KEY_UP, key = key} }
Tap :: proc "contextless" (key: Key) -> Step { return {kind = .KEY_TAP, key = key} }
// A gamepad button pressed for one frame (a script has no pad: the input says it went down)
PadTap :: proc "contextless" (button: PadButton) -> Step { return {kind = .PAD_TAP, pad = button} }
Hold :: proc "contextless" (key: Key, frames: u32) -> Step { return {kind = .KEY_HOLD, key = key, frames = frames} }
MoveTo :: proc "contextless" (position: Vec2) -> Step { return {kind = .MOUSE_MOVE, position = position} }
MouseDownStep :: proc "contextless" (button: MouseButton = .LEFT) -> Step { return {kind = .MOUSE_DOWN, button = button} }
MouseUpStep :: proc "contextless" (button: MouseButton = .LEFT) -> Step { return {kind = .MOUSE_UP, button = button} }
Click :: proc "contextless" (position: Vec2, button: MouseButton = .LEFT) -> Step { return {kind = .MOUSE_CLICK, position = position, button = button} }
// A click at a place that is only known while the script runs: a Check before it finds a widget (by its rectangle of the last frame) and writes the point into `target`.
// For layouts that depend on the widths of texts, where a fixed number would be right for one font only.
ClickAt :: proc "contextless" (target: ^Vec2, button: MouseButton = .LEFT) -> Step { return {kind = .MOUSE_CLICK, target = target, button = button} }
// The pointer goes to a place that is only known while the script runs (see ClickAt): with MouseDownStep and MouseUpStep around it, a drag between widgets that a
// Check found.
MoveAt :: proc "contextless" (target: ^Vec2) -> Step { return {kind = .MOUSE_MOVE, target = target} }
// Hold a button and move from one point to another over `frames` frames
Drag :: proc "contextless" (from: Vec2, to: Vec2, frames: u32, button: MouseButton = .LEFT) -> Step { return {kind = .MOUSE_DRAG, from = from, position = to, frames = frames, button = button} }
// The mouse moves by this much in this frame (a captured mouse, a first person look) without a position
LookBy :: proc "contextless" (delta: Vec2) -> Step { return {kind = .MOUSE_DELTA, position = delta} }
Scroll :: proc "contextless" (amount: f32) -> Step { return {kind = .WHEEL, amount = amount} }
Type :: proc "contextless" (text: string) -> Step { return {kind = .TEXT, text = text} }
// Waits until `check` is true, looking at it in every frame, and goes on in that very frame (a condition that is true already costs no frame). A thing that happens on another clock than the
// frames of the script (a server that starts, a network that answers, a window of another program) is waited for with this, never with a fixed `Wait` that is right on a quiet computer and
// short on a busy one. When it is still false after `frames` frames the report says `message` (like a failed Check) and the script goes on.
WaitUntil :: proc "contextless" (check: proc(ctx: ^Context) -> bool, message: string, frames: u32 = 3000) -> Step { return {kind = .WAIT_UNTIL, check = check, text = message, frames = max(frames, 1)} }

// The check says if what the demo shows is right, `message` is what the report says when it is not
Check :: proc "contextless" (check: proc(ctx: ^Context) -> bool, message: string) -> Step { return {kind = .CHECK, check = check, text = message} }

CAPTURE_FRAMES :: 4         // masking frames of one capture (CaptureIn)

// Takes the pixels of the frame that is drawn in this frame and compares them with the golden image `captures/<backend>/<name>.png` next to the
// script file (see capture.odin). Only with -define:DEMO_CAPTURE=true and a backend that can capture, else it does nothing.
Capture :: proc "contextless" (name: string, location := #caller_location) -> Step { return {kind = .CAPTURE, text = name, file = location.file_path} }

// A capture that looks only inside of masking frames (x, y, width, height; at most CAPTURE_FRAMES of them): the rest of the picture is masked out, so a picture that changes elsewhere (a clock, a
// scrolling log) does not fail it, and a small region (the corner of a node, the outline of a window) is compared on its own with no pixel allowed to differ (see capture.odin). The golden image is
// the frames' pixels on a transparent picture.
CaptureIn :: proc "contextless" (name: string, frames: []Rect, location := #caller_location) -> Step {
    step: Step = {kind = .CAPTURE, text = name, file = location.file_path}
    for i in 0 ..< min(len(frames), CAPTURE_FRAMES) {
        step.mask[i] = frames[i]
        step.mask_count += 1
    }
    return step
}

// The same with one frame that the script finds when the step runs (the place of an element of the last frame): `frame` is read then.
CaptureAt :: proc "contextless" (name: string, frame: ^Rect, location := #caller_location) -> Step {
    return {kind = .CAPTURE, text = name, file = location.file_path, frame_target = frame}
}

MAX_FAILURES :: 16

Failure :: struct {
    message: string,
    frame: int,
}

// What a run found. `checks` counts the Check steps that ran.
Report :: struct {
    checks: int,
    failed: int,
    failures: [MAX_FAILURES]Failure,    // the first ones, `failed` counts all
    frames: int,
    draw_calls: int,
    captures: int,                      // Capture steps that compared or wrote an image
    captures_skipped: int,
    captures_written: int,              // golden images that were made because there was none
    finished: bool,                     // the script played to its end (false: the frame limit stopped it)
}

Player :: struct {
    script: []Step,
    index: int,
    wait_left: u32,             // frames left of the step that takes time
    active: bool,               // a step that takes time is running
    held_keys: KeySet,
    held_buttons: MouseButtons,
    pad_now: PadButtons,        // a PadTap of this frame
    mouse_position: Vec2,
    release_next: KeySet,       // taps end on the frame after they began
    release_buttons_next: MouseButtons,
    drag_from: Vec2,
    drag_to: Vec2,
    drag_total: u32,
    capture_name: string,       // a Capture step of this frame: the runner takes it after the demo drew
    capture_file: string,
    capture_frames: [CAPTURE_FRAMES]Rect,   // the masking frames of that step (none: the whole picture)
    capture_frame_count: int,
    log: ^Log,                  // where the steps and the input go (nil: nowhere)
    report: Report,
}

PlayerStart :: proc(player: ^Player, script: []Step) {
    player^ = {script = script}
}

PlayerFinished :: proc(player: ^Player) -> bool {
    return player.index >= len(player.script) && !player.active
}

// Make the input of this frame from the script. Called before the demo updates.
PlayerFrame :: proc(player: ^Player, ctx: ^Context, input: ^Input) {
    previous_keys: KeySet = player.held_keys
    previous_buttons: MouseButtons = player.held_buttons
    previous_position: Vec2 = player.mouse_position
    input^ = {}
    player.capture_name = ""
    player.capture_frame_count = 0

    // what a tap or a click of the last frame lets go of
    player.held_keys -= player.release_next
    player.held_buttons -= player.release_buttons_next
    player.release_next = {}
    player.release_buttons_next = {}
    player.pad_now = {}

    // a step that takes time is counted down first. When it ends by letting go of something, the next step waits for the next
    // frame: let go and press again in one frame would be no press at all
    skip_steps: bool = false
    extra_delta: Vec2
    if player.active && player.script[player.index - 1].kind == .WAIT_UNTIL {
        // the condition is looked at in every frame; true: the script goes on in this frame; out of frames: the report says what was waited for
        waiting: ^Step = &player.script[player.index - 1]
        player.report.checks += 1
        if waiting.check != nil && waiting.check(ctx) {
            player.active = false
            logCheck(player.log, ctx, waiting.text, true)
        } else {
            player.report.checks -= 1                       // not decided yet: it counts when it is
            if player.wait_left > 0 { player.wait_left -= 1 }
            if player.wait_left == 0 {
                player.report.checks += 1
                if player.report.failed < MAX_FAILURES { player.report.failures[player.report.failed] = {message = waiting.text, frame = ctx.frame} }
                player.report.failed += 1
                logCheck(player.log, ctx, waiting.text, false)
                player.active = false
            }
        }
    } else if player.active {
        if player.drag_total > 0 {
            progress: f32 = 1 - f32(player.wait_left) / f32(player.drag_total)
            player.mouse_position = player.drag_from + (player.drag_to - player.drag_from) * progress
        }
        if player.wait_left > 0 { player.wait_left -= 1 }
        if player.wait_left == 0 {
            player.active = false
            step: ^Step = &player.script[player.index - 1]
            #partial switch step.kind {
            case .KEY_HOLD:
                player.held_keys -= {step.key}
                skip_steps = true
            case .MOUSE_DRAG:
                skip_steps = true
                player.held_buttons -= {step.button}
                player.mouse_position = step.position
            }
            player.drag_total = 0
        }
    }

    for !skip_steps && !player.active && player.index < len(player.script) {
        step: ^Step = &player.script[player.index]
        player.index += 1
        logStep(player.log, ctx, step, player.index - 1)
        switch step.kind {
        case .WAIT:
            if step.frames > 0 {
                player.active = true
                player.wait_left = step.frames
            }
        case .WAIT_UNTIL:
            if step.check != nil && step.check(ctx) {
                player.report.checks += 1
                logCheck(player.log, ctx, step.text, true)
            } else {
                player.active = true
                player.wait_left = step.frames
            }
        case .KEY_DOWN:
            player.held_keys += {step.key}
        case .KEY_UP:
            player.held_keys -= {step.key}
        case .KEY_TAP:
            player.held_keys += {step.key}
            player.release_next += {step.key}
            player.active = true
            player.wait_left = 2        // pressed in this frame, let go in the next: the next step starts after that, so two taps are two presses
        case .PAD_TAP:
            player.pad_now += {step.pad}
            player.active = true
            player.wait_left = 2
        case .KEY_HOLD:
            player.held_keys += {step.key}
            player.active = true
            player.wait_left = max(step.frames, 1)
        case .MOUSE_MOVE:
            player.mouse_position = step.target^ if step.target != nil else step.position
        case .MOUSE_DOWN:
            player.held_buttons += {step.button}
        case .MOUSE_UP:
            player.held_buttons -= {step.button}
        case .MOUSE_CLICK:
            player.mouse_position = step.target^ if step.target != nil else step.position
            player.held_buttons += {step.button}
            player.release_buttons_next += {step.button}
            player.active = true
            player.wait_left = 2
        case .MOUSE_DRAG:
            player.mouse_position = step.from
            player.held_buttons += {step.button}
            player.drag_from = step.from
            player.drag_to = step.position
            player.drag_total = max(step.frames, 1)
            player.active = true
            player.wait_left = player.drag_total
        case .WHEEL:
            input.mouse_wheel += step.amount
        case .MOUSE_DELTA:
            extra_delta += step.position
        case .TEXT:
            for character in transmute([]u8)step.text {
                if int(input.text_count) >= TEXT_CAPACITY { break }
                input.text[input.text_count] = character
                input.text_count += 1
            }
        case .CAPTURE:
            player.capture_name = step.text
            player.capture_file = step.file
            player.capture_frames, player.capture_frame_count = step.mask, step.mask_count
            if step.frame_target != nil { player.capture_frames[0], player.capture_frame_count = step.frame_target^, 1 }
        case .CHECK:
            player.report.checks += 1
            passed: bool = true
            if step.check != nil && !step.check(ctx) {
                passed = false
                if player.report.failed < MAX_FAILURES {
                    player.report.failures[player.report.failed] = {message = step.text, frame = ctx.frame}
                }
                player.report.failed += 1
            }
            logCheck(player.log, ctx, step.text, passed)
        }
    }

    input.pad_pressed = player.pad_now
    input.pad_down = player.pad_now
    input.keys_down = player.held_keys
    input.mouse_down = player.held_buttons
    input.mouse_position = player.mouse_position
    input.mouse_delta = player.mouse_position - previous_position + extra_delta
    InputFromHeld(input, previous_keys, previous_buttons)
    logInput(player.log, ctx, input)
}
