package font_raylib

// The raylib glue of the font library: the glyph data of an Atlas as a float texture, the shader of the method of the atlas (Slug or the Scanline Sweeper), and text drawn as triangles.
//
//     renderer: font_raylib.Renderer
//     font_raylib.RendererInit(&renderer, &atlas, make([]font.TextVertex, 6 * 2048))      // after InitWindow
//     ...
//     font_raylib.DrawText(&renderer, "Hello", {20, 100}, 32, rl.WHITE)
//     font_raylib.RendererDestroy(&renderer)
//
// The slot of a glyph travels in the red and green bytes of the vertex color and the index of the color of the text in the blue one (the colors are in a palette row of the atlas texture), so text
// of any number of colors is one batch. A call of DrawText draws at once; with `renderer.deferred` set it only adds to the batch, and RendererFlush draws it (a program that mixes text with
// other drawing flushes before it draws something else, so that everything stays in order). Glyphs that are baked later are uploaded as the rows of texels that changed; an atlas that is full is
// cleared and filled again (what is batched is drawn first).

import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import font ".."

VERTEX_SOURCE :: #load("../shaders/vertex_raylib.glsl", cstring)
SLUG_FRAGMENT :: #load("../shaders/slug_fragment.glsl", cstring)
SCANLINE_FRAGMENT :: #load("../shaders/scanline_fragment.glsl", cstring)

Renderer :: struct {
    atlas: ^font.Atlas,
    shader: rl.Shader,
    texture_id: c.uint,
    location_data: c.int,
    location_params: c.int,
    weight: f32,                // the exponent of the coverage: 1 as it is, under 1 heavier text (light text on a dark ground looks thin)
    deferred: bool,             // DrawText adds to the batch and RendererFlush draws it
    count: int,                 // vertices in the batch
    vertices: []font.TextVertex, // the batch (the caller's memory: 6 vertices per glyph)
}

// Makes the shader and the texture (as tall as the atlas can get). Needs a window.
RendererInit :: proc(renderer: ^Renderer, atlas: ^font.Atlas, vertices: []font.TextVertex) -> bool {
    assert(len(vertices) >= 6 * 64, "room for some glyphs")
    renderer.vertices = vertices
    renderer.atlas = atlas
    renderer.weight = 1
    fragment: cstring = SLUG_FRAGMENT if atlas.method == .SLUG else SCANLINE_FRAGMENT
    renderer.shader = rl.LoadShaderFromMemory(VERTEX_SOURCE, fragment)
    if renderer.shader.id == 0 { return false }
    renderer.location_data = rl.GetShaderLocation(renderer.shader, "glyphData")
    renderer.location_params = rl.GetShaderLocation(renderer.shader, "textParams")
    rows: int = font.AtlasCapacityRows(atlas)
    renderer.texture_id = rlgl.LoadTexture(nil, font.ATLAS_WIDTH, c.int(rows), c.int(rl.PixelFormat.UNCOMPRESSED_R32G32B32A32), 1)
    if renderer.texture_id == 0 { return false }
    rlgl.TextureParameters(renderer.texture_id, rlgl.TEXTURE_MIN_FILTER, rlgl.TEXTURE_FILTER_NEAREST)
    rlgl.TextureParameters(renderer.texture_id, rlgl.TEXTURE_MAG_FILTER, rlgl.TEXTURE_FILTER_NEAREST)
    rlgl.TextureParameters(renderer.texture_id, rlgl.TEXTURE_WRAP_S, rlgl.TEXTURE_WRAP_CLAMP)
    rlgl.TextureParameters(renderer.texture_id, rlgl.TEXTURE_WRAP_T, rlgl.TEXTURE_WRAP_CLAMP)
    renderer.atlas.dirty_from = font.ATLAS_HEADER_TEXELS
    renderer.atlas.table_dirty = true
    renderer.atlas.palette_dirty = true
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

// Draws what is batched
RendererFlush :: proc(renderer: ^Renderer) {
    if renderer.count == 0 { return }
    upload(renderer)
    rl.BeginShaderMode(renderer.shader)
    params: [4]f32 = {renderer.weight, 0, 0, 0}
    rl.SetShaderValue(renderer.shader, rl.ShaderLocationIndex(renderer.location_params), &params, .VEC4)
    rlgl.SetUniformSampler(renderer.location_data, renderer.texture_id)
    rlgl.SetTexture(rlgl.GetTextureIdDefault())
    rlgl.Begin(rlgl.TRIANGLES)
    for vertex in renderer.vertices[:renderer.count] {
        slot: [4]u8 = font.SlotColor(vertex.slot, vertex.color)
        rlgl.Color4ub(slot.r, slot.g, slot.b, slot.a)
        rlgl.TexCoord2f(vertex.uv.x, vertex.uv.y)
        rlgl.Vertex2f(vertex.position.x, vertex.position.y)
    }
    rlgl.End()
    rl.EndShaderMode()
    renderer.count = 0
}

// Adds the text to the batch (and draws the batch unless `deferred`), with its baseline starting at `position` (pixels, y down), `size` pixels to the em. Returns where the pen is after the text.
DrawText :: proc(renderer: ^Renderer, text: string, position: rl.Vector2, size: f32, color: rl.Color, options: font.TextOptions = {}) -> rl.Vector2 {
    atlas: ^font.Atlas = renderer.atlas
    if !font.AtlasReserveText(atlas, text) {
        // full: what is batched refers to the glyphs that are about to go
        RendererFlush(renderer)
        font.AtlasClear(atlas)
        if !font.AtlasReserveText(atlas, text) { return position }
    }
    index, color_ok := font.AtlasColor(atlas, [4]u8{color.r, color.g, color.b, color.a})
    if !color_ok {
        RendererFlush(renderer)
        font.AtlasClearColors(atlas)
        index, _ = font.AtlasColor(atlas, [4]u8{color.r, color.g, color.b, color.a})
    }
    needed: int = font.TEXT_VERTICES_PER_GLYPH * len(text)
    if renderer.count + needed > len(renderer.vertices) { RendererFlush(renderer) }
    added, pen, _ := font.TextQuads(atlas, text, {position.x, position.y}, size, renderer.vertices[renderer.count:], options, index)
    renderer.count += added
    if !renderer.deferred { RendererFlush(renderer) }
    return {pen.x, pen.y}
}
