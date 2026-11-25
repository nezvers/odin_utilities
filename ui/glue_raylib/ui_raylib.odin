package ui_raylib

// Glue for raylib: the Painter of the default style drawn with raylib calls, and the input of a frame as ui.Input.
// A frame in a raylib program:
//
//     painter: ui_default.Painter
//     ui_raylib.PainterInit(&painter)
//     style := ui_default.StyleMake()
//     ui.UiInit(&ctx, &storage, ui_default.Measure, &painter)
//
//     rl.BeginDrawing()
//     ... the game ...
//     ui.UiBegin(&ctx, ui_raylib.InputPoll(), rl.GetFrameTime(), ui_raylib.ScreenSize(), &style)
//     ... widgets ...
//     ui.UiEnd(&ctx)
//     ui.UiRender(&ctx)           // draws into the batch of raylib that is open: same one as the game
//     rl.EndDrawing()

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import ui ".."
import ui_default "../default_style"
import font "../../font"
import font_raylib "../../font/glue_raylib"
import icons "../../icons"

// The fonts of the default style as raylib fonts: Inter for text (the labels of controls in semibold), JetBrains Mono for numbers and code, Lucide for the icons.
// The files are part of the program that calls FontsLoad (about 1.5 MB); their licenses (SIL Open Font License, ISC, MIT) ask for their notices to go with the program:
// assets/fonts/inter/Inter-OFL.txt, assets/fonts/jetbrains_mono/OFL.txt, icons/lucide/LICENSE.
Fonts :: struct {
    faces: [ui_default.Face]rl.Font,
    icons: rl.Font,
    // for the text: the file of each face (the embedded ones below), parsed for its exact advances, and the glyphs of the sizes that were drawn (see drawText)
    sources: [ui_default.Face]font.Font,
    source_ok: [ui_default.Face]bool,
    source_bytes: [ui_default.Face][]u8,
    sized: [ui_default.Face][SIZED_FONTS]SizedFont,
    sized_count: [ui_default.Face]int,
    glyph_count: int,
}

SIZED_FONTS :: 12                // the sizes of one face that text was drawn at

// The glyphs of a face made at one size
SizedFont :: struct {
    pixels: i32,
    font: rl.Font,
}

INTER_REGULAR :: #load("../../assets/fonts/inter/Inter-Regular.ttf")
INTER_SEMIBOLD :: #load("../../assets/fonts/inter/Inter-SemiBold.ttf")
INTER_ITALIC :: #load("../../assets/fonts/inter/Inter-Italic.ttf")
JETBRAINS_MONO :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-Regular.ttf")
JETBRAINS_MONO_BOLD :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-Bold.ttf")
JETBRAINS_MONO_ITALIC :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-Italic.ttf")
JETBRAINS_MONO_BOLD_ITALIC :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-BoldItalic.ttf")
INTER_SEMIBOLD_ITALIC :: #load("../../assets/fonts/inter/Inter-SemiBoldItalic.ttf")

