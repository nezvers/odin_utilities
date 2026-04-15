package atlas_packer_raylib

// import "core:fmt"

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

import packer ".."
vec2i:: packer.vec2i
rectf:: packer.rectf

import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect

import "core:unicode/utf8"
import "core:strings"
// import "core:slice"




bak :: proc (
    font_in:^rl.Font, 
    font_out:^rl.Font, 
    baked_texture: rl.Texture,
    letters: string,
    letter_rects: ^[]rectf,
    letter_cstrings: ^[]cstring,
) {
    rune_data :: struct {
        glyph:rl.GlyphInfo,
        rect:rectf,
    }
    glyph_map:map[rune]rune_data // = make_map(map[rune]rune_data)
    defer delete(glyph_map)
    // Cache all glyphs in the source font
    for i:i32 = 0; i < font_in.glyphCount; i += 1 {
        glyph:rl.GlyphInfo = font_in.glyphs[i]
        rect:rectf = transmute(rectf)font_in.recs[i]
        glyph_map[glyph.value] = {glyph, rect}
    }

    // Collect rectangles for letters
    letters:[]rune = utf8.string_to_runes(letters)
    defer delete(letters)

    letter_rects^ = make([]rectf, len(letters))
    glyphs := make([]rl.GlyphInfo, len(letter_rects))
    
    for i:int = 0; i < len(letters); i += 1 {
        value, ok: = glyph_map[letters[i]]
        if !ok {
            continue
        }
        glyphs[i] = {
            value = value.glyph.value,
            offsetX = value.glyph.offsetX,
            offsetY = value.glyph.offsetY,
            advanceX = value.glyph.advanceX,
        }
        letter_rects[i] = value.rect
    }

    font_out^ = {
        baseSize = font_in.baseSize,
        glyphCount = i32(len(glyphs)),
		glyphPadding = 0,
		texture = baked_texture,
		recs = raw_data(transmute([]Rectangle)letter_rects^),
		glyphs = raw_data(glyphs),
    }

    letter_strings:[]string = make_slice([]string, len(letters))
    defer delete(letter_strings)
    // Raylib works with cstrings
    letter_cstrings^ = make_slice([]cstring, len(letters))

    for i:int = 0; i < len(letters); i += 1 {
        letter_strings[i] = utf8.runes_to_string(letters[i:i+1])
        letter_cstrings[i] = strings.clone_to_cstring(letter_strings[i])

        cs:cstring = letter_cstrings[i]
        size:Vector2 = rl.MeasureTextEx(font_in^, cs, cast(f32)font_in.baseSize, 0)
        letter_rects[i].zw = size
    }
    // delete each entry at the end
    defer {
        for i:int = 0; i < len(letters); i += 1 {
            delete(letter_strings[i])
        }
    }
}


// Add 
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

// Raylib Rendertexture is vertically flipped, so recommended to use temporary RenderTexture then transfer that to target RenderTexture
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