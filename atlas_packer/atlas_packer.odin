package atlas_packer

import "core:fmt"
import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect

rectf :: [4]f32
vec2i :: [2]int

AtlasPacker :: struct($buffer_size:int , $atlas_size: i32) {
    ctx: stbrp.Context,
    buffer: [buffer_size]rectf,            // accumulate rects to pack
    stb_buffer: [buffer_size]stb_Rect,     // used for actual packing
    nodes: [atlas_size]stbrp.Node,    // will determine power of 2 atlas size
    length:int,                 // used buffer
}

Init :: proc(
    packer: ^AtlasPacker($B, $A),
){
    packer^ = {}
    atlas_size: = cast(i32)len(packer.nodes)
    stbrp.init_target(&packer.ctx, atlas_size, atlas_size, raw_data(packer.nodes[:]), atlas_size)
}

GetRects :: proc(packer: ^AtlasPacker($B, $A), count: int)->(result:[]rectf, ok:bool) {
    if packer.length + count > len(packer.buffer) - 1 {
        // TODO: maybe support partial return. Or have itteratable function one by one
        return
    }
    result = packer.buffer[packer.length:min(packer.length+count, len(packer.buffer))]
    packer.length += count
    ok = true
    return
}

CopySizes :: proc(original_rects: []rectf, packed_rects: []rectf) {
    assert(len(original_rects) <= len(packed_rects))
    
    for i:int = 0; i < len(original_rects); i += 1 {
        packed_rects[i].zw = original_rects[i].zw
    }
}

Pack :: proc(packer: ^AtlasPacker($B, $A))->(ok:bool) {
    for i:int = 0; i < packer.length; i += 1 {
        rect: ^rectf = &packer.buffer[i]
        packer.stb_buffer[i] = {
            id = cast(i32)i,
            w = stbrp.Coord(rect.z),
            h = stbrp.Coord(rect.w),
        }
    }

    // Packing
    rect_pack_res := stbrp.pack_rects(&packer.ctx, raw_data(packer.stb_buffer[:packer.length]), i32(packer.length))
    if rect_pack_res != 1 {
        fmt.printf("Failed packing \n")
        // TODO: add support for overflowing into multiple textures
        return false
    }

    // Read packed positions
    for i:int = 0; i < packer.length; i += 1 {
        rect:^stb_Rect = &packer.stb_buffer[i]
        // TODO: multi-texture support - check rect.was_packed
        id:i32 = rect.id
        tex_pos:[2]f32 = {cast(f32)rect.x, cast(f32)rect.y}
        packer.buffer[id].xy = tex_pos
    }
    return true
}