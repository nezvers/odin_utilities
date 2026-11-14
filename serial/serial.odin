// Binary files for level editors and saves: a small writer and reader, chunks and a file frame.
//
//   file  = header (magic, format version, flags, size, crc32 of everything after the header) + chunks
//   chunk = tag (4 letters) + version + length + payload
//
// A chunk has its own version and a length, so a reader skips chunks it does not know and a newer file still opens in an older
// program. Every library writes and reads its own chunks (tilemap, box2d, scene levels), one file holds them all.
// Values are little endian whatever the machine is, written field by field (no struct memcpy, no padding, no pointers).
//
// Memory: the writer fills a buffer the user provides (a counting pass tells the size to provide), the reader works on a byte slice
// the user loaded. Strings and byte runs that are read are views into that slice: they live as long as the data does.
//
// Reading untrusted data is safe: every read is bounds checked, a failed read sets a sticky flag and gives zeros, counts are
// checked against limits before anything is sized from them. Check `ReaderOk` when you are done, not after every value.
// This package builds for js_wasm32, the tests are in serial_test.odin.
package serial

import "core:hash"

MAGIC :: u32(0x564C444F)            // "ODLV" in the file
FORMAT_VERSION :: u16(1)
FILE_HEADER_SIZE :: 16
CHUNK_HEADER_SIZE :: 12
MAX_CHUNK_DEPTH :: 4

// Four letters: Tag("TMAP")
Tag :: distinct u32

MakeTag :: proc "contextless" (a: u8, b: u8, c: u8, d: u8) -> Tag {
    return Tag(u32(a) | u32(b) << 8 | u32(c) << 16 | u32(d) << 24)
}

// ============================================================ Writer

Writer :: struct {
    data: []byte,
    offset: int,
    counting: bool,                 // only counts, to learn the size to provide
    failed: bool,                   // the buffer was too small
    chunk_starts: [MAX_CHUNK_DEPTH]int,
    depth: int,
}

// Write into `buffer`. If it is too small the writer fails, `WriterNeeded` still says how much was needed
WriterInit :: proc(writer: ^Writer, buffer: []byte) {
    writer^ = {data = buffer}
}

// Count instead of write: run the same code, then allocate `WriterNeeded` bytes and run it again
WriterInitCounting :: proc(writer: ^Writer) {
    writer^ = {counting = true}
}

WriterOk :: proc(writer: ^Writer) -> bool {
    return !writer.failed && writer.depth == 0
}

// Bytes written so far, or the total that is needed after a counting or failed pass
WriterNeeded :: proc(writer: ^Writer) -> int {
    return writer.offset
}

// What was written
WriterBytes :: proc(writer: ^Writer) -> []byte {
    return writer.data[:writer.offset] if !writer.counting && !writer.failed else nil
}

@(private)
Reserve :: proc(writer: ^Writer, size: int) -> []byte {
    start: int = writer.offset
    writer.offset += size
    if writer.counting { return nil }
    if writer.offset > len(writer.data) {
        writer.failed = true
        return nil
    }
    return writer.data[start:writer.offset]
}

WriteU8 :: proc(writer: ^Writer, value: u8) {
    if slot := Reserve(writer, 1); slot != nil { slot[0] = value }
}

WriteBool :: proc(writer: ^Writer, value: bool) {
    WriteU8(writer, 1 if value else 0)
}

WriteU16 :: proc(writer: ^Writer, value: u16) {
    if slot := Reserve(writer, 2); slot != nil {
        slot[0] = u8(value)
        slot[1] = u8(value >> 8)
    }
}

WriteU32 :: proc(writer: ^Writer, value: u32) {
    if slot := Reserve(writer, 4); slot != nil {
        for i in 0 ..< 4 { slot[i] = u8(value >> u32(8 * i)) }
    }
}

WriteU64 :: proc(writer: ^Writer, value: u64) {
    if slot := Reserve(writer, 8); slot != nil {
        for i in 0 ..< 8 { slot[i] = u8(value >> u32(8 * i)) }
    }
}

WriteI32 :: proc(writer: ^Writer, value: i32) {
    WriteU32(writer, u32(value))
}

WriteF32 :: proc(writer: ^Writer, value: f32) {
    WriteU32(writer, transmute(u32)value)
}

WriteBytes :: proc(writer: ^Writer, bytes: []byte) {
    if slot := Reserve(writer, len(bytes)); slot != nil { copy(slot, bytes) }
}

