package font_karl2d

// The Karl2D glue of the font library: the glyph data of an Atlas as a float texture, the shader of the method of the atlas (Slug or the Scanline Sweeper) for the Direct3D 11 or the OpenGL
// backend, and text drawn as quads with Karl2D's own batch.
//
//     renderer: font_karl2d.Renderer
//     font_karl2d.RendererInit(&renderer, &atlas, make([]font.TextVertex, 6 * 2048))      // after karl2d.init
//     ...
//     font_karl2d.DrawText(&renderer, "Hello", {20, 100}, 32, karl2d.WHITE)
//     font_karl2d.RendererDestroy(&renderer)
//
// A glyph is a textured quad whose texture coordinates are the coordinates in the em square and whose color holds the slot of the glyph (red and green bytes) and the index of the color of the
// text in the palette row of the atlas texture (blue): text of any number of colors shares the batch of Karl2D. A call of DrawText draws at once; with `renderer.deferred` set it only collects
// the text and RendererFlush draws it (a program that mixes text with other drawing flushes before it draws something else, so that everything stays in order). An atlas that is full is cleared
// and filled again (what is batched is drawn first). The WebGL backend is not supported (the shaders need integer texel fetches of float textures).

import "core:slice"
import k2 "../../karl2d"
import font ".."

when k2.RENDER_BACKEND_NAME == "d3d11" {
    SLUG_VERTEX :: #load("../shaders/slug_d3d11.hlsl")
    SLUG_FRAGMENT :: SLUG_VERTEX
    SCANLINE_VERTEX :: #load("../shaders/scanline_d3d11.hlsl")
    SCANLINE_FRAGMENT :: SCANLINE_VERTEX
    PARAMS_NAME :: "text_params"
    DATA_NAME :: "glyph_data"
} else {
    SLUG_VERTEX :: #load("../shaders/vertex_karl2d.glsl")
    SLUG_FRAGMENT :: #load("../shaders/slug_fragment.glsl")
    SCANLINE_VERTEX :: SLUG_VERTEX
    SCANLINE_FRAGMENT :: #load("../shaders/scanline_fragment.glsl")
    PARAMS_NAME :: "textParams"
    DATA_NAME :: "glyphData"
}

Renderer :: struct {
    atlas: ^font.Atlas,
    shader: k2.Shader,
    data: k2.Texture,           // the glyph data
    blank: k2.Texture,          // a texture of one pixel: the quads need one, the shader does not read it
    params_location: k2.Shader_Constant_Location,
    data_bindpoint: int,
    weight: f32,                // the exponent of the coverage: 1 as it is, under 1 heavier text (light text on a dark ground looks thin)
    deferred: bool,             // DrawText adds to the batch and RendererFlush draws it
    count: int,                 // vertices in the batch
    vertices: []font.TextVertex, // the batch (the caller's memory: 6 vertices per glyph)
}

// Makes the shader and the texture (as tall as the atlas can get). Needs a window.
RendererInit :: proc(renderer: ^Renderer, atlas: ^font.Atlas, vertices: []font.TextVertex) -> bool {
    assert(len(vertices) >= 6 * 64, "room for some glyphs")
    renderer.vertices = vertices
    when k2.RENDER_BACKEND_NAME == "webgl" {
        return false
    } else {
        renderer.atlas = atlas
        renderer.weight = 1
        vertex: []u8 = SLUG_VERTEX if atlas.method == .SLUG else SCANLINE_VERTEX
        fragment: []u8 = SLUG_FRAGMENT if atlas.method == .SLUG else SCANLINE_FRAGMENT
        shader, shader_ok := k2.load_shader_from_bytes(vertex, fragment)
        if !shader_ok { return false }
        renderer.shader = shader
        location, has_params := renderer.shader.constant_lookup[PARAMS_NAME]
        bindpoint, has_data := renderer.shader.texture_lookup[DATA_NAME]
        if !has_params || !has_data { return false }
        renderer.params_location = location
        renderer.data_bindpoint = bindpoint
        data, data_ok := k2.create_texture(font.ATLAS_WIDTH, font.AtlasCapacityRows(atlas), .RGBA_32_Float)
        if !data_ok { return false }
        renderer.data = data
        k2.set_texture_filter(renderer.data, .Point)
        blank, blank_ok := k2.create_texture(1, 1, .RGBA_8_Norm)
        if !blank_ok { return false }
        renderer.blank = blank
        k2.set_shader_texture(renderer.shader, renderer.data_bindpoint, renderer.data)
        atlas.dirty_from = font.ATLAS_HEADER_TEXELS
        atlas.table_dirty = true
        atlas.palette_dirty = true
        return true
    }
}

RendererDestroy :: proc(renderer: ^Renderer) {
    k2.destroy_texture(renderer.data)
    k2.destroy_texture(renderer.blank)
    k2.destroy_shader(renderer.shader)
    renderer^ = {}
}

