#+build !js
package spacetimedb

// Code generation from the schema of a database (`GET /v1/database/<name>/schema?version=9`, see `DatabaseSchema`, or a saved copy): an Odin file with a struct for every type of the module, the
// readers and writers of them (BSATN), one `Call<Reducer>` proc per reducer, and the tables to keep in a `Cache`, like `spacetime generate` does for the other languages. The generated code
// uses this library for everything else, so what it contains is only what the module says.
//
//     source, ok := GenerateSource(schema_json, {package_name = "game_data", library = "../spacetimedb"}, context.allocator)
//
// Types: bool, the integers (128 and 256 bit ones are byte arrays, see wide.odin), f32, f64, string, Identity, ConnectionId, Timestamp, TimeDuration, `Maybe(T)` for an option, `[]T` for an array
// (made with the temp allocator when read: free it with the frame), a struct for a product, an enum for a sum of units and a union of `Type_Variant` structs for the other sums.
// Strings and bytes that are read point into the frame (or the cache) they came from.

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strings"
import "base:runtime"

GenerateOptions :: struct {
    package_name: string,           // the package of the generated file
    library: string,                // the import path of this library, as written in the generated file ("../spacetimedb")
    call_buffer: int,               // bytes of the stack buffer of a reducer call (default 4096)
}

@(private)
Generator :: struct {
    types: json.Array,                          // the typespace
    names: []string,                            // the name of each typespace entry: "" until the `types` list names it
    out: strings.Builder,
    helpers: strings.Builder,                   // the readers and writers of arrays and options, once each
    emitted: map[string]bool,
    allocator: runtime.Allocator,
}

@(private)
jsonField :: proc(value: json.Value, key: string) -> (field: json.Value, ok: bool) {
    object, is_object := value.(json.Object)
    if !is_object { return nil, false }
    return object[key]
}

// A value of the schema JSON that is a tagged one (`{"Ref": 0}`, `{"String": []}`): the tag and what it holds
@(private)
jsonTag :: proc(value: json.Value) -> (tag: string, payload: json.Value, ok: bool) {
    object, is_object := value.(json.Object)
    if !is_object || len(object) != 1 { return "", nil, false }
    for key, item in object { return key, item, true }
    return "", nil, false
}

// `{"some": x}` or `{"none": []}` of the schema JSON
@(private)
jsonSome :: proc(value: json.Value) -> (inner: json.Value, ok: bool) {
    return jsonField(value, "some")
}

@(private)
jsonInt :: proc(value: json.Value) -> int {
    #partial switch v in value {
    case json.Integer: return int(v)
    case json.Float: return int(v)
    }
    return 0
}

@(private)
jsonStr :: proc(value: json.Value) -> string {
    text, _ := value.(json.String)
    return text
}

@(private)
KEYWORDS :: [?]string{"asm", "auto_cast", "bit_field", "bit_set", "break", "case", "cast", "context", "continue", "defer", "distinct", "do", "dynamic", "else", "enum", "fallthrough", "for", "foreign", "if", "import", "in", "map", "matrix", "not_in", "or_break", "or_continue", "or_else", "or_return", "package", "proc", "return", "struct", "switch", "transmute", "typeid", "union", "using", "when", "where"}

@(private)
identifier :: proc(name: string, allocator: runtime.Allocator) -> string {
    keywords := KEYWORDS
    for keyword in keywords {
        if name == keyword { return strings.concatenate({name, "_"}, allocator) }
    }
    return name
}

@(private)
pascal :: proc(name: string, allocator: runtime.Allocator) -> string {
    builder: strings.Builder
    strings.builder_init(&builder, allocator)
    upper: bool = true
    for r in name {
        if r == '_' || r == ' ' || r == '-' {
            upper = true
            continue
        }
        if upper && r >= 'a' && r <= 'z' { strings.write_rune(&builder, r - 32) } else { strings.write_rune(&builder, r) }
        upper = false
    }
    return strings.to_string(builder)
}

