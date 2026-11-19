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
    drawVertices(renderer, renderer.vertices[:renderer.count])
    renderer.count = 0
}

// Starts a batch: DrawText only collects until RendererEnd, which draws it all in one go. Another batch inside is not needed: it is the same one.
RendererBegin :: proc(renderer: ^Renderer) {
    renderer.deferred = true
}

RendererEnd :: proc(renderer: ^Renderer) {
    RendererFlush(renderer)
    renderer.deferred = false
}

// Draws a list of vertices that the program made itself (TextQuads, the rich text, a list it kept from an earlier frame) with one draw call, after what is batched (the order stays). The list
// may be of any length and need not be in the batch of the renderer: build it once, draw it as often as you like.
RendererDraw :: proc(renderer: ^Renderer, vertices: []font.TextVertex) {
    RendererFlush(renderer)
    drawVertices(renderer, vertices)
}

@(private)
drawVertices :: proc(renderer: ^Renderer, vertices: []font.TextVertex) {
    if len(vertices) == 0 { return }
    upload(renderer)
    rl.BeginShaderMode(renderer.shader)
    params: [4]f32 = {renderer.weight, 0, 0, 0}
    rl.SetShaderValue(renderer.shader, rl.ShaderLocationIndex(renderer.location_params), &params, .VEC4)
    rlgl.SetUniformSampler(renderer.location_data, renderer.texture_id)
    rlgl.SetTexture(rlgl.GetTextureIdDefault())
    rlgl.Begin(rlgl.TRIANGLES)
    for vertex in vertices {
        slot: [4]u8 = font.SlotColor(vertex.slot, vertex.color, vertex.alpha)
        rlgl.Color4ub(slot.r, slot.g, slot.b, slot.a)
        rlgl.TexCoord2f(vertex.uv.x, vertex.uv.y)
        rlgl.Vertex2f(vertex.position.x, vertex.position.y)
    }
    rlgl.End()
    rl.EndShaderMode()
}

// ------------------------------------------------------------------------------------------------------------------------
// A mesh in a vertex buffer of the GPU: text that is built once and drawn many times (a label that does not change, a page of a book) costs one draw call and no work of the CPU per frame.

VertexOnGpu :: struct #packed {
    position: [2]f32,
    em: [2]f32,
    packed: [4]u8,              // the slot, the palette index and the fade, as in the vertex color of the batch
}

TextMesh :: struct {
    vao: c.uint,
    vbo: c.uint,
    count: int,
}

// Makes a vertex buffer of the vertices (the renderer has to exist: the attributes are the ones of its shader). The palette indices and the slots of the vertices must stay valid (do not clear the
// atlas or its palette while the mesh is in use; a mesh made before AtlasClear has to be made again).
TextMeshCreate :: proc(renderer: ^Renderer, vertices: []font.TextVertex) -> (mesh: TextMesh) {
    if len(vertices) == 0 { return }
    data: []VertexOnGpu = make([]VertexOnGpu, len(vertices), context.temp_allocator)
    for vertex, i in vertices {
        data[i] = {vertex.position, vertex.uv, font.SlotColor(vertex.slot, vertex.color, vertex.alpha)}
    }
    mesh.count = len(vertices)
    mesh.vao = rlgl.LoadVertexArray()
    rlgl.EnableVertexArray(mesh.vao)
    mesh.vbo = rlgl.LoadVertexBuffer(raw_data(data), c.int(len(data) * size_of(VertexOnGpu)), false)
    stride: c.int = size_of(VertexOnGpu)
    position: c.int = rl.GetShaderLocationAttrib(renderer.shader, "vertexPosition")
    em: c.int = rl.GetShaderLocationAttrib(renderer.shader, "vertexTexCoord")
    packed: c.int = rl.GetShaderLocationAttrib(renderer.shader, "vertexColor")
    rlgl.SetVertexAttribute(c.uint(position), 2, rlgl.FLOAT, false, stride, 0)
    rlgl.EnableVertexAttribute(c.uint(position))
    rlgl.SetVertexAttribute(c.uint(em), 2, rlgl.FLOAT, false, stride, 8)
    rlgl.EnableVertexAttribute(c.uint(em))
    rlgl.SetVertexAttribute(c.uint(packed), 4, rlgl.UNSIGNED_BYTE, true, stride, 16)
    rlgl.EnableVertexAttribute(c.uint(packed))
    rlgl.DisableVertexArray()
    return
}

TextMeshDestroy :: proc(mesh: ^TextMesh) {
    if mesh.vao != 0 { rlgl.UnloadVertexArray(mesh.vao) }
    if mesh.vbo != 0 { rlgl.UnloadVertexBuffer(mesh.vbo) }
    mesh^ = {}
}

// Draws the mesh moved by `offset` pixels (one draw call)
TextMeshDraw :: proc(renderer: ^Renderer, mesh: TextMesh, offset: rl.Vector2 = {}) {
    if mesh.count == 0 { return }
    RendererFlush(renderer)
    upload(renderer)
    rlgl.DrawRenderBatchActive()
    rlgl.EnableShader(renderer.shader.id)
    moved: rl.Matrix = rl.MatrixTranslate(offset.x, offset.y, 0)
    mvp: rl.Matrix = rlgl.GetMatrixProjection() * (moved * rlgl.GetMatrixModelview())
    rlgl.SetUniformMatrix(rl.GetShaderLocation(renderer.shader, "mvp"), mvp)
    params: [4]f32 = {renderer.weight, 0, 0, 0}
    rlgl.SetUniform(renderer.location_params, &params, c.int(rl.ShaderUniformDataType.VEC4), 1)
    rlgl.ActiveTextureSlot(0)
    rlgl.EnableTexture(renderer.texture_id)
    slot: c.int = 0
    rlgl.SetUniform(renderer.location_data, &slot, c.int(rl.ShaderUniformDataType.INT), 1)
    if rlgl.EnableVertexArray(mesh.vao) {
        rlgl.DrawVertexArray(0, c.int(mesh.count))
        rlgl.DisableVertexArray()
    }
    rlgl.DisableTexture()
    rlgl.DisableShader()
}

// Adds the text to the batch (and draws the batch unless `deferred`), with its baseline starting at `position` (pixels, y down), `size` pixels to the em. Returns where the pen is after the text.
DrawText :: proc(renderer: ^Renderer, text: string, position: rl.Vector2, size: f32, color: rl.Color, options: font.TextOptions = {}) -> rl.Vector2 {
    atlas: ^font.Atlas = renderer.atlas
    if !font.AtlasReserveText(atlas, text, int(options.face)) {
        // full: what is batched refers to the glyphs that are about to go
        RendererFlush(renderer)
        font.AtlasClear(atlas)
        if !font.AtlasReserveText(atlas, text, int(options.face)) { return position }
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
DrawRich :: proc(renderer: ^Renderer, rich: ^font.RichText, position: rl.Vector2, time: f32, options: font.RichDrawOptions = {}) {
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
