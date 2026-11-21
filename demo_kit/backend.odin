package demo_kit

import "base:runtime"

// What a demo needs from a framework, as a table of procs. The demos of a library are written once (demo_common/) against this and
// the same code runs on raylib, on Karl2D and headless (no window, for tests). A framework gets one implementation: demo_kit/glue_raylib,
// demo_kit/glue_karl2d, and Headless below.
//
// Handles (Texture, Sound) are numbers the backend gives out: a demo holds them in plain data and never sees a framework type.
// Anything a framework does that is not in here belongs in a demo of that framework (demo_raylib/, demo_karl2d/), not in demo_common.

Texture :: distinct u32
Sound :: distinct u32
Font :: distinct u32

FONT_DEFAULT :: Font(0)         // the font of the framework: latin letters only
TEXTURE_NONE :: Texture(0)
SOUND_NONE :: Sound(0)

// A 2D camera: `target` of the world is at `offset` of the screen
Camera :: struct {
    target: Vec2,
    offset: Vec2,
    zoom: f32,
    rotation: f32,          // degrees
}

// Counted by the kit, in every backend: tests use it to see that a frame did draw something
Stats :: struct {
    draw_calls: int,        // primitives drawn since the start
    frames: int,
}

Backend :: struct {
    name: string,
    state: rawptr,                          // the backend's own data
    headless: bool,                         // nothing is shown, a Player drives the input
    stats: Stats,

    // frame: begin polls the window and the devices into `input` (the kit lets a Player replace it) and says if the window lives
    begin_frame: proc(backend: ^Backend, input: ^Input) -> (running: bool, delta_time: f32),
    end_frame: proc(backend: ^Backend),
    shutdown: proc(backend: ^Backend),
    screen_size: proc(backend: ^Backend) -> Vec2,
    clear: proc(backend: ^Backend, color: Color),

    // shapes and text. Positions are the top left, text size is the height in pixels
    draw_rect: proc(backend: ^Backend, rect: Rect, color: Color),
    draw_rect_outline: proc(backend: ^Backend, rect: Rect, thickness: f32, color: Color),
    draw_line: proc(backend: ^Backend, from: Vec2, to: Vec2, thickness: f32, color: Color),
    draw_circle: proc(backend: ^Backend, center: Vec2, radius: f32, color: Color),
    draw_circle_outline: proc(backend: ^Backend, center: Vec2, radius: f32, thickness: f32, color: Color),
    draw_triangle: proc(backend: ^Backend, a: Vec2, b: Vec2, c: Vec2, color: Color),
    draw_text: proc(backend: ^Backend, text: string, position: Vec2, size: f32, color: Color),
    measure_text: proc(backend: ^Backend, text: string, size: f32) -> Vec2,

    // a font from the bytes of a ttf file with the glyphs of the unicode range first_glyph .. first_glyph + glyph_count (a language other than english needs more than the
    // first 128, an icon font has its glyphs in the private use area)
    font_load: proc(backend: ^Backend, bytes: []u8, size: f32, glyph_count: int, first_glyph: int) -> Font,
    font_unload: proc(backend: ^Backend, font: Font),
    measure_text_font: proc(backend: ^Backend, font: Font, text: string, size: f32) -> Vec2,
    draw_text_font: proc(backend: ^Backend, font: Font, text: string, position: Vec2, size: f32, color: Color),

    // images: loaded from the bytes of a file (`#load` embeds them, so no working directory matters)
    texture_load: proc(backend: ^Backend, bytes: []u8) -> Texture,
    // a texture from pixels made at run time (an atlas baked in memory): width * height * 4 bytes, RGBA, 8 bits each
    texture_from_pixels: proc(backend: ^Backend, width: int, height: int, rgba: []u8) -> Texture,
    texture_unload: proc(backend: ^Backend, texture: Texture),
    texture_size: proc(backend: ^Backend, texture: Texture) -> Vec2,
    // `source` of the texture on `destination` of the screen, turned around `origin` (a point of destination, from its top left)
    texture_draw: proc(backend: ^Backend, texture: Texture, source: Rect, destination: Rect, origin: Vec2, rotation: f32, tint: Color),

    // the clipboard of the system, optional: nil where the framework has none (`ClipboardGet` / `ClipboardSet` then keep a copy inside of the program, so copy and paste still work between the
    // fields of a demo). `clipboard_get` writes the text (UTF-8) into `buffer` and returns its length.
    clipboard_get: proc(backend: ^Backend, buffer: []u8) -> int,
    clipboard_set: proc(backend: ^Backend, text: string),

    // the mouse is hidden and gives only movement (a first person camera); the position keeps counting but is not the pointer anymore
    mouse_capture: proc(backend: ^Backend, captured: bool),

    camera_begin: proc(backend: ^Backend, camera: Camera),
    camera_end: proc(backend: ^Backend),
    clip_begin: proc(backend: ^Backend, rect: Rect),
    clip_end: proc(backend: ^Backend),

    // the pixels of the frame that was drawn (RGBA 8 bits, top left first), made with `allocator`. nil: the backend cannot (headless).
    // Called after the demo drew and before the frame is presented.
    capture: proc(backend: ^Backend, allocator: runtime.Allocator) -> (rgba: []u8, width: int, height: int),

    sound_load: proc(backend: ^Backend, bytes: []u8) -> Sound,
    sound_unload: proc(backend: ^Backend, sound: Sound),
    sound_play: proc(backend: ^Backend, sound: Sound, volume: f32, pitch: f32),
}

