package atlas_packer_raylib

import "core:fmt"
import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
vec2i::[2]i32
rectf::[4]f32

import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect

import "core:unicode/utf8"
import "core:strings"
// import "core:slice"


pack_rectangles :: proc(rc: ^stbrp.Context, rect_list:[]rectf)->(ok:bool) {
    // Prepare rectangle list for packing
    pack_rects:[dynamic]stb_Rect
    defer delete(pack_rects)

    for i:int = 0; i < len(rect_list); i += 1 {
        rect:rectf = rect_list[i]
        append(&pack_rects, stb_Rect {
            id = cast(i32)i,
            w = stbrp.Coord(rect.z),
            h = stbrp.Coord(rect.w),
        })
    }

    // Packing
    rect_pack_res := stbrp.pack_rects(rc, raw_data(pack_rects), i32(len(pack_rects)))
    if rect_pack_res != 1 {
        fmt.printf("Failed packing \n")
        return false
    }

    // Read packed positions
    for i:int = 0; i < len(pack_rects); i += 1 {
        rect:^stb_Rect = &pack_rects[i]
        id:i32 = rect.id
        tex_pos:[2]f32 = {cast(f32)rect.x, cast(f32)rect.y}
        rect_list[id].xy = tex_pos
    }
    return true
}

prepare_font_rects :: proc(font_in:^rl.Font, font_out:^rl.Font) {
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
    letters:[]rune = utf8.string_to_runes(LETTERS_IN_FONT)
    defer delete(letters)
    letter_rects = make([]rectf, len(letters))
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
        baseSize = font_source.baseSize,
        glyphCount = i32(len(glyphs)),
		glyphPadding = 0,
		texture = render_texture.texture,
		recs = raw_data(transmute([]Rectangle)letter_rects),
		glyphs = raw_data(glyphs),
    }

    letter_strings:[]string = make_slice([]string, len(letters))
    defer delete(letter_strings)
    // Raylib works with cstrings
    letter_cstrings = make_slice([]cstring, len(letters))

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