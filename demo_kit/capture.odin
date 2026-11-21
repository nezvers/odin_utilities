#+build !js
package demo_kit

// Screen capture tests. A script step `Capture("name")` takes the pixels of the frame that was just drawn and compares them with a
// golden image that sits next to the script file: `<folder of the script>/captures/<backend>/<name>.png`.
//
//     kit.Wait(3),
//     kit.Click({80, 64}),
//     kit.Wait(2),
//     kit.Capture("widgets_clicked"),
//
// - The first run (no golden yet) writes the golden image and says so. Look at it, commit it.
// - Later runs compare: a pixel differs when a channel is off by more than CAPTURE_TOLERANCE, the test fails when more than
//   CAPTURE_MAX_BAD (a part, 0.002 = 0.2 percent) of the pixels differ. The frame is saved as `<name>.actual.png` next to the golden.
// - `-define:DEMO_CAPTURE_UPDATE=true` replaces the golden images with what is drawn now.
// - Capturing is on only with `-define:DEMO_CAPTURE=true` (a window is needed: `odin run <lib>/demo_raylib -define:DEMO_TEST=true
//   -define:DEMO_CAPTURE=true`). Without it, and on the headless backend, a Capture step is skipped, so `odin test` is not affected.
// - One folder per backend: raylib and Karl2D draw text differently, their images are not meant to match.
//
// A frame is deterministic when the script is: the runner of a test uses a fixed time step of 1/60.

import "core:fmt"
import "core:hash"
import "core:image/png"
import "core:os"
import "core:path/filepath"

DEMO_CAPTURE :: #config(DEMO_CAPTURE, false)
DEMO_CAPTURE_UPDATE :: #config(DEMO_CAPTURE_UPDATE, false)
CAPTURE_TOLERANCE :: #config(DEMO_CAPTURE_TOLERANCE, 8)
CAPTURE_MAX_BAD :: f32(0.002)

// What came of one capture
CaptureResult :: enum u8 {
    SKIPPED,        // no backend support, or capturing is off
    WRITTEN,        // there was no golden image: this frame is it now
    MATCH,
    DIFFERENT,
    SIZE_CHANGED,   // the golden image has another size than the screen
    ERROR,          // a file could not be read or written
}

// The pixels of the frame that was just drawn (RGBA, 8 bits each, from the top left). Call it in a demo after drawing, before the frame ends.
// Memory comes from `allocator`. Not available on every backend: `ok` is false then.
CaptureFrame :: proc(ctx: ^Context, allocator := context.allocator) -> (rgba: []u8, width: int, height: int, ok: bool) {
    if ctx.backend.capture == nil { return nil, 0, 0, false }
    rgba, width, height = ctx.backend.capture(ctx.backend, allocator)
    return rgba, width, height, rgba != nil && width > 0 && height > 0
}

// How many pixels of two images of the same size differ by more than `tolerance` in a channel, and the biggest difference of a channel
ImageDifference :: proc(a: []u8, b: []u8, tolerance: int = CAPTURE_TOLERANCE) -> (pixels: int, biggest: int) {
    assert(len(a) == len(b))
    for i := 0; i + 3 < len(a); i += 4 {
        worst: int = 0
        for channel in 0 ..< 4 {
            worst = max(worst, abs(int(a[i + channel]) - int(b[i + channel])))
        }
        biggest = max(biggest, worst)
        if worst > tolerance { pixels += 1 }
    }
    return
}

// The golden image of a capture step: next to the file of the script, in a folder per backend
CapturePath :: proc(script_file: string, backend_name: string, name: string, suffix: string = "", allocator := context.temp_allocator) -> string {
    folder: string = filepath.dir(script_file)
    return fmt.aprintf("%s/captures/%s/%s%s.png", folder, backend_name, name, suffix, allocator = allocator)
}

