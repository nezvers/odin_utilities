#+build !js
package demo_kit_karl2d

import "core:os"

// the exit code of a test run: 0 when every check passed
@(private)
exit_process :: proc(passed: bool) {
    os.exit(0 if passed else 1)
}
