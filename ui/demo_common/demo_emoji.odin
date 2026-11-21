#+private file
package demo_common

// Baldr's 31_emoji (https://github.com/BuLEEto/Baldr, by Lee Fry and the Baldr contributors, zlib License) remade with this library: a composer with a button that opens the
// emoji picker in a popover, the chosen emoji written at the caret, and the app keeping its own recents and skin tone (preferences that outlive the picker, so the ui
// does not keep them). Baldr draws the emoji with a color emoji font; there is none here, so every emoji is drawn from shapes (circles, quads, triangles) by a CUSTOM
// draw proc, in the colors of the emoji, and what the composer holds is a shortcode (`:thumbs_up~3:`, the number is the skin tone) that the messages draw as the shape
// again, inline with the words. The hands take the skin tone, the faces stay yellow.

import "core:math"
import "core:strings"
import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"

@(private="package")
demo_emoji: kit.Demo = {
    name = "baldr emoji",
    init = init,
    draw = draw,
    script = script,
}

Emoji :: enum u8 {
    SMILE, GRIN, WINK, LAUGH, HEART_EYES, COOL, SAD, ANGRY, SURPRISED, NEUTRAL,
    WAVE, THUMBS_UP, FIST, PEACE,
    HEART, STAR, SUN, MOON, CLOUD, DROP, LEAF, FLOWER, CHECK, CROSS, FIRE,
}

Category :: enum u8 {
    FACES,
    HANDS,
    THINGS,
}

CATEGORY_NAMES: [3]string = {"Faces", "Hands", "Things"}

EmojiInfo :: struct {
    code: string,
    category: Category,
    skin: bool,                 // takes the skin tone
}

INFO: [Emoji]EmojiInfo = {
    .SMILE = {"smile", .FACES, false}, .GRIN = {"grin", .FACES, false}, .WINK = {"wink", .FACES, false}, .LAUGH = {"laugh", .FACES, false},
    .HEART_EYES = {"heart_eyes", .FACES, false}, .COOL = {"cool", .FACES, false}, .SAD = {"sad", .FACES, false}, .ANGRY = {"angry", .FACES, false},
    .SURPRISED = {"surprised", .FACES, false}, .NEUTRAL = {"neutral", .FACES, false},
    .WAVE = {"wave", .HANDS, true}, .THUMBS_UP = {"thumbs_up", .HANDS, true}, .FIST = {"fist", .HANDS, true}, .PEACE = {"peace", .HANDS, true},
    .HEART = {"heart", .THINGS, false}, .STAR = {"star", .THINGS, false}, .SUN = {"sun", .THINGS, false}, .MOON = {"moon", .THINGS, false},
    .CLOUD = {"cloud", .THINGS, false}, .DROP = {"drop", .THINGS, false}, .LEAF = {"leaf", .THINGS, false}, .FLOWER = {"flower", .THINGS, false},
    .CHECK = {"check", .THINGS, false}, .CROSS = {"cross", .THINGS, false}, .FIRE = {"fire", .THINGS, false},
}

TONES: [6]ui.Color = {{255, 205, 70, 255}, {250, 222, 196, 255}, {236, 196, 150, 255}, {200, 150, 105, 255}, {145, 100, 66, 255}, {96, 66, 46, 255}}

MESSAGES :: 8
MESSAGE_BYTES :: 96
RECENTS :: 6

ID_COMPOSER :: 0
ID_MENU :: 1
ID_SEND :: 2
ID_TONE :: 3                    // 6 of them
ID_CELL :: 10                   // an id per emoji, 25 of them
ID_SLOTS :: 40

State :: struct {
    app: UiDemo,
    ids: [ID_SLOTS]ui.Id,
    composer: [MESSAGE_BYTES]u8,
    composer_length: int,
    messages: [MESSAGES][MESSAGE_BYTES]u8,
    message_lengths: [MESSAGES]int,
    message_count: int,
    recents: [RECENTS]Emoji,
    recent_count: int,
    tone: int,
    category: int,
    picker_cells: int,          // how many cells the picker drew in the last frame
    inserted: int,
}

