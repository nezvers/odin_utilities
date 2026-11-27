package demo_kit_raylib

// The raylib backend of demo_kit. `Run` opens a window and runs the demos of a library until it is closed:
//
//     main :: proc() { kit_raylib.Run("tween", demo_common.demos[:]) }

import "base:runtime"
import "core:math"
import "core:os"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import kit ".."
import font "../../font"
import font_raylib "../../font/glue_raylib"

MAX_TEXTURES :: 64
MAX_SOUNDS :: 64
SIZED_FONTS :: 12                // the sizes of one font that text was drawn at (see sizedFace)
MAX_FONTS :: 16                 // one less than the faces of a text system has room for the fonts after the default one

// The glyphs of a font made at one size
SizedFont :: struct {
    pixels: i32,
    font: rl.Font,
}

State :: struct {
    textures: [MAX_TEXTURES]rl.Texture2D,
    texture_count: u32,
    sounds: [MAX_SOUNDS]rl.Sound,
    sound_count: u32,
    fonts: [MAX_FONTS]rl.Font,
    font_count: u32,
    font_used: [MAX_FONTS]bool,     // a slot is free again after font_unload: demos that load fonts one after the other must not run out of them
    // what the text needs to look like the Karl2D text: the glyphs made at the size they are drawn at (raylib scales one atlas, which blurs) and the exact advances of the file
    // (raylib keeps whole pixels, which crowds the letters)
    sources: [MAX_FONTS]font.Font,
    source_ok: [MAX_FONTS]bool,
    source_bytes: [MAX_FONTS][]u8,
    source_first: [MAX_FONTS]int,
    source_count: [MAX_FONTS]int,
    sized: [MAX_FONTS][SIZED_FONTS]SizedFont,
    sized_count: [MAX_FONTS]int,
    last_mouse: kit.Vec2,
    default_font: kit.Font,         // Fira Code (assets/fonts): the font of every text that does not ask for another one
    vector_text: font_raylib.TextSystem,    // the text drawn from the outlines of the font (-define:DEMO_VECTOR_TEXT)
}

FIRA_CODE :: #load("../../assets/fonts/FiraCode-Regular.ttf")

// Open a window and run. Escape closes it.
Run :: proc(title: string, demos: []kit.Demo, width: i32 = 1280, height: i32 = 720) {
    // a test window does not keep the focus and does not take clicks (see passive_windows.odin)
    previous_focus: rawptr
    when kit.DEMO_TEST { previous_focus = kit.PassiveWindowBegin() } else { _ = previous_focus }
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(width, height, strings.clone_to_cstring(title, context.temp_allocator))
    when kit.DEMO_TEST { kit.PassiveWindowEnd(previous_focus) }
    // DEMO_MONITOR names the display the window goes to; a test run also makes sure that the size of the picture is the wanted one
    when kit.DEMO_TEST {
        if !placeOnDisplay(width, height) {
            rl.CloseWindow()
            exit_process(false)
        }
    } else {
        if kit.DisplayRequest() != "" { placeOnDisplay(width, height) }
    }
    rl.InitAudioDevice()
    rl.SetTargetFPS(60)
    rl.SetExitKey(.KEY_NULL)        // the runner closes on escape, like with the other backends

    // on the heap: a State holds a parsed font (34 KB) for every font the demos load, far more than a stack has room for
    state: ^State = new(State)
    defer free(state)
    backend: kit.Backend
    Init(&backend, state)
    when kit.DEMO_TEST {
        passed: bool = kit.RunTests(demos, &backend)
        backend.shutdown(&backend)
        exit_process(passed)
    } else {
        runner: kit.Runner
        kit.Run(&runner, demos, &backend)
    }
}

