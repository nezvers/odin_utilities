#+private file
package demo_common

// Menu buttons. Intro is one tween with parallel steps inside of a pool, hover animation is a Tween embedded in each button, no pool needed

import tw ".."
import kit "../../demo_kit"

@(private="package")
demo_buttons: kit.Demo = {
    name = "buttons",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

MenuButton :: struct {
    text: string,
    position: kit.Vec2,
    target_x: f32,
    size: kit.Vec2,
    color: [4]u8,
    scale: f32,
    hovered: bool,
    hover_tween: tw.Tween,
}

BUTTON_COUNT :: 3
buttons: [BUTTON_COUNT]MenuButton
title_y: f32
intro_done: bool
intro_system: tw.TweenSystem(4)

init :: proc(ctx: ^kit.Context) {
    names: [BUTTON_COUNT]string = {"Start", "Options", "Quit"}
    for i in 0 ..< BUTTON_COUNT {
        buttons[i] = {
            text = names[i],
            target_x = 200,
            position = {-300, 200 + f32(i) * 80},
            size = {240, 60},
            color = {80, 140, 220, 0},
            scale = 1,
            hover_tween = tw.TweenMake(),
        }
    }
    play_intro()
}

play_intro :: proc() {
    tw.SystemClear(&intro_system)
    intro_done = false
    title_y = -100
    for i in 0 ..< BUTTON_COUNT {
        buttons[i].position.x = -300
        buttons[i].color.a = 0
    }

    tween, ok := tw.SystemNew(&intro_system)
    if !ok { return }
    // First step runs alone, next ones are parallel with different delays
    tw.TweenProperty(tween, &title_y, 80, 0.8, .Bounce_Out)
    for i in 0 ..< BUTTON_COUNT {
        delay: f32 = f32(i) * 0.15
        tw.TweenProperty(tween, &buttons[i].position.x, buttons[i].target_x, 0.6, .Back_Out, delay = delay, parallel = true if i > 0 else false)
        tw.TweenProperty(tween, &buttons[i].color, [4]u8{80, 140, 220, 255}, 0.4, delay = delay, parallel = true)
    }
    tw.TweenCallback(tween, proc(tween: ^tw.Tween) { intro_done = true })
    tw.TweenPlay(tween)
}

update :: proc(ctx: ^kit.Context) {
    tw.SystemUpdate(&intro_system, ctx.delta_time)

    if kit.KeyPressed(&ctx.input, .SPACE) {
        play_intro()
    }

    for i in 0 ..< BUTTON_COUNT {
        button: ^MenuButton = &buttons[i]
        rect: kit.Rect = {button.position.x, button.position.y, button.size.x, button.size.y}
        hovered: bool = intro_done && kit.PointInRect(ctx.input.mouse_position, rect) && !ctx.ui_hover
        if hovered != button.hovered {
            button.hovered = hovered
            // Restart from the current scale
            tw.TweenClear(&button.hover_tween)
            tw.TweenProperty(&button.hover_tween, &button.scale, 1.15 if hovered else 1.0, 0.2, .Cubic_Out)
            tw.TweenPlay(&button.hover_tween)
        }
        tw.TweenUpdate(&button.hover_tween, ctx.delta_time)
    }
}

draw :: proc(ctx: ^kit.Context) {
    kit.DrawText(ctx, "TITLE SCREEN", {200, title_y}, 40, kit.DARK_GRAY)
    for i in 0 ..< BUTTON_COUNT {
        button: ^MenuButton = &buttons[i]
        size: kit.Vec2 = button.size * button.scale
        rect: kit.Rect = {
            button.position.x + (button.size.x - size.x) * 0.5,
            button.position.y + (button.size.y - size.y) * 0.5,
            size.x,
            size.y,
        }
        kit.DrawRect(ctx, rect, button.color)
        kit.DrawText(ctx, button.text, {rect.x + 20, rect.y + rect.w * 0.5 - 10}, 20, kit.WHITE)
    }
    kit.DrawText(ctx, "tween: parallel steps with delay in a pool, embedded Tween for hover. SPACE replays intro", {10, 10}, 20, kit.BLACK)
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !intro_done && buttons[0].position.x < 0 }, "the intro starts with the buttons outside of the screen"),
    kit.Wait(150),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return intro_done && buttons[2].position.x == 200 && buttons[2].color.a == 255 && title_y == 80 }, "the intro ends: parallel steps and delays are done"),
    kit.MoveTo({300, 230}),
    kit.Wait(30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return buttons[0].hovered && buttons[0].scale == 1.15 }, "a hovered button grows with its own tween"),
    kit.MoveTo({900, 650}),
    kit.Wait(30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !buttons[0].hovered && buttons[0].scale == 1 }, "and shrinks back"),
    kit.Tap(.SPACE),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !intro_done && buttons[0].position.x < 0 }, "space plays the intro again"),
    kit.Wait(2),
    kit.Capture("tween_buttons_end"),
    kit.Wait(1),
}