state: State
target: ui.Vec2

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
}

// ---- the shapes ---------------------------------------------------------------------------------------------------------------------------------------------

YELLOW :: ui.Color{255, 204, 77, 255}
INK :: ui.Color{72, 52, 24, 255}

@(private="file")
At :: proc(r: ui.Rect, x: f32, y: f32) -> ui.Vec2 {
    return {r.x + x * r.z, r.y + y * r.w}
}

disc :: proc(painter: ^ui_default.Painter, r: ui.Rect, x: f32, y: f32, radius: f32, color: ui.Color) {
    side: f32 = radius * 2 * r.z
    ui_default.FillRounded(painter, {r.x + x * r.z - side * 0.5, r.y + y * r.w - side * 0.5, side, side}, 1, color)
}

// A line of `width` (a part of the side) between two points, as a quad
stroke :: proc(painter: ^ui_default.Painter, r: ui.Rect, a: ui.Vec2, b: ui.Vec2, width: f32, color: ui.Color) {
    pa: ui.Vec2 = At(r, a.x, a.y)
    pb: ui.Vec2 = At(r, b.x, b.y)
    direction: ui.Vec2 = pb - pa
    length: f32 = math.sqrt(direction.x * direction.x + direction.y * direction.y)
    if length == 0 { return }
    normal: ui.Vec2 = {-direction.y, direction.x} * (width * r.z * 0.5 / length)
    points: [4]ui.Vec2 = {pa + normal, pb + normal, pb - normal, pa - normal}
    if painter.fill_polygon != nil { painter.fill_polygon(painter, points[:], color) }
}

poly :: proc(painter: ^ui_default.Painter, r: ui.Rect, points: []ui.Vec2, color: ui.Color) {
    pixels: [12]ui.Vec2
    for point, i in points { pixels[i] = At(r, point.x, point.y) }
    if painter.fill_polygon != nil { painter.fill_polygon(painter, pixels[:len(points)], color) }
}

// A curve of the circle around (cx, cy) from one angle to the other (degrees, 0 to the right, 90 down), as dots joined by lines
arc :: proc(painter: ^ui_default.Painter, r: ui.Rect, cx: f32, cy: f32, radius: f32, from: f32, to: f32, width: f32, color: ui.Color) {
    STEPS :: 10
    previous: ui.Vec2
    for i in 0 ..= STEPS {
        angle: f32 = math.to_radians(from + (to - from) * f32(i) / STEPS)
        point: ui.Vec2 = {cx + radius * math.cos(angle), cy + radius * math.sin(angle)}
        disc(painter, r, point.x, point.y, width * 0.5, color)
        if i > 0 { stroke(painter, r, previous, point, width, color) }
        previous = point
    }
}

rounded :: proc(painter: ^ui_default.Painter, r: ui.Rect, x: f32, y: f32, w: f32, h: f32, rounding: f32, color: ui.Color) {
    ui_default.FillRounded(painter, {r.x + x * r.z, r.y + y * r.w, w * r.z, h * r.w}, rounding, color)
}

face :: proc(painter: ^ui_default.Painter, r: ui.Rect, base: ui.Color = YELLOW) {
    disc(painter, r, 0.5, 0.5, 0.46, {base.r / 2, base.g / 2, base.b / 2, 255})
    disc(painter, r, 0.5, 0.5, 0.43, base)
}

eyes :: proc(painter: ^ui_default.Painter, r: ui.Rect, size: f32 = 0.06) {
    disc(painter, r, 0.35, 0.4, size, INK)
    disc(painter, r, 0.65, 0.4, size, INK)
}

