package sprite

import "core:math"


// vec2 animation with sin & cos
Oscillator :: struct {
    t: f32, // t += delta_time * timescale
    time_scale: f32,
    phase: f32, // phase * TAU // TAU is (2 * PI)
    amplitude: f32,
    offset: f32, // shifts the result
}
Oscillator2D :: [2]Oscillator


OscillatorSprite :: struct {
    position: Oscillator2D,
    origin: Oscillator2D,
    offset: Oscillator2D,
    scale: Oscillator2D,
    rotation: Oscillator,
}

OscilateProperty :: proc(osc: ^Oscillator, delta_time: f32)->(value:f32) {
    _cos: = math.cos(osc.t * osc.time_scale * math.TAU + osc.phase * math.TAU)
    value = _cos * osc.amplitude + osc.offset
    osc.t += delta_time
    return
}

OscilateProperty2D :: proc(osc: ^Oscillator2D, delta_time: f32)->(value: vec2) {
    osc[1].t = osc[0].t
    value.x = OscilateProperty(&osc[0], delta_time)
    value.y = OscilateProperty(&osc[1], delta_time)
    return
}