@(private)
primitiveType :: proc(tag: string) -> (odin: string, read: string, write: string, ok: bool) {
    switch tag {
    case "Bool": return "bool", "st.ReadBool", "st.WriteBool", true
    case "I8": return "i8", "st.ReadI8", "st.WriteI8", true
    case "U8": return "u8", "st.ReadU8", "st.WriteU8", true
    case "I16": return "i16", "st.ReadI16", "st.WriteI16", true
    case "U16": return "u16", "st.ReadU16", "st.WriteU16", true
    case "I32": return "i32", "st.ReadI32", "st.WriteI32", true
    case "U32": return "u32", "st.ReadU32", "st.WriteU32", true
    case "I64": return "i64", "st.ReadI64", "st.WriteI64", true
    case "U64": return "u64", "st.ReadU64", "st.WriteU64", true
    case "I128", "U128": return "[16]u8", "st.ReadWide16", "st.WriteWide16", true
    case "I256", "U256": return "[32]u8", "st.ReadWide32", "st.WriteWide32", true
    case "F32": return "f32", "st.ReadF32", "st.WriteF32", true
    case "F64": return "f64", "st.ReadF64", "st.WriteF64", true
    case "String": return "string", "st.ReadString", "st.WriteString", true
    }
    return "", "", "", false
}

// The types that the server defines for itself: an Identity is a product of one u256 named `__identity__`, a ScheduleAt a sum of Interval and Time. They are written inline in a column
// by a module that makes its own description, and as a reference to a named type by others: `specialInline` looks at the type itself, `specialType` at an entry of the typespace.
@(private)
specialInline :: proc(t: json.Value) -> (odin: string, read: string, write: string, ok: bool) {
    tag, payload, tagged := jsonTag(t)
    if !tagged { return }
    if tag == "Sum" {
        variants, _ := jsonField(payload, "variants")
        list, is_list := variants.(json.Array)
        if !is_list || len(list) != 2 { return }
        first, _ := jsonSome(jsonField(list[0], "name") or_else nil)
        second, _ := jsonSome(jsonField(list[1], "name") or_else nil)
        if jsonStr(first) == "Interval" && jsonStr(second) == "Time" { return "st.ScheduleAt", "st.ReadScheduleAt", "st.WriteScheduleAt", true }
        return
    }
    if tag != "Product" { return }
    elements, _ := jsonField(payload, "elements")
    list, is_list := elements.(json.Array)
    if !is_list || len(list) != 1 { return }
    name, _ := jsonSome(jsonField(list[0], "name") or_else nil)
    switch jsonStr(name) {
    case "__identity__": return "st.Identity", "st.ReadIdentity", "st.WriteIdentity", true
    case "__connection_id__": return "st.ConnectionId", "st.ReadConnectionId", "st.WriteConnectionId", true
    case "__timestamp_micros_since_unix_epoch__": return "st.Timestamp", "readTimestamp", "writeTimestamp", true
    case "__time_duration_micros__": return "st.TimeDuration", "readTimeDuration", "writeTimeDuration", true
    }
    return
}

@(private)
specialType :: proc(g: ^Generator, index: int) -> (odin: string, read: string, write: string, ok: bool) {
    if index < 0 || index >= len(g.types) { return }
    return specialInline(g.types[index])
}

@(private)
isOption :: proc(payload: json.Value) -> (inner: json.Value, ok: bool) {
    variants, _ := jsonField(payload, "variants")
    list, is_list := variants.(json.Array)
    if !is_list || len(list) != 2 { return nil, false }
    first, _ := jsonSome(jsonField(list[0], "name") or_else nil)
    second, _ := jsonSome(jsonField(list[1], "name") or_else nil)
    if jsonStr(first) == "some" && jsonStr(second) == "none" { return jsonField(list[0], "algebraic_type") }
    if jsonStr(first) == "none" && jsonStr(second) == "some" { return jsonField(list[1], "algebraic_type") }
    return nil, false
}

// Is this the product with no elements (a unit): the payload of a variant that carries nothing
@(private)
isUnit :: proc(value: json.Value) -> bool {
    tag, payload, ok := jsonTag(value)
    if !ok || tag != "Product" { return false }
    elements, _ := jsonField(payload, "elements")
    list, is_list := elements.(json.Array)
    return is_list && len(list) == 0
}