heart :: proc(painter: ^ui_default.Painter, r: ui.Rect, cx: f32, cy: f32, size: f32, color: ui.Color) {
    disc(painter, r, cx - size * 0.45, cy - size * 0.25, size * 0.5, color)
    disc(painter, r, cx + size * 0.45, cy - size * 0.25, size * 0.5, color)
    poly(painter, r, {{cx - size * 0.93, cy - size * 0.05}, {cx + size * 0.93, cy - size * 0.05}, {cx, cy + size * 1.0}}, color)
}

// The palm of a hand with its fingers; `up` fingers are long
hand :: proc(painter: ^ui_default.Painter, r: ui.Rect, skin: ui.Color, fingers: [4]f32) {
    shade: ui.Color = {skin.r * 4 / 5, skin.g * 4 / 5, skin.b * 4 / 5, 255}
    for length, i in fingers {
        x: f32 = 0.27 + f32(i) * 0.13
        if length > 0 {
            rounded(painter, r, x - 0.01, 0.56 - length - 0.02, 0.13, length + 0.1, 1, shade)
            rounded(painter, r, x, 0.56 - length, 0.11, length + 0.06, 1, skin)
        }
    }
    rounded(painter, r, 0.25, 0.5, 0.46, 0.38, 0.35, skin)
    // the thumb leans out on the left
    stroke(painter, r, {0.3, 0.62}, {0.14, 0.44}, 0.12, skin)
    disc(painter, r, 0.14, 0.44, 0.06, skin)
}

