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

import "core:math"
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
    upload(renderer)
    params: [4]f32 = {renderer.weight, 0, 0, 0}
    k2.set_shader(renderer.shader)
    k2.set_shader_constant(renderer.shader, renderer.params_location, params)
    k2.set_shader_texture(renderer.shader, renderer.data_bindpoint, renderer.data)
    for glyph in 0 ..< renderer.count / font.TEXT_VERTICES_PER_GLYPH {
        first: int = glyph * font.TEXT_VERTICES_PER_GLYPH
        bottom_left: font.TextVertex = renderer.vertices[first]
        bottom_right: font.TextVertex = renderer.vertices[first + 1]
        top_right: font.TextVertex = renderer.vertices[first + 2]
        top_left: font.TextVertex = renderer.vertices[first + 5]
        slot: [4]u8 = font.SlotColor(bottom_left.slot, bottom_left.color, bottom_left.alpha)
        // the quad is a rectangle that may be turned: its top left corner is where it turns, its sides give the size and the angle. The texture of one pixel is addressed in em units: the
        // source is the box in the em square, upside down because y goes up there
        across: k2.Vec2 = bottom_right.position - bottom_left.position
        down: k2.Vec2 = bottom_left.position - top_left.position
        source: k2.Rect = {bottom_left.uv.x, bottom_left.uv.y, top_right.uv.x - bottom_left.uv.x, -(top_right.uv.y - bottom_left.uv.y)}
        destination: k2.Rect = {top_left.position.x, top_left.position.y, math.sqrt(across.x * across.x + across.y * across.y), math.sqrt(down.x * down.x + down.y * down.y)}
        k2.draw_texture_fit(renderer.blank, source, destination, {}, math.atan2(across.y, across.x), slot)
    }
    k2.set_shader(nil)
    renderer.count = 0
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
