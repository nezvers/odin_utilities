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
    KEY_DOWN,
    KEY_UP,
    KEY_TAP,
    KEY_HOLD,
    MOUSE_MOVE,
    MOUSE_DOWN,
    MOUSE_UP,
    MOUSE_CLICK,
    MOUSE_DRAG,
    WHEEL,
    TEXT,
    CHECK,
}

Step :: struct {
    kind: StepKind,
    frames: u32,                // Wait, Hold, Drag
    key: Key,
    button: MouseButton,
    position: Vec2,             // MoveTo, Click, Drag: where it goes
    from: Vec2,                 // Drag: where it starts
    amount: f32,                // Scroll
    text: string,               // Type, and the message of a Check
    check: proc(ctx: ^Context) -> bool,
}

Wait :: proc "contextless" (frames: u32) -> Step { return {kind = .WAIT, frames = frames} }
KeyDownStep :: proc "contextless" (key: Key) -> Step { return {kind = .KEY_DOWN, key = key} }
KeyUpStep :: proc "contextless" (key: Key) -> Step { return {kind = .KEY_UP, key = key} }
Tap :: proc "contextless" (key: Key) -> Step { return {kind = .KEY_TAP, key = key} }
Hold :: proc "contextless" (key: Key, frames: u32) -> Step { return {kind = .KEY_HOLD, key = key, frames = frames} }
MoveTo :: proc "contextless" (position: Vec2) -> Step { return {kind = .MOUSE_MOVE, position = position} }
MouseDownStep :: proc "contextless" (button: MouseButton = .LEFT) -> Step { return {kind = .MOUSE_DOWN, button = button} }
MouseUpStep :: proc "contextless" (button: MouseButton = .LEFT) -> Step { return {kind = .MOUSE_UP, button = button} }
Click :: proc "contextless" (position: Vec2, button: MouseButton = .LEFT) -> Step { return {kind = .MOUSE_CLICK, position = position, button = button} }
// Hold a button and move from one point to another over `frames` frames
Drag :: proc "contextless" (from: Vec2, to: Vec2, frames: u32, button: MouseButton = .LEFT) -> Step { return {kind = .MOUSE_DRAG, from = from, position = to, frames = frames, button = button} }
Scroll :: proc "contextless" (amount: f32) -> Step { return {kind = .WHEEL, amount = amount} }
Type :: proc "contextless" (text: string) -> Step { return {kind = .TEXT, text = text} }
// The check says if what the demo shows is right, `message` is what the report says when it is not
Check :: proc "contextless" (check: proc(ctx: ^Context) -> bool, message: string) -> Step { return {kind = .CHECK, check = check, text = message} }

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
    finished: bool,                     // the script played to its end (false: the frame limit stopped it)
}

Player :: struct {
    script: []Step,
    index: int,
    wait_left: u32,             // frames left of the step that takes time
    active: bool,               // a step that takes time is running
    held_keys: KeySet,
    held_buttons: MouseButtons,
    mouse_position: Vec2,
    release_next: KeySet,       // taps end on the frame after they began
    release_buttons_next: MouseButtons,
    drag_from: Vec2,
    drag_to: Vec2,
    drag_total: u32,
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

    // what a tap or a click of the last frame lets go of
    player.held_keys -= player.release_next
    player.held_buttons -= player.release_buttons_next
    player.release_next = {}
    player.release_buttons_next = {}

    // a step that takes time is counted down first. When it ends by letting go of something, the next step waits for the next
    // frame: let go and press again in one frame would be no press at all
    skip_steps: bool = false
    if player.active {
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
        switch step.kind {
        case .WAIT:
            if step.frames > 0 {
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
        case .KEY_HOLD:
            player.held_keys += {step.key}
            player.active = true
            player.wait_left = max(step.frames, 1)
        case .MOUSE_MOVE:
            player.mouse_position = step.position
        case .MOUSE_DOWN:
            player.held_buttons += {step.button}
        case .MOUSE_UP:
            player.held_buttons -= {step.button}
        case .MOUSE_CLICK:
            player.mouse_position = step.position
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
        case .TEXT:
            for character in transmute([]u8)step.text {
                if int(input.text_count) >= TEXT_CAPACITY { break }
                input.text[input.text_count] = character
                input.text_count += 1
            }
        case .CHECK:
            player.report.checks += 1
            if step.check != nil && !step.check(ctx) {
                if player.report.failed < MAX_FAILURES {
                    player.report.failures[player.report.failed] = {message = step.text, frame = ctx.frame}
                }
                player.report.failed += 1
            }
        }
    }

    input.keys_down = player.held_keys
    input.mouse_down = player.held_buttons
    input.mouse_position = player.mouse_position
    input.mouse_delta = player.mouse_position - previous_position
    InputFromHeld(input, previous_keys, previous_buttons)
}