drawEmoji :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^ui_default.Painter = ui_default.PainterOf(ctx)
    r: ui.Rect = info.rect
    skin: ui.Color = TONES[clamp(info.cursor, 0, len(TONES) - 1)]
    switch Emoji(clamp(int(info.actual), 0, len(Emoji) - 1)) {
    case .SMILE:
        face(painter, r)
        eyes(painter, r)
        arc(painter, r, 0.5, 0.52, 0.24, 25, 155, 0.055, INK)
    case .GRIN:
        face(painter, r)
        eyes(painter, r)
        poly(painter, r, {{0.24, 0.55}, {0.76, 0.55}, {0.7, 0.72}, {0.58, 0.8}, {0.42, 0.8}, {0.3, 0.72}}, INK)
        rounded(painter, r, 0.3, 0.56, 0.4, 0.09, 0.2, {255, 255, 255, 255})
    case .WINK:
        face(painter, r)
        disc(painter, r, 0.35, 0.4, 0.06, INK)
        stroke(painter, r, {0.56, 0.4}, {0.74, 0.4}, 0.055, INK)
        arc(painter, r, 0.5, 0.52, 0.24, 25, 155, 0.055, INK)
    case .LAUGH:
        face(painter, r)
        arc(painter, r, 0.35, 0.46, 0.09, 200, 340, 0.05, INK)
        arc(painter, r, 0.65, 0.46, 0.09, 200, 340, 0.05, INK)
        poly(painter, r, {{0.25, 0.56}, {0.75, 0.56}, {0.68, 0.74}, {0.56, 0.83}, {0.44, 0.83}, {0.32, 0.74}}, INK)
        rounded(painter, r, 0.4, 0.72, 0.2, 0.1, 1, {230, 90, 90, 255})
    case .HEART_EYES:
        face(painter, r)
        heart(painter, r, 0.34, 0.4, 0.1, {225, 50, 70, 255})
        heart(painter, r, 0.66, 0.4, 0.1, {225, 50, 70, 255})
        arc(painter, r, 0.5, 0.54, 0.22, 25, 155, 0.055, INK)
    case .COOL:
        face(painter, r)
        rounded(painter, r, 0.17, 0.32, 0.31, 0.17, 0.4, INK)
        rounded(painter, r, 0.52, 0.32, 0.31, 0.17, 0.4, INK)
        stroke(painter, r, {0.47, 0.37}, {0.53, 0.37}, 0.04, INK)
        arc(painter, r, 0.5, 0.52, 0.22, 30, 150, 0.055, INK)
    case .SAD:
        face(painter, r)
        eyes(painter, r)
        arc(painter, r, 0.5, 0.8, 0.2, 215, 325, 0.055, INK)
        disc(painter, r, 0.27, 0.56, 0.04, {90, 160, 240, 255})
    case .ANGRY:
        face(painter, r, {238, 118, 62, 255})
        disc(painter, r, 0.36, 0.45, 0.05, INK)
        disc(painter, r, 0.64, 0.45, 0.05, INK)
        stroke(painter, r, {0.24, 0.3}, {0.43, 0.38}, 0.06, INK)
        stroke(painter, r, {0.76, 0.3}, {0.57, 0.38}, 0.06, INK)
        arc(painter, r, 0.5, 0.82, 0.18, 215, 325, 0.055, INK)
    case .SURPRISED:
        face(painter, r)
        disc(painter, r, 0.35, 0.38, 0.075, {255, 255, 255, 255})
        disc(painter, r, 0.65, 0.38, 0.075, {255, 255, 255, 255})
        disc(painter, r, 0.35, 0.38, 0.04, INK)
        disc(painter, r, 0.65, 0.38, 0.04, INK)
        rounded(painter, r, 0.42, 0.6, 0.16, 0.22, 1, INK)
    case .NEUTRAL:
        face(painter, r)
        eyes(painter, r)
        stroke(painter, r, {0.34, 0.68}, {0.66, 0.68}, 0.055, INK)
    case .WAVE:
        hand(painter, r, skin, {0.3, 0.38, 0.36, 0.28})
    case .THUMBS_UP:
        rounded(painter, r, 0.08, 0.46, 0.2, 0.4, 0.15, {70, 110, 200, 255})
        rounded(painter, r, 0.3, 0.44, 0.58, 0.42, 0.3, skin)
        rounded(painter, r, 0.3, 0.12, 0.19, 0.46, 1, skin)
        for i in 0 ..< 3 { stroke(painter, r, {0.4, 0.56 + f32(i) * 0.1}, {0.8, 0.56 + f32(i) * 0.1}, 0.012, {skin.r * 3 / 4, skin.g * 3 / 4, skin.b * 3 / 4, 255}) }
    case .FIST:
        rounded(painter, r, 0.22, 0.34, 0.56, 0.5, 0.3, skin)
        for i in 0 ..< 4 { disc(painter, r, 0.31 + f32(i) * 0.127, 0.36, 0.075, skin) }
        for i in 1 ..< 4 { stroke(painter, r, {0.25 + f32(i) * 0.127, 0.34}, {0.25 + f32(i) * 0.127, 0.5}, 0.012, {skin.r * 3 / 4, skin.g * 3 / 4, skin.b * 3 / 4, 255}) }
    case .PEACE:
        hand(painter, r, skin, {0.0, 0.52, 0.46, 0.0})
        rounded(painter, r, 0.27, 0.5, 0.11, 0.24, 1, skin)
        rounded(painter, r, 0.66, 0.5, 0.11, 0.24, 1, skin)
    case .HEART:
        heart(painter, r, 0.5, 0.4, 0.4, {228, 58, 80, 255})
    case .STAR:
        // ten triangles from the middle: the points and the dents in turn
        points: [10]ui.Vec2
        for i in 0 ..< 10 {
            angle: f32 = math.to_radians(-90 + f32(i) * 36)
            radius: f32 = 0.46 if i % 2 == 0 else 0.19
            points[i] = {0.5 + radius * math.cos(angle), 0.54 + radius * math.sin(angle)}
        }
        for i in 0 ..< 10 { poly(painter, r, {{0.5, 0.54}, points[i], points[(i + 1) % 10]}, {255, 200, 40, 255}) }
    case .SUN:
        for i in 0 ..< 8 {
            angle: f32 = math.to_radians(f32(i) * 45)
            stroke(painter, r, {0.5 + 0.32 * math.cos(angle), 0.5 + 0.32 * math.sin(angle)}, {0.5 + 0.45 * math.cos(angle), 0.5 + 0.45 * math.sin(angle)}, 0.07, {255, 170, 40, 255})
        }
        disc(painter, r, 0.5, 0.5, 0.24, {255, 196, 50, 255})
    case .MOON:
        disc(painter, r, 0.5, 0.5, 0.4, {240, 222, 140, 255})
        disc(painter, r, 0.38, 0.4, 0.08, {214, 194, 110, 255})
        disc(painter, r, 0.6, 0.6, 0.11, {214, 194, 110, 255})
        disc(painter, r, 0.62, 0.32, 0.05, {214, 194, 110, 255})
    case .CLOUD:
        cloud: ui.Color = {226, 234, 246, 255}
        disc(painter, r, 0.3, 0.58, 0.18, cloud)
        disc(painter, r, 0.5, 0.45, 0.24, cloud)
        disc(painter, r, 0.72, 0.6, 0.17, cloud)
        rounded(painter, r, 0.3, 0.56, 0.42, 0.2, 0, cloud)
    case .DROP:
        poly(painter, r, {{0.5, 0.08}, {0.27, 0.54}, {0.73, 0.54}}, {70, 140, 232, 255})
        disc(painter, r, 0.5, 0.62, 0.25, {70, 140, 232, 255})
        disc(painter, r, 0.42, 0.58, 0.05, {170, 210, 250, 255})
    case .LEAF:
        poly(painter, r, {{0.14, 0.86}, {0.2, 0.36}, {0.8, 0.14}, {0.78, 0.62}}, {82, 172, 92, 255})
        stroke(painter, r, {0.16, 0.84}, {0.7, 0.3}, 0.035, {190, 235, 190, 255})
    case .FLOWER:
        for i in 0 ..< 5 {
            angle: f32 = math.to_radians(-90 + f32(i) * 72)
            disc(painter, r, 0.5 + 0.24 * math.cos(angle), 0.5 + 0.24 * math.sin(angle), 0.17, {240, 120, 170, 255})
        }
        disc(painter, r, 0.5, 0.5, 0.13, {255, 205, 60, 255})
    case .CHECK:
        disc(painter, r, 0.5, 0.5, 0.44, {70, 170, 100, 255})
        stroke(painter, r, {0.28, 0.52}, {0.44, 0.68}, 0.1, {255, 255, 255, 255})
        stroke(painter, r, {0.44, 0.68}, {0.73, 0.34}, 0.1, {255, 255, 255, 255})
    case .CROSS:
        disc(painter, r, 0.5, 0.5, 0.44, {220, 70, 70, 255})
        stroke(painter, r, {0.32, 0.32}, {0.68, 0.68}, 0.1, {255, 255, 255, 255})
        stroke(painter, r, {0.68, 0.32}, {0.32, 0.68}, 0.1, {255, 255, 255, 255})
    case .FIRE:
        poly(painter, r, {{0.5, 0.06}, {0.8, 0.58}, {0.7, 0.86}, {0.3, 0.86}, {0.2, 0.58}}, {240, 120, 40, 255})
        poly(painter, r, {{0.5, 0.4}, {0.65, 0.68}, {0.55, 0.86}, {0.45, 0.86}, {0.35, 0.68}}, {255, 210, 70, 255})
    }
}