// Loads the fonts of the style (the window has to be open). `size` is the height the glyphs are made in: text of that size is the sharpest.
// `skin`: the font files of a skin (ui_default.SkinFontsRead): a face that has bytes is drawn in that font.
FontsLoad :: proc(fonts: ^Fonts, size: i32 = 32, glyph_count: int = 1280, skin: ^ui_default.SkinFontBytes = nil) {
    codepoints: []rune = make([]rune, max(glyph_count, len(icons.Icon)), context.temp_allocator)
    for i in 0 ..< glyph_count { codepoints[i] = rune(i) }
    load :: proc(bytes: []u8, size: i32, codepoints: []rune) -> rl.Font {
        loaded: rl.Font = rl.LoadFontFromMemory(".ttf", raw_data(bytes), i32(len(bytes)), size, raw_data(codepoints), i32(len(codepoints)))
        rl.SetTextureFilter(loaded.texture, .BILINEAR)
        return loaded
    }
    sources: [ui_default.Face][]u8 = {
        .REGULAR = INTER_REGULAR, .STRONG = INTER_SEMIBOLD, .ITALIC = INTER_ITALIC, .MONO = JETBRAINS_MONO, .MONO_STRONG = JETBRAINS_MONO_BOLD,
        .STRONG_ITALIC = INTER_SEMIBOLD_ITALIC, .MONO_ITALIC = JETBRAINS_MONO_ITALIC, .MONO_STRONG_ITALIC = JETBRAINS_MONO_BOLD_ITALIC,
    }
    if skin != nil {
        for face in ui_default.Face {
            if len(skin[face]) > 0 { sources[face] = skin[face] }
        }
    }
    for face in ui_default.Face { fonts.faces[face] = load(sources[face], size, codepoints[:glyph_count]) }
    fonts.glyph_count = glyph_count
    for face in ui_default.Face {
        fonts.source_bytes[face] = sources[face]
        fonts.source_ok[face] = font.FontInit(&fonts.sources[face], sources[face])
    }
    // the icons without NONE, which has no glyph
    for i in 0 ..< len(icons.Icon) - 1 { codepoints[i] = icons.ICON_FIRST_CHARACTER + rune(i) }
    fonts.icons = load(icons.LUCIDE_FONT, size, codepoints[:len(icons.Icon) - 1])
}

FontsUnload :: proc(fonts: ^Fonts) {
    for face in fonts.faces { rl.UnloadFont(face) }
    for face in ui_default.Face {
        for i in 0 ..< fonts.sized_count[face] { rl.UnloadFont(fonts.sized[face][i].font) }
    }
    rl.UnloadFont(fonts.icons)
    fonts^ = {}
}

// The painter draws its text in the faces of `fonts` and gets the icons. `fonts` has to live as long as the painter.
PainterUseFonts :: proc(painter: ^ui_default.Painter, fonts: ^Fonts) {
    painter.fonts = fonts
    for face in ui_default.Face { painter.glue_fonts[face] = 1 }
    painter.glue_icon_font = 1
    painter.glue_ready = true
    painter.draw_icon = proc(painter: ^ui_default.Painter, icon: icons.Icon, rect: ui.Rect, color: ui.Color) {
        ui_default.PainterFlush(painter)
        text, length := icons.IconText(icon)
        buffer: [TEXT_BUFFER_SIZE]u8
        box: ui.Rect = ui_default.PaintRect(painter, rect)
        rl.DrawTextEx((cast(^Fonts)painter.fonts).icons, cstringInto(&buffer, icons.IconString(&text, length)), {box.x, box.y}, min(box.z, box.w), 0, rl.Color(color))
    }
}

// The same for a painter that draws its text from outlines (PainterUseVectorText): the faces are added to the text system (their bytes are the ones of this package) and
// the painter picks them. Call it after PainterUseVectorText. False when the system has no room for the faces.
PainterUseVectorFonts :: proc(painter: ^ui_default.Painter, system: ^font_raylib.TextSystem) -> bool {
    FIRST_FACE :: font.ATLAS_FACES - 8          // the last eight faces of an atlas: the first ones are the family of the font the system was made with
    sources: [8][]u8 = {INTER_SEMIBOLD, INTER_ITALIC, INTER_SEMIBOLD_ITALIC, JETBRAINS_MONO, JETBRAINS_MONO_BOLD, JETBRAINS_MONO_ITALIC, JETBRAINS_MONO_BOLD_ITALIC, icons.LUCIDE_FONT}
    for bytes, i in sources {
        if !font_raylib.TextSystemAddFace(system, FIRST_FACE + i, bytes) { return false }
    }
    painter.vector_faces = {.REGULAR = 0, .STRONG = FIRST_FACE, .ITALIC = FIRST_FACE + 1, .STRONG_ITALIC = FIRST_FACE + 2, .MONO = FIRST_FACE + 3, .MONO_STRONG = FIRST_FACE + 4, .MONO_ITALIC = FIRST_FACE + 5, .MONO_STRONG_ITALIC = FIRST_FACE + 6}
    painter.vector_icon_face = FIRST_FACE + 7
    painter.glue_fonts[.MONO] = 1
    painter.draw_icon = proc(painter: ^ui_default.Painter, icon: icons.Icon, rect: ui.Rect, color: ui.Color) {
        text, length := icons.IconText(icon)
        box: ui.Rect = ui_default.PaintRect(painter, rect)
        font_raylib.TextSystemDraw(cast(^font_raylib.TextSystem)painter.vector_text, icons.IconString(&text, length), {box.x, box.y}, min(box.z, box.w), rl.Color(color), {face = painter.vector_icon_face})
    }
    return true
}

