#+build !js
// Tests of serial.odin. They are in their own file because serial builds for js_wasm32, where core:testing does not compile.
package serial

import "core:hash"
import "core:math"
import "core:testing"

@(private="file")
TAG_A :: Tag(u32('A') | u32('A') << 8 | u32('A') << 16 | u32('A') << 24)
@(private="file")
TAG_B :: Tag(u32('B') | u32('B') << 8 | u32('B') << 16 | u32('B') << 24)

@(test)
test_make_tag_spells_four_letters :: proc(t: ^testing.T) {
    testing.expect_value(t, MakeTag('T', 'M', 'A', 'P'), Tag(u32('T') | u32('M') << 8 | u32('A') << 16 | u32('P') << 24))
    testing.expect_value(t, MakeTag('A', 'A', 'A', 'A'), TAG_A)
}

@(test)
test_values_round_trip_exactly :: proc(t: ^testing.T) {
    buffer: [256]byte
    writer: Writer
    WriterInit(&writer, buffer[:])
    WriteU8(&writer, 0xAB)
    WriteBool(&writer, true)
    WriteBool(&writer, false)
    WriteU16(&writer, 0xBEEF)
    WriteU32(&writer, 0xDEADBEEF)
    WriteU64(&writer, 0x0123456789ABCDEF)
    WriteI32(&writer, -123456)
    WriteF32(&writer, -0.0)
    WriteF32(&writer, math.INF_F32)
    WriteF32(&writer, 3.14159)
    WriteString(&writer, "")
    WriteString(&writer, "Sveiki, pasaule! Ā ē ž")
    WriteBytes(&writer, {1, 2, 3})
    testing.expect(t, WriterOk(&writer))

    reader: Reader
    ReaderInit(&reader, WriterBytes(&writer))
    testing.expect_value(t, ReadU8(&reader), u8(0xAB))
    testing.expect_value(t, ReadBool(&reader), true)
    testing.expect_value(t, ReadBool(&reader), false)
    testing.expect_value(t, ReadU16(&reader), u16(0xBEEF))
    testing.expect_value(t, ReadU32(&reader), u32(0xDEADBEEF))
    testing.expect_value(t, ReadU64(&reader), u64(0x0123456789ABCDEF))
    testing.expect_value(t, ReadI32(&reader), i32(-123456))
    negative_zero: f32 = ReadF32(&reader)
    testing.expect(t, negative_zero == 0 && math.sign(negative_zero) < 0 || transmute(u32)negative_zero == 0x80000000, "negative zero keeps its sign")
    testing.expect_value(t, ReadF32(&reader), math.INF_F32)
    testing.expect_value(t, ReadF32(&reader), f32(3.14159))
    testing.expect_value(t, ReadString(&reader), "")
    testing.expect_value(t, ReadString(&reader), "Sveiki, pasaule! Ā ē ž")
    testing.expect_value(t, len(ReadBytes(&reader, 3)), 3)
    testing.expect(t, ReaderOk(&reader) && ReaderRemaining(&reader) == 0)
}

@(test)
test_bytes_are_little_endian_on_any_machine :: proc(t: ^testing.T) {
    buffer: [8]byte
    writer: Writer
    WriterInit(&writer, buffer[:])
    WriteU32(&writer, 0x01020304)
    WriteU16(&writer, 0x0A0B)
    testing.expect_value(t, buffer[0], u8(4))
    testing.expect_value(t, buffer[3], u8(1))
    testing.expect_value(t, buffer[4], u8(0x0B))
    testing.expect_value(t, buffer[5], u8(0x0A))
}

@(test)
test_counting_pass_gives_the_size_and_a_small_buffer_fails_cleanly :: proc(t: ^testing.T) {
    write_all :: proc(writer: ^Writer) {
        FileBegin(writer)
        ChunkBegin(writer, TAG_A, 1)
        WriteString(writer, "hello")
        WriteU64(writer, 7)
        ChunkEnd(writer)
        FileEnd(writer)
    }

    counting: Writer
    WriterInitCounting(&counting)
    write_all(&counting)
    needed: int = WriterNeeded(&counting)
    testing.expect_value(t, needed, FILE_HEADER_SIZE + CHUNK_HEADER_SIZE + 2 + 5 + 8)
    testing.expect(t, WriterBytes(&counting) == nil, "a counting writer has no bytes")

    exact: [64]byte
    writer: Writer
    WriterInit(&writer, exact[:needed])
    write_all(&writer)
    testing.expect(t, WriterOk(&writer))
    testing.expect_value(t, WriterNeeded(&writer), needed)

    small: Writer
    WriterInit(&small, exact[:needed - 1])
    write_all(&small)
    testing.expect(t, !WriterOk(&small), "one byte too few")
    testing.expect_value(t, WriterNeeded(&small), needed)                            // it still says what it needed
    testing.expect(t, WriterBytes(&small) == nil)
}

