#+private file
package game

import "../../../karl2d"
import "core:math/ease"

import tw "../../"

@(private="package")
tween_state: GameState = {
    init,
    finit,
    process,
    draw,
}

@(private="package")
tween_ease_state: GameState = {
    init_ease,
    finit,
    process_ease,
    draw_ease,
}

// Menu buttons. Intro is one tween with parallel steps inside of a pool,
// hover animation is a Tween embedded in each button, no pool needed

MenuButton :: struct {
    text: string,
    position: Vec2,
    target_x: f32,
    size: Vec2,
    color: Color,
    scale: f32,
    hovered: bool,
    hover_tween: tw.Tween,
}

BUTTON_COUNT :: 3
buttons: [BUTTON_COUNT]MenuButton
title_y: f32
intro_done: bool
intro_system: tw.TweenSystem(4)

init :: proc() {
    background_color = karl2d.LIGHT_BLUE

    names: [BUTTON_COUNT]string = {"Start", "Options", "Quit"}
    for i: int = 0; i < BUTTON_COUNT; i += 1 {
        buttons[i] = {
            text = names[i],
            target_x = 200,
            position = {-300, 200 + cast(f32)i * 80},
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
    for i: int = 0; i < BUTTON_COUNT; i += 1 {
        buttons[i].position.x = -300
        buttons[i].color.a = 0
    }

    tween, ok: = tw.SystemNew(&intro_system)
    if !ok { return }
    // First step runs alone, next ones are parallel with different delays
    tw.TweenProperty(tween, &title_y, 80, 0.8, .Bounce_Out)
    for i: int = 0; i < BUTTON_COUNT; i += 1 {
        delay: f32 = cast(f32)i * 0.15
        tw.TweenProperty(tween, &buttons[i].position.x, buttons[i].target_x, 0.6, .Back_Out, delay = delay, parallel = true if i > 0 else false)
        tw.TweenProperty(tween, &buttons[i].color, Color{80, 140, 220, 255}, 0.4, delay = delay, parallel = true)
    }
    tw.TweenCallback(tween, proc(tween: ^tw.Tween) { intro_done = true })
    tw.TweenPlay(tween)
}

finit :: proc() {}

process :: proc() {
    delta_time: f32 = karl2d.get_frame_time()
    tw.SystemUpdate(&intro_system, delta_time)

    if karl2d.key_went_down(.Space) {
        play_intro()
    }

    mouse_position: Vec2 = karl2d.get_mouse_position()
    for i: int = 0; i < BUTTON_COUNT; i += 1 {
        button: ^MenuButton = &buttons[i]
        rect: Rect = {button.position.x, button.position.y, button.size.x, button.size.y}
        hovered: bool = intro_done && check_hover(mouse_position, rect)
        if hovered != button.hovered {
            button.hovered = hovered
            // Restart from the current scale
            tw.TweenClear(&button.hover_tween)
            tw.TweenProperty(&button.hover_tween, &button.scale, 1.15 if hovered else 1.0, 0.2, .Cubic_Out)
            tw.TweenPlay(&button.hover_tween)
        }
        tw.TweenUpdate(&button.hover_tween, delta_time)
    }
}

draw :: proc() {
    karl2d.draw_text("TITLE SCREEN", {200, title_y}, 40, karl2d.DARK_GRAY)
    for i: int = 0; i < BUTTON_COUNT; i += 1 {
        button: ^MenuButton = &buttons[i]
        size: Vec2 = button.size * button.scale
        rect: Rect = {
            button.position.x + (button.size.x - size.x) * 0.5,
            button.position.y + (button.size.y - size.y) * 0.5,
            size.x,
            size.y,
        }
        karl2d.draw_rect(rect, button.color)
        karl2d.draw_text(button.text, {rect.x + 20, rect.y + rect.h * 0.5 - 10}, 20, karl2d.WHITE)
    }
    karl2d.draw_text("parallel steps with delay in a pool, embedded Tween for hover. SPACE replays intro", {10, 10}, 20, karl2d.BLACK)
}

// Easing comparison. Each row is a looping Tween owned by the demo, no pool

EASE_COUNT :: 8
ease_list: [EASE_COUNT]ease.Ease = {
    .Linear,
    .Quadratic_In_Out,
    .Cubic_Out,
    .Sine_In_Out,
    .Exponential_Out,
    .Elastic_Out,
    .Back_In_Out,
    .Bounce_Out,
}
ease_names: [EASE_COUNT]string = {
    "Linear",
    "Quadratic_In_Out",
    "Cubic_Out",
    "Sine_In_Out",
    "Exponential_Out",
    "Elastic_Out",
    "Back_In_Out",
    "Bounce_Out",
}
ease_x: [EASE_COUNT]f32
ease_tweens: [EASE_COUNT]tw.Tween

init_ease :: proc() {
    background_color = karl2d.LIGHT_BLUE
    for i: int = 0; i < EASE_COUNT; i += 1 {
        ease_x[i] = 250
        ease_tweens[i] = tw.TweenMake()
        tw.TweenProperty(&ease_tweens[i], &ease_x[i], 900, 1.5, ease_list[i])
        tw.TweenInterval(&ease_tweens[i], 0.3)
        tw.TweenProperty(&ease_tweens[i], &ease_x[i], 250, 0.6, .Quadratic_In_Out)
        tw.TweenSetLoops(&ease_tweens[i], 0)
        tw.TweenPlay(&ease_tweens[i])
    }
}

process_ease :: proc() {
    delta_time: f32 = karl2d.get_frame_time()
    for i: int = 0; i < EASE_COUNT; i += 1 {
        tw.TweenUpdate(&ease_tweens[i], delta_time)
    }
}

draw_ease :: proc() {
    for i: int = 0; i < EASE_COUNT; i += 1 {
        y: f32 = 80 + cast(f32)i * 50
        karl2d.draw_text(ease_names[i], {20, y}, 20, karl2d.DARK_GRAY)
        karl2d.draw_line({250, y + 10}, {900, y + 10}, 1, karl2d.LIGHT_GRAY)
        karl2d.draw_circle({ease_x[i], y + 10}, 10, karl2d.RL_SKYBLUE)
    }
    karl2d.draw_text("chained steps (ease, interval, return) with infinite loops", {10, 10}, 20, karl2d.BLACK)
}
