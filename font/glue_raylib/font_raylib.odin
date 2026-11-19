package font_raylib

// The raylib glue of the font library: the glyph data of an Atlas as a float texture, the shader of the method of the atlas (Slug or the Scanline Sweeper), and text drawn as triangles.
//
//     renderer: font_raylib.Renderer
//     font_raylib.RendererInit(&renderer, &atlas)                 // after InitWindow
//     ...
//     font_raylib.DrawText(&renderer, "Hello", {20, 100}, 32, rl.WHITE)
//     font_raylib.RendererDestroy(&renderer)
//
// The text color is a uniform of the shader and the slot of the glyph travels in the red and green of the vertex color, so a call of DrawText is one batch. Glyphs that are baked after the
// first frame are uploaded as the rows of texels that changed.

import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import font ".."

VERTEX_VALUES :: #load("../shaders/vertex_raylib.glsl", cstring)
SLUG_FRAGMENT :: #load("../shaders/slug_fragment.glsl", cstring)
SCANLINE_FRAGMENT :: #load("../shaders/scanline_fragment.glsl", cstring)

VERTEX_CAPACITY :: 6 * 1024

Renderer :: struct {
    atlas: ^font.Atlas,
    shader: rl.Shader,
    texture_id: c.uint,
    location_data: c.int,
    location_color: c.int,
    vertices: [VERTEX_CAPACITY]font.TextVertex,
}

// Makes the shader and the texture (as tall as the atlas can get). Needs a window.
RendererInit :: proc(renderer: ^Renderer, atlas: ^font.Atlas) -> bool {
    renderer.atlas = atlas
    fragment: cstring = SLUG_FRAGMENT if atlas.method == .SLUG else SCANLINE_FRAGMENT
    renderer.shader = rl.LoadShaderFromMemory(VERTEX_VALUES, fragment)
    if renderer.shader.id == 0 { return false }
    renderer.location_data = rl.GetShaderLocation(renderer.shader, "glyphData")
    renderer.location_color = rl.GetShaderLocation(renderer.shader, "textColor")
    rows: int = font.AtlasCapacityRows(atlas)
    renderer.texture_id = rlgl.LoadTexture(nil, font.ATLAS_WIDTH, c.int(rows), c.int(rl.PixelFormat.UNCOMPRESSED_R32G32B32A32), 1)
    if renderer.texture_id == 0 { return false }
    rlgl.TextureParameters(renderer.texture_id, rlgl.TEXTURE_MIN_FILTER, rlgl.TEXTURE_FILTER_NEAREST)
    rlgl.TextureParameters(renderer.texture_id, rlgl.TEXTURE_MAG_FILTER, rlgl.TEXTURE_FILTER_NEAREST)
    rlgl.TextureParameters(renderer.texture_id, rlgl.TEXTURE_WRAP_S, rlgl.TEXTURE_WRAP_CLAMP)
    rlgl.TextureParameters(renderer.texture_id, rlgl.TEXTURE_WRAP_T, rlgl.TEXTURE_WRAP_CLAMP)
    renderer.atlas.dirty_from = 0
    renderer.atlas.table_dirty = true
    return true
}

RendererDestroy :: proc(renderer: ^Renderer) {
    if renderer.texture_id != 0 { rlgl.UnloadTexture(renderer.texture_id) }
    if renderer.shader.id != 0 { rl.UnloadShader(renderer.shader) }
    renderer^ = {}
}

// What changed in the atlas goes to the texture
@(private)
upload :: proc(renderer: ^Renderer) {
    row_values: int = font.ATLAS_WIDTH * 4
    for range in font.AtlasTakeDirty(renderer.atlas) {
        if range.count == 0 || range.first >= font.AtlasCapacityRows(renderer.atlas) { continue }
        rows: int = min(range.count, font.AtlasCapacityRows(renderer.atlas) - range.first)
        rlgl.UpdateTexture(renderer.texture_id, 0, c.int(range.first), font.ATLAS_WIDTH, c.int(rows), c.int(rl.PixelFormat.UNCOMPRESSED_R32G32B32A32), raw_data(renderer.atlas.texels[range.first * row_values:]))
    }
}

// Draws the text with its baseline starting at `position` (pixels, y down), `size` pixels to the em. Returns the position of the pen after the text.
DrawText :: proc(renderer: ^Renderer, text: string, position: rl.Vector2, size: f32, color: rl.Color, options: font.TextOptions = {}) -> rl.Vector2 {
    count, pen, _ := font.TextQuads(renderer.atlas, text, {position.x, position.y}, size, renderer.vertices[:], options)
    upload(renderer)
    draw(renderer, count, color)
    return {pen.x, pen.y}
}

@(private)
draw :: proc(renderer: ^Renderer, vertex_count: int, color: rl.Color) {
    if vertex_count == 0 { return }
    rl.BeginShaderMode(renderer.shader)
    tint: [4]f32 = {f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
    rl.SetShaderValue(renderer.shader, rl.ShaderLocationIndex(renderer.location_color), &tint, .VEC4)
    rlgl.SetUniformSampler(renderer.location_data, renderer.texture_id)
    rlgl.SetTexture(rlgl.GetTextureIdDefault())
    rlgl.Begin(rlgl.TRIANGLES)
    for vertex in renderer.vertices[:vertex_count] {
        slot: [4]u8 = font.SlotColor(vertex.slot)
        rlgl.Color4ub(slot.r, slot.g, slot.b, slot.a)
        rlgl.TexCoord2f(vertex.uv.x, vertex.uv.y)
        rlgl.Vertex2f(vertex.position.x, vertex.position.y)
    }
    rlgl.End()
    rl.EndShaderMode()
}