@(private)
typeName :: proc(g: ^Generator, index: int) -> string {
    if index >= 0 && index < len(g.names) && g.names[index] != "" { return g.names[index] }
    return fmt.aprintf("Type%d", index, allocator = g.allocator)
}

// The name used to build the names of the helpers of one type (`Array_U32`, `Option_Person`)
@(private)
mangle :: proc(g: ^Generator, t: json.Value) -> string {
    tag, payload, _ := jsonTag(t)
    if odin, _, _, special := specialInline(t); special { return strings.trim_prefix(odin, "st.") }
    switch tag {
    case "Ref":
        index: int = jsonInt(payload)
        if odin, _, _, special := specialType(g, index); special { return strings.trim_prefix(odin, "st.") }
        return typeName(g, index)
    case "Array": return strings.concatenate({"Array_", mangle(g, payload)}, g.allocator)
    case "Sum":
        if inner, ok := isOption(payload); ok { return strings.concatenate({"Option_", mangle(g, inner)}, g.allocator) }
        return "Sum"
    }
    return tag
}

@(private)
odinType :: proc(g: ^Generator, t: json.Value) -> string {
    tag, payload, _ := jsonTag(t)
    if odin, _, _, ok := primitiveType(tag); ok { return odin }
    if odin, _, _, special := specialInline(t); special { return odin }
    switch tag {
    case "Ref":
        index: int = jsonInt(payload)
        if odin, _, _, special := specialType(g, index); special { return odin }
        return typeName(g, index)
    case "Array": return strings.concatenate({"[]", odinType(g, payload)}, g.allocator)
    case "Sum":
        if inner, ok := isOption(payload); ok { return strings.concatenate({"Maybe(", odinType(g, inner), ")"}, g.allocator) }
    }
    return "struct {}"
}

// The reader (`proc(reader: ^st.Reader) -> T`) of a type; the ones of arrays and options are written once into `helpers`
@(private)
readProc :: proc(g: ^Generator, t: json.Value) -> string {
    tag, payload, _ := jsonTag(t)
    if _, read, _, ok := primitiveType(tag); ok { return read }
    if _, read, _, special := specialInline(t); special { return read }
    switch tag {
    case "Ref":
        index: int = jsonInt(payload)
        if _, read, _, special := specialType(g, index); special { return read }
        return strings.concatenate({typeName(g, index), "Read"}, g.allocator)
    case "Array":
        name: string = strings.concatenate({"Read_", mangle(g, t)}, g.allocator)
        if !g.emitted[name] {
            g.emitted[name] = true
            inner: string = readProc(g, payload)
            fmt.sbprintfln(&g.helpers, "%s :: proc(reader: ^st.Reader) -> %s {{", name, odinType(g, t))
            fmt.sbprintln(&g.helpers, "    count: int = st.ReadLength(reader, 1)")
            fmt.sbprintfln(&g.helpers, "    values: %s = make(%s, count, context.temp_allocator)", odinType(g, t), odinType(g, t))
            fmt.sbprintfln(&g.helpers, "    for i in 0 ..< count {{ values[i] = %s(reader) }}", inner)
            fmt.sbprintln(&g.helpers, "    return values\n}\n")
        }
        return name
    case "Sum":
        if inner_type, ok := isOption(payload); ok {
            name: string = strings.concatenate({"Read_", mangle(g, t)}, g.allocator)
            if !g.emitted[name] {
                g.emitted[name] = true
                inner: string = readProc(g, inner_type)
                fmt.sbprintfln(&g.helpers, "%s :: proc(reader: ^st.Reader) -> %s {{", name, odinType(g, t))
                fmt.sbprintfln(&g.helpers, "    if st.ReadTag(reader) == 0 {{ return %s(reader) }}", inner)
                fmt.sbprintln(&g.helpers, "    return nil\n}\n")
            }
            return name
        }
    }
    return "st.ReadU8"
}

