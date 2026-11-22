#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "core:testing"
import "core:time"
import "../wait_for"

// The timeouts of the requests follow ODIN_SLOW (a slower device needs more time for the same thing)
@(test)
test_the_timeout_of_a_request_follows_the_time_scale :: proc(t: ^testing.T) {
    testing.expect_value(t, TimeScale, wait_for.Scale())                      // the program picked up the environment variable
    testing.expect_value(t, timeoutScaled(15 * time.Second, 1), 15 * time.Second)
    testing.expect_value(t, timeoutScaled(15 * time.Second, 4), 60 * time.Second)
    testing.expect_value(t, timeoutScaled(15 * time.Second, 0.5), 15 * time.Second)
    testing.expect_value(t, requestTimeout(), timeoutScaled(HTTP_TIMEOUT, wait_for.Scale()))
}