// An emoji of `side` pixels in the flow. `tone` is the skin tone of the hands.
glyph :: proc(c: ^ui.Context, emoji: Emoji, tone: int, side: f32) {
    ui.ElementOpen(c, {layout = {size = {ui.Fixed(side), ui.Fixed(side)}}, draw = {kind = .CUSTOM, custom = drawEmoji, actual = f32(emoji), cursor = tone}})
    ui.ElementClose(c)
}

// ---- shortcodes ---------------------------------------------------------------------------------------------------------------------------------------------

// The shortcode of an emoji with the tone: ":thumbs_up~3:" for a hand with a tone, ":smile:" for the others
shortcode :: proc(c: ^ui.Context, emoji: Emoji, tone: int) -> string {
    if INFO[emoji].skin && tone > 0 { return ui.UiFormat(c, ":%s~%d:", INFO[emoji].code, tone) }
    return ui.UiFormat(c, ":%s:", INFO[emoji].code)
}

// The emoji a shortcode names (`text` between the colons) and its tone
parseCode :: proc(text: string) -> (emoji: Emoji, tone: int, ok: bool) {
    name: string = text
    if at := strings.index_byte(text, '~'); at >= 0 {
        name = text[:at]
        if at + 1 < len(text) && text[at + 1] >= '0' && text[at + 1] <= '5' { tone = int(text[at + 1] - '0') }
    }
    for info, e in INFO {
        if info.code == name { return e, tone, true }
    }
    return
}

