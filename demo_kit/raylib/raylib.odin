package demo_kit_raylib

// The raylib backend of demo_kit. `Run` opens a window and runs the demos of a library until it is closed:
//
//     main :: proc() { kit_raylib.Run("tween", demo_common.demos[:]) }

import "core:os"
import "core:strings"
import rl "vendor:raylib"
import kit ".."

MAX_TEXTURES :: 64
MAX_SOUNDS :: 64

State :: struct {
    textures: [MAX_TEXTURES]rl.Texture2D,
    texture_count: u32,
    sounds: [MAX_SOUNDS]rl.Sound,
    sound_count: u32,
    last_mouse: kit.Vec2,
}

// Open a window and run. Escape closes it.
Run :: proc(title: string, demos: []kit.Demo, width: i32 = 1280, height: i32 = 720) {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(width, height, strings.clone_to_cstring(title, context.temp_allocator))
    rl.InitAudioDevice()
    rl.SetTargetFPS(60)
    rl.SetExitKey(.KEY_NULL)        // the runner closes on escape, like with the other backends

    state: State
    backend: kit.Backend
    Init(&backend, &state)
    when kit.DEMO_TEST {
        passed: bool = kit.RunTests(demos, &backend)
        backend.shutdown(&backend)
        os.exit(0 if passed else 1)
    } else {
        runner: kit.Runner
        kit.Run(&runner, demos, &backend)
    }
}

// Fill a Backend with the raylib procs. The window has to be open. `state` has to live as long as the backend.
Init :: proc(backend: ^kit.Backend, state: ^State) {
    state.last_mouse = rl.GetMousePosition()
    backend^ = {
        name = "raylib",
        state = state,
        begin_frame = beginFrame,
        end_frame = proc(backend: ^kit.Backend) { rl.EndDrawing() },
        shutdown = shutdown,
        screen_size = proc(backend: ^kit.Backend) -> kit.Vec2 { return {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())} },
        clear = proc(backend: ^kit.Backend, color: kit.Color) { rl.ClearBackground(rl.Color(color)) },
        draw_rect = proc(backend: ^kit.Backend, rect: kit.Rect, color: kit.Color) {
            rl.DrawRectangleRec(transmute(rl.Rectangle)rect, rl.Color(color))
        },
        draw_rect_outline = proc(backend: ^kit.Backend, rect: kit.Rect, thickness: f32, color: kit.Color) {
            rl.DrawRectangleLinesEx(transmute(rl.Rectangle)rect, thickness, rl.Color(color))
        },
        draw_line = proc(backend: ^kit.Backend, from: kit.Vec2, to: kit.Vec2, thickness: f32, color: kit.Color) {
            rl.DrawLineEx(from, to, thickness, rl.Color(color))
        },
        draw_circle = proc(backend: ^kit.Backend, center: kit.Vec2, radius: f32, color: kit.Color) {
            rl.DrawCircleV(center, radius, rl.Color(color))
        },
        draw_circle_outline = proc(backend: ^kit.Backend, center: kit.Vec2, radius: f32, thickness: f32, color: kit.Color) {
            rl.DrawRing(center, max(radius - thickness, 0), radius, 0, 360, 36, rl.Color(color))
        },
        draw_triangle = drawTriangle,
        draw_text = proc(backend: ^kit.Backend, text: string, position: kit.Vec2, size: f32, color: kit.Color) {
            rl.DrawText(strings.clone_to_cstring(text, context.temp_allocator), i32(position.x), i32(position.y), i32(size), rl.Color(color))
        },
        measure_text = proc(backend: ^kit.Backend, text: string, size: f32) -> kit.Vec2 {
            return {f32(rl.MeasureText(strings.clone_to_cstring(text, context.temp_allocator), i32(size))), size}
        },
        texture_load = textureLoad,
        texture_unload = proc(backend: ^kit.Backend, texture: kit.Texture) {
            state: ^State = cast(^State)backend.state
            if u32(texture) == 0 || u32(texture) > state.texture_count { return }
            rl.UnloadTexture(state.textures[texture])
            state.textures[texture] = {}
        },
        texture_size = proc(backend: ^kit.Backend, texture: kit.Texture) -> kit.Vec2 {
            state: ^State = cast(^State)backend.state
            if u32(texture) == 0 || u32(texture) > state.texture_count { return {} }
            return {f32(state.textures[texture].width), f32(state.textures[texture].height)}
        },
        texture_draw = proc(backend: ^kit.Backend, texture: kit.Texture, source: kit.Rect, destination: kit.Rect, origin: kit.Vec2, rotation: f32, tint: kit.Color) {
            state: ^State = cast(^State)backend.state
            if u32(texture) == 0 || u32(texture) > state.texture_count { return }
            rl.DrawTexturePro(state.textures[texture], transmute(rl.Rectangle)source, transmute(rl.Rectangle)destination, origin, rotation, rl.Color(tint))
        },
        camera_begin = proc(backend: ^kit.Backend, camera: kit.Camera) {
            rl.BeginMode2D({offset = camera.offset, target = camera.target, rotation = camera.rotation, zoom = camera.zoom})
        },
        camera_end = proc(backend: ^kit.Backend) { rl.EndMode2D() },
        clip_begin = proc(backend: ^kit.Backend, rect: kit.Rect) {
            rl.BeginScissorMode(i32(rect.x), i32(rect.y), i32(rect.z), i32(rect.w))
        },
        clip_end = proc(backend: ^kit.Backend) { rl.EndScissorMode() },
        sound_load = soundLoad,
        sound_unload = proc(backend: ^kit.Backend, sound: kit.Sound) {
            state: ^State = cast(^State)backend.state
            if u32(sound) == 0 || u32(sound) > state.sound_count { return }
            rl.UnloadSound(state.sounds[sound])
            state.sounds[sound] = {}
        },
        sound_play = proc(backend: ^kit.Backend, sound: kit.Sound, volume: f32, pitch: f32) {
            state: ^State = cast(^State)backend.state
            if u32(sound) == 0 || u32(sound) > state.sound_count { return }
            rl.SetSoundVolume(state.sounds[sound], volume)
            rl.SetSoundPitch(state.sounds[sound], pitch)
            rl.PlaySound(state.sounds[sound])
        },
    }
}

