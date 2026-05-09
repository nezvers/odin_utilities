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

// Use only first t & time_scale
Oscillator2D :: [2]Oscillator


OscillatorSprite :: struct {
    position: Oscillator2D,
    origin: Oscillator2D,
    offset: Oscillator2D,
    scale: Oscillator2D,
    rotation: Oscillator,
}

OscilateProperty :: proc(osc: ^Oscillator, delta_time: f32)->(value:f32) {
    _cos: = math.cos(osc.t * math.TAU + osc.phase * math.TAU)
    value = _cos * osc.amplitude + osc.offset
    osc.t += delta_time * osc.time_scale
    osc.t -= math.floor(osc.t)
    return
}

OscilateProperty2D :: proc(osc: ^Oscillator2D, delta_time: f32)->(value: vec2) {
    t:f32 = osc[0].t
    _cos: = math.cos(t * math.TAU + osc[0].phase * math.TAU)
    _sin: = math.sin(t * math.TAU + osc[1].phase * math.TAU)

    value.x = _cos * osc[0].amplitude + osc[0].offset
    value.y = _sin * osc[1].amplitude + osc[1].offset

    osc[0].t += delta_time * osc[0].time_scale
    osc[0].t -= math.floor(osc[0].t)
    return
}