// Fills a painter with raylib draw procs. `font` is the font of the text (nil: the default font of raylib), it has to live as long as the painter.
PainterInit :: proc(painter: ^ui_default.Painter, font: ^rl.Font = nil) {
    painter^ = {
        user = font,
        theme = ui_default.THEME_DARK,
        fill_rect = proc(painter: ^ui_default.Painter, rect: ui.Rect, color: ui.Color) {
            ui_default.PainterFlush(painter)
            rl.DrawRectangleRec(transmute(rl.Rectangle)ui_default.PaintRect(painter, rect), rl.Color(color))
        },
        fill_polygon = fillPolygon,
        fill_mesh = fillMesh,
        mesh = {vertices = meshStorage[:]},
        fill_rounded = proc(painter: ^ui_default.Painter, rect: ui.Rect, radius: f32, color: ui.Color) {
            ui_default.PainterFlush(painter)
            // raylib's roundness is the radius as a part of half of the shortest side: the same as the rounding of the ui
            scale: f32 = ui_default.PainterScale(painter)
            roundness: f32 = radius / (min(rect.z, rect.w) * 0.5)
            rl.DrawRectangleRounded(transmute(rl.Rectangle)ui_default.PaintRect(painter, rect), roundness, i32(ui.RoundedSegments(radius * scale) * 4), rl.Color(color))
        },
        draw_text = proc(painter: ^ui_default.Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color) {
            buffer: [TEXT_BUFFER_SIZE]u8
            scale: f32 = ui_default.PainterScale(painter)
            if painter.fonts != nil && drawText(cast(^Fonts)painter.fonts, painter.face, text, ui_default.PaintPoint(painter, position), size * scale, color) { return }
            rl.DrawTextEx(fontOf(painter), cstringInto(&buffer, text), ui_default.PaintPoint(painter, position), size * scale, spacingOf(painter, size * scale), rl.Color(color))
        },
        measure_text = proc(painter: ^ui_default.Painter, text: string, size: f32) -> ui.Vec2 {
            buffer: [TEXT_BUFFER_SIZE]u8
            scale: f32 = ui_default.PainterScale(painter)
            if painter.fonts != nil {
                if width, ok := measureText(cast(^Fonts)painter.fonts, painter.face, text, size * scale); ok { return {width, size * scale} / scale }
            }
            return rl.MeasureTextEx(fontOf(painter), cstringInto(&buffer, text), size * scale, spacingOf(painter, size * scale)) / scale
        },
        draw_texture = proc(painter: ^ui_default.Painter, texture: u32, source: ui.Rect, destination: ui.Rect, tint: ui.Color) {
            if texture == 0 || int(texture) > texture_count { return }
            ui_default.PainterFlush(painter)
            picture: rl.Texture2D = textures[texture - 1]
            from: ui.Rect = source
            if from.z <= 0 || from.w <= 0 { from = {0, 0, f32(picture.width), f32(picture.height)} }
            rl.DrawTexturePro(picture, transmute(rl.Rectangle)from, transmute(rl.Rectangle)ui_default.PaintRect(painter, destination), {}, 0, rl.Color(tint))
        },
        clip = proc(painter: ^ui_default.Painter, rect: ui.Rect, begin: bool) {
            ui_default.PainterFlush(painter)
            if begin {
                physical: ui.Rect = ui_default.PaintRect(painter, rect)
                rl.BeginScissorMode(i32(physical.x), i32(physical.y), i32(physical.z), i32(physical.w))
            } else {
                rl.EndScissorMode()
            }
        },
    }
}