@(private)
shutdown :: proc(backend: ^kit.Backend) {
    rl.CloseAudioDevice()
    rl.CloseWindow()
}

@(private)
beginFrame :: proc(backend: ^kit.Backend, input: ^kit.Input) -> (running: bool, delta_time: f32) {
    state: ^State = cast(^State)backend.state
    if rl.WindowShouldClose() { return false, 0 }
    input^ = {}
    for key in kit.Key {
        raylib_key: rl.KeyboardKey = keys[key]
        if key == .None || raylib_key == .KEY_NULL { continue }
        if rl.IsKeyDown(raylib_key) { input.keys_down += {key} }
        if rl.IsKeyPressed(raylib_key) { input.keys_pressed += {key} }
        if rl.IsKeyReleased(raylib_key) { input.keys_released += {key} }
    }
    mouse_buttons: [kit.MouseButton]rl.MouseButton = {.LEFT = .LEFT, .RIGHT = .RIGHT, .MIDDLE = .MIDDLE}
    for button in kit.MouseButton {
        if rl.IsMouseButtonDown(mouse_buttons[button]) { input.mouse_down += {button} }
        if rl.IsMouseButtonPressed(mouse_buttons[button]) { input.mouse_pressed += {button} }
        if rl.IsMouseButtonReleased(mouse_buttons[button]) { input.mouse_released += {button} }
    }
    input.mouse_position = rl.GetMousePosition()
    input.mouse_delta = input.mouse_position - state.last_mouse
    state.last_mouse = input.mouse_position
    input.mouse_wheel = rl.GetMouseWheelMove()
    for {
        character: rune = rl.GetCharPressed()
        if character == 0 { break }
        if character < 128 && int(input.text_count) < kit.TEXT_CAPACITY {
            input.text[input.text_count] = u8(character)
            input.text_count += 1
        }
    }
    rl.BeginDrawing()
    return true, rl.GetFrameTime()
}

// raylib wants the corners counter clockwise
@(private)
drawTriangle :: proc(backend: ^kit.Backend, a: kit.Vec2, b: kit.Vec2, c: kit.Vec2, color: kit.Color) {
    cross: f32 = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    if cross > 0 {
        rl.DrawTriangle(a, c, b, rl.Color(color))
    } else {
        rl.DrawTriangle(a, b, c, rl.Color(color))
    }
}

