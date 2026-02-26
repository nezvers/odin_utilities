package atlas_packer

import "core:os"
import "core:c"
// import "core:strings"
import stbtt "vendor:stb/truetype"
// import stbim "vendor:stb/image"

rectf :: [4]f32
vec2i :: [2]int

Glyph :: struct {
	value: rune,
	offset: vec2i,
	advance_x: int,
}

GetFontRects :: proc(font_path:string, font_height:f32, letters:[]rune, rectangles:[]rectf, glyphs:[]Glyph)->(ok:bool) {
    assert(len(letters) != 0)
    assert(len(letters) == len(rectangles))
    assert(len(letters) == len(glyphs))

    font_data, file_ok := os.read_entire_file(font_path)
    if !file_ok {
        return false
    }

    fi: stbtt.fontinfo
    if !stbtt.InitFont(&fi, raw_data(font_data), 0){
        return false
    }

    scale_factor := stbtt.ScaleForPixelHeight(&fi, font_height)
    ascent: c.int
    stbtt.GetFontVMetrics(&fi, &ascent, nil, nil)

    for r, r_idx in letters {
        advance_x: c.int
        stbtt.GetCodepointHMetrics(&fi, r, &advance_x, nil)

        w, h, ox, oy: c.int
        // Is this the only way to get offsets?
        data := stbtt.GetCodepointBitmap(&fi, scale_factor, scale_factor, r, &w, &h, &ox, &oy)

        glyphs[r_idx] = {
            value = r,
            offset = {int(ox), int(f32(oy) + f32(ascent)*scale_factor)},
            advance_x = int(f32(advance_x)*scale_factor),
        }
        rectangles[r_idx].zw = {cast(f32)w + 2, cast(f32)h + 2}
    }

    return true
}