// u16 length and the bytes. Longer than 65535 fails the writer
WriteString :: proc(writer: ^Writer, text: string) {
    if len(text) > int(max(u16)) {
        writer.failed = true
        return
    }
    WriteU16(writer, u16(len(text)))
    WriteBytes(writer, transmute([]byte)text)
}

// A chunk: everything written until ChunkEnd belongs to it. Chunks nest.
ChunkBegin :: proc(writer: ^Writer, tag: Tag, version: u16) {
    if writer.depth >= MAX_CHUNK_DEPTH {
        writer.failed = true
        return
    }
    writer.chunk_starts[writer.depth] = writer.offset
    writer.depth += 1
    WriteU32(writer, u32(tag))
    WriteU16(writer, version)
    WriteU16(writer, 0)
    WriteU32(writer, 0)                 // the length is filled in by ChunkEnd
}

ChunkEnd :: proc(writer: ^Writer) {
    if writer.depth == 0 {
        writer.failed = true
        return
    }
    writer.depth -= 1
    start: int = writer.chunk_starts[writer.depth]
    if writer.counting || writer.failed { return }
    length: u32 = u32(writer.offset - start - CHUNK_HEADER_SIZE)
    for i in 0 ..< 4 { writer.data[start + 8 + i] = u8(length >> u32(8 * i)) }
}

// The file header. Everything written after it is covered by the checksum
FileBegin :: proc(writer: ^Writer, flags: u16 = 0) {
    WriteU32(writer, MAGIC)
    WriteU16(writer, FORMAT_VERSION)
    WriteU16(writer, flags)
    WriteU32(writer, 0)                 // size, filled in by FileEnd
    WriteU32(writer, 0)                 // checksum, filled in by FileEnd
}

// Fill in the size and the checksum of the file. Returns the bytes of the file, nil if anything failed
FileEnd :: proc(writer: ^Writer) -> []byte {
    if !WriterOk(writer) { return nil }
    if writer.counting { return nil }
    size: u32 = u32(writer.offset)
    crc: u32 = hash.crc32(writer.data[FILE_HEADER_SIZE:writer.offset])
    for i in 0 ..< 4 {
        writer.data[8 + i] = u8(size >> u32(8 * i))
        writer.data[12 + i] = u8(crc >> u32(8 * i))
    }
    return writer.data[:writer.offset]
}

// Run-length encoded bytes: the total length, then runs of (value, count). Good for tile ids, which repeat a lot.
RleWrite :: proc(writer: ^Writer, bytes: []byte) {
    WriteU32(writer, u32(len(bytes)))
    i: int
    for i < len(bytes) {
        run: int = 1
        for i + run < len(bytes) && bytes[i + run] == bytes[i] && run < int(max(u16)) { run += 1 }
        WriteU8(writer, bytes[i])
        WriteU16(writer, u16(run))
        i += run
    }
}

// ============================================================ Reader

Reader :: struct {
    data: []byte,
    offset: int,
    failed: bool,                   // a read went past the end, or a value was not acceptable. Reads give zeros after that
}

ReaderInit :: proc(reader: ^Reader, data: []byte) {
    reader^ = {data = data}
}

ReaderOk :: proc(reader: ^Reader) -> bool {
    return !reader.failed
}

ReaderRemaining :: proc(reader: ^Reader) -> int {
    return len(reader.data) - reader.offset
}

// Mark the data as bad, for a value that is out of range
ReaderFail :: proc(reader: ^Reader) {
    reader.failed = true
}

@(private)
Take :: proc(reader: ^Reader, size: int) -> []byte {
    if reader.failed || size < 0 || size > len(reader.data) - reader.offset {
        reader.failed = true
        return nil
    }
    slice: []byte = reader.data[reader.offset:reader.offset + size]
    reader.offset += size
    return slice
}

ReadU8 :: proc(reader: ^Reader) -> u8 {
    if slice := Take(reader, 1); slice != nil { return slice[0] }
    return 0
}

ReadBool :: proc(reader: ^Reader) -> bool {
    return ReadU8(reader) != 0
}

ReadU16 :: proc(reader: ^Reader) -> u16 {
    if slice := Take(reader, 2); slice != nil { return u16(slice[0]) | u16(slice[1]) << 8 }
    return 0
}

ReadU32 :: proc(reader: ^Reader) -> u32 {
    if slice := Take(reader, 4); slice != nil {
        value: u32
        for i in 0 ..< 4 { value |= u32(slice[i]) << u32(8 * i) }
        return value
    }
    return 0
}

