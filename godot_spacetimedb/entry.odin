package godot_spacetimedb

// The entry point that Godot calls when it loads the library (`entry_symbol` of the .gdextension file) and the registration of the class `SpacetimeDBClient` (a RefCounted: GDScript makes
// it with `SpacetimeDBClient.new()` and polls it). Its methods are a table: a name, the types of the arguments and of the result, and an Odin procedure on plain values. Two adapters turn
// that into the two ways Godot calls a method: with Variants (`call_func`, what untyped GDScript does) and with the native types (`ptrcall_func`, what typed code does).

import "base:runtime"
import "core:strings"

CLASS_NAME :: "SpacetimeDBClient"
PARENT_NAME :: "RefCounted"

ValueKind :: enum u8 {
    NONE,
    BOOL,
    INT,
    STRING,
    BYTES,                  // a PackedByteArray (the bytes are in `text`)
}

Value :: struct {
    kind: ValueKind,
    number: i64,
    text: []u8,
}

MAX_ARGUMENTS :: 4
ARGUMENT_TEXT :: 1 << 17        // the biggest String argument (the arguments of a reducer in hex)

Method :: struct {
    name: cstring,
    arguments: []ValueKind,
    result: ValueKind,
    call: proc(client: ^Client, arguments: []Value) -> Value,
}

class_name: GdStringName
parent_name: GdStringName

@(private)
method_names: [32]GdStringName
@(private)
method_infos: [32]GdMethodInfo
@(private)
property_infos: [32][MAX_ARGUMENTS + 1]GdPropertyInfo
@(private)
empty_name: GdStringName
@(private)
empty_string: GdString              // the hint of every property: Godot reads it, so it has to be a real String
@(private)
metadata: [MAX_ARGUMENTS]u32

variantTypeOf :: proc "contextless" (kind: ValueKind) -> GdVariantType {
    switch kind {
    case .BOOL: return .BOOL
    case .INT: return .INT
    case .STRING: return .STRING
    case .BYTES: return .PACKED_BYTE_ARRAY
    case .NONE: return .NIL
    }
    return .NIL
}

// The Variant call: the arguments are Variants, converted to values; the result goes back into a Variant
@(private)
callMethod :: proc "c" (userdata: rawptr, instance: GdInstance, args: [^]rawptr, argument_count: GdInt, result: ^GdVariant, error: ^GdCallError) {
    context = defaultContext()
    method: ^Method = cast(^Method)userdata
    if int(argument_count) < len(method.arguments) {
        error.error, error.expected = .TOO_FEW_ARGUMENTS, i32(len(method.arguments))
        return
    }
    values: [MAX_ARGUMENTS]Value
    for kind, i in method.arguments {
        variant: ^GdVariant = cast(^GdVariant)args[i]
        if gd.variant_get_type(variant) != variantTypeOf(kind) {
            error.error, error.argument, error.expected = .INVALID_ARGUMENT, i32(i), i32(variantTypeOf(kind))
            return
        }
        switch kind {
        case .INT:
            gd.to_int(&values[i].number, variant)
        case .BOOL:
            flag: GdBool
            gd.to_bool(&flag, variant)
            values[i].number = i64(flag)
        case .STRING:
            string_value: GdString
            gd.to_string(&string_value, variant)
            buffer: []u8 = make([]u8, ARGUMENT_TEXT, context.temp_allocator)
            values[i].text = buffer[:stringRead(&string_value, buffer)]
            gd.destroy_string(&string_value)
        case .BYTES:
            array: GdBytes
            gd.to_bytes(&array, variant)
            values[i].text = readBytes(&array, context.temp_allocator)
            gd.bytes_destroy(&array)
        case .NONE:
        }
        values[i].kind = kind
    }
    answer: Value = method.call(clientOf(instance), values[:len(method.arguments)])
    switch method.result {
    case .NONE:
    case .BOOL: variantBool(result, answer.number != 0)
    case .INT: variantInt(result, answer.number)
    case .STRING: variantString(result, answer.text)
    case .BYTES: variantBytes(result, answer.text)
    }
    free_all(context.temp_allocator)
}

