package demo_karl2d

// The text of the demos with Karl2D: an atlas and a renderer for each method, made the first time the text is drawn (the window exists by then).

import k2 "../../karl2d"
import kit "../../demo_kit"
import demo_common "../demo_common"
import font "../"
import font_karl2d "../glue_karl2d"

ATLAS_ROWS :: 16

Method_Renderer :: struct {
    ready: bool,
    texels: []f32,
    slots: []i32,
    atlas: font.Atlas,
    renderer: font_karl2d.Renderer,
}

renderers: [font.Method]Method_Renderer

draw_text :: proc(ctx: ^kit.Context, face: ^font.Font, requests: []demo_common.TextRequest) {
    for request in requests {
        entry: ^Method_Renderer = &renderers[request.method]
        if !entry.ready {
            entry.texels = make([]f32, 4 * font.ATLAS_WIDTH * ATLAS_ROWS)
            entry.slots = make([]i32, face.glyph_count)
            font.AtlasInit(&entry.atlas, face, request.method, entry.texels, entry.slots)
            if !font_karl2d.RendererInit(&entry.renderer, &entry.atlas, make([]font.TextVertex, 6 * 2048)) { return }
            entry.ready = true
        }
        font_karl2d.DrawText(&entry.renderer, request.text, {request.position.x, request.position.y}, request.size, k2.Color(request.color))
    }
}
