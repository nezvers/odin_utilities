#+build !js
// Tests of example.odin. They are in their own file when the library builds for the web (core:testing does not compile for
// js_wasm32), otherwise they go to the bottom of the file they test.
package example

import "core:testing"

@(test)
test_counter_stops_at_its_limit :: proc(t: ^testing.T) {
    counter: Counter
    CounterInit(&counter, 5)
    testing.expect_value(t, CounterAdd(&counter, 3), 3)
    testing.expect_value(t, CounterAdd(&counter, 3), 2)
    testing.expect(t, CounterIsFull(&counter))
    testing.expect_value(t, CounterAdd(&counter, -9), -5)
}
