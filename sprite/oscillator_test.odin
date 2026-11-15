#+build !js
// Tests of oscillator.odin. They are in their own file because the library is used by games with a web build, and core:testing does not
// compile for js_wasm32.
package sprite

import "core:testing"

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
