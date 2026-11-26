// The ui library over the demo kit (odin_utilities/demo_kit): a Painter that draws through kit.Context and the input of a kit frame as ui.Input.
// So a demo written against the kit has the ui on raylib, on Karl2D and headless (the scripts of the tests click real widgets).
package ui_kit

import "core:reflect"

import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"
import icons "../../icons"

// The fonts of the default style: Inter for text (the labels of controls in semibold), JetBrains Mono for numbers and code, Lucide for the icons. They are loaded into the
// backend of the kit once (the first Begin) and stay for the run of the program: every demo of a program shares them.
INTER_REGULAR :: #load("../../assets/fonts/inter/Inter-Regular.ttf")
INTER_SEMIBOLD :: #load("../../assets/fonts/inter/Inter-SemiBold.ttf")
INTER_ITALIC :: #load("../../assets/fonts/inter/Inter-Italic.ttf")
JETBRAINS_MONO :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-Regular.ttf")
JETBRAINS_MONO_BOLD :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-Bold.ttf")
JETBRAINS_MONO_ITALIC :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-Italic.ttf")
JETBRAINS_MONO_BOLD_ITALIC :: #load("../../assets/fonts/jetbrains_mono/JetBrainsMono-BoldItalic.ttf")
INTER_SEMIBOLD_ITALIC :: #load("../../assets/fonts/inter/Inter-SemiBoldItalic.ttf")

@(private)
Fonts :: struct {
    backend: ^kit.Backend,
    faces: [ui_default.Face]kit.Font,
    icons: kit.Font,
    skin_serial: u32,           // the skin the faces were made from
}

@(private)
fonts: Fonts

// The font files of a skin (ui_default.SkinFontsRead): a face that has bytes is drawn in that font, the others in the built in one. The bytes have to stay alive until the next call; the kit loads the
// fonts again before the next frame.
@(private)
skin_bytes: ui_default.SkinFontBytes
@(private)
skin_serial: u32

UseSkinFonts :: proc(bytes: ^ui_default.SkinFontBytes) {
    skin_bytes = bytes^ if bytes != nil else {}
    skin_serial += 1
}

// Loads the fonts into the backend of `ctx` when they are not there yet, and tells the painter their numbers
@(private)
fontsEnsure :: proc(painter: ^ui_default.Painter, ctx: ^kit.Context) {
    if fonts.backend == ctx.backend && fonts.skin_serial != skin_serial {
        // another skin: the faces of the old one go (the icons stay)
        for face in ui_default.Face {
            if fonts.faces[face] != kit.FONT_DEFAULT { kit.FontUnload(ctx, fonts.faces[face]) }
        }
        icons_font: kit.Font = fonts.icons
        fonts = {backend = ctx.backend, icons = icons_font}
        fontsLoadFaces(ctx)
    } else if fonts.backend != ctx.backend {
        fonts = {backend = ctx.backend}
        fontsLoadFaces(ctx)
        fonts.icons = kit.FontLoad(ctx, icons.LUCIDE_FONT, 32, len(icons.Icon) - 1, int(icons.ICON_FIRST_CHARACTER))       // without NONE, which has no glyph
    }
    for face in ui_default.Face { painter.glue_fonts[face] = u32(fonts.faces[face]) }
    painter.glue_icon_font = u32(fonts.icons)
    painter.glue_ready = true
}

@(private)
fontsLoadFaces :: proc(ctx: ^kit.Context) {
    sources: [ui_default.Face][]u8 = {
        .REGULAR = INTER_REGULAR, .STRONG = INTER_SEMIBOLD, .ITALIC = INTER_ITALIC, .MONO = JETBRAINS_MONO, .MONO_STRONG = JETBRAINS_MONO_BOLD,
        .STRONG_ITALIC = INTER_SEMIBOLD_ITALIC, .MONO_ITALIC = JETBRAINS_MONO_ITALIC, .MONO_STRONG_ITALIC = JETBRAINS_MONO_BOLD_ITALIC,
    }
    for face in ui_default.Face {
        bytes: []u8 = skin_bytes[face] if len(skin_bytes[face]) > 0 else sources[face]
        loaded: kit.Font = kit.FontLoad(ctx, bytes, 32, 1280)
        if loaded == kit.FONT_DEFAULT && len(skin_bytes[face]) > 0 { loaded = kit.FontLoad(ctx, sources[face], 32, 1280) }       // a file that is no font: the built in one
        fonts.faces[face] = loaded
    }
    fonts.skin_serial = skin_serial
}