@(private)
writeProc :: proc(g: ^Generator, t: json.Value) -> string {
    tag, payload, _ := jsonTag(t)
    if _, _, write, ok := primitiveType(tag); ok { return write }
    if _, _, write, special := specialInline(t); special { return write }
    switch tag {
    case "Ref":
        index: int = jsonInt(payload)
        if _, _, write, special := specialType(g, index); special { return write }
        return strings.concatenate({typeName(g, index), "Write"}, g.allocator)
    case "Array":
        name: string = strings.concatenate({"Write_", mangle(g, t)}, g.allocator)
        if !g.emitted[name] {
            g.emitted[name] = true
            inner: string = writeProc(g, payload)
            fmt.sbprintfln(&g.helpers, "%s :: proc(writer: ^st.Writer, values: %s) {{", name, odinType(g, t))
            fmt.sbprintln(&g.helpers, "    st.WriteLength(writer, len(values))")
            fmt.sbprintfln(&g.helpers, "    for value in values {{ %s(writer, value) }}", inner)
            fmt.sbprintln(&g.helpers, "}\n")
        }
        return name
    case "Sum":
        if inner_type, ok := isOption(payload); ok {
            name: string = strings.concatenate({"Write_", mangle(g, t)}, g.allocator)
            if !g.emitted[name] {
                g.emitted[name] = true
                inner: string = writeProc(g, inner_type)
                fmt.sbprintfln(&g.helpers, "%s :: proc(writer: ^st.Writer, value: %s) {{", name, odinType(g, t))
                fmt.sbprintfln(&g.helpers, "    if inner, ok := value.?; ok {{\n        st.WriteTag(writer, 0)\n        %s(writer, inner)\n    }} else {{\n        st.WriteTag(writer, 1)\n    }}", inner)
                fmt.sbprintln(&g.helpers, "}\n")
            }
            return name
        }
    }
    return "st.WriteU8"
}

// The size in bytes of a type that is the same for every value (a primary key can be cut from the start of a row only then); 0 when it varies
@(private)
fixedSize :: proc(g: ^Generator, t: json.Value) -> int {
    tag, payload, _ := jsonTag(t)
    if odin, _, _, special := specialInline(t); special {
        switch odin {
        case "st.Identity": return 32
        case "st.ConnectionId": return 16
        case "st.Timestamp", "st.TimeDuration": return 8
        }
        return 0
    }
    switch tag {
    case "Bool", "I8", "U8": return 1
    case "I16", "U16": return 2
    case "I32", "U32", "F32": return 4
    case "I64", "U64", "F64": return 8
    case "I128", "U128": return 16
    case "I256", "U256": return 32
    case "Ref":
        index: int = jsonInt(payload)
        if index < 0 || index >= len(g.types) { return 0 }
        ref_tag, ref_payload, _ := jsonTag(g.types[index])
        if ref_tag != "Product" { return 0 }
        elements, _ := jsonField(ref_payload, "elements")
        total: int
        for element in elements.(json.Array) or_else nil {
            algebraic, _ := jsonField(element, "algebraic_type")
            size: int = fixedSize(g, algebraic)
            if size == 0 { return 0 }
            total += size
        }
        return total
    }
    return 0
}

@(private)
fieldName :: proc(g: ^Generator, element: json.Value, index: int) -> string {
    name, has := jsonSome(jsonField(element, "name") or_else nil)
    if has && jsonStr(name) != "" { return identifier(jsonStr(name), g.allocator) }
    return fmt.aprintf("field%d", index, allocator = g.allocator)
}

