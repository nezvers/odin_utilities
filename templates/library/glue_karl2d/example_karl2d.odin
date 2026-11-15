package example_karl2d

// Glue for Karl2D, the same as raylib/ for the other framework. Karl2D is odin_utilities/karl2d, a junction to the fork.

import "../../karl2d"
import example ".."

DrawCounter :: proc(counter: ^example.Counter, position: [2]f32, width: f32, color: karl2d.Color) {
    karl2d.draw_rect({position.x, position.y, width, 12}, karl2d.LIGHT_GRAY)
    karl2d.draw_rect({position.x, position.y, width * f32(counter.value) / f32(counter.limit), 12}, color)
}