// Gives the fonts back to the backend. A program that loads its code again while it runs (hot reload) calls this from the old code, so the new code loads them again into free slots
FontsRelease :: proc(ctx: ^kit.Context) {
    if fonts.backend != ctx.backend { return }
    for face in ui_default.Face { if fonts.faces[face] != kit.FONT_DEFAULT { kit.FontUnload(ctx, fonts.faces[face]) } }
    if fonts.icons != kit.FONT_DEFAULT { kit.FontUnload(ctx, fonts.icons) }
    fonts = {}
}

// The kit font of the face the painter is set to (the regular one for a face that could not be loaded, the font of the kit before the fonts are loaded)
@(private)
fontOf :: proc(painter: ^ui_default.Painter) -> kit.Font {
    font: kit.Font = kit.Font(painter.glue_fonts[painter.face])
    face: ui_default.Face = painter.face
    for font == kit.FONT_DEFAULT && face != .REGULAR {
        face = ui_default.FaceFallback(face)
        font = kit.Font(painter.glue_fonts[face])
    }
    return font if font != kit.FONT_DEFAULT else kit.Font(painter.glue_fonts[.REGULAR])
}

// Where the soft edged shapes are built (a shape is drawn as soon as it is built, so one storage serves all painters)
MESH_VERTICES :: 24576
@(private)
meshStorage: [MESH_VERTICES]ui.AaVertex

// The triangles of a smooth shape through the kit, in chunks: alpha of the color times the coverage of each corner
@(private)
fillMesh :: proc(painter: ^ui_default.Painter, triangles: []ui.AaVertex, color: ui.Color) {
    ctx: ^kit.Context = contextOf(painter)
    if !kit.CanDrawTriangles(ctx) { return }
    CHUNK :: 768
    converted: [CHUNK]kit.Vertex
    offset: int = 0
    for offset < len(triangles) {
        count: int = min(CHUNK, len(triangles) - offset)
        for i in 0 ..< count {
            vertex: ui.AaVertex = triangles[offset + i]
            converted[i] = {ui_default.PaintPoint(painter, vertex.position), {color.r, color.g, color.b, u8(f32(color.a) * vertex.coverage + 0.5)}}
        }
        kit.DrawTriangles(ctx, converted[:count])
        offset += count
    }
}

// Fills a painter with the procs that draw through the kit. Call Begin every frame: it tells the painter which kit.Context it draws into.
PainterInit :: proc(painter: ^ui_default.Painter) {
    painter^ = {
        theme = ui_default.THEME_DARK,
        fill_rect = proc(painter: ^ui_default.Painter, rect: ui.Rect, color: ui.Color) {
            kit.DrawRect(contextOf(painter), kit.Rect(ui_default.PaintRect(painter, rect)), kit.Color(color))
        },
        fill_polygon = proc(painter: ^ui_default.Painter, points: []ui.Vec2, color: ui.Color) {
            // the polygon is convex: a fan from its first point
            first: ui.Vec2 = ui_default.PaintPoint(painter, points[0])
            for i in 1 ..< len(points) - 1 {
                kit.DrawTriangle(contextOf(painter), first, ui_default.PaintPoint(painter, points[i]), ui_default.PaintPoint(painter, points[i + 1]), kit.Color(color))
            }
        },
        fill_mesh = fillMesh,
        mesh = {vertices = meshStorage[:]},
        fill_rounded = proc(painter: ^ui_default.Painter, rect: ui.Rect, radius: f32, color: ui.Color) {
            scale: f32 = ui_default.PainterScale(painter)
            fillRounded(painter, ui_default.PaintRect(painter, rect), radius * scale, color)
        },
        draw_text = proc(painter: ^ui_default.Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color) {
            scale: f32 = ui_default.PainterScale(painter)
            kit.DrawTextFont(contextOf(painter), fontOf(painter), text, ui_default.PaintPoint(painter, position), size * scale, kit.Color(color))
        },
        measure_text = proc(painter: ^ui_default.Painter, text: string, size: f32) -> ui.Vec2 {
            scale: f32 = ui_default.PainterScale(painter)
            return kit.MeasureTextFont(contextOf(painter), fontOf(painter), text, size * scale) / scale
        },
        draw_icon = proc(painter: ^ui_default.Painter, icon: icons.Icon, rect: ui.Rect, color: ui.Color) {
            if painter.glue_icon_font == 0 { return }
            // an icon is a letter of the icon font: its box is the em, so the size of the text is the side of the square
            text, length := icons.IconText(icon)
            box: ui.Rect = ui_default.PaintRect(painter, rect)
            kit.DrawTextFont(contextOf(painter), kit.Font(painter.glue_icon_font), icons.IconString(&text, length), {box.x, box.y}, min(box.z, box.w), kit.Color(color))
        },
        draw_texture = proc(painter: ^ui_default.Painter, texture: u32, source: ui.Rect, destination: ui.Rect, tint: ui.Color) {
            ctx: ^kit.Context = contextOf(painter)
            handle: kit.Texture = kit.Texture(texture)
            from: kit.Rect = kit.Rect(source)
            if from.z <= 0 || from.w <= 0 {
                size: kit.Vec2 = kit.TextureSize(ctx, handle)
                from = {0, 0, size.x, size.y}
            }
            kit.DrawTextureRect(ctx, handle, from, kit.Rect(ui_default.PaintRect(painter, destination)), {}, 0, kit.Color(tint))
        },
        clip = proc(painter: ^ui_default.Painter, rect: ui.Rect, begin: bool) {
            if begin {
                kit.ClipBegin(contextOf(painter), kit.Rect(ui_default.PaintRect(painter, rect)))
            } else {
                kit.ClipEnd(contextOf(painter))
            }
        },
    }
}