// What a demo gets in every call
Context :: struct {
    backend: ^Backend,
    input: Input,
    delta_time: f32,
    time: f64,              // seconds since the start of the run
    frame: int,             // frames since the demo started
    screen: Vec2,
    ui_hover: bool,         // the mouse is over the kit's demo menu: a demo ignores clicks then
    background: Color,      // what the screen is cleared with each frame: a demo may change it (RAY_WHITE when it starts)
    log: ^Log,              // the log of a test run (log.odin), nil when there is none: `LogNote(ctx, ...)` writes to it
}

// ------------------------------------------------------------------------------------------------------------------------
// Drawing from a demo: ctx is what every demo proc gets. They count the draw calls and leave the rest to the backend.

DrawRect :: proc(ctx: ^Context, rect: Rect, color: Color) {
    ctx.backend.stats.draw_calls += 1
    ctx.backend.draw_rect(ctx.backend, rect, color)
}

DrawRectOutline :: proc(ctx: ^Context, rect: Rect, thickness: f32, color: Color) {
    ctx.backend.stats.draw_calls += 1
    ctx.backend.draw_rect_outline(ctx.backend, rect, thickness, color)
}

DrawLine :: proc(ctx: ^Context, from: Vec2, to: Vec2, thickness: f32, color: Color) {
    ctx.backend.stats.draw_calls += 1
    ctx.backend.draw_line(ctx.backend, from, to, thickness, color)
}

DrawCircle :: proc(ctx: ^Context, center: Vec2, radius: f32, color: Color) {
    ctx.backend.stats.draw_calls += 1
    ctx.backend.draw_circle(ctx.backend, center, radius, color)
}

DrawCircleOutline :: proc(ctx: ^Context, center: Vec2, radius: f32, thickness: f32, color: Color) {
    ctx.backend.stats.draw_calls += 1
    ctx.backend.draw_circle_outline(ctx.backend, center, radius, thickness, color)
}

DrawTriangle :: proc(ctx: ^Context, a: Vec2, b: Vec2, c: Vec2, color: Color) {
    ctx.backend.stats.draw_calls += 1
    ctx.backend.draw_triangle(ctx.backend, a, b, c, color)
}

DrawText :: proc(ctx: ^Context, text: string, position: Vec2, size: f32, color: Color) {
    ctx.backend.stats.draw_calls += 1
    ctx.backend.draw_text(ctx.backend, text, position, size, color)
}

MeasureText :: proc(ctx: ^Context, text: string, size: f32) -> Vec2 {
    return ctx.backend.measure_text(ctx.backend, text, size)
}

// Text with its center at `center`
DrawTextCentered :: proc(ctx: ^Context, text: string, center: Vec2, size: f32, color: Color) {
    measured: Vec2 = MeasureText(ctx, text, size)
    DrawText(ctx, text, center - measured * 0.5, size, color)
}

// `size` is the size the glyphs are made in (draw at this size for a sharp text), glyph_count the number of unicode code points from `first_glyph` on. `bytes` have to stay
// as long as the font is used. With -define:DEMO_VECTOR_TEXT the font is drawn from its outlines like the other text.
FontLoad :: proc(ctx: ^Context, bytes: []u8, size: f32 = 32, glyph_count: int = 1280, first_glyph: int = 0) -> Font {
    return ctx.backend.font_load(ctx.backend, bytes, size, glyph_count, first_glyph)
}

FontUnload :: proc(ctx: ^Context, font: Font) {
    if font == FONT_DEFAULT { return }
    ctx.backend.font_unload(ctx.backend, font)
}

// The size of a text in a loaded font (FONT_DEFAULT: the font of the framework, the same as MeasureText).
MeasureTextFont :: proc(ctx: ^Context, font: Font, text: string, size: f32) -> Vec2 {
    if font == FONT_DEFAULT { return MeasureText(ctx, text, size) }
    return ctx.backend.measure_text_font(ctx.backend, font, text, size)
}

DrawTextFont :: proc(ctx: ^Context, font: Font, text: string, position: Vec2, size: f32, color: Color) {
    ctx.backend.stats.draw_calls += 1
    ctx.backend.draw_text_font(ctx.backend, font, text, position, size, color)
}

TextureLoad :: proc(ctx: ^Context, bytes: []u8) -> Texture {
    return ctx.backend.texture_load(ctx.backend, bytes)
}

