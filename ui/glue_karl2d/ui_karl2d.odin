package ui_karl2d

// Glue for Karl2D: the Painter of the default style drawn with Karl2D calls, and the input of a frame as ui.Input.
// A frame in a Karl2D program:
//
//     painter: ui_default.Painter
//     ui_karl2d.PainterInit(&painter)
//     style := ui_default.StyleMake()
//     ui.UiInit(&ctx, &storage, ui_default.Measure, &painter)
//
//     for karl2d.update() {
//         karl2d.clear(...)
//         ... the game ...
//         ui.UiBegin(&ctx, ui_karl2d.InputPoll(), karl2d.get_frame_time(), ui_karl2d.ScreenSize(), &style)
//         ... widgets ...
//         ui.UiEnd(&ctx)
//         ui.UiRender(&ctx)       // the style procs draw into the batch of Karl2D that is open: the one of the game
//         karl2d.present()
//     }
//
// Karl2D has no rounded rectangle: the painter does not set `fill_rounded`, so the default style fills the polygon of ui.RoundedPoints.

import "../../karl2d"
import ui ".."
import ui_default "../default_style"
import font "../../font"
import font_karl2d "../../font/glue_karl2d"
import icons "../../icons"

// The fonts of the default style as Karl2D fonts: Inter for text (the labels of controls in semibold), JetBrains Mono for numbers and code, Lucide for the icons.
// The files are part of the program that calls FontsLoad (about 1.5 MB); their licenses (SIL Open Font License, ISC, MIT) ask for their notices to go with the program:
// assets/fonts/inter/Inter-OFL.txt, assets/fonts/jetbrains_mono/OFL.txt, icons/lucide/LICENSE.
Fonts :: struct {
    faces: [ui_default.Face]karl2d.Font,
    icons: karl2d.Font,
}

INTER_REGULAR :: #load("../../assets/fonts/inter/Inter-Regular.ttf")
INTER_SEMIBOLD :: #load("../../assets/fonts/inter/Inter-SemiBold.ttf")
INTER_ITALIC :: #load("../../assets/fonts/inter/Inter-Italic.ttf")
JETBRAINS_MONO :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-Regular.ttf")
JETBRAINS_MONO_BOLD :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-Bold.ttf")
JETBRAINS_MONO_ITALIC :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-Italic.ttf")
JETBRAINS_MONO_BOLD_ITALIC :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-BoldItalic.ttf")
INTER_SEMIBOLD_ITALIC :: #load("../../assets/fonts/inter/Inter-SemiBoldItalic.ttf")

// Loads the fonts of the style (after karl2d.init). The fonts make their glyphs at the sizes they are drawn in. False when one could not be loaded (it is then the default font).
// `skin`: the font files of a skin (ui_default.SkinFontsRead): a face that has bytes is drawn in that font, a font that does not load is the built in one.
FontsLoad :: proc(fonts: ^Fonts, skin: ^ui_default.SkinFontBytes = nil) -> bool {
    all: bool = true
    load :: proc(bytes: []u8, all: ^bool) -> karl2d.Font {
        loaded, ok := karl2d.load_dynamic_font_from_bytes(bytes)
        if !ok {
            all^ = false
            return karl2d.FONT_DEFAULT
        }
        return loaded
    }
    sources: [ui_default.Face][]u8 = {
        .REGULAR = INTER_REGULAR, .STRONG = INTER_SEMIBOLD, .ITALIC = INTER_ITALIC, .MONO = JETBRAINS_MONO, .MONO_STRONG = JETBRAINS_MONO_BOLD,
        .STRONG_ITALIC = INTER_SEMIBOLD_ITALIC, .MONO_ITALIC = JETBRAINS_MONO_ITALIC, .MONO_STRONG_ITALIC = JETBRAINS_MONO_BOLD_ITALIC,
    }
    for face in ui_default.Face {
        if skin != nil && len(skin[face]) > 0 {
            own, ok := karl2d.load_dynamic_font_from_bytes(skin[face])
            if ok {
                fonts.faces[face] = own
                continue
            }
        }
        fonts.faces[face] = load(sources[face], &all)
    }
    fonts.icons = load(icons.LUCIDE_FONT, &all)
    return all
}

FontsUnload :: proc(fonts: ^Fonts) {
    for face in fonts.faces {
        if face != karl2d.FONT_DEFAULT { karl2d.destroy_font(face) }
    }
    if fonts.icons != karl2d.FONT_DEFAULT { karl2d.destroy_font(fonts.icons) }
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
        box: ui.Rect = ui_default.PaintRect(painter, rect)
        karl2d.draw_text(icons.IconString(&text, length), {box.x, box.y}, min(box.z, box.w), color, (cast(^Fonts)painter.fonts).icons)
    }
}