// Keeps the pixels inside of the frames and clears the rest (RGBA 0): the picture a masked capture stores and compares. Frames are cut to the picture.
CaptureMask :: proc(rgba: []u8, width: int, height: int, frames: []Rect, allocator := context.temp_allocator) -> []u8 {
    masked: []u8 = make([]u8, len(rgba), allocator)
    for frame in frames {
        x0: int = clamp(int(frame.x), 0, width)
        y0: int = clamp(int(frame.y), 0, height)
        x1: int = clamp(int(frame.x + frame.z + 0.999), 0, width)
        y1: int = clamp(int(frame.y + frame.w + 0.999), 0, height)
        for y in y0 ..< y1 {
            copy(masked[(y * width + x0) * 4:(y * width + x1) * 4], rgba[(y * width + x0) * 4:(y * width + x1) * 4])
        }
    }
    return masked
}

// Takes the frame and compares it with the golden image (or writes it). Used by the runner, a demo may call it too. With `frames` only the pixels inside of them count: the picture is masked
// first, and not one pixel of them may differ by more than the tolerance (a frame is a small region: the part of bad pixels that a whole picture may have would hide a corner).
CaptureCompare :: proc(ctx: ^Context, script_file: string, name: string, frames: []Rect = nil) -> (result: CaptureResult, message: string) {
    when !DEMO_CAPTURE {
        return .SKIPPED, ""
    }
    full, width, height, ok := CaptureFrame(ctx, context.temp_allocator)
    if !ok { return .SKIPPED, "" }
    rgba: []u8 = CaptureMask(full, width, height, frames) if len(frames) > 0 else full
    golden_path: string = CapturePath(script_file, ctx.backend.name, name)
    exists: bool = os.exists(golden_path)
    if !exists || DEMO_CAPTURE_UPDATE {
        if !PngWrite(golden_path, width, height, rgba) {
            return .ERROR, fmt.aprintf("capture %s: could not write %s", name, golden_path)
        }
        fmt.printfln("[DEMO TEST] capture %s: wrote %s", name, golden_path)
        return .WRITTEN, ""
    }
    golden, golden_width, golden_height, golden_ok := PngRead(golden_path, context.temp_allocator)
    if !golden_ok {
        return .ERROR, fmt.aprintf("capture %s: could not read %s", name, golden_path)
    }
    if golden_width != width || golden_height != height {
        PngWrite(CapturePath(script_file, ctx.backend.name, name, ".actual"), width, height, rgba)
        return .SIZE_CHANGED, fmt.aprintf("capture %s: the screen is %dx%d, the golden image %dx%d", name, width, height, golden_width, golden_height)
    }
    different, biggest := ImageDifference(rgba, golden)
    if f32(different) > f32(width * height) * CAPTURE_MAX_BAD || (len(frames) > 0 && different > 0) {
        actual_path: string = CapturePath(script_file, ctx.backend.name, name, ".actual")
        PngWrite(actual_path, width, height, full)
        return .DIFFERENT, fmt.aprintf("capture %s: %d of %d pixels differ (up to %d in a channel), see %s", name, different, width * height, biggest, actual_path)
    }
    return .MATCH, ""
}

// ------------------------------------------------------------------------------------------------------------------------
// PNG files. The writer compresses with the one trick that matters for a picture of a ui, a pixel that repeats the one before it (flat areas
// become a few bytes): fixed Huffman codes, no other matches. The reader is core:image/png.

PngWrite :: proc(path: string, width: int, height: int, rgba: []u8) -> bool {
    assert(len(rgba) >= width * height * 4)
    filepath_dir: string = filepath.dir(path)
    if filepath_dir != "" && filepath_dir != "." { os.make_directory_all(filepath_dir) }

    // every row starts with a filter byte (0: none)
    row_bytes: int = width * 4
    raw: []u8 = make([]u8, (row_bytes + 1) * height, context.temp_allocator)
    for y in 0 ..< height {
        copy(raw[y * (row_bytes + 1) + 1:], rgba[y * row_bytes:(y + 1) * row_bytes])
    }
    zlib: [dynamic]u8
    zlib.allocator = context.temp_allocator
    append(&zlib, 0x78, 0x01)
    deflateRepeats(&zlib, raw)
    adler: u32 = hash.adler32(raw)
    append(&zlib, u8(adler >> 24), u8(adler >> 16), u8(adler >> 8), u8(adler))

    file: [dynamic]u8
    file.allocator = context.temp_allocator
    append(&file, 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A)
    header: [13]u8 = {
        u8(width >> 24), u8(width >> 16), u8(width >> 8), u8(width),
        u8(height >> 24), u8(height >> 16), u8(height >> 8), u8(height),
        8, 6, 0, 0, 0,          // 8 bits, color type 6 (RGBA), deflate, no filter method, no interlace
    }
    pngChunk(&file, "IHDR", header[:])
    pngChunk(&file, "IDAT", zlib[:])
    pngChunk(&file, "IEND", nil)
    return os.write_entire_file(path, file[:]) == nil
}

