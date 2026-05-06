package atlas_packer_karl2d

import "core:log"
import "core:image"
Image :: ^image.Image
Color :: [4]u8

// Color buffer for atlas image, Size is squared N * N
AtlasBuffer :: struct($N: int) {
    buffer: [N * N]Color,
}

load_image_from_bytes :: proc(bytes: []u8, options: image.Options = {}, allocator := context.allocator) -> (result: Image, ok:bool) {
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

destroy_image :: proc(img: Image, allocator := context.allocator ) {
    image.destroy(img, allocator)
}

// TODO: texture from image

generate_image_from_bytes :: proc(atlas_buffer: AtlasBuffer($N)) -> (result: Image, ok:bool) {
    result, ok = image.pixels_to_image(atlas_buffer.buffer[:], N, N)
	return
}