@(private)
contextOf :: proc(painter: ^ui_default.Painter) -> ^kit.Context {
    return cast(^kit.Context)painter.user
}

// The kit has no rounded rectangle: three rectangles and four circles make one, with the same radius on every corner
@(private)
fillRounded :: proc(painter: ^ui_default.Painter, rect: ui.Rect, radius: f32, color: ui.Color) {
    ctx: ^kit.Context = contextOf(painter)
    color_kit: kit.Color = kit.Color(color)
    r: f32 = radius
    kit.DrawRect(ctx, {rect.x + r, rect.y, rect.z - 2 * r, rect.w}, color_kit)
    kit.DrawRect(ctx, {rect.x, rect.y + r, r, rect.w - 2 * r}, color_kit)
    kit.DrawRect(ctx, {rect.x + rect.z - r, rect.y + r, r, rect.w - 2 * r}, color_kit)
    kit.DrawCircle(ctx, {rect.x + r, rect.y + r}, r, color_kit)
    kit.DrawCircle(ctx, {rect.x + rect.z - r, rect.y + r}, r, color_kit)
    kit.DrawCircle(ctx, {rect.x + r, rect.y + rect.w - r}, r, color_kit)
    kit.DrawCircle(ctx, {rect.x + rect.z - r, rect.y + rect.w - r}, r, color_kit)
}

// The table of hotkeys of the kit: which key, mouse button or button of a gamepad does which action of the ui. KeyMapDefault is what the keys were before they were a
// table (Godot's default input map and the shortcuts of the editors); a program changes it with `ui.KeyMapSet` on `KeyMapOf()`.
KeyMapDefault :: proc() -> ui.KeyMap {
    k :: proc(key: kit.Key) -> u16 { return u16(key) }
    p :: proc(button: kit.PadButton) -> u16 { return u16(button) }
    return ui.KeyMapFromCodes(
        {
            enter = k(.ENTER), space = k(.SPACE), escape = k(.ESCAPE), tab = k(.TAB),
            up = k(.UP), down = k(.DOWN), left = k(.LEFT), right = k(.RIGHT), page_up = k(.PAGE_UP), page_down = k(.PAGE_DOWN), home = k(.HOME), end = k(.END),
            f2 = k(.F2), c = k(.C), x = k(.X), v = k(.V), a = k(.A), d = k(.D), z = k(.Z), y = k(.Y), i = k(.I), r = k(.R),
        },
        {
            present = true, up = p(.DPAD_UP), down = p(.DPAD_DOWN), left = p(.DPAD_LEFT), right = p(.DPAD_RIGHT),
            accept = p(.FACE_DOWN), cancel = p(.FACE_RIGHT), previous = p(.LEFT_SHOULDER), next = p(.RIGHT_SHOULDER),
        },
    )
}

@(private)
keymap: ui.KeyMap
@(private)
keymap_ready: bool

// The table of hotkeys that every frame of the kit goes through; the default one until a program changes it
KeyMapOf :: proc() -> ^ui.KeyMap {
    if !keymap_ready {
        keymap, keymap_ready = KeyMapDefault(), true
    }
    return &keymap
}