// The same for a painter that draws its text from outlines (PainterUseVectorText): the faces are added to the text system (their bytes are the ones of this package) and
// the painter picks them. Call it after PainterUseVectorText. False when the system has no room for the faces.
PainterUseVectorFonts :: proc(painter: ^ui_default.Painter, system: ^font_karl2d.TextSystem) -> bool {
    FIRST_FACE :: font.ATLAS_FACES - 8          // the last eight faces of an atlas: the first ones are the family of the font the system was made with
    sources: [8][]u8 = {INTER_SEMIBOLD, INTER_ITALIC, INTER_SEMIBOLD_ITALIC, JETBRAINS_MONO, JETBRAINS_MONO_BOLD, JETBRAINS_MONO_ITALIC, JETBRAINS_MONO_BOLD_ITALIC, icons.LUCIDE_FONT}
    for bytes, i in sources {
        if !font_karl2d.TextSystemAddFace(system, FIRST_FACE + i, bytes) { return false }
    }
    painter.vector_faces = {.REGULAR = 0, .STRONG = FIRST_FACE, .ITALIC = FIRST_FACE + 1, .STRONG_ITALIC = FIRST_FACE + 2, .MONO = FIRST_FACE + 3, .MONO_STRONG = FIRST_FACE + 4, .MONO_ITALIC = FIRST_FACE + 5, .MONO_STRONG_ITALIC = FIRST_FACE + 6}
    painter.vector_icon_face = FIRST_FACE + 7
    painter.glue_fonts[.MONO] = 1
    painter.draw_icon = proc(painter: ^ui_default.Painter, icon: icons.Icon, rect: ui.Rect, color: ui.Color) {
        text, length := icons.IconText(icon)
        box: ui.Rect = ui_default.PaintRect(painter, rect)
        font_karl2d.TextSystemDraw(cast(^font_karl2d.TextSystem)painter.vector_text, icons.IconString(&text, length), {box.x, box.y}, min(box.z, box.w), color, {face = painter.vector_icon_face})
    }
    return true
}

// Draws the text of the ui from the outlines of a font with the font library (sharp at any size and scale) instead of Karl2D's own font: the size of a text stays the height of its line, so the
// layout does not change. The system (font_karl2d.TextSystem) has to live as long as the painter and be made after karl2d.init.
PainterUseVectorText :: proc(painter: ^ui_default.Painter, system: ^font_karl2d.TextSystem) {
    painter.vector_text = system
    // the text of a run of labels is one batch: it is collected here and drawn when a shape comes, a clip changes or UiRender ends
    system.renderer.deferred = true
    painter.flush = proc(painter: ^ui_default.Painter) {
        if painter.vector_text != nil { font_karl2d.RendererFlush(&(cast(^font_karl2d.TextSystem)painter.vector_text).renderer) }
    }
    painter.draw_text = proc(painter: ^ui_default.Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color) {
        scale: f32 = ui_default.PainterScale(painter)
        font_karl2d.TextSystemDraw(cast(^font_karl2d.TextSystem)painter.vector_text, text, ui_default.PaintPoint(painter, position), size * scale, color, {face = painter.vector_faces[painter.face]})
    }
    painter.measure_text = proc(painter: ^ui_default.Painter, text: string, size: f32) -> ui.Vec2 {
        scale: f32 = ui_default.PainterScale(painter)
        return font_karl2d.TextSystemMeasure(cast(^font_karl2d.TextSystem)painter.vector_text, text, size * scale, {face = painter.vector_faces[painter.face]}) / scale
    }
}

