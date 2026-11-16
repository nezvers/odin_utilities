package demo_kit_karl2d

// The Karl2D backend of demo_kit. `Run` opens a window and runs the demos of a library until it is closed:
//
//     main :: proc() { kit_karl2d.Run("tween", demo_common.demos[:]) }
//
// Karl2D has to be next to the other libraries (odin_utilities/karl2d, a junction to the fork).

import "base:runtime"
import "../../karl2d"
import kit ".."

MAX_TEXTURES :: 64
MAX_SOUNDS :: 64
MAX_FONTS :: 8

State :: struct {
    textures: [MAX_TEXTURES]karl2d.Texture,
    texture_count: u32,
    sounds: [MAX_SOUNDS]karl2d.Audio_Clip,
    sound_count: u32,
    fonts: [MAX_FONTS]karl2d.Font,
    font_count: u32,
    last_mouse: kit.Vec2,
}

// `options` is what Karl2D is started with: a demo of the 3D layer of the fork needs depth_test = true
Run :: proc(title: string, demos: []kit.Demo, width: int = 1280, height: int = 720, options: karl2d.Init_Options = {window_mode = .Windowed_Resizable}) {
    run_options: karl2d.Init_Options = options
    // reading the screen back is a function of the 3D layer of the fork, which needs the depth buffer
    when kit.DEMO_CAPTURE { run_options.depth_test = true }
    karl2d.init(width, height, title, options = run_options)
    when kit.DEMO_CAPTURE { karl2d.r3d_init() }
    state: State
    backend: kit.Backend
    Init(&backend, &state)
    when kit.DEMO_TEST {
        passed: bool = kit.RunTests(demos, &backend)
        backend.shutdown(&backend)
        exit_process(passed)
    } else {
        runner: kit.Runner
        kit.Run(&runner, demos, &backend)
    }
}

