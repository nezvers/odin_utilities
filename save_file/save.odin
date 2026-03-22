package save_file

import "core:os"
import "core:io"
import "core:fmt"
import "core:mem"

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
    read_buffer(file, data[:])
    return
}