// Draws the text of the ui from the outlines of a font with the font library (sharp at any size and scale) instead of raylib's bitmap font: the size of a text stays the height of its line, so the
// layout does not change. The system (font_raylib.TextSystem) has to live as long as the painter and be made after the window exists.
PainterUseVectorText :: proc(painter: ^ui_default.Painter, system: ^font_raylib.TextSystem) {
    painter.vector_text = system
    // the text of a run of labels is one draw call: it is collected here and drawn when a shape comes, a clip changes or UiRender ends
    system.renderer.deferred = true
    painter.flush = proc(painter: ^ui_default.Painter) {
        if painter.vector_text != nil { font_raylib.RendererFlush(&(cast(^font_raylib.TextSystem)painter.vector_text).renderer) }
    }
    painter.draw_text = proc(painter: ^ui_default.Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color) {
        scale: f32 = ui_default.PainterScale(painter)
        font_raylib.TextSystemDraw(cast(^font_raylib.TextSystem)painter.vector_text, text, ui_default.PaintPoint(painter, position), size * scale, rl.Color(color), {face = painter.vector_faces[painter.face]})
    }
    painter.measure_text = proc(painter: ^ui_default.Painter, text: string, size: f32) -> ui.Vec2 {
        scale: f32 = ui_default.PainterScale(painter)
        return font_raylib.TextSystemMeasure(cast(^font_raylib.TextSystem)painter.vector_text, text, size * scale, {face = painter.vector_faces[painter.face]}) / scale
    }
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

// ---- text ---------------------------------------------------------------------------------------------------------------------------------------------------
// raylib makes one bitmap of a font at the size it is loaded in and scales it: smaller text is a blurred copy, and its advances are whole pixels of the loading size, so
// the letters crowd or drift apart. Karl2D makes the glyphs at the size they are drawn at and moves the pen by the exact advance. The same here (as in demo_kit's raylib
// glue): the glyphs of a size are made once from the file of the face (a cache of SIZED_FONTS sizes per face), each is drawn on a whole pixel and the pen moves by the
// advance of the file in em units, so a text measures the same at every size and the layout agrees with Karl2D's. Kerning pairs are not applied (measure and draw agree).

// The glyphs of `face` for text of `size` pixels. False when the file is not known or the cache is full: the atlas of the loading size is used then.
@(private)
sizedFace :: proc(fonts: ^Fonts, face: ui_default.Face, size: f32) -> (result: rl.Font, ok: bool) {
    if !fonts.source_ok[face] { return {}, false }
    pixels: i32 = clamp(i32(size + 0.5), 4, 256)
    for i in 0 ..< fonts.sized_count[face] {
        if fonts.sized[face][i].pixels == pixels { return fonts.sized[face][i].font, true }
    }
    if fonts.sized_count[face] >= SIZED_FONTS { return {}, false }
    codepoints: [dynamic]rune
    defer delete(codepoints)
    for i in 0 ..< fonts.glyph_count { append(&codepoints, rune(i)) }
    bytes: []u8 = fonts.source_bytes[face]
    loaded: rl.Font = rl.LoadFontFromMemory(".ttf", raw_data(bytes), i32(len(bytes)), pixels, raw_data(codepoints), i32(len(codepoints)))
    if loaded.texture.id == 0 { return {}, false }
    fonts.sized[face][fonts.sized_count[face]] = {pixels, loaded}
    fonts.sized_count[face] += 1
    return loaded, true
}

// The size of an em in pixels when the text is `size` pixels high (raylib's size runs from the ascent to the descent)
@(private)
emPixels :: proc(source: ^font.Font, size: f32) -> f32 {
    height: f32 = source.ascent - source.descent
    return size / height if height > 0 else size
}

@(private)
measureText :: proc(fonts: ^Fonts, face: ui_default.Face, text: string, size: f32) -> (width: f32, ok: bool) {
    if !fonts.source_ok[face] { return 0, false }
    source: ^font.Font = &fonts.sources[face]
    em: f32 = emPixels(source, size)
    for character in text {
        if character < 32 { continue }
        width += font.FontAdvance(source, font.FontGlyph(source, character)) * em
    }
    return width, true
}

// False when the exact path cannot draw it (the caller draws with the atlas of the loading size)
@(private)
drawText :: proc(fonts: ^Fonts, face: ui_default.Face, text: string, position: ui.Vec2, size: f32, color: ui.Color) -> bool {
    sized, ok := sizedFace(fonts, face, size)
    if !ok { return false }
    source: ^font.Font = &fonts.sources[face]
    em: f32 = emPixels(source, size)
    x: f32 = position.x
    for character in text {
        if character < 32 { continue }
        // a whole pixel for the glyph, the exact advance for the pen: the glyph is sharp and the spacing does not drift
        rl.DrawTextCodepoint(sized, character, {math.round(x), math.round(position.y)}, size, rl.Color(color))
        x += font.FontAdvance(source, font.FontGlyph(source, character)) * em
    }
    return true
}

// The font of the face the painter is set to: of its set of fonts (PainterUseFonts), else the one font it was made with, else the font of raylib
@(private)
fontOf :: proc(painter: ^ui_default.Painter) -> rl.Font {
    if painter.fonts != nil { return (cast(^Fonts)painter.fonts).faces[painter.face] }
    if painter.user == nil { return rl.GetFontDefault() }
    return (cast(^rl.Font)painter.user)^
}

// The room between letters: the fonts of the style bring their own, the pixel font of raylib needs a tenth of its size
@(private)
spacingOf :: proc(painter: ^ui_default.Painter, size: f32) -> f32 {
    return 0 if painter.fonts != nil else size / 10
}

// raylib wants the corners of a fan counter clockwise, the points of the ui go clockwise
@(private)
fillPolygon :: proc(painter: ^ui_default.Painter, points: []ui.Vec2, color: ui.Color) {
    ui_default.PainterFlush(painter)
    buffer: ui.RoundedBuffer
    count: int = min(len(points), len(buffer))
    for i in 0 ..< count {
        buffer[i] = ui_default.PaintPoint(painter, points[count - 1 - i])
    }
    rl.DrawTriangleFan(raw_data(buffer[:]), i32(count), rl.Color(color))
}

// Where the soft edged shapes are built (a shape is drawn as soon as it is built, so one storage serves all painters)
MESH_VERTICES :: 24576
@(private)
meshStorage: [MESH_VERTICES]ui.AaVertex

// The triangles of a smooth shape: alpha of the color times the coverage of each corner, in the batch of raylib that is open. Raylib culls clockwise triangles, so each one is turned the right way.
@(private)
fillMesh :: proc(painter: ^ui_default.Painter, triangles: []ui.AaVertex, color: ui.Color) {
    ui_default.PainterFlush(painter)
    rlgl.Begin(rlgl.TRIANGLES)
    defer rlgl.End()
    for i := 0; i + 2 < len(triangles); i += 3 {
        a: ui.Vec2 = ui_default.PaintPoint(painter, triangles[i].position)
        b: ui.Vec2 = ui_default.PaintPoint(painter, triangles[i + 1].position)
        c: ui.Vec2 = ui_default.PaintPoint(painter, triangles[i + 2].position)
        first, second: int = i + 1, i + 2
        if (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y) > 0 {
            first, second = second, first
        }
        corners: [3]int = {i, first, second}
        for corner in corners {
            vertex: ui.AaVertex = triangles[corner]
            point: ui.Vec2 = ui_default.PaintPoint(painter, vertex.position)
            rlgl.Color4ub(color.r, color.g, color.b, u8(f32(color.a) * vertex.coverage + 0.5))
            rlgl.Vertex2f(point.x, point.y)
        }
    }
}

// The size of the window in logical units: pass the UI scale of the painter (`ui_default.PainterScale(&painter)`)
ScreenSize :: proc(scale: f32 = 1) -> ui.Vec2 {
    return {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())} / scale
}

