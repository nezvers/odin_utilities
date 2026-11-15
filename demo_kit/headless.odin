package demo_kit

// A backend with no window and no device: drawing is only counted, input comes from a Player. For tests: the demo code runs for real
// (init, update, draw) and a script checks what it did. Time is whatever the runner says (RunnerStep with fixed_delta).

HEADLESS_SCREEN :: Vec2{1280, 720}
HEADLESS_TEXTURES :: 64

HeadlessState :: struct {
    screen: Vec2,
    texture_sizes: [HEADLESS_TEXTURES]Vec2,     // read from the png header, the pixels are never decoded
    texture_count: u32,
    sounds_played: int,
    sounds_loaded: u32,
    fonts_loaded: u32,
}

// `state` has to live as long as the backend
HeadlessInit :: proc(backend: ^Backend, state: ^HeadlessState, screen: Vec2 = HEADLESS_SCREEN) {
    state^ = {screen = screen}
    backend^ = {
        name = "headless",
        state = state,
        headless = true,
        begin_frame = headlessBeginFrame,
        end_frame = proc(backend: ^Backend) {},
        shutdown = nil,
        screen_size = proc(backend: ^Backend) -> Vec2 { return (cast(^HeadlessState)backend.state).screen },
        clear = proc(backend: ^Backend, color: Color) {},
        draw_rect = proc(backend: ^Backend, rect: Rect, color: Color) {},
        draw_rect_outline = proc(backend: ^Backend, rect: Rect, thickness: f32, color: Color) {},
        draw_line = proc(backend: ^Backend, from: Vec2, to: Vec2, thickness: f32, color: Color) {},
        draw_circle = proc(backend: ^Backend, center: Vec2, radius: f32, color: Color) {},
        draw_circle_outline = proc(backend: ^Backend, center: Vec2, radius: f32, thickness: f32, color: Color) {},
        draw_triangle = proc(backend: ^Backend, a: Vec2, b: Vec2, c: Vec2, color: Color) {},
        draw_text = proc(backend: ^Backend, text: string, position: Vec2, size: f32, color: Color) {},
        measure_text = proc(backend: ^Backend, text: string, size: f32) -> Vec2 { return {f32(len(text)) * size * 0.5, size} },
        font_load = proc(backend: ^Backend, bytes: []u8, size: f32, glyph_count: int) -> Font {
            state: ^HeadlessState = cast(^HeadlessState)backend.state
            state.fonts_loaded += 1
            return Font(state.fonts_loaded)
        },
        font_unload = proc(backend: ^Backend, font: Font) {},
        draw_text_font = proc(backend: ^Backend, font: Font, text: string, position: Vec2, size: f32, color: Color) {},
        texture_load = headlessTextureLoad,
        texture_unload = proc(backend: ^Backend, texture: Texture) {},
        texture_size = headlessTextureSize,
        texture_draw = proc(backend: ^Backend, texture: Texture, source: Rect, destination: Rect, origin: Vec2, rotation: f32, tint: Color) {},
        mouse_capture = proc(backend: ^Backend, captured: bool) {},
        camera_begin = proc(backend: ^Backend, camera: Camera) {},
        camera_end = proc(backend: ^Backend) {},
        clip_begin = proc(backend: ^Backend, rect: Rect) {},
        clip_end = proc(backend: ^Backend) {},
        sound_load = proc(backend: ^Backend, bytes: []u8) -> Sound {
            state: ^HeadlessState = cast(^HeadlessState)backend.state
            state.sounds_loaded += 1
            return Sound(state.sounds_loaded)
        },
        sound_unload = proc(backend: ^Backend, sound: Sound) {},
        sound_play = proc(backend: ^Backend, sound: Sound, volume: f32, pitch: f32) {
            (cast(^HeadlessState)backend.state).sounds_played += 1
        },
    }
}

@(private)
headlessBeginFrame :: proc(backend: ^Backend, input: ^Input) -> (running: bool, delta_time: f32) {
    // the input is the Player's: a headless run has no devices
    return true, 1.0 / 60.0
}

@(private)
headlessTextureLoad :: proc(backend: ^Backend, bytes: []u8) -> Texture {
    state: ^HeadlessState = cast(^HeadlessState)backend.state
    if state.texture_count + 1 >= HEADLESS_TEXTURES { return TEXTURE_NONE }
    state.texture_count += 1
    size: Vec2 = {64, 64}
    // png: 8 bytes of signature, then the IHDR chunk, its width and height are big endian u32 at 16 and 20
    if len(bytes) >= 24 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G' {
        size.x = f32(u32(bytes[16]) << 24 | u32(bytes[17]) << 16 | u32(bytes[18]) << 8 | u32(bytes[19]))
        size.y = f32(u32(bytes[20]) << 24 | u32(bytes[21]) << 16 | u32(bytes[22]) << 8 | u32(bytes[23]))
    }
    state.texture_sizes[state.texture_count] = size
    return Texture(state.texture_count)
}

@(private)
headlessTextureSize :: proc(backend: ^Backend, texture: Texture) -> Vec2 {
    state: ^HeadlessState = cast(^HeadlessState)backend.state
    if texture == TEXTURE_NONE || u32(texture) > state.texture_count { return {} }
    return state.texture_sizes[texture]
}
