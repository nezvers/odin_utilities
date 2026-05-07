package atlas_packer_karl2d

import "core:log"
import "core:image"
Image :: image.Image
Color :: [4]u8
rectf :: [4]f32

import "../../karl2d"


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

DestroyImage :: proc(img: ^Image, allocator := context.allocator ) {
    image.destroy(img, allocator)
}


LoadTextureFromImage :: proc(img: ^Image)->karl2d.Texture {
    return karl2d.load_texture_from_bytes_raw(img.pixels.buf[:], img.width, img.height, .RGBA_8_Norm)
}

// size == width == height
// Don't call destroy on this image, instead destroy buffer when needed.
GenerateImageFromBuffer :: proc(buffer: []Color, size:int) -> (result: Image, ok:bool) {
    result, ok = image.pixels_to_image(buffer, size, size)
    ok = image.premultiply_alpha(&result)
	return
}

ClearImage :: proc(img: ^Image, color: Color = {0,0,0,0}) {
    count:int = len(img.pixels.buf) / 4
    color_slice: [^]Color = cast([^]Color)raw_data(img.pixels.buf)
    for i:int = 0; i < count; i += 1 {
        color_slice[i] = color
    }
}

BakeImageRects :: proc(
    source_img: ^Image,
    target_img: ^Image,
    source_rects: []rectf,
    target_rects: []rectf,
    padding: f32 = 0,
) {
    source_slice: [^]Color = cast([^]Color)raw_data(source_img.pixels.buf)
    target_slice: [^]Color = cast([^]Color)raw_data(target_img.pixels.buf)

    for i:int = 0; i < len(source_rects); i += 1 {
        source_rect: ^rectf = &source_rects[i]
        target_rect: ^rectf = &target_rects[i]
        // Hopefully catch out of range indexing
        assert((cast(int)source_rect.x + cast(int)source_rect.w + (cast(int)source_rect.y + source_img.width)) < len(source_img.pixels.buf))
        assert((cast(int)target_rect.x + cast(int)target_rect.w + (cast(int)target_rect.y + target_img.width)) < len(target_img.pixels.buf))

        for y:i32 = 0; y < cast(i32)source_rect.w; y += 1 {
            for x:i32 = 0; x < cast(i32)source_rect.z; x += 1 {
                _X:i32 = cast(i32)source_rect.x + x
                _Y:i32 = cast(i32)source_rect.y + y
                _W:i32 = cast(i32)source_img.width
                source_index:i32 = _X + _Y * _W
                col:Color = source_slice[source_index]

                _X = cast(i32)target_rect.x + x
                _Y = cast(i32)target_rect.y + y
                _W = cast(i32)target_img.width
                target_index:i32 = _X + _Y * _W
                target_slice[target_index] = col
            }
        }
    }
}