// The native call: the arguments and the result are the engine's own types
@(private)
ptrCallMethod :: proc "c" (userdata: rawptr, instance: GdInstance, args: [^]rawptr, result: rawptr) {
    context = defaultContext()
    method: ^Method = cast(^Method)userdata
    values: [MAX_ARGUMENTS]Value
    for kind, i in method.arguments {
        switch kind {
        case .INT: values[i].number = (cast(^i64)args[i])^
        case .BOOL: values[i].number = i64((cast(^GdBool)args[i])^)
        case .STRING:
            buffer: []u8 = make([]u8, ARGUMENT_TEXT, context.temp_allocator)
            values[i].text = buffer[:stringRead(cast(^GdString)args[i], buffer)]
        case .BYTES: values[i].text = readBytes(args[i], context.temp_allocator)
        case .NONE:
        }
        values[i].kind = kind
    }
    answer: Value = method.call(clientOf(instance), values[:len(method.arguments)])
    switch method.result {
    case .NONE:
    case .BOOL: (cast(^GdBool)result)^ = 1 if answer.number != 0 else 0
    case .INT: (cast(^i64)result)^ = answer.number
    case .STRING: nativeString(result, answer.text)
    case .BYTES: makeBytes(result, answer.text)
    }
    free_all(context.temp_allocator)
}

@(private)
clientOf :: proc "contextless" (instance: GdInstance) -> ^Client {
    return cast(^Client)instance
}

@(private)
createInstance :: proc "c" (class_userdata: rawptr, notify_postinitialize: GdBool) -> GdObject {
    context = defaultContext()
    object: GdObject = gd.construct_object(&parent_name)
    client: ^Client = new(Client)
    client.current = -1
    gd.object_set_instance(object, &class_name, client)
    return object
}

@(private)
freeInstance :: proc "c" (class_userdata: rawptr, instance: GdInstance) {
    context = defaultContext()
    clientFree(clientOf(instance))
}

@(private)
registerClass :: proc "c" () {
    context = defaultContext()
    class_name = stringName(CLASS_NAME)
    parent_name = stringName(PARENT_NAME)
    empty_name = stringName("")
    gd.string_new_utf8(&empty_string, "")
    info: GdClassInfo4 = {
        is_exposed = 1,
        create_instance_func = createInstance,
        free_instance_func = freeInstance,
    }
    gd.register_class(gd.library, &class_name, &parent_name, &info)
    for &method, i in methods {
        method_names[i] = stringName(method.name)
        for kind, a in method.arguments {
            property_infos[i][a + 1] = {type = variantTypeOf(kind), name = &empty_name, class_name = &empty_name, hint_string = &empty_string, usage = 6}
        }
        property_infos[i][0] = {type = variantTypeOf(method.result), name = &empty_name, class_name = &empty_name, hint_string = &empty_string, usage = 6}
        method_infos[i] = {
            name = &method_names[i],
            method_userdata = &method,
            call_func = callMethod,
            ptrcall_func = ptrCallMethod,
            method_flags = 1,                                   // normal
            has_return_value = 1 if method.result != .NONE else 0,
            return_value_info = &property_infos[i][0] if method.result != .NONE else nil,
            argument_count = u32(len(method.arguments)),
            arguments_info = &property_infos[i][1] if len(method.arguments) > 0 else nil,
            arguments_metadata = raw_data(metadata[:]) if len(method.arguments) > 0 else nil,
        }
        gd.register_method(gd.library, &class_name, &method_infos[i])
    }
}

@(private)
initialize :: proc "c" (userdata: rawptr, level: GdInitializationLevel) {
    if level == .SCENE { registerClass() }
}

@(private)
deinitialize :: proc "c" (userdata: rawptr, level: GdInitializationLevel) {
    if level == .SCENE { gd.unregister_class(gd.library, &class_name) }
}