@(private)
emitType :: proc(g: ^Generator, index: int) {
    if _, _, _, special := specialType(g, index); special { return }
    t: json.Value = g.types[index]
    tag, payload, _ := jsonTag(t)
    name: string = typeName(g, index)
    out: ^strings.Builder = &g.out
    switch tag {
    case "Product":
        elements, _ := jsonField(payload, "elements")
        list, _ := elements.(json.Array)
        fmt.sbprintfln(out, "%s :: struct {{", name)
        for element, i in list {
            algebraic, _ := jsonField(element, "algebraic_type")
            fmt.sbprintfln(out, "    %s: %s,", fieldName(g, element, i), odinType(g, algebraic))
        }
        fmt.sbprintln(out, "}\n")
        fmt.sbprintfln(out, "%sRead :: proc(reader: ^st.Reader) -> %s {{", name, name)
        fmt.sbprintfln(out, "    value: %s", name)
        for element, i in list {
            algebraic, _ := jsonField(element, "algebraic_type")
            fmt.sbprintfln(out, "    value.%s = %s(reader)", fieldName(g, element, i), readProc(g, algebraic))
        }
        fmt.sbprintln(out, "    return value\n}\n")
        fmt.sbprintfln(out, "%sWrite :: proc(writer: ^st.Writer, value: %s) {{", name, name)
        for element, i in list {
            algebraic, _ := jsonField(element, "algebraic_type")
            fmt.sbprintfln(out, "    %s(writer, value.%s)", writeProc(g, algebraic), fieldName(g, element, i))
        }
        fmt.sbprintln(out, "}\n")
    case "Sum":
        variants, _ := jsonField(payload, "variants")
        list, _ := variants.(json.Array)
        all_units: bool = true
        for variant in list {
            algebraic, _ := jsonField(variant, "algebraic_type")
            if !isUnit(algebraic) { all_units = false }
        }
        if all_units {
            fmt.sbprintfln(out, "%s :: enum u8 {{", name)
            for variant, i in list {
                variant_name, _ := jsonSome(jsonField(variant, "name") or_else nil)
                fmt.sbprintfln(out, "    %s,", pascal(jsonStr(variant_name), g.allocator) if jsonStr(variant_name) != "" else fmt.aprintf("Variant%d", i, allocator = g.allocator))
            }
            fmt.sbprintln(out, "}\n")
            fmt.sbprintfln(out, "%sRead :: proc(reader: ^st.Reader) -> %s {{\n    return %s(st.ReadTag(reader))\n}}\n", name, name, name)
            fmt.sbprintfln(out, "%sWrite :: proc(writer: ^st.Writer, value: %s) {{\n    st.WriteTag(writer, u8(value))\n}}\n", name, name)
        } else {
            names: [dynamic]string
            names.allocator = g.allocator
            for variant, i in list {
                variant_name, _ := jsonSome(jsonField(variant, "name") or_else nil)
                algebraic, _ := jsonField(variant, "algebraic_type")
                full: string = fmt.aprintf("%s_%s", name, pascal(jsonStr(variant_name), g.allocator) if jsonStr(variant_name) != "" else fmt.aprintf("Variant%d", i, allocator = g.allocator), allocator = g.allocator)
                append(&names, full)
                if isUnit(algebraic) { fmt.sbprintfln(out, "%s :: struct {{}}", full) } else { fmt.sbprintfln(out, "%s :: struct {{ value: %s }}", full, odinType(g, algebraic)) }
            }
            fmt.sbprintfln(out, "%s :: union {{", name)
            for full in names { fmt.sbprintfln(out, "    %s,", full) }
            fmt.sbprintln(out, "}\n")
            fmt.sbprintfln(out, "%sRead :: proc(reader: ^st.Reader) -> %s {{", name, name)
            fmt.sbprintln(out, "    switch st.ReadTag(reader) {")
            for variant, i in list {
                algebraic, _ := jsonField(variant, "algebraic_type")
                if isUnit(algebraic) { fmt.sbprintfln(out, "    case %d: return %s{{}}", i, names[i]) } else { fmt.sbprintfln(out, "    case %d: return %s{{value = %s(reader)}}", i, names[i], readProc(g, algebraic)) }
            }
            fmt.sbprintln(out, "    }\n    reader.failed = true\n    return nil\n}\n")
            fmt.sbprintfln(out, "%sWrite :: proc(writer: ^st.Writer, value: %s) {{", name, name)
            fmt.sbprintln(out, "    switch variant in value {")
            for variant, i in list {
                algebraic, _ := jsonField(variant, "algebraic_type")
                fmt.sbprintfln(out, "    case %s:", names[i])
                fmt.sbprintfln(out, "        st.WriteTag(writer, %d)", i)
                if !isUnit(algebraic) { fmt.sbprintfln(out, "        %s(writer, variant.value)", writeProc(g, algebraic)) }
            }
            fmt.sbprintln(out, "    }\n}\n")
        }
    case:
        // an alias of another type (an array or a primitive named by the module): the name is the type
        fmt.sbprintfln(out, "%s :: %s\n", name, odinType(g, t))
    }
}

