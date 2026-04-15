package atlas_packer_raylib

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

import packer ".."
vec2i:: packer.vec2i
rectf:: packer.rectf

import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect


// Add padding to space out Glyphs
init_packed_font :: proc (
    font_source:^rl.Font,
    font_packed:^rl.Font,
    glyphs: []rl.GlyphInfo,
    letter_rects: []rectf,
    padding: f32 = 0,
) {
    for i:i32 = 0; i < font_source.glyphCount; i += 1 {
        glyphs[i] = font_source.glyphs[i]
        letter_rects[i] = transmute(rectf)font_source.recs[i]
        // Add extra padding
        letter_rects[i].zw += {padding * 2, padding * 2}
    }

    font_packed^ = {
        baseSize = font_source.baseSize,
        glyphCount = i32(len(glyphs)),
		glyphPadding = font_source.glyphPadding,
		recs = raw_data(transmute([]Rectangle)letter_rects),
		glyphs = raw_data(glyphs),
    }
}

BakeImageRects :: proc(
    source_img: ^rl.Image,
    target_img: ^rl.Image,
    source_rects: []rectf,
    target_rects: []rectf,
    padding: f32 = 0,
) {
    for i:int = 0; i < len(source_rects); i += 1 {
        rect_source: ^rectf = &source_rects[i]
        rect_dest: ^rectf = &target_rects[i]
        for y:i32 = 0; y < cast(i32)rect_source.w; y += 1 {
            for x:i32 = 0; x < cast(i32)rect_source.z; x += 1 {
                col:rl.Color = rl.GetImageColor(source_img^, x + cast(i32)rect_source.x, y + cast(i32)rect_source.y)
                rl.ImageDrawPixelV(target_img, {rect_dest.x + cast(f32)x + padding, rect_dest.y + cast(f32)y + padding}, col)
            }
        }
    }
}

// Raylib Rendertexture is vertically flipped, so recommended to use temporary RenderTexture then transfer that to target RenderTexture
// Recommend to use BakeImageRects
BakeTextureRects :: proc(
    render_texture: rl.RenderTexture,
    source_texture:rl.Texture2D,
    source_rects: []rectf,
    target_rects: []rectf,
) {
    rl.BeginTextureMode(render_texture)

    for i:int = 0; i < len(source_rects); i += 1 {
        rl.DrawTextureRec(source_texture, transmute(Rectangle)source_rects[i], target_rects[i].xy, rl.WHITE)
    }

    rl.EndTextureMode()
}