package web_build

// What a WebAssembly binary imports and exports, read from its sections without running it: a build of a program that is not a browser program (a SpacetimeDB module, a plugin of a host, a
// game mod) can be checked right after it is built: has it the exports the host calls (`__describe_module__`, `memory`), and does it import only what the host offers. Pure data, no `core:os`:
// it builds for every target. Only the import and export sections are read; the rest is skipped by its size.
//
//     info, ok := WasmInspect(bytes, context.temp_allocator)
//     WasmExports(&info, "memory")                  // is there an export of that name
//     for entry in info.imports { entry.module, entry.name, entry.kind }

import "base:runtime"

WasmKind :: enum u8 {
    FUNCTION = 0,
    TABLE = 1,
    MEMORY = 2,
    GLOBAL = 3,
    TAG = 4,
}

WasmImport :: struct {
    module: string,         // "env", "odin_env", "spacetime_10.0": the namespace the host has to offer
    name: string,
    kind: WasmKind,
}

WasmExport :: struct {
    name: string,
    kind: WasmKind,
    index: u32,
}

WasmInfo :: struct {
    imports: []WasmImport,
    exports: []WasmExport,
}

@(private)
Cursor :: struct {
    data: []u8,
    at: int,
    failed: bool,
}

@(private)
cursorByte :: proc(cursor: ^Cursor) -> u8 {
    if cursor.at >= len(cursor.data) {
        cursor.failed = true
        return 0
    }
    value: u8 = cursor.data[cursor.at]
    cursor.at += 1
    return value
}

// LEB128, unsigned, at most 32 bits (what the lengths and indexes of a module are)
@(private)
cursorLeb :: proc(cursor: ^Cursor) -> u32 {
    result: u32
    shift: u32
    for {
        byte: u8 = cursorByte(cursor)
        if cursor.failed { return 0 }
        result |= u32(byte & 0x7f) << shift
        if byte & 0x80 == 0 { return result }
        shift += 7
        if shift > 35 {
            cursor.failed = true
            return 0
        }
    }
}

@(private)
cursorName :: proc(cursor: ^Cursor) -> string {
    length: int = int(cursorLeb(cursor))
    if cursor.failed || cursor.at + length > len(cursor.data) {
        cursor.failed = true
        return ""
    }
    name: string = string(cursor.data[cursor.at:cursor.at + length])
    cursor.at += length
    return name
}

@(private)
cursorLimits :: proc(cursor: ^Cursor) {
    flags: u8 = cursorByte(cursor)
    cursorLeb(cursor)                       // the minimum
    if flags & 1 != 0 { cursorLeb(cursor) }       // the maximum
}

// The imports and exports of a binary. `ok` is false when it is not a WebAssembly binary or is cut short. Strings point into `bytes`; the two arrays are made with `allocator`.
WasmInspect :: proc(bytes: []u8, allocator: runtime.Allocator) -> (info: WasmInfo, ok: bool) {
    if len(bytes) < 8 || bytes[0] != 0 || bytes[1] != 'a' || bytes[2] != 's' || bytes[3] != 'm' { return {}, false }
    cursor: Cursor = {data = bytes, at = 8}
    imports: [dynamic]WasmImport
    exports: [dynamic]WasmExport
    imports.allocator, exports.allocator = allocator, allocator
    for cursor.at < len(bytes) && !cursor.failed {
        id: u8 = cursorByte(&cursor)
        size: int = int(cursorLeb(&cursor))
        end: int = cursor.at + size
        if cursor.failed || end > len(bytes) { return {}, false }
        switch id {
        case 2:
            count: u32 = cursorLeb(&cursor)
            for _ in 0 ..< count {
                entry: WasmImport = {module = cursorName(&cursor), name = cursorName(&cursor)}
                kind: u8 = cursorByte(&cursor)
                entry.kind = WasmKind(kind)
                switch kind {
                case 0: cursorLeb(&cursor)                    // the index of the function type
                case 1:
                    cursorByte(&cursor)                       // the type of the elements
                    cursorLimits(&cursor)
                case 2: cursorLimits(&cursor)
                case 3:
                    cursorByte(&cursor)                       // the value type
                    cursorByte(&cursor)                       // mutable or not
                case 4:
                    cursorByte(&cursor)
                    cursorLeb(&cursor)
                case: return {}, false
                }
                append(&imports, entry)
            }
        case 7:
            count: u32 = cursorLeb(&cursor)
            for _ in 0 ..< count {
                entry: WasmExport = {name = cursorName(&cursor)}
                entry.kind = WasmKind(cursorByte(&cursor))
                entry.index = cursorLeb(&cursor)
                append(&exports, entry)
            }
        }
        cursor.at = end
    }
    if cursor.failed { return {}, false }
    return {imports = imports[:], exports = exports[:]}, true
}

WasmHasExport :: proc(info: ^WasmInfo, name: string, kind: WasmKind) -> bool {
    for entry in info.exports {
        if entry.name == name && entry.kind == kind { return true }
    }
    return false
}

// The imports whose module is not one of `allowed` (a host offers some namespaces: a module that imports another one will not load)
WasmUnknownImports :: proc(info: ^WasmInfo, allowed: []string, allocator: runtime.Allocator) -> []WasmImport {
    unknown: [dynamic]WasmImport
    unknown.allocator = allocator
    for entry in info.imports {
        known: bool
        for module in allowed {
            if entry.module == module { known = true }
        }
        if !known { append(&unknown, entry) }
    }
    return unknown[:]
}