// A message as a row of words and emoji
messageRow :: proc(c: ^ui.Context, text: string) {
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 3, align = {y = .CENTER}}})
    start: int
    i: int
    for i < len(text) {
        if text[i] != ':' {
            i += 1
            continue
        }
        close: int = strings.index_byte(text[i + 1:], ':')
        if close < 0 { break }
        emoji, tone, ok := parseCode(text[i + 1:i + 1 + close])
        if !ok {
            i += 1
            continue
        }
        if i > start { ui.UiLabel(c, text[start:i]) }
        glyph(c, emoji, tone, 24)
        i += close + 2
        start = i
    }
    if start < len(text) { ui.UiLabel(c, text[start:]) }
    ui.ElementClose(c)
}

// ---- the picker ---------------------------------------------------------------------------------------------------------------------------------------------

// One cell of the picker. True when it was clicked.
cell :: proc(c: ^ui.Context, emoji: Emoji, name: string) -> (clicked: bool) {
    id: ui.Id = ui.UiId(c, name)
    state.ids[ID_CELL + int(emoji)] = id
    interaction: ui.Interaction = ui.UiInteract(c, id)
    ui.ElementOpen(c, {
        id = id,
        layout = {size = {ui.Fixed(42), ui.Fixed(42)}, align = {x = .CENTER, y = .CENTER}},
        hit = {.INTERACTIVE},
        draw = {kind = .SELECTABLE, hover = 1 if interaction.hovered else 0, flags = {.HOVERED} if interaction.hovered else {}},
    })
    glyph(c, emoji, state.tone, 30)
    ui.ElementClose(c)
    state.picker_cells += 1
    return interaction.clicked
}

