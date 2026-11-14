// What the demo executables give to the demo game DLL, and the build helper they share.
// The DLL draws through this table, so it never shares the state of raylib or karl2d.
package demo_game_api

import "core:fmt"
import "core:os"

Vec2 :: [2]f32
Rect :: [4]f32     // x, y, width, height
Color :: [4]u8

Host :: struct {
    draw_rect: proc(rect: Rect, color: Color),
    draw_text: proc(text: string, position: Vec2, size: f32, color: Color),
    frame_time: proc() -> f32,
    screen_size: proc() -> Vec2,
    // Optional, called by the game every frame so a test can follow the game memory
    report: proc(counter: int),
}

GAME_DIRECTORY :: #directory + "/.."

// Build the demo game as a DLL. Returns false when the compiler fails, the message goes to stderr
BuildGameDll :: proc(dll_path: string, defines: ..string) -> bool {
    command: [dynamic]string
    defer delete(command)
    append(&command, "odin", "build", GAME_DIRECTORY, "-build-mode:dll", fmt.tprintf("-out:%s", dll_path))
    append(&command, ..defines)

    state, _, errors, err := os.process_exec({command = command[:]}, context.allocator)
    defer delete(errors)
    if err != nil || state.exit_code != 0 {
        fmt.eprintfln("Building the demo game failed:\n%s", string(errors))
        return false
    }
    return true
}
