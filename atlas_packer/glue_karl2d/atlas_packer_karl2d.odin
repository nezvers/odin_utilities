package atlas_packer_karl2d

import "core:log"
import "core:image"
// Registers the decoders that LoadImageFromBytes depends on, otherwise it only works when the caller happens to import them
import _ "core:image/png"
import _ "core:image/jpeg"
import "core:slice"
import "core:testing"
Image :: image.Image
Color :: [4]u8
rectf :: [4]f32

import "../../karl2d"
import packer ".."

// Decoded image uses `allocator` (give it an arena, there is no need to destroy)
LoadImageFromBytes :: proc(bytes: []u8, options: image.Options = {}, allocator := context.allocator) -> (result: ^Image, ok:bool) {
	load_options := image.Options {
		.alpha_add_if_missing,
	}

	if .alpha_premultiply in options {
		load_options += { .alpha_premultiply }
	}

	img, img_err := image.load_from_bytes(bytes, options = load_options, allocator = allocator)

	if img_err != nil {
		log.errorf("Error loading texture: %v", img_err)
		return
	}
    result = img
    ok = true

	return
}

// Only needed when image wasn't allocated from an arena
DestroyImage :: proc(img: ^Image, allocator := context.allocator ) {
    image.destroy(img, allocator)
}

LoadTextureFromImage :: proc(img: ^Image)->karl2d.Texture {
    return karl2d.load_texture_from_bytes_raw(img.pixels[:], img.width, img.height, .RGBA_8_Norm)
}

// Transparent RGBA image where pixel memory comes from `allocator`, for example an arena.
// size == width == height. Don't call DestroyImage on arena memory, free the arena instead.
CreateImage :: proc(size:int, allocator := context.allocator) -> (result: Image, ok:bool) {
    pixels, err := make([dynamic]u8, size * size * 4, allocator)
    if err != nil {
        return
    }
    result = {
        width = size,
        height = size,
        channels = 4,
        depth = 8,
        pixels = pixels,
    }
    ok = true
    return
}

ClearImage :: proc(img: ^Image, color: Color = {0,0,0,0}) {
    count:int = len(img.pixels) / 4
    color_slice: [^]Color = cast([^]Color)raw_data(img.pixels[:])
    for i:int = 0; i < count; i += 1 {
        color_slice[i] = color
    }
}

// Copy source rectangles to the positions of target rectangles. Target gets `padding` pixels offset
BakeImageRects :: proc(
    source_img: ^Image,
    target_img: ^Image,
    source_rects: []rectf,
    target_rects: []rectf,
    padding: f32 = 0,
) {
    assert(len(source_rects) <= len(target_rects))
    source_slice: [^]Color = cast([^]Color)raw_data(source_img.pixels[:])
    target_slice: [^]Color = cast([^]Color)raw_data(target_img.pixels[:])

    for i:int = 0; i < len(source_rects); i += 1 {
        source_rect: ^rectf = &source_rects[i]
        target_rect: ^rectf = &target_rects[i]
        offset_x: int = cast(int)target_rect.x + cast(int)padding
        offset_y: int = cast(int)target_rect.y + cast(int)padding
        assert(cast(int)source_rect.x + cast(int)source_rect.z <= source_img.width)
        assert(cast(int)source_rect.y + cast(int)source_rect.w <= source_img.height)
        assert(offset_x + cast(int)source_rect.z <= target_img.width)
        assert(offset_y + cast(int)source_rect.w <= target_img.height)

        for y:int = 0; y < cast(int)source_rect.w; y += 1 {
            for x:int = 0; x < cast(int)source_rect.z; x += 1 {
                source_index: int = (cast(int)source_rect.x + x) + (cast(int)source_rect.y + y) * source_img.width
                target_index: int = (offset_x + x) + (offset_y + y) * target_img.width
                target_slice[target_index] = source_slice[source_index]
            }
        }
    }
}

