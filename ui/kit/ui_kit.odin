// The ui library over the demo kit (odin_utilities/demo_kit): a Painter that draws through kit.Context and the input of a kit frame as ui.Input.
// So a demo written against the kit has the ui on raylib, on Karl2D and headless (the scripts of the tests click real widgets).
package ui_kit

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
}

@(private)
fonts: Fonts

// Loads the fonts into the backend of `ctx` when they are not there yet, and tells the painter their numbers
@(private)
fontsEnsure :: proc(painter: ^ui_default.Painter, ctx: ^kit.Context) {
    if fonts.backend != ctx.backend {
        fonts = {backend = ctx.backend}
        fonts.faces[.REGULAR] = kit.FontLoad(ctx, INTER_REGULAR, 32, 1280)
        fonts.faces[.STRONG] = kit.FontLoad(ctx, INTER_SEMIBOLD, 32, 1280)
        fonts.faces[.ITALIC] = kit.FontLoad(ctx, INTER_ITALIC, 32, 1280)
        fonts.faces[.MONO] = kit.FontLoad(ctx, JETBRAINS_MONO, 32, 1280)
        fonts.faces[.MONO_STRONG] = kit.FontLoad(ctx, JETBRAINS_MONO_BOLD, 32, 1280)
        fonts.faces[.STRONG_ITALIC] = kit.FontLoad(ctx, INTER_SEMIBOLD_ITALIC, 32, 1280)
        fonts.faces[.MONO_ITALIC] = kit.FontLoad(ctx, JETBRAINS_MONO_ITALIC, 32, 1280)
        fonts.faces[.MONO_STRONG_ITALIC] = kit.FontLoad(ctx, JETBRAINS_MONO_BOLD_ITALIC, 32, 1280)
        fonts.icons = kit.FontLoad(ctx, icons.LUCIDE_FONT, 32, len(icons.Icon) - 1, int(icons.ICON_FIRST_CHARACTER))       // without NONE, which has no glyph
    }
    for face in ui_default.Face { painter.glue_fonts[face] = u32(fonts.faces[face]) }
    painter.glue_icon_font = u32(fonts.icons)
    painter.glue_ready = true
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
    table: ui.KeyMap
    key :: proc(table: ^ui.KeyMap, action: ui.Action, slot: int, key: kit.Key, ctrl: ui.Tri = .ANY, alt: ui.Tri = .ANY, shift: ui.Tri = .ANY) {
        ui.KeyMapSet(table, action, slot, {device = .KEYBOARD, code = u16(key), ctrl = ctrl, alt = alt, shift = shift})
    }
    key(&table, .ACCEPT, 0, .ENTER)
    key(&table, .ACCEPT, 1, .SPACE)
    key(&table, .SELECT, 0, .SPACE)
    key(&table, .CANCEL, 0, .ESCAPE)
    key(&table, .FOCUS_NEXT, 0, .TAB, shift = .NO)
    key(&table, .FOCUS_PREV, 0, .TAB, shift = .YES)
    key(&table, .UP, 0, .UP)
    key(&table, .DOWN, 0, .DOWN)
    // Alt + left and right turn (the timeline); with Ctrl as well they are plain arrows again
    key(&table, .LEFT, 0, .LEFT, alt = .NO)
    key(&table, .LEFT, 1, .LEFT, ctrl = .YES, alt = .YES)
    key(&table, .RIGHT, 0, .RIGHT, alt = .NO)
    key(&table, .RIGHT, 1, .RIGHT, ctrl = .YES, alt = .YES)
    key(&table, .PAGE_UP, 0, .PAGE_UP)
    key(&table, .PAGE_DOWN, 0, .PAGE_DOWN)
    key(&table, .HOME, 0, .HOME)
    key(&table, .END, 0, .END)
    key(&table, .RENAME, 0, .F2)
    key(&table, .COPY, 0, .C, ctrl = .YES)
    key(&table, .CUT, 0, .X, ctrl = .YES)
    key(&table, .PASTE, 0, .V, ctrl = .YES)
    key(&table, .SELECT_ALL, 0, .A, ctrl = .YES)
    key(&table, .DUPLICATE, 0, .D, ctrl = .YES)
    key(&table, .UNDO, 0, .Z, ctrl = .YES, shift = .NO)
    key(&table, .REDO, 0, .Z, ctrl = .YES, shift = .YES)
    key(&table, .REDO, 1, .Y, ctrl = .YES)
    key(&table, .INVERT, 0, .I, ctrl = .NO, alt = .YES)
    key(&table, .REVERSE, 0, .R, ctrl = .NO, alt = .YES)
    key(&table, .REPEAT, 0, .D, ctrl = .NO, alt = .YES)
    key(&table, .ROTATE_LEFT, 0, .LEFT, ctrl = .NO, alt = .YES)
    key(&table, .ROTATE_RIGHT, 0, .RIGHT, ctrl = .NO, alt = .YES)
    return table
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
    case .KEYBOARD: return kit.Key(u8(code)) in source.keys_pressed
    case .MOUSE: return kit.MouseButton(u8(code)) in source.mouse_pressed
    case .GAMEPAD, .NONE: return false
    }
    return false
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
    for key in ui.Key {
        if keys[key] in source.keys_pressed { result.keys += {key} }
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
