#+private file
package demo_common

import "core:fmt"
import kit "../../demo_kit"
import timer_package ".."

Timer :: timer_package.Timer

@(private="package")
demo_loop_timer: kit.Demo = {
    name = "loop timer",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

HEIGHT_CLOCK :: 160

InputValue :: struct {
    digits: [6]u8,          // the digits of hh:mm:ss, the last typed is digits[0]
    count: u8,
}
input_value: InputValue

loop_timer: Timer = {
    mode = .loop,
    callbacks = {timeout},
}
alert_sound: kit.Sound
flash_value: f32 = 0
timeouts: int               // how many times the timer ran out

init :: proc(ctx: ^kit.Context) {
    input_value = {}
    input_value.count = 3
    input_value.digits[2] = 2       // 2 minutes
    loop_timer.wait = input_to_seconds()
    flash_value = 0
    timeouts = 0
    timer_package.Reset(&loop_timer)
    alert_sound = kit.SoundLoad(ctx, #load("../../assets/sounds/alert_sound.wav"))
}

finit :: proc(ctx: ^kit.Context) {
    kit.SoundUnload(ctx, alert_sound)
}

// the callback has no context: what it needs to do is remembered here and done in update
pending_alert: bool

update :: proc(ctx: ^kit.Context) {
    timer_package.Update(&loop_timer, ctx.delta_time)
    if pending_alert {
        pending_alert = false
        kit.SoundPlay(ctx, alert_sound)
    }
    flash_update(ctx, ctx.delta_time)
    update_keyboard_input(&ctx.input)
}

draw :: proc(ctx: ^kit.Context) {
    center: kit.Vec2 = ctx.screen * 0.5
    measure_clock: kit.Vec2 = kit.MeasureText(ctx, "00:00:00.000", HEIGHT_CLOCK)

    // Clock
    kit.DrawText(ctx, seconds_to_clock(loop_timer.remain), {center.x - measure_clock.x * 0.5, center.y - HEIGHT_CLOCK * 0.5}, HEIGHT_CLOCK, kit.BLACK)

    // Input
    is_valid: bool = input_is_valid()
    input_y: f32 = center.y - HEIGHT_CLOCK
    number_x: f32 = center.x + measure_clock.x * 0.5 - measure_clock.x / 5
    OFF_INPUT :: 75
    for i in 0 ..< len(input_value.digits) {
        color: kit.Color = kit.LIGHT_GRAY
        number_x -= OFF_INPUT
        if u8(i) < input_value.count {
            color = kit.GRAY if is_valid else kit.RED
        }
        kit.DrawText(ctx, fmt.tprintf("%d", input_value.digits[i]), {number_x, input_y}, HEIGHT_CLOCK / 2, color)

        if i != 1 && i != 3 { continue }
        number_x -= OFF_INPUT / 2
        kit.DrawText(ctx, ":", {number_x, input_y}, HEIGHT_CLOCK / 2, color)
    }

    percent: f32 = loop_timer.remain / loop_timer.wait
    progress: kit.Rect = {center.x - measure_clock.x * 0.5, center.y + HEIGHT_CLOCK * 0.5, measure_clock.x, HEIGHT_CLOCK / 2}
    kit.DrawRect(ctx, progress, kit.LIGHT_GRAY)
    progress.z *= percent
    kit.DrawRect(ctx, progress, kit.GREEN)

    kit.DrawText(ctx, "digits: time    enter: set    space: start / stop    backspace: remove a digit", {10, 10}, 18, kit.DARK_GRAY)
}

timeout :: proc(timer: ^Timer) {
    flash_value = 1
    pending_alert = true
    timeouts += 1
}

seconds_to_clock :: proc(seconds_total: f32) -> string {
    seconds, minutes, hours, ms := timer_package.seconds_to_clock(seconds_total)
    return fmt.tprintf("%02d:%02d:%02d.%03d", hours, minutes, seconds, ms)
}

input_pop :: proc() {
    if input_value.count == 0 { return }
    input_value.count -= 1
    for i in 0 ..< len(input_value.digits) - 1 {
        input_value.digits[i] = input_value.digits[i + 1]
    }
    input_value.digits[len(input_value.digits) - 1] = 0
}

input_push :: proc(value: u8) {
    if input_value.count == len(input_value.digits) { return }
    assert(value < 10)
    last: int = len(input_value.digits) - 1
    for i in 0 ..< last {
        input_value.digits[last - i] = input_value.digits[last - i - 1]
    }
    input_value.digits[0] = value
    input_value.count += 1
}

input_is_valid :: proc() -> bool {
    return input_value.digits[1] < 7 && input_value.digits[3] < 7
}

digit_keys: [10]kit.Key = {.N0, .N1, .N2, .N3, .N4, .N5, .N6, .N7, .N8, .N9}

update_keyboard_input :: proc(input: ^kit.Input) {
    if kit.KeyPressed(input, .BACKSPACE) || kit.KeyPressed(input, .DELETE) {
        input_pop()
    }
    for key, digit in digit_keys {
        if kit.KeyPressed(input, key) { input_push(u8(digit)) }
    }
    if kit.KeyPressed(input, .ENTER) && input_is_valid() {
        loop_timer.wait = input_to_seconds()
        loop_timer.active = false
        timer_package.Reset(&loop_timer)
    }
    if kit.KeyPressed(input, .SPACE) {
        if loop_timer.mode == .loop {
            loop_timer.active = !loop_timer.active
        } else if loop_timer.mode == .single {
            if loop_timer.remain > 0 {
                loop_timer.active = !loop_timer.active
            } else {
                timer_package.Start(&loop_timer)
            }
        }
    }
}

input_to_seconds :: proc() -> f32 {
    hours: u32 = u32(input_value.digits[5] * 10 + input_value.digits[4])
    minutes: u32 = u32(input_value.digits[3] * 10 + input_value.digits[2])
    seconds: u32 = u32(input_value.digits[1] * 10 + input_value.digits[0])
    return f32(seconds + minutes * 60 + hours * 60 * 60)
}

// The screen flashes yellow when the timer runs out
flash_update :: proc(ctx: ^kit.Context, delta_time: f32, mult: f32 = 2) {
    if flash_value == 0 { return }
    flash_value = max(0, flash_value - delta_time * mult)
    ctx.background = {
        u8(f32(kit.WHITE.r) + f32(int(kit.YELLOW.r) - int(kit.WHITE.r)) * flash_value),
        u8(f32(kit.WHITE.g) + f32(int(kit.YELLOW.g) - int(kit.WHITE.g)) * flash_value),
        u8(f32(kit.WHITE.b) + f32(int(kit.YELLOW.b) - int(kit.WHITE.b)) * flash_value),
        255,
    }
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return loop_timer.wait == 120 && loop_timer.remain == 120 }, "starts with 2 minutes"),
    // type 3 seconds: remove the three digits, then 0 0 3
    kit.Tap(.BACKSPACE), kit.Tap(.BACKSPACE), kit.Tap(.BACKSPACE),
    kit.Tap(.N0), kit.Tap(.N0), kit.Tap(.N3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return input_to_seconds() == 3 }, "the typed digits are 3 seconds"),
    kit.Tap(.ENTER),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return loop_timer.wait == 3 && !loop_timer.active }, "enter sets the time and waits"),
    kit.Tap(.SPACE),
    kit.Wait(90),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return loop_timer.active && loop_timer.remain < 2 && timeouts == 0 }, "running, not out yet"),
    kit.Wait(110),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return timeouts == 1 }, "ran out once and the callback was called"),
    kit.Tap(.SPACE),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !loop_timer.active }, "space stops it"),
    // 70 seconds is not a time: the digits before the minutes are red and enter does nothing
    kit.Tap(.N7), kit.Tap(.N0),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !input_is_valid() || input_value.digits[1] < 7 }, "digits are checked"),
    kit.Wait(2),
    kit.Capture("timer_loop_timer_end"),
    kit.Wait(1),
}
