package sprite

import "core:math"
import "core:testing"


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

// --- Tests ---

@(test)
test_oscillator_property :: proc(t: ^testing.T) {
    osc: Oscillator = {time_scale = 1, amplitude = 2, offset = 10}
    testing.expect(t, abs(OscilateProperty(&osc, 0.25) - 12) < 1e-4, "starts at the top of the cosine")
    testing.expect(t, abs(OscilateProperty(&osc, 0.25) - 10) < 1e-4, "a quarter period later it is back on the offset")
    testing.expect(t, abs(OscilateProperty(&osc, 0.25) - 8) < 1e-4, "and then on the bottom")

    osc.t = 0.9
    OscilateProperty(&osc, 0.3)
    testing.expect(t, osc.t >= 0 && osc.t < 1 && abs(osc.t - 0.2) < 1e-4, "the phase wraps around")

    shifted: Oscillator = {time_scale = 1, amplitude = 1, phase = 0.25}                    // a quarter turn ahead
    testing.expect(t, abs(OscilateProperty(&shifted, 0)) < 1e-4)
}

@(test)
test_oscillator_2d_uses_cos_and_sin :: proc(t: ^testing.T) {
    osc: Oscillator2D = {{time_scale = 1, amplitude = 4}, {amplitude = 3}}
    start: vec2 = OscilateProperty2D(&osc, 0.25)
    testing.expect(t, abs(start.x - 4) < 1e-4 && abs(start.y) < 1e-4)
    later: vec2 = OscilateProperty2D(&osc, 0.25)                                           // a quarter period: cos is 0, sin is 1
    testing.expect(t, abs(later.x) < 1e-4 && abs(later.y - 3) < 1e-4)
    testing.expect(t, abs(osc[0].t - 0.5) < 1e-4, "only the first oscillator keeps the time")
    testing.expect_value(t, osc[1].t, f32(0))
}
