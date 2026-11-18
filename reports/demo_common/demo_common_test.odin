#+build !js
package demo_common

import "core:testing"
import kit "../../demo_kit"

// Every demo of the library with simulated input and its checks, without a window
@(test)
test_demos_run_their_scripts :: proc(t: ^testing.T) {
	state: kit.HeadlessState
	backend: kit.Backend
	kit.HeadlessInit(&backend, &state)
	for demo in demos {
		report: kit.Report = kit.TestDemo(demo, &backend)
		for failure in report.failures[:min(report.failed, kit.MAX_FAILURES)] {
			testing.expectf(t, false, "%s, frame %d: %s", demo.name, failure.frame, failure.message)
		}
		testing.expectf(t, report.finished, "%s: the script did not reach its end", demo.name)
		testing.expectf(t, report.draw_calls > 0, "%s: nothing was drawn", demo.name)
	}
}