// What raylib knows of this frame, for ui.UiBegin. Call it once per frame (it drains the typed characters). The pointer is given in logical units: pass the UI scale of the painter.
InputPoll :: proc(scale: f32 = 1) -> ui.Input {
    input: ui.Input = {
        mouse_position = rl.GetMousePosition() / scale,
        mouse_down = rl.IsMouseButtonDown(.LEFT),
        mouse_pressed = rl.IsMouseButtonPressed(.LEFT),
        mouse_released = rl.IsMouseButtonReleased(.LEFT),
        wheel = rl.GetMouseWheelMoveV(),
    }
    ctrl: bool = rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) || rl.IsKeyDown(.LEFT_SUPER) || rl.IsKeyDown(.RIGHT_SUPER)
    if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) { input.modifiers += {.SHIFT} }
    if ctrl { input.modifiers += {.CTRL} }
    if rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT) { input.modifiers += {.ALT} }
    // typed characters come as runes: written as UTF-8 (with Ctrl held they are commands: drained and dropped)
    for int(input.text_count) < ui.INPUT_TEXT_CAPACITY - 4 {
        character: rune = rl.GetCharPressed()
        if character == 0 { break }
        if ctrl { continue }
        encoded, width := encodeRune(character)
        for i in 0 ..< width {
            input.text[input.text_count] = encoded[i]
            input.text_count += 1
        }
    }
    // a key that is held repeats (the key repeat of raylib), like in a text editor
    keys: [ui.Key]rl.KeyboardKey = {
        .BACKSPACE = .BACKSPACE, .DELETE = .DELETE, .LEFT = .LEFT, .RIGHT = .RIGHT, .HOME = .HOME, .END = .END,
        .ENTER = .ENTER, .ESCAPE = .ESCAPE, .TAB = .TAB,
    }
    for key in ui.Key {
        if rl.IsKeyPressed(keys[key]) || rl.IsKeyPressedRepeat(keys[key]) { input.keys += {key} }
    }
    input.actions = ui.KeyMapActions(KeyMapOf(), inputProbe, nil, input.modifiers)
    return input
}