// Fill a Backend with the raylib procs. The window has to be open. `state` has to live as long as the backend.
Init :: proc(backend: ^kit.Backend, state: ^State) {
    state.last_mouse = rl.GetMousePosition()
    when kit.DEMO_VECTOR_TEXT != "" {
        method: font.Method = .SCANLINE if kit.DEMO_VECTOR_TEXT == "scanline" else .SLUG
        if !font_raylib.TextSystemInit(&state.vector_text, FIRA_CODE, method) { exit_process(false) }
    }
    state.default_font = fontLoad(nil, FIRA_CODE, 32, 1280, 0, state)
    backend^ = {
        name = "raylib" when kit.DEMO_VECTOR_TEXT == "" else "raylib_" + kit.DEMO_VECTOR_TEXT,
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
        draw_triangles = drawTriangles,
        draw_text = proc(backend: ^kit.Backend, text: string, position: kit.Vec2, size: f32, color: kit.Color) {
            state: ^State = cast(^State)backend.state
            when kit.DEMO_VECTOR_TEXT != "" {
                font_raylib.TextSystemDraw(&state.vector_text, text, position, size, rl.Color(color))
            } else {
                drawText(state, kit.FONT_DEFAULT, text, position, size, color)
            }
        },
        measure_text = proc(backend: ^kit.Backend, text: string, size: f32) -> kit.Vec2 {
            state: ^State = cast(^State)backend.state
            when kit.DEMO_VECTOR_TEXT != "" {
                return font_raylib.TextSystemMeasure(&state.vector_text, text, size)
            } else {
                return measureText(state, kit.FONT_DEFAULT, text, size)
            }
        },
        font_load = proc(backend: ^kit.Backend, bytes: []u8, size: f32, glyph_count: int, first_glyph: int) -> kit.Font { return fontLoad(backend, bytes, size, glyph_count, first_glyph, cast(^State)backend.state) },
        font_unload = proc(backend: ^kit.Backend, font: kit.Font) {
            state: ^State = cast(^State)backend.state
            if u32(font) == 0 || u32(font) > state.font_count || !state.font_used[font] { return }
            rl.UnloadFont(state.fonts[font])
            state.fonts[font] = {}
            state.font_used[font] = false
            state.source_ok[font] = false
            // the copies of the font at other sizes belong to the slot: the next font in it must not draw with them
            for i in 0 ..< state.sized_count[font] { rl.UnloadFont(state.sized[font][i].font) }
            state.sized_count[font] = 0
        },
        measure_text_font = proc(backend: ^kit.Backend, font: kit.Font, text: string, size: f32) -> kit.Vec2 {
            state: ^State = cast(^State)backend.state
            when kit.DEMO_VECTOR_TEXT != "" {
                return font_raylib.TextSystemMeasure(&state.vector_text, text, size, {face = vectorFace(state, font)})
            } else {
                return measureText(state, font, text, size)
            }
        },
        draw_text_font = proc(backend: ^kit.Backend, font: kit.Font, text: string, position: kit.Vec2, size: f32, color: kit.Color) {
            state: ^State = cast(^State)backend.state
            when kit.DEMO_VECTOR_TEXT != "" {
                font_raylib.TextSystemDraw(&state.vector_text, text, position, size, rl.Color(color), {face = vectorFace(state, font)})
            } else {
                drawText(state, font, text, position, size, color)
            }
        },
        texture_load = textureLoad,
        texture_from_pixels = proc(backend: ^kit.Backend, width: int, height: int, rgba: []u8) -> kit.Texture {
            state: ^State = cast(^State)backend.state
            if state.texture_count + 1 >= MAX_TEXTURES { return kit.TEXTURE_NONE }
            image: rl.Image = {data = raw_data(rgba), width = i32(width), height = i32(height), mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
            state.texture_count += 1
            state.textures[state.texture_count] = rl.LoadTextureFromImage(image)     // copies the pixels to the GPU
            return kit.Texture(state.texture_count)
        },
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
        clipboard_get = proc(backend: ^kit.Backend, buffer: []u8) -> int {
            text: string = string(rl.GetClipboardText())
            return copy(buffer, text)
        },
        clipboard_set = proc(backend: ^kit.Backend, text: string) {
            terminated: [kit.CLIPBOARD_LOCAL + 1]u8
            count: int = copy(terminated[:kit.CLIPBOARD_LOCAL], text)
            terminated[count] = 0
            rl.SetClipboardText(cstring(raw_data(terminated[:])))
        },
        mouse_capture = proc(backend: ^kit.Backend, captured: bool) {
            if captured { rl.DisableCursor() } else { rl.EnableCursor() }
        },
        camera_begin = proc(backend: ^kit.Backend, camera: kit.Camera) {
            rl.BeginMode2D({offset = camera.offset, target = camera.target, rotation = camera.rotation, zoom = camera.zoom})
        },
        camera_end = proc(backend: ^kit.Backend) { rl.EndMode2D() },
        clip_begin = proc(backend: ^kit.Backend, rect: kit.Rect) {
            rl.BeginScissorMode(i32(rect.x), i32(rect.y), i32(rect.z), i32(rect.w))
        },
        clip_end = proc(backend: ^kit.Backend) { rl.EndScissorMode() },
        capture = proc(backend: ^kit.Backend, allocator: runtime.Allocator) -> (rgba: []u8, width: int, height: int) {
            // what the batch still holds goes to the screen first
            rlgl.DrawRenderBatchActive()
            image: rl.Image = rl.LoadImageFromScreen()
            defer rl.UnloadImage(image)
            if image.data == nil || image.format != .UNCOMPRESSED_R8G8B8A8 { return nil, 0, 0 }
            width, height = int(image.width), int(image.height)
            rgba = make([]u8, width * height * 4, allocator)
            copy(rgba, ([^]u8)(image.data)[:width * height * 4])
            return
        },
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
    if rl.IsGamepadAvailable(0) {
        pad_buttons: [kit.PadButton]rl.GamepadButton = {
            .DPAD_UP = .LEFT_FACE_UP, .DPAD_DOWN = .LEFT_FACE_DOWN, .DPAD_LEFT = .LEFT_FACE_LEFT, .DPAD_RIGHT = .LEFT_FACE_RIGHT,
            .FACE_UP = .RIGHT_FACE_UP, .FACE_DOWN = .RIGHT_FACE_DOWN, .FACE_LEFT = .RIGHT_FACE_LEFT, .FACE_RIGHT = .RIGHT_FACE_RIGHT,
            .LEFT_SHOULDER = .LEFT_TRIGGER_1, .RIGHT_SHOULDER = .RIGHT_TRIGGER_1, .LEFT_TRIGGER = .LEFT_TRIGGER_2, .RIGHT_TRIGGER = .RIGHT_TRIGGER_2,
            .LEFT_STICK = .LEFT_THUMB, .RIGHT_STICK = .RIGHT_THUMB, .BACK = .MIDDLE_LEFT, .START = .MIDDLE_RIGHT,
        }
        for button in kit.PadButton {
            if rl.IsGamepadButtonDown(0, pad_buttons[button]) { input.pad_down += {button} }
            if rl.IsGamepadButtonPressed(0, pad_buttons[button]) { input.pad_pressed += {button} }
        }
    }
    mouse_buttons: [kit.MouseButton]rl.MouseButton = {.LEFT = .LEFT, .RIGHT = .RIGHT, .MIDDLE = .MIDDLE}
    for button in kit.MouseButton {
        if rl.IsMouseButtonDown(mouse_buttons[button]) { input.mouse_down += {button} }
        if rl.IsMouseButtonPressed(mouse_buttons[button]) { input.mouse_pressed += {button} }
        if rl.IsMouseButtonReleased(mouse_buttons[button]) { input.mouse_released += {button} }
    }
    input.mouse_position = rl.GetMousePosition()
    input.mouse_delta = rl.GetMouseDelta()
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

// raylib wants a C string: the text is copied into a buffer of the caller (on its stack) with a zero at the end, cut when too long.
// No allocation, nothing left in the temp allocator for every text of every frame.
@(private)
TEXT_BUFFER_SIZE :: 512

@(private)
cstringInto :: proc(buffer: ^[TEXT_BUFFER_SIZE]u8, text: string) -> cstring {
    count: int = min(len(text), TEXT_BUFFER_SIZE - 1)
    copy(buffer[:count], text[:count])
    buffer[count] = 0
    return cstring(raw_data(buffer[:]))
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

// A triangle list with a color per vertex. Raylib culls clockwise triangles, so each one is turned the right way.
@(private)
drawTriangles :: proc(backend: ^kit.Backend, vertices: []kit.Vertex) {
    rlgl.Begin(rlgl.TRIANGLES)
    defer rlgl.End()
    for i := 0; i + 2 < len(vertices); i += 3 {
        a, b, c: kit.Vertex = vertices[i], vertices[i + 1], vertices[i + 2]
        if (b.position.x - a.position.x) * (c.position.y - a.position.y) - (b.position.y - a.position.y) * (c.position.x - a.position.x) > 0 {
            b, c = c, b
        }
        for corner in ([3]kit.Vertex{a, b, c}) {
            rlgl.Color4ub(corner.color.r, corner.color.g, corner.color.b, corner.color.a)
            rlgl.Vertex2f(corner.position.x, corner.position.y)
        }
    }
}

// The raylib font of a kit font: FONT_DEFAULT is Fira Code (raylib's own pixel font when it could not be made).
@(private)
face :: proc(state: ^State, font: kit.Font) -> rl.Font {
    id: kit.Font = font if font != kit.FONT_DEFAULT else state.default_font
    if u32(id) != 0 && u32(id) <= state.font_count { return state.fonts[id] }
    return rl.GetFontDefault()
}

// ---- text ---------------------------------------------------------------------------------------------------------------------------------------------------
// raylib makes one bitmap of each font at the size it is loaded in and scales it: smaller text is a blurred copy, and its advances are whole pixels of the loading size,
// so the letters crowd or drift apart. Karl2D makes the glyphs at the size they are drawn at and moves the pen by the exact advance. The same here: the glyphs of a size
// are made once from the file (a cache of SIZED_FONTS sizes per font), each one is drawn on a whole pixel, and the pen moves by the advance of the file in em units, so
// that the text measures the same at every size and the layout of the two frameworks agrees. Kerning pairs are not applied (the measure and the drawing agree).

// The font of `id` made for text of `size` pixels (the whole pixels are the size it is loaded in). False when there is no file or no room: the caller draws with the
// atlas of the loading size then.
@(private)
sizedFace :: proc(state: ^State, id: kit.Font, size: f32) -> (result: rl.Font, ok: bool) {
    if u32(id) == 0 || u32(id) > state.font_count || !state.source_ok[id] { return {}, false }
    pixels: i32 = clamp(i32(size + 0.5), 4, 256)
    for i in 0 ..< state.sized_count[id] {
        if state.sized[id][i].pixels == pixels { return state.sized[id][i].font, true }
    }
    if state.sized_count[id] >= SIZED_FONTS { return {}, false }
    codepoints: [dynamic]rune
    defer delete(codepoints)
    for i in 0 ..< state.source_count[id] { append(&codepoints, rune(state.source_first[id] + i)) }
    bytes: []u8 = state.source_bytes[id]
    loaded: rl.Font = rl.LoadFontFromMemory(".ttf", raw_data(bytes), i32(len(bytes)), pixels, raw_data(codepoints), i32(len(codepoints)))
    if loaded.texture.id == 0 { return {}, false }
    state.sized[id][state.sized_count[id]] = {pixels, loaded}
    state.sized_count[id] += 1
    return loaded, true
}

// How many pixels an em is when the text is `size` pixels high (raylib's size is the height from the ascent to the descent)
@(private)
emPixels :: proc(source: ^font.Font, size: f32) -> f32 {
    height: f32 = source.ascent - source.descent
    return size / height if height > 0 else size
}

@(private)
measureText :: proc(state: ^State, font_id: kit.Font, text: string, size: f32) -> kit.Vec2 {
    id: kit.Font = font_id if font_id != kit.FONT_DEFAULT else state.default_font
    if u32(id) == 0 || u32(id) > state.font_count || !state.source_ok[id] {
        buffer: [TEXT_BUFFER_SIZE]u8
        return rl.MeasureTextEx(face(state, font_id), cstringInto(&buffer, text), size, 0)
    }
    source: ^font.Font = &state.sources[id]
    em: f32 = emPixels(source, size)
    width: f32
    for character in text {
        if character < 32 { continue }
        width += font.FontAdvance(source, font.FontGlyph(source, character)) * em
    }
    return {width, size}
}

@(private)
drawText :: proc(state: ^State, font_id: kit.Font, text: string, position: kit.Vec2, size: f32, color: kit.Color) {
    id: kit.Font = font_id if font_id != kit.FONT_DEFAULT else state.default_font
    sized, ok := sizedFace(state, id, size)
    if !ok {
        buffer: [TEXT_BUFFER_SIZE]u8
        rl.DrawTextEx(face(state, font_id), cstringInto(&buffer, text), position, size, 0, rl.Color(color))
        return
    }
    source: ^font.Font = &state.sources[id]
    em: f32 = emPixels(source, size)
    x: f32 = position.x
    for character in text {
        if character < 32 { continue }
        // a whole pixel for the glyph, the exact advance for the pen: the glyph is sharp and the spacing does not drift
        rl.DrawTextCodepoint(sized, character, {math.round(x), math.round(position.y)}, size, rl.Color(color))
        x += font.FontAdvance(source, font.FontGlyph(source, character)) * em
    }
}

// The face of the vector text a kit font is: the default font is the regular face, the others were added when they were loaded (font n is face n - 1)
@(private)
vectorFace :: proc(state: ^State, font: kit.Font) -> u8 {
    if font == kit.FONT_DEFAULT || font == state.default_font || u32(font) > state.font_count { return 0 }
    return u8(u32(font) - 1)
}

@(private)
fontLoad :: proc(backend: ^kit.Backend, bytes: []u8, size: f32, glyph_count: int, first_glyph: int, state: ^State) -> kit.Font {
    index: u32 = 0
    for candidate in 1 ..< u32(MAX_FONTS) { if !state.font_used[candidate] { index = candidate; break } }
    if index == 0 { return kit.FONT_DEFAULT }
    when kit.DEMO_VECTOR_TEXT != "" {
        // the text is drawn from outlines: the font is one more face of the text system (the first font is the regular face it was made with)
        if index > 1 && !font_raylib.TextSystemAddFace(&state.vector_text, int(index) - 1, bytes) { return kit.FONT_DEFAULT }
    }
    codepoints: [dynamic]rune
    defer delete(codepoints)
    for i in 0 ..< glyph_count { append(&codepoints, rune(first_glyph + i)) }
    loaded: rl.Font = rl.LoadFontFromMemory(".ttf", raw_data(bytes), i32(len(bytes)), i32(size), raw_data(codepoints), i32(len(codepoints)))
    if loaded.texture.id == 0 { return kit.FONT_DEFAULT }
    state.font_used[index] = true
    state.font_count = max(state.font_count, index)
    state.fonts[index] = loaded
    // the file stays with the caller (an embedded font lives for ever): the exact advances and the glyphs of other sizes are made from it
    state.source_bytes[index] = bytes
    state.source_ok[index] = font.FontInit(&state.sources[index], bytes)
    state.source_first[index], state.source_count[index] = first_glyph, glyph_count
    return kit.Font(index)
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

// the exit code of a test run: 0 when every check passed
@(private)
exit_process :: proc(passed: bool) {
    os.exit(0 if passed else 1)
}
