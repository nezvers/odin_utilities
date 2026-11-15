package example_raylib

// Glue for raylib: only what needs raylib (drawing, loading). The core does not know this package.
// Name: <lib>_raylib.odin, package <lib>_raylib. Remove the folder when a library has no drawing.

import rl "vendor:raylib"
import example ".."

DrawCounter :: proc(counter: ^example.Counter, position: [2]f32, width: f32, color: rl.Color) {
    rl.DrawRectangleV(position, {width, 12}, rl.LIGHTGRAY)
    rl.DrawRectangleV(position, {width * f32(counter.value) / f32(counter.limit), 12}, color)
}