// The hotkeys of the ui as data, in the numbers of raylib (a key is `u16(rl.KeyboardKey)`, a pad button `u16(rl.GamepadButton)`): Godot's default input map from the keyboard and the
// first gamepad (d-pad, A accepts, B cancels, the shoulders are next and previous) and the shortcuts of the editors. A program changes the table with `ui.KeyMapSet(ui_raylib.KeyMapOf(), ...)`.
KeyMapDefault :: proc() -> ui.KeyMap {
    k :: proc(key: rl.KeyboardKey) -> u16 { return u16(key) }
    p :: proc(button: rl.GamepadButton) -> u16 { return u16(button) }
    return ui.KeyMapFromCodes(
        {
            enter = k(.ENTER), keypad_enter = k(.KP_ENTER), space = k(.SPACE), escape = k(.ESCAPE), tab = k(.TAB),
            up = k(.UP), down = k(.DOWN), left = k(.LEFT), right = k(.RIGHT), page_up = k(.PAGE_UP), page_down = k(.PAGE_DOWN), home = k(.HOME), end = k(.END),
            f2 = k(.F2), c = k(.C), x = k(.X), v = k(.V), a = k(.A), d = k(.D), z = k(.Z), y = k(.Y), i = k(.I), r = k(.R),
        },
        {
            present = true, up = p(.LEFT_FACE_UP), down = p(.LEFT_FACE_DOWN), left = p(.LEFT_FACE_LEFT), right = p(.LEFT_FACE_RIGHT),
            accept = p(.RIGHT_FACE_DOWN), cancel = p(.RIGHT_FACE_RIGHT), previous = p(.LEFT_TRIGGER_1), next = p(.RIGHT_TRIGGER_1),
        },
    )
}

@(private)
keymap: ui.KeyMap
@(private)
keymap_ready: bool

// The table every call of InputPoll goes through; the default one until a program changes it
KeyMapOf :: proc() -> ^ui.KeyMap {
    if !keymap_ready {
        keymap, keymap_ready = KeyMapDefault(), true
    }
    return &keymap
}