// Render font glyphs into the atlas as white pixels with glyph alpha (same format Karl2D uses for its own static fonts).
// `rects` are packed rectangles that include `padding`. alpha_buffer has to fit the biggest glyph (packer.GlyphsMaxBytes), can be temporary memory.
BakeFontGlyphs :: proc(
    font: ^packer.Font,
    glyphs: []packer.Glyph,
    rects: []rectf,
    atlas: ^Image,
    alpha_buffer: []u8,
    padding: f32 = 0,
) -> (ok:bool) {
    assert(len(glyphs) <= len(rects))
    atlas_slice: [^]Color = cast([^]Color)raw_data(atlas.pixels[:])

    for i:int = 0; i < len(glyphs); i += 1 {
        glyph: ^packer.Glyph = &glyphs[i]
        width: int = int(glyph.size.x)
        height: int = int(glyph.size.y)
        if width * height == 0 { continue }
        if !packer.RenderGlyph(font, glyph, alpha_buffer) {
            return false
        }

        offset_x: int = cast(int)rects[i].x + cast(int)padding
        offset_y: int = cast(int)rects[i].y + cast(int)padding
        assert(offset_x + width <= atlas.width)
        assert(offset_y + height <= atlas.height)

        for y:int = 0; y < height; y += 1 {
            for x:int = 0; x < width; x += 1 {
                alpha: u8 = alpha_buffer[x + y * width]
                atlas_slice[(offset_x + x) + (offset_y + y) * atlas.width] = {255, 255, 255, alpha}
            }
        }
    }
    return true
}

// Make a Karl2D static font that draws glyphs from `atlas` (texture of the baked image).
// Karl2D owns the glyph slices and frees them in destroy_font, so they are allocated with state.allocator, not an arena.
// destroy_font also destroys `atlas` texture, so call it instead of destroying the texture yourself.
// `rects` are the packed rectangles that include `padding`.
RegisterFont :: proc(
    state: ^karl2d.State,
    atlas: karl2d.Texture,
    font: ^packer.Font,
    glyphs: []packer.Glyph,
    rects: []rectf,
    padding: f32 = 0,
    options: karl2d.Font_Options = {},
) -> (result: karl2d.Font, ok:bool) {
    assert(len(glyphs) <= len(rects))
    if len(glyphs) == 0 {
        return
    }

    static_glyphs: []karl2d.Font_Baked_Glyph = make([]karl2d.Font_Baked_Glyph, len(glyphs), state.allocator)
    for glyph, i in glyphs {
        static_glyphs[i] = {
            value = glyph.value,
            index = glyph.index,
            // Real glyph bitmap without padding
            rect = {rects[i].x + padding, rects[i].y + padding, f32(glyph.size.x), f32(glyph.size.y)},
            offset = glyph.offset,
            advance = glyph.advance_x,
        }
    }
    // Karl2D looks glyphs up through ranges of consecutive characters
    slice.sort_by(static_glyphs, proc(a, b: karl2d.Font_Baked_Glyph) -> bool { return a.value < b.value })

    range_count: int = 1
    for i:int = 1; i < len(static_glyphs); i += 1 {
        if static_glyphs[i].value != static_glyphs[i-1].value + 1 {
            range_count += 1
        }
    }
    ranges: []karl2d.Font_Baked_Glyph_Range = make([]karl2d.Font_Baked_Glyph_Range, range_count, state.allocator)
    range_index: int = 0
    ranges[0] = {start_idx = 0, start = static_glyphs[0].value, end = static_glyphs[0].value + 1}
    for i:int = 1; i < len(static_glyphs); i += 1 {
        if static_glyphs[i].value != static_glyphs[i-1].value + 1 {
            range_index += 1
            ranges[range_index] = {start_idx = i, start = static_glyphs[i].value}
        }
        ranges[range_index].end = static_glyphs[i].value + 1
    }

    font_data: karl2d.Font_Data = {
        options = options,
        type = .Static,
        static_atlas = atlas,
        static_glyphs = static_glyphs,
        static_glyph_ranges = ranges,
        static_font_size = font.height,
        static_line_spacing = font.line_spacing,
    }
    result = karl2d.Font(len(state.fonts))
    append(&state.fonts, font_data)
    ok = true
    return
}

// --- Tests ---
// Only the CPU side is tested here, everything that needs a texture or a window is left out.

@(test)
test_create_and_clear_image :: proc(t: ^testing.T) {
    image, ok := CreateImage(8)
    testing.expect(t, ok)
    defer delete(image.pixels)
    testing.expect_value(t, image.width, 8)
    testing.expect_value(t, image.height, 8)
    testing.expect_value(t, image.channels, 4)
    testing.expect_value(t, len(image.pixels), 8 * 8 * 4)
    for value in image.pixels { testing.expect(t, value == 0, "starts transparent") }

    ClearImage(&image, {10, 20, 30, 40})
    pixels: [^]Color = cast([^]Color)raw_data(image.pixels[:])
    for i in 0 ..< 64 {
        if pixels[i] != {10, 20, 30, 40} {
            testing.expectf(t, false, "pixel %d is %v", i, pixels[i])
            return
        }
    }
    ClearImage(&image)
    testing.expect_value(t, pixels[63], Color{0, 0, 0, 0})
}