// What the picker returned this frame: the emoji that was chosen
picker :: proc(c: ^ui.Context) -> (chosen: Emoji, picked: bool) {
    // the skin tone
    ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 6, align = {y = .CENTER}}})
    ui.UiLabelDim(c, "Skin tone")
    for tone in 0 ..< len(TONES) {
        id: ui.Id = ui.UiId(c, ui.UiFormat(c, "##tone%d", tone))
        state.ids[ID_TONE + tone] = id
        interaction: ui.Interaction = ui.UiInteract(c, id)
        if interaction.clicked { state.tone = tone }
        ui.ElementOpen(c, {
            id = id,
            layout = {size = {ui.Fixed(26), ui.Fixed(26)}, padding = ui.PaddingAll(3), align = {x = .CENTER, y = .CENTER}},
            hit = {.INTERACTIVE},
            draw = {kind = .FILL, color = {110, 160, 255, 255} if state.tone == tone else {0, 0, 0, 0}},
        })
        ui.ElementOpen(c, {layout = {size = {ui.Fixed(20), ui.Fixed(20)}}, draw = {kind = .SWATCH, color = TONES[tone]}})
        ui.ElementClose(c)
        ui.ElementClose(c)
    }
    ui.ElementClose(c)
    ui.UiSegmented(c, "##category", CATEGORY_NAMES[:], &state.category)
    // the recents come first
    if state.recent_count > 0 {
        ui.UiLabelDim(c, "Recent")
        ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 2}})
        for i in 0 ..< state.recent_count {
            if cell(c, state.recents[i], ui.UiFormat(c, "##recent%d", i)) { chosen, picked = state.recents[i], true }
        }
        ui.ElementClose(c)
    }
    ui.UiLabelDim(c, CATEGORY_NAMES[state.category])
    column: int
    ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, direction = .TOP_TO_BOTTOM, gap = 2}})
    ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 2}})
    for emoji in Emoji {
        if INFO[emoji].category != Category(state.category) { continue }
        if column == 6 {
            ui.ElementClose(c)
            ui.ElementOpen(c, {layout = {size = {ui.Fit(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 2}})
            column = 0
        }
        if cell(c, emoji, ui.UiFormat(c, "##emoji%d", int(emoji))) { chosen, picked = emoji, true }
        column += 1
    }
    ui.ElementClose(c)
    ui.ElementClose(c)
    return
}

// The emoji goes to the front of the recents (once)
remember :: proc(emoji: Emoji) {
    at: int = state.recent_count
    for i in 0 ..< state.recent_count {
        if state.recents[i] == emoji { at = i }
    }
    if at == state.recent_count && state.recent_count < RECENTS { state.recent_count += 1 }
    at = min(at, state.recent_count - 1)
    for i := at; i > 0; i -= 1 { state.recents[i] = state.recents[i - 1] }
    state.recents[0] = emoji
}

send :: proc() {
    if state.composer_length == 0 { return }
    if state.message_count == MESSAGES {
        for i in 0 ..< MESSAGES - 1 {
            state.messages[i] = state.messages[i + 1]
            state.message_lengths[i] = state.message_lengths[i + 1]
        }
        state.message_count -= 1
    }
    n: int = state.message_count
    state.message_lengths[n] = copy(state.messages[n][:], state.composer[:state.composer_length])
    state.message_count += 1
    state.composer_length = 0
}

// ---- the page -----------------------------------------------------------------------------------------------------------------------------------------------

draw :: proc(ctx: ^kit.Context) {
    state.app.painter.theme = ui_default.THEME_DARK
    ctx.background = kit.Color(state.app.painter.theme.background)
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    ui.ElementOpen(c, {layout = {size = {ui.Fixed(ctx.screen.x), ui.Fixed(ctx.screen.y)}, direction = .TOP_TO_BOTTOM, align = {x = .CENTER, y = .CENTER}}})
    ui.ElementOpen(c, {
        layout = {size = {ui.Fixed(580), ui.Fixed(520)}, direction = .TOP_TO_BOTTOM, gap = 12, padding = ui.PaddingAll(24)},
        hit = {.BLOCKER}, draw = {kind = .PANEL},
    })
    ui.UiTitle(c, "Emoji", 1.6)
    ui.UiLabelDim(c, "The Emoji button opens the picker over the composer: a click writes the emoji at the caret. The hands take the skin tone; the emoji are drawn from shapes.", .WORDS)
    // the composer: a field, the picker in a popover, Send
    ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 8, align = {y = .CENTER}}})
    state.ids[ID_COMPOSER] = ui.UiId(c, "Message##composer")
    _, submitted := ui.UiTextField(c, "Message##composer", state.composer[:], &state.composer_length, {ui.Grow(), {}})
    state.picker_cells = 0                      // counted again by the picker while it is open
    state.ids[ID_MENU] = ui.UiId(c, "Emoji##picker")
    ui.UiPushTag(c, "outline")
    if ui.UiMenu(c, "Emoji##picker") {
        chosen, picked := picker(c)
        if picked {
            if ui.UiTextInsert(c, state.ids[ID_COMPOSER], state.composer[:], &state.composer_length, shortcode(c, chosen, state.tone)) {
                state.inserted += 1
                remember(chosen)
            }
            c.open_menu = 0
        }
    }
    ui.UiPopTag(c)
    state.ids[ID_SEND] = ui.UiId(c, "Send")
    ui.UiPushTag(c, "primary")
    sent: bool = ui.UiButton(c, "Send")
    ui.UiPopTag(c)
    ui.ElementClose(c)
    if sent || submitted { send() }
    ui.UiSeparator(c)
    if state.message_count == 0 { ui.UiLabelDim(c, "No messages yet.") }
    for i in 0 ..< state.message_count { messageRow(c, string(state.messages[i][:state.message_lengths[i]])) }
    ui.ElementClose(c)
    ui.ElementClose(c)
    ui_demo_end(&state.app)
}