@(test)
test_writer_refuses_misuse :: proc(t: ^testing.T) {
    buffer: [64]byte
    writer: Writer
    WriterInit(&writer, buffer[:])
    ChunkEnd(&writer)                                                                // nothing to end
    testing.expect(t, !WriterOk(&writer))

    WriterInit(&writer, buffer[:])
    ChunkBegin(&writer, TAG_A, 1)                                                    // never ended
    testing.expect(t, !WriterOk(&writer), "an open chunk is not a finished file")

    WriterInit(&writer, buffer[:])
    for _ in 0 ..< MAX_CHUNK_DEPTH + 1 { ChunkBegin(&writer, TAG_A, 1) }
    testing.expect(t, !WriterOk(&writer), "nested too deep")

    long: [70000]byte
    WriterInit(&writer, buffer[:])
    WriteString(&writer, string(long[:]))
    testing.expect(t, !WriterOk(&writer), "a string longer than its length field")
}

@(private="file")
build_file :: proc(buffer: []byte) -> []byte {
    writer: Writer
    WriterInit(&writer, buffer)
    FileBegin(&writer, 0x0102)
    ChunkBegin(&writer, TAG_A, 3)
    WriteU32(&writer, 11)
    ChunkBegin(&writer, TAG_B, 9)                                                    // nested
    WriteString(&writer, "inner")
    ChunkEnd(&writer)
    WriteU32(&writer, 22)
    ChunkEnd(&writer)
    ChunkBegin(&writer, TAG_B, 1)
    WriteU8(&writer, 5)
    ChunkEnd(&writer)
    return FileEnd(&writer)
}

@(test)
test_chunks_nest_have_versions_and_are_found_by_tag :: proc(t: ^testing.T) {
    buffer: [256]byte
    file: []byte = build_file(buffer[:])
    reader, flags, ok := FileOpen(file)
    testing.expect(t, ok)
    testing.expect_value(t, flags, u16(0x0102))

    tag, version, payload, next_ok := ChunkNext(&reader)
    testing.expect(t, next_ok)
    testing.expect_value(t, tag, TAG_A)
    testing.expect_value(t, version, u16(3))
    testing.expect_value(t, ReadU32(&payload), u32(11))
    inner_tag, inner_version, inner, inner_ok := ChunkNext(&payload)
    testing.expect(t, inner_ok && inner_tag == TAG_B && inner_version == 9)
    testing.expect_value(t, ReadString(&inner), "inner")
    testing.expect_value(t, ReadU32(&payload), u32(22))
    testing.expect(t, ReaderOk(&payload))

    second_tag, _, second, second_ok := ChunkNext(&reader)
    testing.expect(t, second_ok && second_tag == TAG_B)
    testing.expect_value(t, ReadU8(&second), u8(5))
    _, _, _, third_ok := ChunkNext(&reader)
    testing.expect(t, !third_ok, "that was the last one")

    // by tag, from the start, the reader is not moved
    fresh, _, _ := FileOpen(file)
    found_version, found, found_ok := ChunkFind(fresh, TAG_B)
    testing.expect(t, found_ok && found_version == 1, "the first chunk with this tag at the top level")
    testing.expect_value(t, ReadU8(&found), u8(5))
    testing.expect_value(t, ChunkCount(fresh, TAG_A), 1)
    testing.expect_value(t, ChunkCount(fresh, TAG_B), 1)
    _, _, missing := ChunkFind(fresh, MakeTag('N', 'O', 'P', 'E'))
    testing.expect(t, !missing)
}

@(test)
test_a_chunk_reader_cannot_read_into_the_next_chunk :: proc(t: ^testing.T) {
    buffer: [256]byte
    file: []byte = build_file(buffer[:])
    reader, _, _ := FileOpen(file)
    _, _, payload, _ := ChunkNext(&reader)
    for _ in 0 ..< 40 { ReadU32(&payload) }                                          // more than the chunk holds
    testing.expect(t, !ReaderOk(&payload), "the payload reader stops at the end of its chunk")
    testing.expect_value(t, ReadU32(&payload), u32(0))                               // zeros after a failure
    testing.expect(t, ReaderOk(&reader), "and the file reader is not affected")
}