// What went down in this frame, for the table: the keys and the mouse buttons of the kit input
@(private)
inputProbe :: proc(user: rawptr, device: ui.InputDevice, code: u16) -> bool {
    source: ^kit.Input = cast(^kit.Input)user
    switch device {
    case .KEYBOARD:
        key: kit.Key = kit.Key(u8(code))
        // the directions and the pages repeat while held (lists, menus, tables), the other keys act once
        if key == .UP || key == .DOWN || key == .LEFT || key == .RIGHT || key == .PAGE_UP || key == .PAGE_DOWN { return key in source.keys_repeat }
        return key in source.keys_pressed
    case .MOUSE: return kit.MouseButton(u8(code)) in source.mouse_pressed
    case .GAMEPAD: return kit.PadButton(u8(code)) in source.pad_pressed
    case .NONE: return false
    }
    return false
}

// A picture of the program's own per gamepad button (the art of the pad in use): set an entry and `GlyphOf` draws that texture instead of the vector shape. A zero texture
// keeps the shape. `source` is the part of the texture (zero size: all of it).
GlyphTexture :: struct {
    texture: kit.Texture,
    source: ui.Rect,
}
GlyphTextures: [kit.PadButton]GlyphTexture

// How the kit's inputs look (a `ui.GlyphProc`): keys by their names, the buttons of a gamepad as the shapes of an Xbox pad (the face buttons in its colors), the mouse buttons
// as "LMB", "RMB", "MMB". The names of keys are the names of `kit.Key` ("LEFT_BRACKET"); a program that wants nicer words passes its own proc.
GlyphOf :: proc(user: rawptr, binding: ui.Binding) -> ui.Glyph {
    switch binding.device {
    case .NONE:
        return {}
    case .KEYBOARD:
        return {shape = .KEY, label = keyLabel(kit.Key(u8(binding.code)))}
    case .MOUSE:
        switch kit.MouseButton(u8(binding.code)) {
        case .LEFT: return {shape = .MOUSE, label = "LMB"}
        case .RIGHT: return {shape = .MOUSE, label = "RMB"}
        case .MIDDLE: return {shape = .MOUSE, label = "MMB"}
        }
    case .GAMEPAD:
        button: kit.PadButton = kit.PadButton(u8(binding.code))
        glyph: ui.Glyph
        switch button {
        case .FACE_DOWN: glyph = {shape = .FACE, label = "A", color = {76, 160, 92, 255}}
        case .FACE_RIGHT: glyph = {shape = .FACE, label = "B", color = {206, 70, 64, 255}}
        case .FACE_LEFT: glyph = {shape = .FACE, label = "X", color = {66, 120, 210, 255}}
        case .FACE_UP: glyph = {shape = .FACE, label = "Y", color = {214, 170, 50, 255}}
        case .LEFT_SHOULDER: glyph = {shape = .SHOULDER, label = "LB"}
        case .RIGHT_SHOULDER: glyph = {shape = .SHOULDER, label = "RB"}
        case .LEFT_TRIGGER: glyph = {shape = .TRIGGER, label = "LT"}
        case .RIGHT_TRIGGER: glyph = {shape = .TRIGGER, label = "RT"}
        case .DPAD_UP: glyph = {shape = .DPAD, label = "U"}
        case .DPAD_DOWN: glyph = {shape = .DPAD, label = "D"}
        case .DPAD_LEFT: glyph = {shape = .DPAD, label = "L"}
        case .DPAD_RIGHT: glyph = {shape = .DPAD, label = "R"}
        case .LEFT_STICK: glyph = {shape = .STICK, label = "L"}
        case .RIGHT_STICK: glyph = {shape = .STICK, label = "R"}
        case .BACK: glyph = {shape = .KEY, label = "Back"}
        case .START: glyph = {shape = .KEY, label = "Start"}
        }
        if GlyphTextures[button].texture != kit.TEXTURE_NONE {
            glyph.texture, glyph.source = u32(GlyphTextures[button].texture), GlyphTextures[button].source
        }
        return glyph
    }
    return {}
}