// ---- the script -----------------------------------------------------------------------------------------------------------------------------------------------

center :: proc(slot: int) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, state.ids[slot])
    target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return found && rect.z > 0
}

composerText :: proc() -> string {
    return string(state.composer[:state.composer_length])
}

drawn :: proc(kind: ui.StyleKind, name: string) -> bool {
    for command in ui.UiCommands(&state.app.ctx) {
        info: ui.DrawInfo = command.info
        if command.kind == .DRAW && info.kind == kind && (info.name == name || info.text == name) {
            target = {info.rect.x + info.rect.z * 0.5, info.rect.y + info.rect.w * 0.5}
            return true
        }
    }
    return false
}

script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_COMPOSER) }, "the composer"),
    kit.ClickAt(&target),
    kit.Type("hi "),
    kit.Wait(2),
    // the picker opens over the composer; a click on an emoji writes its shortcode at the caret
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_MENU) }, "the Emoji button"),
    kit.ClickAt(&target),
    kit.MoveTo({1100, 700}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.picker_cells == len(Emoji) - 15 && center(ID_CELL + int(Emoji.SMILE)) }, "the picker shows the faces"),
    kit.Capture("emoji_picker"),
    kit.Wait(2),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return composerText() == "hi :smile:" && state.recent_count == 1 && state.recents[0] == .SMILE }, "the emoji is written at the caret and is the first recent"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.picker_cells == 0 }, "the picker closed"),
    // the hands take the skin tone
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_MENU) }, "the Emoji button again"),
    kit.ClickAt(&target),
    kit.MoveTo({1100, 700}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_TONE + 3) }, "the fourth skin tone"),
    kit.ClickAt(&target),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.tone == 3 && drawn(.SEGMENT, "Hands") }, "the tone is chosen and the categories are there"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.category == 1 && center(ID_CELL + int(Emoji.THUMBS_UP)) }, "the hands"),
    kit.MoveTo({1100, 700}),
    kit.Wait(3),
    kit.Capture("emoji_picker_hands"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return drawn(.SEGMENT, "Things") }, "the Things category"),
    kit.ClickAt(&target),
    kit.MoveTo({1100, 700}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.category == 2 && state.picker_cells == 1 + 11 }, "the things: the recent one and eleven"),
    kit.Capture("emoji_picker_things"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return drawn(.SEGMENT, "Hands") }, "back to the Hands"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_CELL + int(Emoji.THUMBS_UP)) }, "the thumbs up"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return composerText() == "hi :smile::thumbs_up~3:" && state.recents[0] == .THUMBS_UP && state.recents[1] == .SMILE }, "the hand has its tone in the shortcode, the recents are in order"),
    // Send: the message draws the emoji inline
    kit.Check(proc(ctx: ^kit.Context) -> bool { return center(ID_SEND) }, "Send"),
    kit.ClickAt(&target),
    kit.MoveTo({1100, 700}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.message_count == 1 && state.composer_length == 0 }, "the message is sent"),
    kit.Capture("emoji_message"),
    kit.Wait(2),
}