@(private)
textureLoad :: proc(backend: ^kit.Backend, bytes: []u8) -> kit.Texture {
    state: ^State = cast(^State)backend.state
    if state.texture_count + 1 >= MAX_TEXTURES { return kit.TEXTURE_NONE }
    image: rl.Image = rl.LoadImageFromMemory(fileType(bytes), raw_data(bytes), i32(len(bytes)))
    if image.data == nil { return kit.TEXTURE_NONE }
    defer rl.UnloadImage(image)
    state.texture_count += 1
    state.textures[state.texture_count] = rl.LoadTextureFromImage(image)
    return kit.Texture(state.texture_count)
}

@(private)
soundLoad :: proc(backend: ^kit.Backend, bytes: []u8) -> kit.Sound {
    state: ^State = cast(^State)backend.state
    if state.sound_count + 1 >= MAX_SOUNDS { return kit.SOUND_NONE }
    wave: rl.Wave = rl.LoadWaveFromMemory(fileType(bytes), raw_data(bytes), i32(len(bytes)))
    if wave.data == nil { return kit.SOUND_NONE }
    defer rl.UnloadWave(wave)
    state.sound_count += 1
    state.sounds[state.sound_count] = rl.LoadSoundFromWave(wave)
    return kit.Sound(state.sound_count)
}

// raylib decides by the extension, the bytes say it as well
@(private)
fileType :: proc(bytes: []u8) -> cstring {
    if len(bytes) >= 4 {
        if bytes[0] == 0x89 && bytes[1] == 'P' { return ".png" }
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return ".jpg" }
        if bytes[0] == 'B' && bytes[1] == 'M' { return ".bmp" }
        if bytes[0] == 'O' && bytes[1] == 'g' && bytes[2] == 'g' { return ".ogg" }
        if bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' { return ".wav" }
        if bytes[0] == 'I' && bytes[1] == 'D' && bytes[2] == '3' { return ".mp3" }
    }
    return ".png"
}

@(private)
keys: [kit.Key]rl.KeyboardKey = {
    .None = .KEY_NULL,
    .A = .A, .B = .B, .C = .C, .D = .D, .E = .E, .F = .F, .G = .G, .H = .H, .I = .I, .J = .J, .K = .K, .L = .L, .M = .M,
    .N = .N, .O = .O, .P = .P, .Q = .Q, .R = .R, .S = .S, .T = .T, .U = .U, .V = .V, .W = .W, .X = .X, .Y = .Y, .Z = .Z,
    .N0 = .ZERO, .N1 = .ONE, .N2 = .TWO, .N3 = .THREE, .N4 = .FOUR, .N5 = .FIVE, .N6 = .SIX, .N7 = .SEVEN, .N8 = .EIGHT, .N9 = .NINE,
    .SPACE = .SPACE, .ENTER = .ENTER, .ESCAPE = .ESCAPE, .TAB = .TAB, .BACKSPACE = .BACKSPACE, .DELETE = .DELETE, .INSERT = .INSERT,
    .LEFT = .LEFT, .RIGHT = .RIGHT, .UP = .UP, .DOWN = .DOWN,
    .HOME = .HOME, .END = .END, .PAGE_UP = .PAGE_UP, .PAGE_DOWN = .PAGE_DOWN,
    .LEFT_SHIFT = .LEFT_SHIFT, .RIGHT_SHIFT = .RIGHT_SHIFT, .LEFT_CTRL = .LEFT_CONTROL, .RIGHT_CTRL = .RIGHT_CONTROL,
    .LEFT_ALT = .LEFT_ALT, .RIGHT_ALT = .RIGHT_ALT,
    .COMMA = .COMMA, .PERIOD = .PERIOD, .MINUS = .MINUS, .EQUAL = .EQUAL, .SLASH = .SLASH,
    .LEFT_BRACKET = .LEFT_BRACKET, .RIGHT_BRACKET = .RIGHT_BRACKET,
    .F1 = .F1, .F2 = .F2, .F3 = .F3, .F4 = .F4, .F5 = .F5, .F6 = .F6, .F7 = .F7, .F8 = .F8, .F9 = .F9, .F10 = .F10, .F11 = .F11, .F12 = .F12,
}
