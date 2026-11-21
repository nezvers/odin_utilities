package spacetimedb

// 128 and 256 bit integers of a module's types (u128, i128, u256, i256): Odin has i128 and u128 but not as BSATN's little endian bytes in an order a generated reader can rely on without
// casting, and nothing of 256 bits, so they are plain byte arrays here (little endian, as on the wire). The generated code uses these.

ReadWide16 :: proc(reader: ^Reader) -> [16]u8 {
    value: [16]u8
    copy(value[:], ReadRaw(reader, 16))
    return value
}

ReadWide32 :: proc(reader: ^Reader) -> [32]u8 {
    value: [32]u8
    copy(value[:], ReadRaw(reader, 32))
    return value
}

WriteWide16 :: proc(writer: ^Writer, value: [16]u8) {
    value := value
    WriteRaw(writer, value[:])
}

WriteWide32 :: proc(writer: ^Writer, value: [32]u8) {
    value := value
    WriteRaw(writer, value[:])
}