ReadU64 :: proc(reader: ^Reader) -> u64 {
    if slice := Take(reader, 8); slice != nil {
        value: u64
        for i in 0 ..< 8 { value |= u64(slice[i]) << u64(8 * i) }
        return value
    }
    return 0
}

ReadI32 :: proc(reader: ^Reader) -> i32 {
    return i32(ReadU32(reader))
}

ReadF32 :: proc(reader: ^Reader) -> f32 {
    return transmute(f32)ReadU32(reader)
}

// A view into the data, not a copy
ReadBytes :: proc(reader: ^Reader, count: int) -> []byte {
    return Take(reader, count)
}

// A view into the data, not a copy
ReadString :: proc(reader: ^Reader) -> string {
    length: int = int(ReadU16(reader))
    return string(Take(reader, length))
}

// A count that is going to size something: fails the reader when it is more than `limit`, so bad data cannot ask for a lot of
// memory or a long loop. Also fails when the data left cannot hold that many items of `item_size` bytes.
ReadCount :: proc(reader: ^Reader, limit: int, item_size: int = 1) -> int {
    count: int = int(ReadU32(reader))
    if count > limit || count * max(item_size, 1) > ReaderRemaining(reader) {
        reader.failed = true
        return 0
    }
    return count
}

// Decode what RleWrite wrote into `destination`. The length has to be the one that was written, else the reader fails
RleRead :: proc(reader: ^Reader, destination: []byte) -> bool {
    total: int = int(ReadU32(reader))
    if total != len(destination) {
        reader.failed = true
        return false
    }
    filled: int
    for filled < total && !reader.failed {
        value: u8 = ReadU8(reader)
        run: int = int(ReadU16(reader))
        if run == 0 || filled + run > total {
            reader.failed = true
            return false
        }
        for i in 0 ..< run { destination[filled + i] = value }
        filled += run
    }
    return !reader.failed
}

// The length that RleWrite wrote, to size a buffer before reading
RlePeekLength :: proc(reader: Reader) -> int {
    peek: Reader = reader
    return int(ReadU32(&peek))
}

// ============================================================ Files and chunks

// Check the header and the checksum. Returns a reader over the chunks. Fails for a file of another kind, a newer format,
// a size that does not match or any changed byte
FileOpen :: proc(data: []byte) -> (reader: Reader, flags: u16, ok: bool) {
    header: Reader
    ReaderInit(&header, data)
    if ReadU32(&header) != MAGIC { return }
    version: u16 = ReadU16(&header)
    flags = ReadU16(&header)
    size: int = int(ReadU32(&header))
    crc: u32 = ReadU32(&header)
    if header.failed || version > FORMAT_VERSION || size != len(data) || size < FILE_HEADER_SIZE { return }
    if hash.crc32(data[FILE_HEADER_SIZE:]) != crc { return }
    ReaderInit(&reader, data[FILE_HEADER_SIZE:])
    return reader, flags, true
}

// The next chunk: its tag, its version and a reader that is limited to its payload. Chunks that nobody reads are skipped by
// calling ChunkNext again. Returns false at the end of the data, or when a chunk says it is longer than what is left.
ChunkNext :: proc(reader: ^Reader) -> (tag: Tag, version: u16, payload: Reader, ok: bool) {
    if ReaderRemaining(reader) < CHUNK_HEADER_SIZE { return }
    tag = Tag(ReadU32(reader))
    version = ReadU16(reader)
    ReadU16(reader)
    length: int = int(ReadU32(reader))
    body: []byte = Take(reader, length)
    if reader.failed { return }
    ReaderInit(&payload, body)
    return tag, version, payload, true
}

// The first chunk with this tag, searching from the start of `file`. The reader `file` is not moved.
ChunkFind :: proc(file: Reader, tag: Tag) -> (version: u16, payload: Reader, ok: bool) {
    scan: Reader = file
    for {
        found_tag, found_version, found_payload, next_ok := ChunkNext(&scan)
        if !next_ok { return }
        if found_tag == tag { return found_version, found_payload, true }
    }
}

// How many chunks have this tag
ChunkCount :: proc(file: Reader, tag: Tag) -> (count: int) {
    scan: Reader = file
    for {
        found_tag, _, _, next_ok := ChunkNext(&scan)
        if !next_ok { return }
        if found_tag == tag { count += 1 }
    }
}
