package atlas_packer

import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect

rectf :: [4]f32
vec2i :: [2]int

AtlasPacker :: struct($size: i32) {
    ctx: stbrp.Context,
    buffer: []rectf,            // accumulate rects to pack
    nodes: [size]stbrp.Node,    // will determine power of 2 atlas size
    length:int,                 // used buffer
}

Init :: proc(
    packer: ^AtlasPacker,
    buffer: []rectf,
){
    packer.buffer = buffer
    packer.length = 0
    atlas_size: = cast(i32)len(packer.rc_nodes)
    stbrp.init_target(&packer.ctx, atlas_size, atlas_size, raw_data(packer.rc_nodes[:]), atlas_size)
}


GetRects :: proc(packer: ^AtlasPacker, count: int)->[]rectf {
    assert(packer.length + count <= len(packer.buffer))
    result: []rectf = packer.buffer[packer.length:min(packer.length+count, len(packer.buffer))]
    packer.length += count
    return result
}

Pack :: proc(packer: ^AtlasPacker)->(ok:bool) {
    // Prepare rectangle list for packing
    pack_rects:[dynamic]stb_Rect = make_dynamic_array_len([dynamic]stb_Rect, packer.length)
    defer delete(pack_rects)

    for i:int = 0; i < packer.length; i += 1 {
        rect:rectf = packer.buffer[i]
        append(&pack_rects, stb_Rect {
            id = cast(i32)i,
            w = stbrp.Coord(rect.z),
            h = stbrp.Coord(rect.w),
        })
    }

    // Packing
    rect_pack_res := stbrp.pack_rects(packer.ctx, raw_data(pack_rects), i32(len(pack_rects)))
    if rect_pack_res != 1 {
        fmt.printf("Failed packing \n")
        return false
    }

    // Read packed positions
    for i:int = 0; i < len(pack_rects); i += 1 {
        rect:^stb_Rect = &pack_rects[i]
        id:i32 = rect.id
        tex_pos:[2]f32 = {cast(f32)rect.x, cast(f32)rect.y}
        packer.buffer[id].xy = tex_pos
    }
    return true
}