#+private file
package game

import "core:fmt"
import "../../../karl2d"
Rect :: karl2d.Rect

import sp "../.."
// import glue "../../karl2d"

import "core:math"
PI :: math.PI

@(private="package")
oscillator_state: GameState = {
    init,
    finit,
    process,
    draw,
}

osc: sp.Oscillator2D
osc_slider_state: sp.Oscillator2D

init :: proc() {
    background_color = karl2d.WHITE
}

finit :: proc() {
}

process :: proc() {
}

draw :: proc() {
    ZOOM :: 8
    camera:karl2d.Camera
    camera.zoom = ZOOM
    karl2d.set_camera(camera)

    pixel: Rect = {32, 32, 1, 1}
    off:Vec2 = sp.OscilateProperty2D(&osc, karl2d.get_frame_time())
    pixel.x += off.x
    pixel.y += off.y
    karl2d.draw_rect(pixel, karl2d.ORANGE)
    
    karl2d.set_camera(nil)

    mouse: = get_local_mouse_position()
    is_held:bool = karl2d.mouse_button_is_held(.Left)
    SLIDER_X :: 100
    SLIDER_Y :: 34
    SLIDER_W :: 50
    SLIDER_H :: 6
    SLIDER_INC_X :: SLIDER_W + 2
    SLIDER_INC_Y :: SLIDER_H + 2
    slider_rect:Rect = {SLIDER_X * ZOOM, SLIDER_Y * ZOOM, SLIDER_W * ZOOM, SLIDER_H * ZOOM}

    if Slider(&osc_slider_state[0].time_scale, &osc[0].time_scale, 0, 6, slider_rect, mouse, is_held, fmt.tprintf("time scale = %.2v", osc[0].time_scale)) {
        osc[0].time_scale = math.round(osc[0].time_scale * 10) * 0.1
        if is_held {reset_oscillator(&osc)}
        if karl2d.key_went_down(.Left_Control) {
            osc[0].time_scale = 0
        }
    }
    slider_rect.y += SLIDER_INC_Y * ZOOM

    if Slider(&osc_slider_state[0].amplitude, &osc[0].amplitude, 0, 16, slider_rect, mouse, is_held, fmt.tprintf("amplitude = %.2v", osc[0].amplitude)) {
        if is_held {reset_oscillator(&osc)}
        if karl2d.key_went_down(.Left_Control) {
            osc[0].amplitude = 0
        }
    }
    slider_rect.y += SLIDER_INC_Y * ZOOM

    if Slider(&osc_slider_state[0].phase, &osc[0].phase, -math.PI, math.PI, slider_rect, mouse, is_held, fmt.tprintf("phase = %.2v", osc[0].phase)) {
        if is_held {reset_oscillator(&osc)}
        if karl2d.key_went_down(.Left_Control) {
            osc[0].phase = 0
        }
    }
    slider_rect.y += SLIDER_INC_Y * ZOOM

    if Slider(&osc_slider_state[0].offset, &osc[0].offset, -16, 16, slider_rect, mouse, is_held, fmt.tprintf("offset = %.2v", osc[0].offset)) {
        if is_held {reset_oscillator(&osc)}
        if karl2d.key_went_down(.Left_Control) {
            osc[0].offset = 0
        }
    }
    slider_rect.y += SLIDER_INC_Y * ZOOM

    // SECOND COLUMN
    slider_rect.x += (SLIDER_INC_X) * ZOOM
    slider_rect.y = (SLIDER_Y) * ZOOM

    if Slider(&osc_slider_state[1].time_scale, &osc[1].time_scale, 0, 6, slider_rect, mouse, is_held, fmt.tprintf("time scale = %.2v", osc[1].time_scale)) {
        osc[1].time_scale = math.round(osc[0].time_scale * 10) * 0.1
        if is_held {reset_oscillator(&osc)}
        if karl2d.key_went_down(.Left_Control) {
            osc[1].time_scale = 0
        }
    }
    slider_rect.y += SLIDER_INC_Y * ZOOM

    if Slider(&osc_slider_state[1].amplitude, &osc[1].amplitude, 0, 16, slider_rect, mouse, is_held, fmt.tprintf("amplitude = %.2v", osc[1].amplitude)) {
        if is_held {reset_oscillator(&osc)}
        if karl2d.key_went_down(.Left_Control) {
            osc[1].amplitude = 0
        }
    }
    slider_rect.y += SLIDER_INC_Y * ZOOM

    if Slider(&osc_slider_state[1].phase, &osc[1].phase, -math.PI, math.PI, slider_rect, mouse, is_held, fmt.tprintf("phase = %.2v", osc[1].phase)) {
        if is_held {reset_oscillator(&osc)}
        if karl2d.key_went_down(.Left_Control) {
            osc[1].phase = 0
        }
    }
    slider_rect.y += SLIDER_INC_Y * ZOOM

    if Slider(&osc_slider_state[1].offset, &osc[1].offset, -16, 16, slider_rect, mouse, is_held, fmt.tprintf("offset = %.2v", osc[1].offset)) {
        if is_held {reset_oscillator(&osc)}
        if karl2d.key_went_down(.Left_Control) {
            osc[1].offset = 0
        }
    }
    slider_rect.y += SLIDER_INC_Y * ZOOM
}

reset_oscillator :: proc(o: ^sp.Oscillator2D) {
    o[0].t = 0
    o[1].t = 0
}