@(private)
pngChunk :: proc(file: ^[dynamic]u8, kind: string, data: []u8) {
    length: int = len(data)
    append(file, u8(length >> 24), u8(length >> 16), u8(length >> 8), u8(length))
    start: int = len(file)
    append(file, ..transmute([]u8)kind)
    append(file, ..data)
    crc: u32 = hash.crc32(file[start:])
    append(file, u8(crc >> 24), u8(crc >> 16), u8(crc >> 8), u8(crc))
}

// A png as RGBA 8 bits. Memory comes from `allocator`.
PngRead :: proc(path: string, allocator := context.allocator) -> (rgba: []u8, width: int, height: int, ok: bool) {
    data, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil { return nil, 0, 0, false }
    img, load_err := png.load_from_bytes(data, {.alpha_add_if_missing}, context.temp_allocator)
    if load_err != nil || img == nil || img.depth != 8 || img.channels != 4 { return nil, 0, 0, false }
    rgba = make([]u8, img.width * img.height * 4, allocator)
    copy(rgba, img.pixels[:img.width * img.height * 4])
    return rgba, img.width, img.height, true
}

@(private)
BitWriter :: struct {
    out: ^[dynamic]u8,
    bits: u32,
    count: u32,
}

// Bits go in from the lowest of a byte; a Huffman code goes in from its highest bit
@(private)
bitsPut :: proc(writer: ^BitWriter, value: u32, count: u32) {
    for i in 0 ..< count {
        writer.bits |= ((value >> i) & 1) << writer.count
        writer.count += 1
        if writer.count == 8 {
            append(writer.out, u8(writer.bits))
            writer.bits = 0
            writer.count = 0
        }
    }
}

@(private)
huffmanPut :: proc(writer: ^BitWriter, code: u32, length: u32) {
    for i := i32(length) - 1; i >= 0; i -= 1 {
        bitsPut(writer, (code >> u32(i)) & 1, 1)
    }
}

// The fixed Huffman code of a literal or a length symbol (0..287)
@(private)
symbolPut :: proc(writer: ^BitWriter, symbol: u32) {
    switch {
    case symbol < 144: huffmanPut(writer, 0x30 + symbol, 8)
    case symbol < 256: huffmanPut(writer, 0x190 + symbol - 144, 9)
    case symbol < 280: huffmanPut(writer, symbol - 256, 7)
    case: huffmanPut(writer, 0xC0 + symbol - 280, 8)
    }
}

@(private)
LENGTH_BASE := [29]int{3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258}
@(private)
LENGTH_EXTRA := [29]u32{0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0}

// One deflate block of fixed Huffman codes: literals, and a match of the 4 bytes before (the pixel to the left) for a run of equal bytes
@(private)
deflateRepeats :: proc(out: ^[dynamic]u8, raw: []u8) {
    writer: BitWriter = {out = out}
    bitsPut(&writer, 1, 1)          // the last block
    bitsPut(&writer, 1, 2)          // fixed Huffman codes
    i: int = 0
    for i < len(raw) {
        run: int = 0
        if i >= 4 {
            for i + run < len(raw) && run < 258 && raw[i + run] == raw[i + run - 4] { run += 1 }
        }
        if run >= 3 {
            index: int = 28
            for index > 0 && LENGTH_BASE[index] > run { index -= 1 }
            symbolPut(&writer, u32(257 + index))
            bitsPut(&writer, u32(run - LENGTH_BASE[index]), LENGTH_EXTRA[index])
            huffmanPut(&writer, 3, 5)           // distance code 3: 4 bytes back
            i += run
        } else {
            symbolPut(&writer, u32(raw[i]))
            i += 1
        }
    }
    symbolPut(&writer, 256)
    if writer.count > 0 { append(out, u8(writer.bits)) }
}
