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

// A click the way a window delivers it: the runner is not playing a script, the device gives the input of each frame (a press, a few frames held, a release), and the demo menu of the kit
// is on. Nodes of the graph demo are selected by it.
@(private = "file")
Device :: struct {
    position: kit.Vec2,
    down: bool,
    pressed: bool,
    released: bool,
}

@(private = "file")
device: Device

@(test)
test_a_click_from_a_device_selects_a_node_of_the_graph_demo :: proc(t: ^testing.T) {
    state: kit.HeadlessState
    backend: kit.Backend
    kit.HeadlessInit(&backend, &state)
    backend.begin_frame = proc(backend: ^kit.Backend, input: ^kit.Input) -> (running: bool, delta_time: f32) {
        input^ = {mouse_position = device.position}
        if device.down { input.mouse_down += {.LEFT} }
        if device.pressed { input.mouse_pressed += {.LEFT} }
        if device.released { input.mouse_released += {.LEFT} }
        device.pressed, device.released = false, false
        return true, 1.0 / 60
    }
    graph_index: int = -1
    for demo, i in demos {
        if demo.name == "graph" { graph_index = i }
    }
    testing.expect(t, graph_index >= 0)
    runner: kit.Runner
    kit.RunnerInit(&runner, demos, &backend, graph_index)
    defer kit.RunnerShutdown(&runner)
    device = {position = {600, 400}}
    for _ in 0 ..< 6 { kit.RunnerStep(&runner) }
    selected, title := graphSelectedForTest()
    testing.expect_value(t, selected, 0)
    device.position = title
    for _ in 0 ..< 3 { kit.RunnerStep(&runner) }
    device.down, device.pressed = true, true
    kit.RunnerStep(&runner)
    for _ in 0 ..< 6 { kit.RunnerStep(&runner) }
    device.down, device.released = false, true
    kit.RunnerStep(&runner)
    for _ in 0 ..< 3 { kit.RunnerStep(&runner) }
    selected, _ = graphSelectedForTest()
    testing.expect_value(t, selected, 1)
}
