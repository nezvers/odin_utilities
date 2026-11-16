#+build !js
package options

import "core:testing"
import kit "../../../demo_kit"

// The page against the real background logic, with simulated clicks and no window
@(test)
test_options_script :: proc(t: ^testing.T) {
	OptionsLoopbackInit(true)
	state: kit.HeadlessState
	backend: kit.Backend
	kit.HeadlessInit(&backend, &state)
	report: kit.Report = kit.TestDemo(demo, &backend)
	for failure in report.failures[:min(report.failed, kit.MAX_FAILURES)] {
		testing.expectf(t, false, "frame %d: %s", failure.frame, failure.message)
	}
	testing.expect(t, report.finished, "the script reached its end")
	testing.expect(t, report.draw_calls > 0, "something was drawn")

	// a page that has no list yet and the first reply: nothing crashes, the empty state is shown. Same test: the page is a global, tests run in threads
	OptionsLoopbackInit(false)
	OptionsOnReply("list\n")
	testing.expect_value(t, page.count, 0)
	OptionsOnReply("list\nbad line\naaaaaaaaaaa\tok\n")
	testing.expect_value(t, page.count, 1)
}
