// Runtime rectangle packing for baking sprites, tiles and fonts into one texture.
// All memory comes from the allocator given to Init, so an arena (core:mem Arena over a pre-allocated buffer)
// per scene works well: pack, bake, then free everything at once.
package atlas_packer

import "core:fmt"
import stbrp "vendor:stb/rect_pack"
import "core:testing"
stb_Rect:: stbrp.Rect

rectf :: [4]f32
vec2i :: [2]int

AtlasPacker :: struct {
    ctx: stbrp.Context,
    buffer: []rectf,            // accumulate rects to pack
    stb_buffer: []stb_Rect,     // used for actual packing
    nodes: []stbrp.Node,        // as many nodes as atlas width
    length: int,                // used buffer
    atlas_size: i32,            // width == height
}

// Allocates buffers from `allocator`, nothing is freed by the packer. Use an arena or delete slices yourself.
// rect_capacity - how many rectangles can be requested through GetRects
Init :: proc(
    packer: ^AtlasPacker,
    atlas_size: i32,
    rect_capacity: int,
    allocator := context.allocator,
)->(ok:bool) {
    assert(atlas_size > 0)
    assert(rect_capacity > 0)

    packer^ = {}
    buffer, buffer_err: = make([]rectf, rect_capacity, allocator)
    stb_buffer, stb_err: = make([]stb_Rect, rect_capacity, allocator)
    nodes, nodes_err: = make([]stbrp.Node, atlas_size, allocator)
    if buffer_err != nil || stb_err != nil || nodes_err != nil {
        return false
    }

    packer.buffer = buffer
    packer.stb_buffer = stb_buffer
    packer.nodes = nodes
    packer.atlas_size = atlas_size
    Reset(packer)
    return true
}

// Forget all rectangles and start packing from scratch in the same memory
Reset :: proc(packer: ^AtlasPacker) {
    packer.length = 0
    stbrp.init_target(&packer.ctx, packer.atlas_size, packer.atlas_size, raw_data(packer.nodes), cast(i32)len(packer.nodes))
}

// Returns slice of `count` rectangles to fill with sizes (zw). After Pack the slice holds positions (xy)
GetRects :: proc(packer: ^AtlasPacker, count: int)->(result:[]rectf, ok:bool) {
    if packer.length + count > len(packer.buffer) {
        // TODO: maybe support partial return. Or have itteratable function one by one
        return
    }
    result = packer.buffer[packer.length:packer.length+count]
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

Pack :: proc(packer: ^AtlasPacker)->(ok:bool) {
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

// --- Tests ---

@(test)
test_packed_rects_stay_inside_and_never_overlap :: proc(t: ^testing.T) {
    packer: AtlasPacker
    testing.expect(t, Init(&packer, 64, 16))
    defer { delete(packer.buffer); delete(packer.stb_buffer); delete(packer.nodes) }

    wanted: [10]rectf
    for &rect, i in wanted { rect.zw = {f32(8 + i * 2), f32(6 + (i * 5) % 11)} }
    rects, ok := GetRects(&packer, len(wanted))
    testing.expect(t, ok)
    CopySizes(wanted[:], rects)
    testing.expect_value(t, rects[3].zw, wanted[3].zw)                                     // CopySizes only touches the size
    testing.expect(t, Pack(&packer))

    for a, i in rects {
        testing.expect(t, a.x >= 0 && a.y >= 0 && a.x + a.z <= 64 && a.y + a.w <= 64, "inside the atlas")
        for b, j in rects {
            if i >= j { continue }
            apart: bool = a.x + a.z <= b.x || b.x + b.z <= a.x || a.y + a.w <= b.y || b.y + b.w <= a.y
            testing.expect(t, apart, "no two rectangles share pixels")
        }
    }
}

@(test)
test_get_rects_runs_out_of_capacity :: proc(t: ^testing.T) {
    packer: AtlasPacker
    testing.expect(t, Init(&packer, 32, 4))
    defer { delete(packer.buffer); delete(packer.stb_buffer); delete(packer.nodes) }

    first, first_ok := GetRects(&packer, 3)
    testing.expect(t, first_ok)
    testing.expect_value(t, len(first), 3)
    _, too_many := GetRects(&packer, 2)
    testing.expect(t, !too_many, "the request does not fit the remaining capacity")
    testing.expect_value(t, packer.length, 3)                                              // a refused request reserves nothing
    _, last_ok := GetRects(&packer, 1)
    testing.expect(t, last_ok)
}
