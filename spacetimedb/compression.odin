package spacetimedb

// Gzip frames. The server compresses a frame only when the client asked (`compression=Gzip` in the URL, which the connection does when `ConnectionConfig.inflate` has memory) and only when it is big, so
// most frames still arrive with the byte 0. Brotli is not in the Odin core: it is never asked for.

import "core:compress/deflate"
import "core:mem"

// Inflates a frame whose compression byte is gzip into the memory of `arena` (made with `mem.arena_init` over the caller's buffer, `free_all(mem.arena_allocator(arena))` before every frame): the result
// lives until the arena is cleared. `ok` is false when the frame is not gzip, the data are damaged (the CRC is checked) or the arena is too small for the message: give it room for the biggest one.
ServerFrameInflate :: proc(frame: []u8, arena: ^mem.Arena) -> (body: []u8, ok: bool) {
    if len(frame) < 1 + 4 || frame[0] != COMPRESSION_GZIP { return nil, false }
    data: []u8 = frame[1:]
    // the last four bytes of a gzip member are the size of what it holds: it lets the output be made once. It is only a hint from the network: the arena bounds it.
    size: int = int(u32(data[len(data) - 4]) | u32(data[len(data) - 3]) << 8 | u32(data[len(data) - 2]) << 16 | u32(data[len(data) - 1]) << 24)
    if size > len(arena.data) { return nil, false }
    allocator: mem.Allocator = mem.arena_allocator(arena)
    output: [dynamic]u8
    output.allocator = allocator
    if deflate.decompress_gzip_from_bytes(&output, data, size, allocator = allocator) != nil { return nil, false }
    return output[:], true
}
