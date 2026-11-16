#+build !js
// A plain zip file, written here instead of by a program of the system: the same bytes on every machine, nothing but what the format needs.
// Every entry is stored (not compressed): no data descriptors, no extra fields, no zip64, so every reader takes it (Firefox is strict about
// its add-ons, and `tar` of Windows writes streaming entries with Info-ZIP extras). The wasm is the only large part and the files of an
// extension are small, a stored package is about 1.6 MB.
package browser_extension

import "core:fmt"
import "core:hash"
import "core:os"
import "core:testing"

// 1 January 1980 00:00, the oldest date a zip can say, so the package does not change with the time it was made
@(private)
ZIP_DOS_TIME :: u16(0)
@(private)
ZIP_DOS_DATE :: u16(1 << 5 | 1)

@(private)
ZipEntry :: struct {
    name: string,
    crc: u32,
    size: u32,
    offset: u32,
}

@(private)
zipPut16 :: proc(out: ^[dynamic]u8, value: u16) {
    append(out, u8(value), u8(value >> 8))
}

@(private)
zipPut32 :: proc(out: ^[dynamic]u8, value: u32) {
    append(out, u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24))
}

// The bytes of a zip with these files. `names` are the paths inside, with forward slashes; `contents` are the bytes in the same order.
ZipBytes :: proc(names: []string, contents: [][]u8, allocator := context.temp_allocator) -> []u8 {
    assert(len(names) == len(contents))
    out: [dynamic]u8
    out.allocator = allocator
    entries: [dynamic]ZipEntry
    entries.allocator = context.temp_allocator

    for name, i in names {
        data: []u8 = contents[i]
        entry: ZipEntry = {name = name, crc = hash.crc32(data), size = u32(len(data)), offset = u32(len(out))}
        append(&entries, entry)
        zipPut32(&out, 0x04034b50)      // local file header
        zipPut16(&out, 20)              // version needed
        zipPut16(&out, 0x0800)          // flags: the name is UTF-8
        zipPut16(&out, 0)               // stored
        zipPut16(&out, ZIP_DOS_TIME)
        zipPut16(&out, ZIP_DOS_DATE)
        zipPut32(&out, entry.crc)
        zipPut32(&out, entry.size)      // compressed size
        zipPut32(&out, entry.size)
        zipPut16(&out, u16(len(name)))
        zipPut16(&out, 0)               // no extra field
        append(&out, ..transmute([]u8)name)
        append(&out, ..data)
    }

    directory_start: u32 = u32(len(out))
    for entry in entries {
        zipPut32(&out, 0x02014b50)      // central directory header
        zipPut16(&out, 20)              // made by
        zipPut16(&out, 20)              // version needed
        zipPut16(&out, 0x0800)
        zipPut16(&out, 0)
        zipPut16(&out, ZIP_DOS_TIME)
        zipPut16(&out, ZIP_DOS_DATE)
        zipPut32(&out, entry.crc)
        zipPut32(&out, entry.size)
        zipPut32(&out, entry.size)
        zipPut16(&out, u16(len(entry.name)))
        zipPut16(&out, 0)               // extra
        zipPut16(&out, 0)               // comment
        zipPut16(&out, 0)               // disk
        zipPut16(&out, 0)               // internal attributes
        zipPut32(&out, 0)               // external attributes
        zipPut32(&out, entry.offset)
        append(&out, ..transmute([]u8)entry.name)
    }
    directory_size: u32 = u32(len(out)) - directory_start

    zipPut32(&out, 0x06054b50)          // end of central directory
    zipPut16(&out, 0)
    zipPut16(&out, 0)
    zipPut16(&out, u16(len(entries)))
    zipPut16(&out, u16(len(entries)))
    zipPut32(&out, directory_size)
    zipPut32(&out, directory_start)
    zipPut16(&out, 0)                   // no comment
    return out[:]
}

// A zip file with the named files of a folder
ZipWriteFolder :: proc(package_path, folder: string, files: []string) -> bool {
    contents: [dynamic][]u8
    contents.allocator = context.temp_allocator
    for file in files {
        data, error := os.read_entire_file(fmt.tprintf("%s/%s", folder, file), context.temp_allocator)
        if error != nil {
            fmt.eprintfln("browser_extension: could not read %s/%s for the package", folder, file)
            return false
        }
        append(&contents, data)
    }
    if os.write_entire_file(package_path, ZipBytes(files, contents[:])) != nil {
        fmt.eprintfln("browser_extension: could not write %s", package_path)
        return false
    }
    return true
}

// --- Tests ---

@(test)
test_zip_layout :: proc(t: ^testing.T) {
    names: []string = {"manifest.json", "options/a.js"}
    contents: [][]u8 = {transmute([]u8)string("{}"), transmute([]u8)string("hello")}
    bytes: []u8 = ZipBytes(names, contents)

    // local header of the first entry: signature, stored, crc of "{}", sizes, name, data
    testing.expect_value(t, bytes[0], u8('P'))
    testing.expect_value(t, bytes[1], u8('K'))
    testing.expect_value(t, bytes[2], u8(3))
    testing.expect_value(t, bytes[3], u8(4))
    testing.expect_value(t, bytes[8], u8(0))
    testing.expect_value(t, u32(bytes[14]) | u32(bytes[15]) << 8 | u32(bytes[16]) << 16 | u32(bytes[17]) << 24, hash.crc32(contents[0]))
    testing.expect_value(t, string(bytes[30:30 + len(names[0])]), "manifest.json")
    testing.expect_value(t, string(bytes[30 + len(names[0]):][:2]), "{}")

    // the end of central directory is the last 22 bytes and counts both entries
    end: []u8 = bytes[len(bytes) - 22:]
    testing.expect_value(t, string(end[:4]), "PK\x05\x06")
    testing.expect_value(t, int(end[10]) | int(end[11]) << 8, 2)
}
