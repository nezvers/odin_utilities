package bsatn

// This package is free of the operating system (no sockets, no files), so the same code runs in a client of the library and in a module of Odin that is built for WebAssembly (module/). The package
// `spacetimedb` re-exports every name of it, a client program uses them from there.
//
// BSATN, the binary format of SpacetimeDB (spacetimedb/SpacetimeDB/docs/docs/00300-resources/00300-internals/00300-bsatn.md): little endian numbers, a string or an array is a u32 length and
// its elements, a product (a struct, a row) is its fields one after the other with no names, a sum (an enum, an option) is a u8 tag and the data of the variant. `Writer` and `Reader` are the two
// halves; nothing allocates: a Writer fills a buffer of the caller, a Reader hands out slices and strings that point into the bytes it reads (they live as long as those bytes do).
//
//     buffer: [256]u8
//     writer: Writer = WriterMake(buffer[:])
//     WriteString(&writer, "Ada")
//     WriteU32(&writer, 36)
//     bytes: []u8 = WriterBytes(&writer)                  // what goes into a reducer call
//     reader: Reader = ReaderMake(bytes)
//     name: string = ReadString(&reader)
//
// An error (a buffer that is too small to write, bytes that end too early to read) is remembered, not returned from every call: ask `WriterFailed` / `ReaderFailed` once at the end. A failed
// Reader reads zeros from then on, so a decoder needs no checks between the fields.


// The 256 bit identity of a client or a database, as the 32 bytes of BSATN (little endian)
Identity :: distinct [32]u8

// The 128 bit id of one connection of a client
ConnectionId :: distinct [16]u8

// Microseconds since 1970 (what the server's `Timestamp` holds)
Timestamp :: distinct i64

TimeDuration :: distinct i64

// ---- writing -------------------------------------------------------------------------------------------------------------------------------------------------------

Writer :: struct {
    data: []u8,
    length: int,
    overflow: bool,
}

WriterMake :: proc(buffer: []u8) -> Writer {
    return {data = buffer}
}

WriterBytes :: proc(writer: ^Writer) -> []u8 {
    return writer.data[:writer.length]
}

WriterFailed :: proc(writer: ^Writer) -> bool {
    return writer.overflow
}

WriterReset :: proc(writer: ^Writer) {
    writer.length, writer.overflow = 0, false
}

// Appends raw bytes (no length in front)
WriteRaw :: proc(writer: ^Writer, bytes: []u8) {
    if writer.overflow || writer.length + len(bytes) > len(writer.data) {
        writer.overflow = true
        return
    }
    copy(writer.data[writer.length:], bytes)
    writer.length += len(bytes)
}

WriteU8 :: proc(writer: ^Writer, value: u8) {
    one: [1]u8 = {value}
    WriteRaw(writer, one[:])
}

WriteBool :: proc(writer: ^Writer, value: bool) {
    WriteU8(writer, 1 if value else 0)
}

WriteU16 :: proc(writer: ^Writer, value: u16) {
    bytes: [2]u8 = {u8(value), u8(value >> 8)}
    WriteRaw(writer, bytes[:])
}

WriteU32 :: proc(writer: ^Writer, value: u32) {
    bytes: [4]u8 = {u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)}
    WriteRaw(writer, bytes[:])
}

WriteU64 :: proc(writer: ^Writer, value: u64) {
    bytes: [8]u8
    for i in 0 ..< 8 { bytes[i] = u8(value >> u32(i * 8)) }
    WriteRaw(writer, bytes[:])
}

WriteI8 :: proc(writer: ^Writer, value: i8) { WriteU8(writer, u8(value)) }
WriteI16 :: proc(writer: ^Writer, value: i16) { WriteU16(writer, u16(value)) }
WriteI32 :: proc(writer: ^Writer, value: i32) { WriteU32(writer, u32(value)) }
WriteI64 :: proc(writer: ^Writer, value: i64) { WriteU64(writer, u64(value)) }
WriteF32 :: proc(writer: ^Writer, value: f32) { WriteU32(writer, transmute(u32)value) }
WriteF64 :: proc(writer: ^Writer, value: f64) { WriteU64(writer, transmute(u64)value) }

// A string or any byte array: the length as a u32, then the bytes
WriteString :: proc(writer: ^Writer, text: string) {
    WriteU32(writer, u32(len(text)))
    WriteRaw(writer, transmute([]u8)text)
}

WriteBytes :: proc(writer: ^Writer, bytes: []u8) {
    WriteU32(writer, u32(len(bytes)))
    WriteRaw(writer, bytes)
}

// The tag of a sum (an enum variant, `Some` is 0 and `None` 1 of an option, `Ok` 0 and `Err` 1 of a result): the data of the variant follows
WriteTag :: proc(writer: ^Writer, tag: u8) {
    WriteU8(writer, tag)
}

// The count of the elements of an array: the elements follow
WriteLength :: proc(writer: ^Writer, count: int) {
    WriteU32(writer, u32(count))
}

WriteIdentity :: proc(writer: ^Writer, identity: Identity) {
    bytes: [32]u8 = cast([32]u8)identity
    WriteRaw(writer, bytes[:])
}

WriteConnectionId :: proc(writer: ^Writer, id: ConnectionId) {
    bytes: [16]u8 = cast([16]u8)id
    WriteRaw(writer, bytes[:])
}