@(test)
test_unknown_chunks_are_skipped_and_newer_versions_are_readable :: proc(t: ^testing.T) {
    // an older program: it only knows TAG_B and ignores TAG_A, even though TAG_A is a newer kind of data
    buffer: [256]byte
    file: []byte = build_file(buffer[:])
    reader, _, _ := FileOpen(file)
    seen: int
    for {
        tag, version, chunk, ok := ChunkNext(&reader)
        if !ok { break }
        if tag != TAG_B { continue }
        seen += 1
        testing.expect(t, version >= 1)
        ReadU8(&chunk)
        testing.expect(t, ReaderOk(&chunk), "the part it knows is readable, extra bytes after it would be ignored")
    }
    testing.expect_value(t, seen, 1)
}

@(test)
test_every_changed_byte_and_every_truncation_is_refused :: proc(t: ^testing.T) {
    buffer: [256]byte
    file: []byte = build_file(buffer[:])
    _, _, valid := FileOpen(file)
    testing.expect(t, valid)

    copy_buffer: [256]byte
    for i in FILE_HEADER_SIZE ..< len(file) {                                        // the checksum covers everything after the header
        copy(copy_buffer[:], file)
        copy_buffer[i] ~= 0x01
        _, _, ok := FileOpen(copy_buffer[:len(file)])
        testing.expectf(t, !ok, "byte %d changed", i)
    }
    for i in 0 ..< FILE_HEADER_SIZE {                                                // the header fields are checked one by one
        copy(copy_buffer[:], file)
        copy_buffer[i] ~= 0x80
        _, _, ok := FileOpen(copy_buffer[:len(file)])
        testing.expectf(t, !ok || i == 6 || i == 7, "header byte %d changed", i)    // the flags are free for the user
    }
    for length in 0 ..< len(file) {
        _, _, ok := FileOpen(file[:length])
        testing.expectf(t, !ok, "cut to %d bytes", length)
    }
    copy(copy_buffer[:], file)
    _, _, longer := FileOpen(copy_buffer[:len(file) + 1])
    testing.expect(t, !longer, "extra bytes at the end")
}

@(test)
test_a_newer_format_and_another_kind_of_file_are_refused :: proc(t: ^testing.T) {
    buffer: [256]byte
    file: []byte = build_file(buffer[:])
    newer: [256]byte
    copy(newer[:], file)
    newer[4] = u8(FORMAT_VERSION + 1)                                                // the version is in the header, not in the checksum
    _, _, newer_ok := FileOpen(newer[:len(file)])
    testing.expect(t, !newer_ok, "this program does not know that format")

    text: string = "this is not a level file at all, just text"
    _, _, text_ok := FileOpen(transmute([]byte)text)
    testing.expect(t, !text_ok)
    _, _, empty_ok := FileOpen(nil)
    testing.expect(t, !empty_ok)
}

@(test)
test_chunk_that_claims_more_than_the_file_holds_is_refused :: proc(t: ^testing.T) {
    buffer: [64]byte
    writer: Writer
    WriterInit(&writer, buffer[:])
    FileBegin(&writer)
    WriteU32(&writer, u32(TAG_A))
    WriteU16(&writer, 1)
    WriteU16(&writer, 0)
    WriteU32(&writer, 1_000_000)                                                     // a length far past the end
    file: []byte = FileEnd(&writer)                                                  // a valid frame around an invalid chunk
    reader, _, ok := FileOpen(file)
    testing.expect(t, ok)
    _, _, _, chunk_ok := ChunkNext(&reader)
    testing.expect(t, !chunk_ok)
    testing.expect(t, !ReaderOk(&reader))
}

@(test)
test_counts_are_checked_before_anything_is_sized_from_them :: proc(t: ^testing.T) {
    buffer: [32]byte
    writer: Writer
    WriterInit(&writer, buffer[:])
    WriteU32(&writer, 4_000_000_000)
    reader: Reader
    ReaderInit(&reader, WriterBytes(&writer))
    testing.expect_value(t, ReadCount(&reader, 1000), 0)
    testing.expect(t, !ReaderOk(&reader), "over the limit")

    WriterInit(&writer, buffer[:])
    WriteU32(&writer, 100)                                                           // under the limit, but the data cannot hold 100 items
    ReaderInit(&reader, WriterBytes(&writer))
    testing.expect_value(t, ReadCount(&reader, 1000, 8), 0)
    testing.expect(t, !ReaderOk(&reader), "not enough data left for that many items")

    WriterInit(&writer, buffer[:])
    WriteU32(&writer, 3)
    WriteBytes(&writer, {1, 2, 3})
    ReaderInit(&reader, WriterBytes(&writer))
    testing.expect_value(t, ReadCount(&reader, 10), 3)
    testing.expect(t, ReaderOk(&reader))
}