// Fills a painter with Karl2D draw procs. `font` is the font of the text (the default font of Karl2D when left as it is).
PainterInit :: proc(painter: ^ui_default.Painter, font: ^karl2d.Font = nil) {
    painter^ = {
        user = font,
        theme = ui_default.THEME_DARK,
        fill_rect = proc(painter: ^ui_default.Painter, rect: ui.Rect, color: ui.Color) {
            ui_default.PainterFlush(painter)
            karl2d.draw_rect(transmute(karl2d.Rect)ui_default.PaintRect(painter, rect), color)
        },
        fill_polygon = proc(painter: ^ui_default.Painter, points: []ui.Vec2, color: ui.Color) {
            ui_default.PainterFlush(painter)
            // the polygon is convex: a fan from its first point
            first: ui.Vec2 = ui_default.PaintPoint(painter, points[0])
            for i in 1 ..< len(points) - 1 {
                karl2d.draw_triangle({first, ui_default.PaintPoint(painter, points[i]), ui_default.PaintPoint(painter, points[i + 1])}, color)
            }
        },
        fill_mesh = fillMesh,
        mesh = {vertices = meshStorage[:]},
        draw_text = proc(painter: ^ui_default.Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color) {
            scale: f32 = ui_default.PainterScale(painter)
            karl2d.draw_text(text, ui_default.PaintPoint(painter, position), size * scale, color, fontOf(painter))
        },
        measure_text = proc(painter: ^ui_default.Painter, text: string, size: f32) -> ui.Vec2 {
            scale: f32 = ui_default.PainterScale(painter)
            return karl2d.measure_text(text, size * scale, fontOf(painter)) / scale
        },
        draw_texture = proc(painter: ^ui_default.Painter, texture: u32, source: ui.Rect, destination: ui.Rect, tint: ui.Color) {
            if texture == 0 || int(texture) > texture_count { return }
            ui_default.PainterFlush(painter)
            picture: karl2d.Texture = textures[texture - 1]
            from: ui.Rect = source
            if from.z <= 0 || from.w <= 0 {
                size: karl2d.Vec2 = karl2d.get_texture_size(picture)
                from = {0, 0, size.x, size.y}
            }
            karl2d.draw_texture_fit(picture, transmute(karl2d.Rect)from, transmute(karl2d.Rect)ui_default.PaintRect(painter, destination), {}, 0, tint)
        },
        clip = proc(painter: ^ui_default.Painter, rect: ui.Rect, begin: bool) {
            ui_default.PainterFlush(painter)
            if begin {
                karl2d.set_scissor_rect(transmute(karl2d.Rect)ui_default.PaintRect(painter, rect))
            } else {
                karl2d.set_scissor_rect(nil)
            }
        },
    }
}

// Where the soft edged shapes of every painter are built (one frame at a time: a shape is drawn as soon as it is built, so one storage serves all painters)
MESH_VERTICES :: 24576
@(private)
meshStorage: [MESH_VERTICES]ui.AaVertex

// The triangles of a smooth shape, each corner with the alpha of the color times its coverage: Karl2D puts them in the batch that is open, with the rectangles and the text
@(private)
fillMesh :: proc(painter: ^ui_default.Painter, triangles: []ui.AaVertex, color: ui.Color) {
    ui_default.PainterFlush(painter)
    CHUNK :: 768
    converted: [CHUNK]karl2d.Colored_Vertex
    offset: int = 0
    for offset < len(triangles) {
        count: int = min(CHUNK, len(triangles) - offset)
        for i in 0 ..< count {
            vertex: ui.AaVertex = triangles[offset + i]
            converted[i] = {ui_default.PaintPoint(painter, vertex.position), {color.r, color.g, color.b, u8(f32(color.a) * vertex.coverage + 0.5)}}
        }
        karl2d.draw_colored_triangles(converted[:count])
        offset += count
    }
}

// The font of the face the painter is set to: of its set of fonts (PainterUseFonts), else the one font it was made with, else the font of Karl2D
@(private)
fontOf :: proc(painter: ^ui_default.Painter) -> karl2d.Font {
    if painter.fonts != nil { return (cast(^Fonts)painter.fonts).faces[painter.face] }
    if painter.user == nil { return karl2d.FONT_DEFAULT }
    return (cast(^karl2d.Font)painter.user)^
}

// The size of the window in logical units: pass the UI scale of the painter (`ui_default.PainterScale(&painter)`)
ScreenSize :: proc(scale: f32 = 1) -> ui.Vec2 {
    return {f32(karl2d.get_screen_width()), f32(karl2d.get_screen_height())} / scale
}

