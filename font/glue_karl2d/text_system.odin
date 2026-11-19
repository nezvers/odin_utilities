package font_karl2d

// Everything a program needs to draw text with the font library in one value: the face, an atlas, a renderer and their memory, made once (the allocator is yours) and used by a user
// interface that places text by a box: the size is the height of the line (what a measured text is high), the position is the top left corner of the box.
//
//     system: font_karl2d.TextSystem
//     font_karl2d.TextSystemInit(&system, #load("Roboto.ttf"), .SLUG)          // after karl2d.init
//     font_karl2d.TextSystemDraw(&system, "Hello", {20, 20}, 20, karl2d.WHITE)  // a line 20 pixels high with its top left corner at (20, 20)
//     size := font_karl2d.TextSystemMeasure(&system, "Hello", 20)

import "base:runtime"
import k2 "../../karl2d"
import font ".."

TEXT_SYSTEM_ATLAS_ROWS :: 16
TEXT_SYSTEM_VERTICES :: 6 * 2048

TextSystem :: struct {
    face: font.Font,
    atlas: font.Atlas,
    renderer: Renderer,
    allocator: runtime.Allocator,
    texels: []f32,
    slots: []i32,
    vertices: []font.TextVertex,
}

// `bytes` is the font file (it has to live as long as the system); the atlas is `rows` rows of 4096 texels (16 bytes each).
TextSystemInit :: proc(system: ^TextSystem, bytes: []u8, method: font.Method, rows: int = TEXT_SYSTEM_ATLAS_ROWS, allocator := context.allocator) -> bool {
    system^ = {allocator = allocator}
    if !font.FontInit(&system.face, bytes) { return false }
    system.texels = make([]f32, 4 * font.ATLAS_WIDTH * rows, allocator)
    system.slots = make([]i32, font.FontSlotCount(&system.face), allocator)
    system.vertices = make([]font.TextVertex, TEXT_SYSTEM_VERTICES, allocator)
    font.AtlasInit(&system.atlas, &system.face, method, system.texels, system.slots)
    return RendererInit(&system.renderer, &system.atlas, system.vertices)
}

TextSystemDestroy :: proc(system: ^TextSystem) {
    RendererDestroy(&system.renderer)
    delete(system.texels, system.allocator)
    delete(system.slots, system.allocator)
    delete(system.vertices, system.allocator)
    system^ = {}
}

// The size of the text in pixels, for a line `line_height` pixels high
TextSystemMeasure :: proc(system: ^TextSystem, text: string, line_height: f32, options: font.TextOptions = {}) -> [2]f32 {
    ppem, _ := font.TextBox(&system.face, line_height)
    return font.TextMeasure(&system.face, text, ppem, options)
}

// Draws the text in a box whose top left corner is `position` (pixels, y down)
TextSystemDraw :: proc(system: ^TextSystem, text: string, position: [2]f32, line_height: f32, color: k2.Color, options: font.TextOptions = {}) {
    ppem, baseline := font.TextBox(&system.face, line_height)
    options := options
    options.snap_to_pixels = true
    DrawText(&system.renderer, text, {position.x, position.y + baseline}, ppem, color, options)
}