@(test)
test_rle_round_trips_and_handles_long_runs :: proc(t: ^testing.T) {
    cases: [5][]byte
    long := make([]byte, 70_000, context.temp_allocator)                             // more than one run can hold
    alternating := make([]byte, 300, context.temp_allocator)
    for &value, i in alternating { value = u8(i % 2) }
    mixed := make([]byte, 1000, context.temp_allocator)
    for &value, i in mixed { value = u8((i / 37) % 5) }
    cases = {nil, {7}, long, alternating, mixed}

    for source, index in cases {
        buffer := make([]byte, len(source) * 3 + 16, context.temp_allocator)
        writer: Writer
        WriterInit(&writer, buffer)
        RleWrite(&writer, source)
        testing.expect(t, WriterOk(&writer))

        reader: Reader
        ReaderInit(&reader, WriterBytes(&writer))
        testing.expect_value(t, RlePeekLength(reader), len(source))
        decoded := make([]byte, len(source), context.temp_allocator)
        testing.expectf(t, RleRead(&reader, decoded), "case %d", index)
        for value, i in decoded {
            if value != source[i] {
                testing.expectf(t, false, "case %d differs at %d", index, i)
                break
            }
        }
    }

    // long runs of one value are small
    buffer: [64]byte
    writer: Writer
    WriterInit(&writer, buffer[:])
    RleWrite(&writer, long[:65535])
    testing.expect_value(t, WriterNeeded(&writer), 4 + 3)
}

@(test)
test_rle_refuses_bad_data :: proc(t: ^testing.T) {
    destination: [10]byte
    reader: Reader

    bad_cases := [][]byte{
        {10, 0, 0, 0, 5, 0, 0},                       // a run of 0
        {10, 0, 0, 0, 5, 20, 0},                      // a run past the end
        {10, 0, 0, 0, 5, 4, 0},                       // ends early: the data stops
        {9, 0, 0, 0, 5, 9, 0},                        // another total than the destination
        {10, 0, 0, 0},                                // no runs at all
    }
    for bad, i in bad_cases {
        ReaderInit(&reader, bad)
        testing.expectf(t, !RleRead(&reader, destination[:]), "bad case %d", i)
        testing.expectf(t, !ReaderOk(&reader), "bad case %d marks the reader", i)
    }
}

@(private="file")
xorshift :: proc(state: ^u32) -> u32 {
    state^ ~= state^ << 13
    state^ ~= state^ >> 17
    state^ ~= state^ << 5
    return state^
}

// Everything a reader of this format does with a file, with all limits: it may fail, it must never crash
@(private="file")
parse_everything :: proc(data: []byte) {
    reader, _, ok := FileOpen(data)
    if !ok { return }
    for {
        tag, _, payload, next_ok := ChunkNext(&reader)
        if !next_ok { break }
        _ = tag
        count: int = ReadCount(&payload, 64, 4)
        for _ in 0 ..< count { ReadF32(&payload) }
        text: string = ReadString(&payload)
        _ = text
        ReadBytes(&payload, int(ReadU16(&payload)))
        scratch: [64]byte
        RleRead(&payload, scratch[:])
        for {
            _, _, inner, inner_ok := ChunkNext(&payload)
            if !inner_ok { break }
            _ = inner
        }
    }
}

@(test)
test_garbage_never_crashes_the_reader :: proc(t: ^testing.T) {
    state: u32 = 2463534242

    // random bytes of random length
    for _ in 0 ..< 3000 {
        length: int = int(xorshift(&state) % 200)
        garbage: [200]byte
        for i in 0 ..< length { garbage[i] = u8(xorshift(&state)) }
        parse_everything(garbage[:length])
    }

    // a valid frame (the checksum is right) around random chunk data, so the parsing behind it is exercised
    for _ in 0 ..< 3000 {
        buffer: [256]byte
        writer: Writer
        WriterInit(&writer, buffer[:])
        FileBegin(&writer)
        length: int = int(xorshift(&state) % 150)
        for _ in 0 ..< length { WriteU8(&writer, u8(xorshift(&state))) }
        file: []byte = FileEnd(&writer)
        parse_everything(file)
    }

    // a valid file with a few changed bytes and a fixed checksum
    valid_buffer: [256]byte
    valid: []byte = build_file(valid_buffer[:])
    for _ in 0 ..< 3000 {
        mutated: [256]byte
        copy(mutated[:], valid)
        for _ in 0 ..< 1 + int(xorshift(&state) % 4) {
            mutated[FILE_HEADER_SIZE + int(xorshift(&state)) % (len(valid) - FILE_HEADER_SIZE)] = u8(xorshift(&state))
        }
        crc: u32 = hash.crc32(mutated[FILE_HEADER_SIZE:len(valid)])
        for i in 0 ..< 4 { mutated[12 + i] = u8(crc >> u32(8 * i)) }
        parse_everything(mutated[:len(valid)])
    }
    testing.expect(t, true, "reached the end without a crash")
}