// The source of a package for a schema (JSON as the server gives it). `ok` false when the JSON is not a schema. The text is made with `allocator`.
GenerateSource :: proc(schema_json: string, options: GenerateOptions, allocator: runtime.Allocator) -> (source: string, ok: bool) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, context.temp_allocator, context.temp_allocator)
    scratch: runtime.Allocator = mem.dynamic_arena_allocator(&arena)
    defer mem.dynamic_arena_destroy(&arena)

    value, error := json.parse(transmute([]u8)schema_json, json.DEFAULT_SPECIFICATION, true, scratch)
    if error != .None { return "", false }
    typespace, has_typespace := jsonField(value, "typespace")
    types_value, _ := jsonField(typespace, "types")
    types, is_array := types_value.(json.Array)
    if !has_typespace || !is_array { return "", false }

    g: Generator = {types = types, allocator = scratch}
    g.names = make([]string, len(types), scratch)
    g.emitted = make(map[string]bool, scratch)
    strings.builder_init(&g.out, scratch)
    strings.builder_init(&g.helpers, scratch)
    named, _ := jsonField(value, "types")
    for entry in named.(json.Array) or_else nil {
        name, _ := jsonField(entry, "name")
        inner, _ := jsonField(name, "name")
        index: int = jsonInt(jsonField(entry, "ty") or_else nil)
        if index >= 0 && index < len(g.names) { g.names[index] = jsonStr(inner) }
    }

    package_name: string = options.package_name if options.package_name != "" else "spacetimedb_schema"
    library: string = options.library if options.library != "" else "../spacetimedb"
    buffer_size: int = options.call_buffer if options.call_buffer > 0 else 4096

    for _, index in types { emitType(&g, index) }

    // the tables: their names, and the cache to keep them
    body: strings.Builder
    strings.builder_init(&body, scratch)
    tables_value, _ := jsonField(value, "tables")
    tables: json.Array = tables_value.(json.Array) or_else nil
    fmt.sbprintln(&body, "// The tables that clients can subscribe to, kept in a `st.Cache` by `TablesAdd`")
    fmt.sbprintln(&body, "Tables :: struct {")
    for table in tables {
        if jsonTableHidden(table) { continue }
        fmt.sbprintfln(&body, "    %s: int,", identifier(jsonStr(jsonField(table, "name") or_else nil), scratch))
    }
    fmt.sbprintln(&body, "}\n")
    fmt.sbprintln(&body, "TablesAdd :: proc(cache: ^st.Cache) -> Tables {")
    fmt.sbprintln(&body, "    tables: Tables")
    for table in tables {
        if jsonTableHidden(table) { continue }
        table_name: string = jsonStr(jsonField(table, "name") or_else nil)
        fmt.sbprintfln(&body, "    tables.%s = st.CacheTableAdd(cache, \"%s\", %d)", identifier(table_name, scratch), table_name, keySize(&g, table))
    }
    fmt.sbprintln(&body, "    return tables\n}\n")
    fmt.sbprintln(&body, "// Subscribes to every public table (`SELECT *` each); the cache then holds the whole database that this client may see")
    fmt.sbprintln(&body, "SubscribeAll :: proc(connection: ^st.Connection, query_set_id: u32) -> u32 {")
    fmt.sbprint(&body, "    queries: [")
    count: int
    for table in tables { if !jsonTableHidden(table) { count += 1 } }
    fmt.sbprintf(&body, "%d]string = {{", count)
    first: bool = true
    for table in tables {
        if jsonTableHidden(table) { continue }
        if !first { fmt.sbprint(&body, ", ") }
        first = false
        fmt.sbprintf(&body, "\"SELECT * FROM %s\"", jsonStr(jsonField(table, "name") or_else nil))
    }
    fmt.sbprintln(&body, "}")
    fmt.sbprintln(&body, "    return st.ConnectionSubscribe(connection, query_set_id, queries[:])\n}\n")

    // the reducers
    reducers_value, _ := jsonField(value, "reducers")
    for reducer in reducers_value.(json.Array) or_else nil {
        if _, lifecycle := jsonSome(jsonField(reducer, "lifecycle") or_else nil); lifecycle { continue }
        reducer_name: string = jsonStr(jsonField(reducer, "name") or_else nil)
        params, _ := jsonField(reducer, "params")
        elements, _ := jsonField(params, "elements")
        list: json.Array = elements.(json.Array) or_else nil
        fmt.sbprintf(&body, "Call%s :: proc(connection: ^st.Connection", pascal(reducer_name, scratch))
        for element, i in list {
            algebraic, _ := jsonField(element, "algebraic_type")
            fmt.sbprintf(&body, ", %s: %s", fieldName(&g, element, i), odinType(&g, algebraic))
        }
        fmt.sbprintln(&body, ") -> u32 {")
        fmt.sbprintfln(&body, "    buffer: [%d]u8", buffer_size)
        fmt.sbprintln(&body, "    writer: st.Writer = st.WriterMake(buffer[:])")
        for element, i in list {
            algebraic, _ := jsonField(element, "algebraic_type")
            fmt.sbprintfln(&body, "    %s(&writer, %s)", writeProc(&g, algebraic), fieldName(&g, element, i))
        }
        fmt.sbprintfln(&body, "    return st.ConnectionCallReducer(connection, \"%s\", st.WriterBytes(&writer))\n}}\n", reducer_name)
    }

    result: strings.Builder
    strings.builder_init(&result, allocator)
    fmt.sbprintfln(&result, "package %s\n", package_name)
    fmt.sbprintln(&result, "// Generated by spacetimedb/tool/generate from the schema of a database. Do not edit: generate it again when the module changes.\n")
    fmt.sbprintfln(&result, "import st \"%s\"\n", library)
    strings.write_string(&result, `// Timestamp and TimeDuration are i64 microseconds on the wire
readTimestamp :: proc(reader: ^st.Reader) -> st.Timestamp {
    return st.Timestamp(st.ReadI64(reader))
}

writeTimestamp :: proc(writer: ^st.Writer, value: st.Timestamp) {
    st.WriteI64(writer, i64(value))
}

readTimeDuration :: proc(reader: ^st.Reader) -> st.TimeDuration {
    return st.TimeDuration(st.ReadI64(reader))
}

writeTimeDuration :: proc(writer: ^st.Writer, value: st.TimeDuration) {
    st.WriteI64(writer, i64(value))
}

`)
    strings.write_string(&result, strings.to_string(g.out))
    strings.write_string(&result, strings.to_string(g.helpers))
    strings.write_string(&result, strings.to_string(body))
    return strings.to_string(result), true
}

@(private)
jsonTableHidden :: proc(table: json.Value) -> bool {
    access, _ := jsonField(table, "table_access")
    tag, _, _ := jsonTag(access)
    return tag == "Private"
}

// The bytes of the primary key at the start of a row, when the key is the first columns and all of them have a fixed size (0: the whole row is the key)
@(private)
keySize :: proc(g: ^Generator, table: json.Value) -> int {
    key, _ := jsonField(table, "primary_key")
    columns: json.Array = key.(json.Array) or_else nil
    if len(columns) == 0 { return 0 }
    index: int = jsonInt(jsonField(table, "product_type_ref") or_else nil)
    if index < 0 || index >= len(g.types) { return 0 }
    _, payload, _ := jsonTag(g.types[index])
    elements, _ := jsonField(payload, "elements")
    list: json.Array = elements.(json.Array) or_else nil
    total: int
    for column, position in columns {
        if jsonInt(column) != position || position >= len(list) { return 0 }
        algebraic, _ := jsonField(list[position], "algebraic_type")
        size: int = fixedSize(g, algebraic)
        if size == 0 { return 0 }
        total += size
    }
    return total
}
