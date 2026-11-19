package font_karl2d

// The Karl2D glue of the font library: the glyph data of an Atlas as a float texture, the shader of the method of the atlas (Slug or the Scanline Sweeper) for the Direct3D 11 or the OpenGL
// backend, and text drawn as quads with Karl2D's own batch.
//
//     renderer: font_karl2d.Renderer
//     font_karl2d.RendererInit(&renderer, &atlas)                 // after karl2d.init
//     ...
//     font_karl2d.DrawText(&renderer, "Hello", {20, 100}, 32, karl2d.WHITE)
//     font_karl2d.RendererDestroy(&renderer)
//
// A glyph is a textured quad whose texture coordinates are the coordinates in the em square and whose color holds the slot of the glyph (the red and green bytes); the color of the text is a
// constant of the shader. The WebGL backend is not supported (the shaders need integer texel fetches of float textures).

import "core:slice"
import k2 "../../karl2d"
import font ".."

when k2.RENDER_BACKEND_NAME == "d3d11" {
    SLUG_VERTEX :: #load("../shaders/slug_d3d11.hlsl")
    SLUG_FRAGMENT :: SLUG_VERTEX
    SCANLINE_VERTEX :: #load("../shaders/scanline_d3d11.hlsl")
    SCANLINE_FRAGMENT :: SCANLINE_VERTEX
    COLOR_NAME :: "text_color"
    DATA_NAME :: "glyph_data"
} else {
    SLUG_VERTEX :: #load("../shaders/vertex_karl2d.glsl")
    SLUG_FRAGMENT :: #load("../shaders/slug_fragment.glsl")
    SCANLINE_VERTEX :: SLUG_VERTEX
    SCANLINE_FRAGMENT :: #load("../shaders/scanline_fragment.glsl")
    COLOR_NAME :: "textColor"
    DATA_NAME :: "glyphData"
}

VERTEX_CAPACITY :: 6 * 1024

Renderer :: struct {
    atlas: ^font.Atlas,
    shader: k2.Shader,
    data: k2.Texture,           // the glyph data
    blank: k2.Texture,          // a texture of one pixel: the quads need one, the shader does not read it
    color_location: k2.Shader_Constant_Location,
    data_bindpoint: int,
    vertices: [VERTEX_CAPACITY]font.TextVertex,
}

// Makes the shader and the texture (as tall as the atlas can get). Needs a window.
RendererInit :: proc(renderer: ^Renderer, atlas: ^font.Atlas) -> bool {
    when k2.RENDER_BACKEND_NAME == "webgl" {
        return false
    } else {
        renderer.atlas = atlas
        vertex: []u8 = SLUG_VERTEX if atlas.method == .SLUG else SCANLINE_VERTEX
        fragment: []u8 = SLUG_FRAGMENT if atlas.method == .SLUG else SCANLINE_FRAGMENT
        shader, shader_ok := k2.load_shader_from_bytes(vertex, fragment)
        if !shader_ok { return false }
        renderer.shader = shader
        location, has_color := renderer.shader.constant_lookup[COLOR_NAME]
        bindpoint, has_data := renderer.shader.texture_lookup[DATA_NAME]
        if !has_color || !has_data { return false }
        renderer.color_location = location
        renderer.data_bindpoint = bindpoint
        data, data_ok := k2.create_texture(font.ATLAS_WIDTH, font.AtlasCapacityRows(atlas), .RGBA_32_Float)
        if !data_ok { return false }
        renderer.data = data
        k2.set_texture_filter(renderer.data, .Point)
        blank, blank_ok := k2.create_texture(1, 1, .RGBA_8_Norm)
        if !blank_ok { return false }
        renderer.blank = blank
        k2.set_shader_texture(renderer.shader, renderer.data_bindpoint, renderer.data)
        atlas.dirty_from = 0
        atlas.table_dirty = true
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

// Draws the text with its baseline starting at `position` (pixels, y down), `size` pixels to the em. Returns the position of the pen after the text.
DrawText :: proc(renderer: ^Renderer, text: string, position: k2.Vec2, size: f32, color: k2.Color, options: font.TextOptions = {}) -> k2.Vec2 {
    count, pen, _ := font.TextQuads(renderer.atlas, text, {position.x, position.y}, size, renderer.vertices[:], options)
    upload(renderer)
    if count > 0 {
        tint: [4]f32 = {f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
        k2.set_shader(renderer.shader)
        k2.set_shader_constant(renderer.shader, renderer.color_location, tint)
        k2.set_shader_texture(renderer.shader, renderer.data_bindpoint, renderer.data)
        for glyph in 0 ..< count / font.TEXT_VERTICES_PER_GLYPH {
            bottom_left: font.TextVertex = renderer.vertices[glyph * font.TEXT_VERTICES_PER_GLYPH]
            top_right: font.TextVertex = renderer.vertices[glyph * font.TEXT_VERTICES_PER_GLYPH + 2]
            slot: [4]u8 = font.SlotColor(bottom_left.slot)
            // the texture of one pixel is addressed in em units: the source is the box in the em square, upside down because y goes up there
            source: k2.Rect = {bottom_left.uv.x, bottom_left.uv.y, top_right.uv.x - bottom_left.uv.x, -(top_right.uv.y - bottom_left.uv.y)}
            destination: k2.Rect = {bottom_left.position.x, top_right.position.y, top_right.position.x - bottom_left.position.x, bottom_left.position.y - top_right.position.y}
            k2.draw_texture_fit(renderer.blank, source, destination, {}, 0, slot)
        }
        k2.set_shader(nil)
    }
    return {pen.x, pen.y}
}