// `entry_symbol` of the .gdextension file
@(export)
spacetimedb_entry :: proc "c" (get_proc_address: GetProcAddress, library: GdLibrary, initialization: ^GdInitialization) -> GdBool {
    if !interfaceLoad(get_proc_address, library) { return 0 }
    initialization.minimum_initialization_level = .SCENE
    initialization.initialize = initialize
    initialization.deinitialize = deinitialize
    return 1
}

// ---- the methods -------------------------------------------------------------------------------------------------------------------------------------------------

@(private)
textOf :: proc(text: string) -> Value {
    return {kind = .STRING, text = transmute([]u8)text}
}

@(private)
intOf :: proc(number: i64) -> Value {
    return {kind = .INT, number = number}
}

@(private)
boolOf :: proc(value: bool) -> Value {
    return {kind = .BOOL, number = 1 if value else 0}
}

@(private)
spanText :: proc(client: ^Client, span: Span) -> Value {
    return {kind = .STRING, text = spanBytes(client, span)}
}

METHOD_COUNT :: 17

methods: [METHOD_COUNT]Method = {
    {"open", {.STRING, .INT, .STRING, .STRING}, .BOOL, proc(client: ^Client, a: []Value) -> Value {
        return boolOf(clientOpen(client, string(a[0].text), int(a[1].number), string(a[2].text), string(a[3].text)))
    }},
    {"close", {}, .NONE, proc(client: ^Client, a: []Value) -> Value {
        clientClose(client)
        return {}
    }},
    {"is_open", {}, .BOOL, proc(client: ^Client, a: []Value) -> Value { return boolOf(client.open) }},
    {"subscribe", {.STRING}, .INT, proc(client: ^Client, a: []Value) -> Value { return intOf(i64(clientSubscribe(client, string(a[0].text)))) }},
    {"call_reducer", {.STRING, .STRING}, .INT, proc(client: ^Client, a: []Value) -> Value {
        return intOf(i64(clientCallReducer(client, string(a[0].text), string(a[1].text))))
    }},
    {"call_reducer_bytes", {.STRING, .BYTES}, .INT, proc(client: ^Client, a: []Value) -> Value {
        return intOf(i64(clientCallReducerBytes(client, string(a[0].text), a[1].text)))
    }},
    {"event_row_bytes", {}, .BYTES, proc(client: ^Client, a: []Value) -> Value {
        hex: []u8 = spanBytes(client, clientEvent(client).row)
        raw: []u8 = make([]u8, len(hex) / 2, context.temp_allocator)
        count, _ := hexDecode(hex, raw)
        return {kind = .BYTES, text = raw[:count]}
    }},
    {"poll", {}, .INT, proc(client: ^Client, a: []Value) -> Value { return intOf(i64(clientPoll(client))) }},
    {"next_event", {}, .BOOL, proc(client: ^Client, a: []Value) -> Value { return boolOf(clientNextEvent(client)) }},
    {"event_kind", {}, .INT, proc(client: ^Client, a: []Value) -> Value { return intOf(i64(clientEvent(client).kind)) }},
    {"event_request", {}, .INT, proc(client: ^Client, a: []Value) -> Value { return intOf(i64(clientEvent(client).request)) }},
    {"event_ok", {}, .BOOL, proc(client: ^Client, a: []Value) -> Value { return boolOf(clientEvent(client).ok) }},
    {"event_table", {}, .STRING, proc(client: ^Client, a: []Value) -> Value { return spanText(client, clientEvent(client).table) }},
    {"event_row", {}, .STRING, proc(client: ^Client, a: []Value) -> Value { return spanText(client, clientEvent(client).row) }},
    {"event_text", {}, .STRING, proc(client: ^Client, a: []Value) -> Value { return spanText(client, clientEvent(client).text) }},
    {"token", {}, .STRING, proc(client: ^Client, a: []Value) -> Value { return textOf(spacetimedb_token(client)) }},
    {"error", {}, .STRING, proc(client: ^Client, a: []Value) -> Value { return textOf(client.error) }},
}

@(private)
spacetimedb_token :: proc(client: ^Client) -> string {
    return strings.clone(string(client.connection.token[:client.connection.token_length]), context.temp_allocator)
}

_ :: runtime
