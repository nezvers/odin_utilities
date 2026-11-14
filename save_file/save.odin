package save_file

import "core:os"
import "core:io"
import "core:fmt"
import "core:mem"
import "core:testing"

// mem is only used inside the generic procs below, which are checked when they are instantiated: this keeps the import used
@(private)
_ :: mem.Allocator

close :: os.close

// If exists, deletes and creates a new file
create :: proc(filepath: string)->(file: ^os.File) {
    if os.exists(filepath) {
        err: = os.remove(filepath)
        if err != nil {
            fmt.println(os.error_string(err))
            return
        }
    }
    f, create_err: = os.create(filepath)
    if create_err != nil {
        fmt.println(os.error_string(create_err))
        return
    }
    file = f
    return
}

// If doesn't exists creates new
write_open :: proc(filepath:string)->(file: ^os.File) {
    f, err: = os.open(filepath, {.Create, .Write, .Append}, {.Write_Other, .Write_Group, .Write_User})
    if err != nil {
        fmt.println(os.error_string(err))
        return
    }
    file = f
    return
}

write_append :: proc(file: ^os.File, data: []u8) {
    assert(file != nil)
    count, err: = os.write(file, data[:])
    if err != nil {
        fmt.println(os.error_string(err))
        return
    }
    if count != len(data) {
        fmt.println("[ERROR] - failed to write all bytes")
        return
    }
}

write_append_struct :: proc(file: ^os.File, value: ^$T) {
    data := mem.byte_slice(value, size_of(T))
    write_append(file, data[:])
}

read_open :: proc(filepath: string)->(file: ^os.File) {
    if !os.exists(filepath) {
        return
    }
    f, err: = os.open(filepath, {.Read}, {.Read_Other, .Read_Group, .Read_User})
    if err != nil {
        fmt.println(os.error_string(err))
        return
    }
    file = f
    return
}

read_buffer :: proc(file: ^os.File, buffer: []u8)->(n: int) {
    assert(file != nil)
    count, err: = os.read_at_least(file, buffer, len(buffer))
    n = count
    if err != nil && err != io.Error.EOF {
        fmt.println(os.error_string(err))
        return
    }
    return
}

read_struct :: proc(file: ^os.File, value: ^$T)->(n: int) {
    data := mem.byte_slice(value, size_of(T))
    n = read_buffer(file, data[:])
    return
}

// --- Tests ---

@(private="file")
SaveRecord :: struct {
    id: u32,
    position: [2]f32,
    flags: [4]u8,
}

@(private="file")
temp_path :: proc(name: string) -> string {
    directory, _ := os.temp_directory(context.temp_allocator)
    return fmt.tprintf("%s/odin_utilities_save_file_%s.bin", directory, name)
}

@(test)
test_save_and_load_structs :: proc(t: ^testing.T) {
    path: string = temp_path("structs")
    defer os.remove(path)

    records: [3]SaveRecord = {
        {1, {1.5, -2}, {1, 2, 3, 4}},
        {2, {3, 4}, {5, 6, 7, 8}},
        {3, {-9, 0.25}, {0, 0, 0, 255}},
    }
    writer: ^os.File = create(path)
    testing.expect(t, writer != nil)
    if writer == nil { return }
    for &record in records { write_append_struct(writer, &record) }
    close(writer)

    reader: ^os.File = read_open(path)
    testing.expect(t, reader != nil)
    if reader == nil { return }
    defer close(reader)
    for expected in records {
        loaded: SaveRecord
        count: int = read_struct(reader, &loaded)
        testing.expect_value(t, count, size_of(SaveRecord))
        testing.expect_value(t, loaded, expected)
    }
}

@(test)
test_create_replaces_and_append_extends :: proc(t: ^testing.T) {
    path: string = temp_path("replace")
    defer os.remove(path)

    first: ^os.File = create(path)
    write_append(first, []u8{1, 2, 3, 4, 5})
    close(first)

    second: ^os.File = create(path)                                                        // an old save is removed first
    write_append(second, []u8{9, 9})
    close(second)

    more: ^os.File = write_open(path)                                                      // opened for appending to the existing file
    write_append(more, []u8{7})
    close(more)

    reader: ^os.File = read_open(path)
    if reader == nil {
        testing.fail_now(t, "the file is missing")
    }
    defer close(reader)
    buffer: [8]u8
    testing.expect_value(t, read_buffer(reader, buffer[:3]), 3)
    testing.expect_value(t, buffer[0], u8(9))
    testing.expect_value(t, buffer[1], u8(9))
    testing.expect_value(t, buffer[2], u8(7))
}

@(test)
test_read_open_missing_file :: proc(t: ^testing.T) {
    testing.expect(t, read_open(temp_path("does_not_exist")) == nil)
}