// ---- reading -------------------------------------------------------------------------------------------------------------------------------------------------------

Reader :: struct {
    data: []u8,
    at: int,
    failed: bool,
}

ReaderMake :: proc(bytes: []u8) -> Reader {
    return {data = bytes}
}

ReaderFailed :: proc(reader: ^Reader) -> bool {
    return reader.failed
}

ReaderLeft :: proc(reader: ^Reader) -> int {
    return len(reader.data) - reader.at
}

// The next `count` bytes as a slice of the input (empty and failed when there are not that many)
ReadRaw :: proc(reader: ^Reader, count: int) -> []u8 {
    if reader.failed || count < 0 || reader.at + count > len(reader.data) {
        reader.failed = true
        return nil
    }
    bytes: []u8 = reader.data[reader.at:reader.at + count]
    reader.at += count
    return bytes
}

ReadU8 :: proc(reader: ^Reader) -> u8 {
    bytes: []u8 = ReadRaw(reader, 1)
    return bytes[0] if len(bytes) == 1 else 0
}

ReadBool :: proc(reader: ^Reader) -> bool {
    return ReadU8(reader) != 0
}

ReadU16 :: proc(reader: ^Reader) -> u16 {
    bytes: []u8 = ReadRaw(reader, 2)
    if len(bytes) != 2 { return 0 }
    return u16(bytes[0]) | u16(bytes[1]) << 8
}

ReadU32 :: proc(reader: ^Reader) -> u32 {
    bytes: []u8 = ReadRaw(reader, 4)
    if len(bytes) != 4 { return 0 }
    return u32(bytes[0]) | u32(bytes[1]) << 8 | u32(bytes[2]) << 16 | u32(bytes[3]) << 24
}

ReadU64 :: proc(reader: ^Reader) -> u64 {
    bytes: []u8 = ReadRaw(reader, 8)
    if len(bytes) != 8 { return 0 }
    value: u64
    for i in 0 ..< 8 { value |= u64(bytes[i]) << u32(i * 8) }
    return value
}

ReadI8 :: proc(reader: ^Reader) -> i8 { return i8(ReadU8(reader)) }
ReadI16 :: proc(reader: ^Reader) -> i16 { return i16(ReadU16(reader)) }
ReadI32 :: proc(reader: ^Reader) -> i32 { return i32(ReadU32(reader)) }
ReadI64 :: proc(reader: ^Reader) -> i64 { return i64(ReadU64(reader)) }
ReadF32 :: proc(reader: ^Reader) -> f32 { return transmute(f32)ReadU32(reader) }
ReadF64 :: proc(reader: ^Reader) -> f64 { return transmute(f64)ReadU64(reader) }

// The bytes of an array of bytes (a slice of the input)
ReadBytes :: proc(reader: ^Reader) -> []u8 {
    count: u32 = ReadU32(reader)
    return ReadRaw(reader, int(count))
}

// A string (a view of the input: no copy; the bytes are not checked to be UTF-8)
ReadString :: proc(reader: ^Reader) -> string {
    return string(ReadBytes(reader))
}

ReadTag :: proc(reader: ^Reader) -> u8 {
    return ReadU8(reader)
}

// The count of the elements of an array. A count that cannot be true (more elements than there are bytes left, when every element is at least `minimum_size` bytes) fails the reader
// instead of letting a caller allocate for a number that came off the wire.
ReadLength :: proc(reader: ^Reader, minimum_size: int = 1) -> int {
    count: int = int(ReadU32(reader))
    if count * max(minimum_size, 1) > ReaderLeft(reader) {
        reader.failed = true
        return 0
    }
    return count
}

ReadIdentity :: proc(reader: ^Reader) -> Identity {
    bytes: []u8 = ReadRaw(reader, 32)
    identity: Identity
    if len(bytes) == 32 { copy(identity[:], bytes) }
    return identity
}

ReadConnectionId :: proc(reader: ^Reader) -> ConnectionId {
    bytes: []u8 = ReadRaw(reader, 16)
    id: ConnectionId
    if len(bytes) == 16 { copy(id[:], bytes) }
    return id
}

// The identity as the hex text that the server and the CLI show (the 32 bytes the other way round: the BSATN is little endian, the text big endian). `out` holds 64 characters.
IdentityHex :: proc(identity: Identity, out: []u8) -> string {
    digits: string = "0123456789abcdef"
    if len(out) < 64 { return "" }
    for i in 0 ..< 32 {
        byte: u8 = identity[31 - i]
        out[i * 2] = digits[byte >> 4]
        out[i * 2 + 1] = digits[byte & 15]
    }
    return string(out[:64])
}

// The identity of a hex text of 64 characters (the other way of IdentityHex)
IdentityFromHex :: proc(text: string) -> (identity: Identity, ok: bool) {
    if len(text) != 64 { return {}, false }
    digit :: proc(character: u8) -> (value: u8, ok: bool) {
        switch character {
        case '0' ..= '9': return character - '0', true
        case 'a' ..= 'f': return character - 'a' + 10, true
        case 'A' ..= 'F': return character - 'A' + 10, true
        }
        return 0, false
    }
    for i in 0 ..< 32 {
        high, high_ok := digit(text[i * 2])
        low, low_ok := digit(text[i * 2 + 1])
        if !high_ok || !low_ok { return {}, false }
        identity[31 - i] = high * 16 + low
    }
    return identity, true
}