// The label of a key on its cap: letters and digits as they are, the others by a short name
@(private)
keyLabel :: proc(key: kit.Key) -> string {
    #partial switch key {
    case .N0: return "0"
    case .N1: return "1"
    case .N2: return "2"
    case .N3: return "3"
    case .N4: return "4"
    case .N5: return "5"
    case .N6: return "6"
    case .N7: return "7"
    case .N8: return "8"
    case .N9: return "9"
    case .SPACE: return "Space"
    case .ENTER: return "Enter"
    case .ESCAPE: return "Esc"
    case .BACKSPACE: return "Back"
    case .LEFT: return "Left"
    case .RIGHT: return "Right"
    case .UP: return "Up"
    case .DOWN: return "Down"
    case .LEFT_SHIFT, .RIGHT_SHIFT: return "Shift"
    case .LEFT_CTRL, .RIGHT_CTRL: return "Ctrl"
    case .LEFT_ALT, .RIGHT_ALT: return "Alt"
    case .PAGE_UP: return "PgUp"
    case .PAGE_DOWN: return "PgDn"
    }
    return reflect.enum_string(key)
}

// The input that went down in this frame as a binding of the kit (device NONE: nothing did): the first key (a modifier alone counts: a game binds Shift), mouse
// button or gamepad button. For `ui.UiBindingField`.
BindingPressed :: proc(input: ^kit.Input) -> ui.Binding {
    for button in kit.PadButton {
        if button in input.pad_pressed { return {device = .GAMEPAD, code = u16(button)} }
    }
    for key in kit.Key {
        if key != .None && key in input.keys_pressed { return {device = .KEYBOARD, code = u16(key)} }
    }
    for button in kit.MouseButton {
        if button in input.mouse_pressed { return {device = .MOUSE, code = u16(button)} }
    }
    return {}
}

// The input of a kit frame for the ui. A pointer over the menu of the kit (ctx.ui_hover) is not for the ui. `scale` is the UI scale: the pointer is given in logical units.
InputFrom :: proc(ctx: ^kit.Context, scale: f32 = 1) -> ui.Input {
    source: ^kit.Input = &ctx.input
    result: ui.Input = {
        mouse_position = source.mouse_position / scale,
        mouse_down = .LEFT in source.mouse_down,
        mouse_pressed = .LEFT in source.mouse_pressed,
        mouse_released = .LEFT in source.mouse_released,
        wheel = {0, source.mouse_wheel},
        text_count = source.text_count,
    }
    if ctx.ui_hover {
        result.mouse_position = {-10000, -10000}
        result.mouse_pressed = false
    }
    if kit.ShiftDown(source) { result.modifiers += {.SHIFT} }
    if .LEFT_ALT in source.keys_down || .RIGHT_ALT in source.keys_down { result.modifiers += {.ALT} }
    if kit.CtrlDown(source) {
        result.modifiers += {.CTRL}
        result.text_count = 0               // Ctrl + a letter is a command, not text
    }
    for i in 0 ..< int(result.text_count) {
        result.text[i] = source.text[i]
    }
    keys: [ui.Key]kit.Key = {
        .BACKSPACE = .BACKSPACE, .DELETE = .DELETE, .LEFT = .LEFT, .RIGHT = .RIGHT, .HOME = .HOME, .END = .END,
        .ENTER = .ENTER, .ESCAPE = .ESCAPE, .TAB = .TAB,
    }
    // the keys of editing repeat while held, like in any text editor (the kit makes `keys_repeat`); Enter, Escape and Tab act once
    for key in ui.Key {
        repeats: bool = key == .BACKSPACE || key == .DELETE || key == .LEFT || key == .RIGHT || key == .HOME || key == .END
        if keys[key] in (source.keys_repeat if repeats else source.keys_pressed) { result.keys += {key} }
    }
    // the actions: what the table of hotkeys says (KeyMapOf), by the keys, the mouse buttons and the buttons of a gamepad that went down in this frame
    result.actions += ui.KeyMapActions(KeyMapOf(), inputProbe, source, result.modifiers)
    return result
}

// Starts a ui frame inside of a demo's draw: the painter draws into `kit_ctx`, the input is the one of the frame.
Begin :: proc(ui_ctx: ^ui.Context, painter: ^ui_default.Painter, style: ^ui.Style, kit_ctx: ^kit.Context) {
    painter.user = kit_ctx
    fontsEnsure(painter, kit_ctx)
    scale: f32 = ui_default.PainterScale(painter)
    ui.UiMeasureCacheScale(ui_ctx, scale)
    ui.UiBegin(ui_ctx, InputFrom(kit_ctx, scale), kit_ctx.delta_time, kit_ctx.screen / scale, style)
}