// What changed in the atlas goes to the texture
@(private)
upload :: proc(renderer: ^Renderer) {
    row_bytes: int = font.ATLAS_WIDTH * 16
    for range in font.AtlasTakeDirty(renderer.atlas) {
        if range.count == 0 || range.first >= font.AtlasCapacityRows(renderer.atlas) { continue }
        rows: int = min(range.count, font.AtlasCapacityRows(renderer.atlas) - range.first)
        bytes: []u8 = slice.to_bytes(renderer.atlas.texels[range.first * font.ATLAS_WIDTH * 4:(range.first + rows) * font.ATLAS_WIDTH * 4])
        k2.update_texture(renderer.data, bytes, {0, f32(range.first), f32(font.ATLAS_WIDTH), f32(rows)}, row_bytes)
    }
}

// Draws what is batched
RendererFlush :: proc(renderer: ^Renderer) {
    if renderer.count == 0 { return }
    drawVertices(renderer, renderer.vertices[:renderer.count], {})
    renderer.count = 0
}

// Starts a batch: DrawText only collects until RendererEnd, which draws it all in one go.
RendererBegin :: proc(renderer: ^Renderer) {
    renderer.deferred = true
}

RendererEnd :: proc(renderer: ^Renderer) {
    RendererFlush(renderer)
    renderer.deferred = false
}

// Draws a list of vertices that the program made itself (TextQuads, the rich text, a list it kept from an earlier frame) in one batch of Karl2D, after what is batched (the order stays).
RendererDraw :: proc(renderer: ^Renderer, vertices: []font.TextVertex) {
    RendererFlush(renderer)
    drawVertices(renderer, vertices, {})
}

@(private)
drawVertices :: proc(renderer: ^Renderer, vertices: []font.TextVertex, offset: k2.Vec2) {
    if len(vertices) == 0 { return }
    upload(renderer)
    params: [4]f32 = {renderer.weight, 0, 0, 0}
    k2.set_shader(renderer.shader)
    k2.set_shader_constant(renderer.shader, renderer.params_location, params)
    k2.set_shader_texture(renderer.shader, renderer.data_bindpoint, renderer.data)
    // the vertices go to the batch of Karl2D as they are: the em coordinates are the texture coordinates (the one pixel texture is not read), so a slanted or turned quad is exact
    blank: ^k2.Texture_Object = k2._get_texture_or_error(renderer.blank, "the blank texture of the font renderer %v", renderer.blank)
    if blank == nil { return }
    for glyph in 0 ..< len(vertices) / font.TEXT_VERTICES_PER_GLYPH {
        first: int = glyph * font.TEXT_VERTICES_PER_GLYPH
        if !k2._begin_textured_draw(blank, font.TEXT_VERTICES_PER_GLYPH) { return }
        for vertex in vertices[first:first + font.TEXT_VERTICES_PER_GLYPH] {
            k2.batch_vertex(vertex.position + offset, vertex.uv, font.SlotColor(vertex.slot, vertex.color, vertex.alpha))
        }
    }
    k2.set_shader(nil)
}

// A list of vertices that is kept and drawn again: Karl2D has no vertex buffer of its own to put it in, so a mesh here is the list itself (a slice of your memory, not a copy), and drawing it is
// one batch of Karl2D. The same calls as the raylib glue have, so a program that is written for one runs on the other.
TextMesh :: struct {
    vertices: []font.TextVertex,
}

TextMeshCreate :: proc(renderer: ^Renderer, vertices: []font.TextVertex) -> TextMesh {
    return {vertices}
}

TextMeshDestroy :: proc(mesh: ^TextMesh) {
    mesh^ = {}
}

// Draws the mesh moved by `offset` pixels
TextMeshDraw :: proc(renderer: ^Renderer, mesh: TextMesh, offset: k2.Vec2 = {}) {
    RendererFlush(renderer)
    drawVertices(renderer, mesh.vertices, offset)
}

// Adds the text to the batch (and draws the batch unless `deferred`), with its baseline starting at `position` (pixels, y down), `size` pixels to the em. Returns where the pen is after the text.
DrawText :: proc(renderer: ^Renderer, text: string, position: k2.Vec2, size: f32, color: k2.Color, options: font.TextOptions = {}) -> k2.Vec2 {
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
    added, pen, _, _ := font.TextQuads(atlas, text, {position.x, position.y}, size, renderer.vertices[renderer.count:], options, index)
    renderer.count += added
    if !renderer.deferred { RendererFlush(renderer) }
    return {pen.x, pen.y}
}

// Draws rich text (font.RichParse and font.RichLayout made it) at `position` (the top left corner of the text, pixels, y down) at `time` seconds: the quads go into the batch like those of
// DrawText. A full palette or a full atlas is dealt with here: what was batched before is drawn, the palette or the atlas is cleared and the text is made again.
DrawRich :: proc(renderer: ^Renderer, rich: ^font.RichText, position: k2.Vec2, time: f32, options: font.RichDrawOptions = {}) {
    atlas: ^font.Atlas = renderer.atlas
    for attempt in 0 ..< 3 {
        start: int = renderer.count
        result: font.RichDrawResult = font.RichDraw(atlas, rich, {position.x, position.y}, time, renderer.vertices[start:], options)
        if result.complete || attempt == 2 {
            renderer.count += result.count
            break
        }
        // not whole: draw what was there before this text, then try again with the whole buffer, a clean palette or a clean atlas
        RendererFlush(renderer)
        if result.palette_full { font.AtlasClearColors(atlas) }
        if result.atlas_full { font.AtlasClear(atlas) }
    }
    if !renderer.deferred { RendererFlush(renderer) }
}