// What Karl2D knows of this frame (call it after karl2d.update), for ui.UiBegin. The pointer is given in logical units: pass the UI scale of the painter.
InputPoll :: proc(scale: f32 = 1) -> ui.Input {
    input: ui.Input = {
        mouse_position = karl2d.get_mouse_position() / scale,
        mouse_down = karl2d.mouse_button_is_held(.Left),
        mouse_pressed = karl2d.mouse_button_went_down(.Left),
        mouse_released = karl2d.mouse_button_went_up(.Left),
    }
    ctrl: bool = karl2d.key_is_held(.Left_Control) || karl2d.key_is_held(.Right_Control) || karl2d.key_is_held(.Left_Super) || karl2d.key_is_held(.Right_Super)
    if karl2d.key_is_held(.Left_Shift) || karl2d.key_is_held(.Right_Shift) { input.modifiers += {.SHIFT} }
    if ctrl { input.modifiers += {.CTRL} }
    if karl2d.key_is_held(.Left_Alt) || karl2d.key_is_held(.Right_Alt) { input.modifiers += {.ALT} }
    for event in karl2d.get_events() {
        #partial switch e in event {
        case karl2d.Event_Mouse_Wheel:
            input.wheel.y += e.delta
        case karl2d.Event_Typed_Rune:
            // printable characters only: a control character (backspace, enter) arrives as a key
            if e.typed >= 32 && e.typed != 127 && !ctrl {
                encoded, width := encodeRune(e.typed)
                if int(input.text_count) + width <= ui.INPUT_TEXT_CAPACITY {
                    for i in 0 ..< width {
                        input.text[input.text_count] = encoded[i]
                        input.text_count += 1
                    }
                }
            }
        }
    }
    keys: [ui.Key]karl2d.Keyboard_Key = {
        .BACKSPACE = .Backspace, .DELETE = .Delete, .LEFT = .Left, .RIGHT = .Right, .HOME = .Home, .END = .End,
        .ENTER = .Enter, .ESCAPE = .Escape, .TAB = .Tab,
    }
    for key in ui.Key {
        if karl2d.key_went_down(keys[key], allow_repeat = true) { input.keys += {key} }
    }
    input.actions = ui.KeyMapActions(KeyMapOf(), inputProbe, nil, input.modifiers)
    return input
}

// The hotkeys of the ui as data, in the numbers of Karl2D (a key is `u16(karl2d.Keyboard_Key)`, a pad button `u16(karl2d.Gamepad_Button)`): Godot's default input map from the keyboard and
// the first gamepad (d-pad, A accepts, B cancels, the shoulders are next and previous) and the shortcuts of the editors. A program changes the table with `ui.KeyMapSet(ui_karl2d.KeyMapOf(), ...)`.
KeyMapDefault :: proc() -> ui.KeyMap {
    k :: proc(key: karl2d.Keyboard_Key) -> u16 { return u16(key) }
    p :: proc(button: karl2d.Gamepad_Button) -> u16 { return u16(button) }
    return ui.KeyMapFromCodes(
        {
            enter = k(.Enter), space = k(.Space), escape = k(.Escape), tab = k(.Tab),
            up = k(.Up), down = k(.Down), left = k(.Left), right = k(.Right), page_up = k(.Page_Up), page_down = k(.Page_Down), home = k(.Home), end = k(.End),
            f2 = k(.F2), c = k(.C), x = k(.X), v = k(.V), a = k(.A), d = k(.D), z = k(.Z), y = k(.Y), i = k(.I), r = k(.R),
        },
        {
            present = true, up = p(.Left_Face_Up), down = p(.Left_Face_Down), left = p(.Left_Face_Left), right = p(.Left_Face_Right),
            accept = p(.Right_Face_Down), cancel = p(.Right_Face_Right), previous = p(.Left_Shoulder), next = p(.Right_Shoulder),
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
        key: karl2d.Keyboard_Key = karl2d.Keyboard_Key(code)
        #partial switch key {
        case .Up, .Down, .Left, .Right, .Page_Up, .Page_Down: return karl2d.key_went_down(key, allow_repeat = true)
        }
        return karl2d.key_went_down(key)
    case .MOUSE:
        return karl2d.mouse_button_went_down(karl2d.Mouse_Button(code))
    case .GAMEPAD:
        return karl2d.is_gamepad_active(0) && karl2d.gamepad_button_went_down(0, karl2d.Gamepad_Button(code))
    case .NONE:
    }
    return false
}

// Pictures of the program's own for `ui.Glyph.texture` (a button of a pad): register a Karl2D texture and put the number it gives in the glyph. The textures stay the program's.
TEXTURE_SLOTS :: 32

@(private)
textures: [TEXTURE_SLOTS]karl2d.Texture
@(private)
texture_count: int

// The number of a texture for `ui.Glyph.texture` (0 when all TEXTURE_SLOTS are taken). The same texture gets the same number.
TextureRegister :: proc(texture: karl2d.Texture) -> u32 {
    for i in 0 ..< texture_count {
        if textures[i] == texture { return u32(i + 1) }
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
    cursor: karl2d.Standard_Cursor
    switch ui.UiCursor(ctx) {
    case .ARROW: cursor = .Default
    case .TEXT: cursor = .Text
    case .HAND: cursor = .Hand
    case .RESIZE_HORIZONTAL: cursor = .Resize_EW
    case .RESIZE_VERTICAL: cursor = .Resize_NS
    case .RESIZE_DIAGONAL_NWSE: cursor = .Resize_NWSE
    case .RESIZE_DIAGONAL_NESW: cursor = .Resize_NESW
    case .NOT_ALLOWED: cursor = .Not_Allowed
    }
    karl2d.set_cursor(cursor)
}
