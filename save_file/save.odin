package save_file

import "core:os"
import "core:fmt"
import "core:strings"

close :: os.close

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

write_open :: proc(filepath:string)->(file: ^os.File) {
    if !os.exists(filepath) {
        return create(filepath)
    }
    f, err: = os.open(filepath, {.Write, .Append}, {.Write_Other, .Write_Group, .Write_User})
    if err != nil {
        fmt.println(os.error_string(err))
        return
    }
    file = f
    return
}

write_append :: proc(file: ^os.File, data: []u8) {
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

read_file :: proc(filepath: string) {
    data, err := os.read_entire_file(filepath, context.allocator) // context.allocator will track the memory held by this data
    if err != nil {
        fmt.println("Error reading file")
    }
    defer delete(data, context.allocator) // we're using the allocator to delete the memory. defer means 'execute this code when the function returns'
    it := string(data)
    for line in strings.split_lines_iterator(&it) { // run through all the lines
        fmt.println(line)
    }
}