// Fill a Backend with the Karl2D procs. Karl2D has to be initialized. `state` has to live as long as the backend.
Init :: proc(backend: ^kit.Backend, state: ^State) {
    state.last_mouse = karl2d.get_mouse_position()
    backend^ = {
        name = "karl2d",
        state = state,
        begin_frame = beginFrame,
        end_frame = proc(backend: ^kit.Backend) { karl2d.present() },
        shutdown = proc(backend: ^kit.Backend) { karl2d.shutdown() },
        screen_size = proc(backend: ^kit.Backend) -> kit.Vec2 { return {f32(karl2d.get_screen_width()), f32(karl2d.get_screen_height())} },
        clear = proc(backend: ^kit.Backend, color: kit.Color) { karl2d.clear(color) },
        draw_rect = proc(backend: ^kit.Backend, rect: kit.Rect, color: kit.Color) {
            karl2d.draw_rect(transmute(karl2d.Rect)rect, color)
        },
        draw_rect_outline = proc(backend: ^kit.Backend, rect: kit.Rect, thickness: f32, color: kit.Color) {
            karl2d.draw_rect_outline(transmute(karl2d.Rect)rect, thickness, color)
        },
        draw_line = proc(backend: ^kit.Backend, from: kit.Vec2, to: kit.Vec2, thickness: f32, color: kit.Color) {
            karl2d.draw_line(from, to, thickness, color)
        },
        draw_circle = proc(backend: ^kit.Backend, center: kit.Vec2, radius: f32, color: kit.Color) {
            karl2d.draw_circle(center, radius, color, 36)
        },
        draw_circle_outline = proc(backend: ^kit.Backend, center: kit.Vec2, radius: f32, thickness: f32, color: kit.Color) {
            karl2d.draw_circle_outline(center, radius, thickness, color, 36)
        },
        draw_triangle = proc(backend: ^kit.Backend, a: kit.Vec2, b: kit.Vec2, c: kit.Vec2, color: kit.Color) {
            karl2d.draw_triangle({a, b, c}, color)
        },
        draw_text = proc(backend: ^kit.Backend, text: string, position: kit.Vec2, size: f32, color: kit.Color) {
            karl2d.draw_text(text, position, size, color)
        },
        measure_text = proc(backend: ^kit.Backend, text: string, size: f32) -> kit.Vec2 {
            return karl2d.measure_text(text, size)
        },
        font_load = proc(backend: ^kit.Backend, bytes: []u8, size: f32, glyph_count: int) -> kit.Font {
            state: ^State = cast(^State)backend.state
            if state.font_count + 1 >= MAX_FONTS { return kit.FONT_DEFAULT }
            // a dynamic font makes the glyphs it needs when they are drawn: any language works
            font, ok := karl2d.load_dynamic_font_from_bytes(bytes)
            if !ok { return kit.FONT_DEFAULT }
            state.font_count += 1
            state.fonts[state.font_count] = font
            return kit.Font(state.font_count)
        },
        font_unload = proc(backend: ^kit.Backend, font: kit.Font) {
            state: ^State = cast(^State)backend.state
            if u32(font) == 0 || u32(font) > state.font_count { return }
            karl2d.destroy_font(state.fonts[font])
            state.fonts[font] = {}
        },
        draw_text_font = proc(backend: ^kit.Backend, font: kit.Font, text: string, position: kit.Vec2, size: f32, color: kit.Color) {
            state: ^State = cast(^State)backend.state
            face: karl2d.Font = karl2d.FONT_DEFAULT
            if u32(font) != 0 && u32(font) <= state.font_count { face = state.fonts[font] }
            karl2d.draw_text(text, position, size, color, face)
        },
        texture_load = proc(backend: ^kit.Backend, bytes: []u8) -> kit.Texture {
            state: ^State = cast(^State)backend.state
            if state.texture_count + 1 >= MAX_TEXTURES { return kit.TEXTURE_NONE }
            texture, ok := karl2d.load_texture_from_bytes(bytes)
            if !ok { return kit.TEXTURE_NONE }
            state.texture_count += 1
            state.textures[state.texture_count] = texture
            return kit.Texture(state.texture_count)
        },
        texture_from_pixels = proc(backend: ^kit.Backend, width: int, height: int, rgba: []u8) -> kit.Texture {
            state: ^State = cast(^State)backend.state
            if state.texture_count + 1 >= MAX_TEXTURES { return kit.TEXTURE_NONE }
            texture, ok := karl2d.create_texture(width, height, .RGBA_8_Norm)
            if !ok { return kit.TEXTURE_NONE }
            karl2d.update_texture(texture, rgba, {0, 0, f32(width), f32(height)})
            state.texture_count += 1
            state.textures[state.texture_count] = texture
            return kit.Texture(state.texture_count)
        },
        texture_unload = proc(backend: ^kit.Backend, texture: kit.Texture) {
            state: ^State = cast(^State)backend.state
            if u32(texture) == 0 || u32(texture) > state.texture_count { return }
            karl2d.destroy_texture(state.textures[texture])
            state.textures[texture] = {}
        },
        texture_size = proc(backend: ^kit.Backend, texture: kit.Texture) -> kit.Vec2 {
            state: ^State = cast(^State)backend.state
            if u32(texture) == 0 || u32(texture) > state.texture_count { return {} }
            return {f32(karl2d.get_texture_width(state.textures[texture])), f32(karl2d.get_texture_height(state.textures[texture]))}
        },
        texture_draw = proc(backend: ^kit.Backend, texture: kit.Texture, source: kit.Rect, destination: kit.Rect, origin: kit.Vec2, rotation: f32, tint: kit.Color) {
            state: ^State = cast(^State)backend.state
            if u32(texture) == 0 || u32(texture) > state.texture_count { return }
            karl2d.draw_texture_fit(state.textures[texture], transmute(karl2d.Rect)source, transmute(karl2d.Rect)destination, origin, rotation * (3.14159265 / 180), tint)
        },
        mouse_capture = proc(backend: ^kit.Backend, captured: bool) {
            karl2d.set_mouse_locked(captured)
            karl2d.set_cursor_hidden(captured)
        },
        camera_begin = proc(backend: ^kit.Backend, camera: kit.Camera) {
            karl2d.set_camera(karl2d.Camera{target = camera.target, offset = camera.offset, rotation = camera.rotation * (3.14159265 / 180), zoom = camera.zoom})
        },
        camera_end = proc(backend: ^kit.Backend) { karl2d.set_camera(nil) },
        clip_begin = proc(backend: ^kit.Backend, rect: kit.Rect) { karl2d.set_scissor_rect(transmute(karl2d.Rect)rect) },
        clip_end = proc(backend: ^kit.Backend) { karl2d.set_scissor_rect(nil) },
        capture = proc(backend: ^kit.Backend, allocator: runtime.Allocator) -> (rgba: []u8, width: int, height: int) {
            when kit.DEMO_CAPTURE {
                pixels, w, h, ok := karl2d.r3d_read_pixels({}, allocator)
                if ok { return pixels, w, h }
            }
            return nil, 0, 0
        },
        sound_load = proc(backend: ^kit.Backend, bytes: []u8) -> kit.Sound {
            state: ^State = cast(^State)backend.state
            if state.sound_count + 1 >= MAX_SOUNDS { return kit.SOUND_NONE }
            clip, ok := karl2d.load_audio_clip_from_bytes(bytes)
            if !ok { return kit.SOUND_NONE }
            state.sound_count += 1
            state.sounds[state.sound_count] = clip
            return kit.Sound(state.sound_count)
        },
        sound_unload = proc(backend: ^kit.Backend, sound: kit.Sound) {
            state: ^State = cast(^State)backend.state
            if u32(sound) == 0 || u32(sound) > state.sound_count { return }
            karl2d.destroy_audio_clip(state.sounds[sound])
            state.sounds[sound] = {}
        },
        sound_play = proc(backend: ^kit.Backend, sound: kit.Sound, volume: f32, pitch: f32) {
            state: ^State = cast(^State)backend.state
            if u32(sound) == 0 || u32(sound) > state.sound_count { return }
            karl2d.play_audio_clip(state.sounds[sound], volume, 0, pitch)
        },
    }
}