TextureFromPixels :: proc(ctx: ^Context, width: int, height: int, rgba: []u8) -> Texture {
    assert(len(rgba) >= width * height * 4)
    return ctx.backend.texture_from_pixels(ctx.backend, width, height, rgba)
}

TextureUnload :: proc(ctx: ^Context, texture: Texture) {
    if texture == TEXTURE_NONE { return }
    ctx.backend.texture_unload(ctx.backend, texture)
}

TextureSize :: proc(ctx: ^Context, texture: Texture) -> Vec2 {
    return ctx.backend.texture_size(ctx.backend, texture)
}

// The whole texture on a rectangle of the screen
DrawTexture :: proc(ctx: ^Context, texture: Texture, destination: Rect, tint: Color = {255, 255, 255, 255}) {
    size: Vec2 = TextureSize(ctx, texture)
    DrawTextureRect(ctx, texture, {0, 0, size.x, size.y}, destination, {}, 0, tint)
}

DrawTextureRect :: proc(ctx: ^Context, texture: Texture, source: Rect, destination: Rect, origin: Vec2 = {}, rotation: f32 = 0, tint: Color = {255, 255, 255, 255}) {
    ctx.backend.stats.draw_calls += 1
    ctx.backend.texture_draw(ctx.backend, texture, source, destination, origin, rotation, tint)
}

MouseCapture :: proc(ctx: ^Context, captured: bool) {
    if ctx.backend.mouse_capture != nil { ctx.backend.mouse_capture(ctx.backend, captured) }
}

CameraBegin :: proc(ctx: ^Context, camera: Camera) {
    ctx.backend.camera_begin(ctx.backend, camera)
}

CameraEnd :: proc(ctx: ^Context) {
    ctx.backend.camera_end(ctx.backend)
}

// Draw only inside of `rect` until ClipEnd
ClipBegin :: proc(ctx: ^Context, rect: Rect) {
    ctx.backend.clip_begin(ctx.backend, rect)
}

ClipEnd :: proc(ctx: ^Context) {
    ctx.backend.clip_end(ctx.backend)
}

SoundLoad :: proc(ctx: ^Context, bytes: []u8) -> Sound {
    return ctx.backend.sound_load(ctx.backend, bytes)
}

SoundUnload :: proc(ctx: ^Context, sound: Sound) {
    if sound == SOUND_NONE { return }
    ctx.backend.sound_unload(ctx.backend, sound)
}

SoundPlay :: proc(ctx: ^Context, sound: Sound, volume: f32 = 1, pitch: f32 = 1) {
    if sound == SOUND_NONE { return }
    ctx.backend.sound_play(ctx.backend, sound, volume, pitch)
}

// The mouse in the world of a camera
CameraScreenToWorld :: proc(camera: Camera, point: Vec2) -> Vec2 {
    return camera.target + (point - camera.offset) / max(camera.zoom, 0.0001)
}

CameraWorldToScreen :: proc(camera: Camera, point: Vec2) -> Vec2 {
    return camera.offset + (point - camera.target) * camera.zoom
}

// A few colors so a demo needs no framework for them
WHITE :: Color{255, 255, 255, 255}
BLACK :: Color{0, 0, 0, 255}
GRAY :: Color{130, 130, 130, 255}
LIGHT_GRAY :: Color{200, 200, 200, 255}
DARK_GRAY :: Color{80, 80, 80, 255}
RED :: Color{230, 41, 55, 255}
GREEN :: Color{0, 200, 70, 255}
DARK_GREEN :: Color{0, 117, 44, 255}
BLUE :: Color{0, 121, 241, 255}
DARK_BLUE :: Color{0, 82, 172, 255}
YELLOW :: Color{253, 249, 0, 255}
ORANGE :: Color{255, 161, 0, 255}
PURPLE :: Color{200, 122, 255, 255}
RAY_WHITE :: Color{245, 245, 245, 255}

// ---- the clipboard ------------------------------------------------------------------------------------------------------------------------------------------------

CLIPBOARD_LOCAL :: 4096

@(private)
local_clipboard: [CLIPBOARD_LOCAL]u8
@(private)
local_clipboard_length: int

// Puts text on the clipboard: the system's when the backend has one, and always the copy of the program
ClipboardSet :: proc(ctx: ^Context, text: string) {
    local_clipboard_length = copy(local_clipboard[:], text)
    if ctx.backend.clipboard_set != nil { ctx.backend.clipboard_set(ctx.backend, text) }
}

// The text on the clipboard, written into `buffer` (a slice of it). The system's when the backend has one and it holds text, else the copy of the program.
ClipboardGet :: proc(ctx: ^Context, buffer: []u8) -> string {
    if ctx.backend.clipboard_get != nil {
        count: int = ctx.backend.clipboard_get(ctx.backend, buffer)
        if count > 0 { return string(buffer[:count]) }
    }
    count: int = copy(buffer, local_clipboard[:local_clipboard_length])
    return string(buffer[:count])
}