// What went down in this frame, for the table. The arrows and the page keys repeat while held, like in a text editor.
@(private)
inputProbe :: proc(user: rawptr, device: ui.InputDevice, code: u16) -> bool {
    switch device {
    case .KEYBOARD:
        key: rl.KeyboardKey = rl.KeyboardKey(code)
        if rl.IsKeyPressed(key) { return true }
        #partial switch key {
        case .UP, .DOWN, .LEFT, .RIGHT, .PAGE_UP, .PAGE_DOWN: return rl.IsKeyPressedRepeat(key)
        }
    case .MOUSE:
        return rl.IsMouseButtonPressed(rl.MouseButton(code))
    case .GAMEPAD:
        return rl.IsGamepadAvailable(0) && rl.IsGamepadButtonPressed(0, rl.GamepadButton(code))
    case .NONE:
    }
    return false
}

// Pictures of the program's own for `ui.Glyph.texture` (a button of a pad): register a raylib texture and put the number it gives in the glyph. The textures stay the program's.
TEXTURE_SLOTS :: 32

@(private)
textures: [TEXTURE_SLOTS]rl.Texture2D
@(private)
texture_count: int

// The number of a texture for `ui.Glyph.texture` (0 when all TEXTURE_SLOTS are taken). The same texture gets the same number.
TextureRegister :: proc(texture: rl.Texture2D) -> u32 {
    for i in 0 ..< texture_count {
        if textures[i].id == texture.id { return u32(i + 1) }
    }
    if texture_count >= TEXTURE_SLOTS { return 0 }
    textures[texture_count] = texture
    texture_count += 1
    return u32(texture_count)
}

@(private)
encodeRune :: proc(character: rune) -> (bytes: [4]u8, width: int) {
    value: u32 = u32(character)
    switch {
    case value < 0x80:
        return {u8(value), 0, 0, 0}, 1
    case value < 0x800:
        return {u8(0xC0 | value >> 6), u8(0x80 | value & 0x3F), 0, 0}, 2
    case value < 0x10000:
        return {u8(0xE0 | value >> 12), u8(0x80 | (value >> 6) & 0x3F), u8(0x80 | value & 0x3F), 0}, 3
    }
    return {u8(0xF0 | value >> 18), u8(0x80 | (value >> 12) & 0x3F), u8(0x80 | (value >> 6) & 0x3F), u8(0x80 | value & 0x3F)}, 4
}

// Sets the mouse cursor to what the ui says the pointer is over (call after UiEnd)
ApplyCursor :: proc(ctx: ^ui.Context) {
    cursor: rl.MouseCursor
    switch ui.UiCursor(ctx) {
    case .ARROW: cursor = .DEFAULT
    case .TEXT: cursor = .IBEAM
    case .HAND: cursor = .POINTING_HAND
    case .RESIZE_HORIZONTAL: cursor = .RESIZE_EW
    case .RESIZE_VERTICAL: cursor = .RESIZE_NS
    case .RESIZE_DIAGONAL_NWSE: cursor = .RESIZE_NWSE
    case .RESIZE_DIAGONAL_NESW: cursor = .RESIZE_NESW
    case .NOT_ALLOWED: cursor = .NOT_ALLOWED
    }
    rl.SetMouseCursor(cursor)
}

// Connects the clipboard of the system to the text fields (call it once after ui.UiInit). Without it copy and paste work inside of the program only.
ClipboardInstall :: proc(ctx: ^ui.Context) {
    ctx.clipboard.get = proc(ctx: ^ui.Context, buffer: []u8) -> int {
        text: string = string(rl.GetClipboardText())
        count: int = min(len(text), len(buffer))
        copy(buffer[:count], text[:count])
        return count
    }
    ctx.clipboard.set = proc(ctx: ^ui.Context, text: string) {
        buffer: [ui.CLIPBOARD_LOCAL + 1]u8
        count: int = min(len(text), ui.CLIPBOARD_LOCAL)
        copy(buffer[:count], text[:count])
        buffer[count] = 0
        rl.SetClipboardText(cstring(raw_data(buffer[:])))
    }
}