@(private)
beginFrame :: proc(backend: ^kit.Backend, input: ^kit.Input) -> (running: bool, delta_time: f32) {
    state: ^State = cast(^State)backend.state
    if !karl2d.update() { return false, 0 }
    input^ = {}
    for key in kit.Key {
        karl2d_key: karl2d.Keyboard_Key = keys[key]
        if key == .None || karl2d_key == .None { continue }
        if karl2d.key_is_held(karl2d_key) { input.keys_down += {key} }
        if karl2d.key_went_down(karl2d_key) { input.keys_pressed += {key} }
        if karl2d.key_went_up(karl2d_key) { input.keys_released += {key} }
    }
    mouse_buttons: [kit.MouseButton]karl2d.Mouse_Button = {.LEFT = .Left, .RIGHT = .Right, .MIDDLE = .Middle}
    for button in kit.MouseButton {
        if karl2d.mouse_button_is_held(mouse_buttons[button]) { input.mouse_down += {button} }
        if karl2d.mouse_button_went_down(mouse_buttons[button]) { input.mouse_pressed += {button} }
        if karl2d.mouse_button_went_up(mouse_buttons[button]) { input.mouse_released += {button} }
    }
    input.mouse_position = karl2d.get_mouse_position()
    input.mouse_delta = karl2d.get_mouse_delta()
    state.last_mouse = input.mouse_position
    for event in karl2d.get_events() {
        #partial switch e in event {
        case karl2d.Event_Mouse_Wheel:
            input.mouse_wheel += e.delta
        case karl2d.Event_Typed_Rune:
            if e.typed > 0 && e.typed < 128 && int(input.text_count) < kit.TEXT_CAPACITY {
                input.text[input.text_count] = u8(e.typed)
                input.text_count += 1
            }
        }
    }
    return true, karl2d.get_frame_time()
}

@(private)
keys: [kit.Key]karl2d.Keyboard_Key = {
    .None = .None,
    .A = .A, .B = .B, .C = .C, .D = .D, .E = .E, .F = .F, .G = .G, .H = .H, .I = .I, .J = .J, .K = .K, .L = .L, .M = .M,
    .N = .N, .O = .O, .P = .P, .Q = .Q, .R = .R, .S = .S, .T = .T, .U = .U, .V = .V, .W = .W, .X = .X, .Y = .Y, .Z = .Z,
    .N0 = .N0, .N1 = .N1, .N2 = .N2, .N3 = .N3, .N4 = .N4, .N5 = .N5, .N6 = .N6, .N7 = .N7, .N8 = .N8, .N9 = .N9,
    .SPACE = .Space, .ENTER = .Enter, .ESCAPE = .Escape, .TAB = .Tab, .BACKSPACE = .Backspace, .DELETE = .Delete, .INSERT = .Insert,
    .LEFT = .Left, .RIGHT = .Right, .UP = .Up, .DOWN = .Down,
    .HOME = .Home, .END = .End, .PAGE_UP = .Page_Up, .PAGE_DOWN = .Page_Down,
    .LEFT_SHIFT = .Left_Shift, .RIGHT_SHIFT = .Right_Shift, .LEFT_CTRL = .Left_Control, .RIGHT_CTRL = .Right_Control,
    .LEFT_ALT = .Left_Alt, .RIGHT_ALT = .Right_Alt,
    .COMMA = .Comma, .PERIOD = .Period, .MINUS = .Minus, .EQUAL = .Equal, .SLASH = .Slash,
    .LEFT_BRACKET = .Left_Bracket, .RIGHT_BRACKET = .Right_Bracket,
    .F1 = .F1, .F2 = .F2, .F3 = .F3, .F4 = .F4, .F5 = .F5, .F6 = .F6, .F7 = .F7, .F8 = .F8, .F9 = .F9, .F10 = .F10, .F11 = .F11, .F12 = .F12,
}