@(test)
test_bake_image_rects_copies_with_padding :: proc(t: ^testing.T) {
    source, source_ok := CreateImage(8)
    target, target_ok := CreateImage(16)
    testing.expect(t, source_ok && target_ok)
    defer { delete(source.pixels); delete(target.pixels) }

    // every source pixel gets a value that tells where it came from
    source_pixels: [^]Color = cast([^]Color)raw_data(source.pixels[:])
    for y in 0 ..< 8 {
        for x in 0 ..< 8 { source_pixels[x + y * 8] = {u8(x), u8(y), 100, 255} }
    }

    source_rects: [2]rectf = {{1, 2, 3, 2}, {4, 4, 2, 2}}
    target_rects: [2]rectf = {{5, 6, 0, 0}, {10, 0, 0, 0}}
    BakeImageRects(&source, &target, source_rects[:], target_rects[:], 1)

    target_pixels: [^]Color = cast([^]Color)raw_data(target.pixels[:])
    // first rectangle: its top left source pixel (1, 2) lands at (5 + 1, 6 + 1)
    testing.expect_value(t, target_pixels[6 + 7 * 16], Color{1, 2, 100, 255})
    testing.expect_value(t, target_pixels[8 + 8 * 16], Color{3, 3, 100, 255})              // the last pixel of the 3x2 block
    testing.expect_value(t, target_pixels[5 + 6 * 16], Color{0, 0, 0, 0})                  // the padding stays untouched
    testing.expect_value(t, target_pixels[9 + 7 * 16], Color{0, 0, 0, 0})                  // nothing is copied beyond the rectangle width
    // second rectangle
    testing.expect_value(t, target_pixels[11 + 1 * 16], Color{4, 4, 100, 255})
    testing.expect_value(t, target_pixels[12 + 2 * 16], Color{5, 5, 100, 255})
}

@(test)
test_bake_font_glyphs_writes_white_with_glyph_alpha :: proc(t: ^testing.T) {
    @(static) font_data := #load("../../assets/fonts/font.ttf")
    font: packer.Font
    testing.expect(t, packer.FontInit(&font, font_data, 24))

    letters: []rune = {'H', 'i'}
    rects: [2]rectf
    glyphs: [2]packer.Glyph
    count, rects_ok := packer.GetFontRects(&font, letters, rects[:], glyphs[:], 1)
    testing.expect(t, rects_ok)
    testing.expect_value(t, count, 2)
    rects[1].x = 40                                                                       // place the second glyph away from the first

    atlas, atlas_ok := CreateImage(64)
    testing.expect(t, atlas_ok)
    defer delete(atlas.pixels)
    alpha := make([]u8, packer.GlyphsMaxBytes(glyphs[:]))
    defer delete(alpha)
    testing.expect(t, BakeFontGlyphs(&font, glyphs[:], rects[:], &atlas, alpha, 1))

    pixels: [^]Color = cast([^]Color)raw_data(atlas.pixels[:])
    inked, wrong: int
    for y in 0 ..< int(glyphs[0].size.y) {
        for x in 0 ..< int(glyphs[0].size.x) {
            pixel: Color = pixels[(int(rects[0].x) + 1 + x) + (int(rects[0].y) + 1 + y) * 64]
            if pixel.a > 0 { inked += 1 }
            if pixel.rgb != {255, 255, 255} { wrong += 1 }
        }
    }
    testing.expect(t, inked > 0, "the letter is drawn")
    testing.expect_value(t, wrong, 0)                                                      // colour is white everywhere inside the glyph box

    testing.expect_value(t, pixels[0], Color{0, 0, 0, 0})                                  // outside of the glyph boxes stays transparent

    small: [1]u8
    testing.expect(t, !BakeFontGlyphs(&font, glyphs[:], rects[:], &atlas, small[:], 1), "an alpha buffer that is too small is reported")
}

@(test)
test_load_image_from_bytes :: proc(t: ^testing.T) {
    @(static) png := #load("../../assets/textures/dust_4_strip.png")
    loaded, ok := LoadImageFromBytes(png)
    testing.expect(t, ok)
    if !ok { return }
    defer DestroyImage(loaded)
    testing.expect(t, loaded.width > 0 && loaded.height > 0)
    testing.expect_value(t, loaded.channels, 4)                                            // alpha is added when the file has none
    testing.expect_value(t, len(loaded.pixels), loaded.width * loaded.height * 4)

    garbage: [32]u8
    context.logger = log.nil_logger()                                                      // the failure is expected, the test runner counts logged errors as failures
    _, garbage_ok := LoadImageFromBytes(garbage[:])
    testing.expect(t, !garbage_ok, "random bytes are not an image")
}
