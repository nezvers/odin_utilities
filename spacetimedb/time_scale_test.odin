#+build !js
package spacetimedb

import "core:testing"
import "core:time"
import "../wait_for"

// The timeouts that depend on the speed of the device follow ODIN_SLOW (a slower device needs more time for the same thing)
@(test)
test_the_timeouts_follow_the_time_scale :: proc(t: ^testing.T) {
    testing.expect_value(t, TimeScale, wait_for.Scale())                      // the program picked up the environment variable
    testing.expect_value(t, scaledBy(5 * time.Second, 1), 5 * time.Second)
    testing.expect_value(t, scaledBy(5 * time.Second, 3), 15 * time.Second)
    testing.expect_value(t, scaledBy(10 * time.Second, 2.5), 25 * time.Second)
    testing.expect_value(t, scaledBy(5 * time.Second, 0.2), 5 * time.Second)  // never shorter
    testing.expect_value(t, scaledBy(5 * time.Second, 0), 5 * time.Second)
    testing.expect_value(t, Scaled(10 * time.Second), scaledBy(10 * time.Second, wait_for.Scale()))
}
