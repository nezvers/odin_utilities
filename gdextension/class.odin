package gdextension

// A GDExtension in a few lines: describe classes (a name, a parent, methods with their argument and result kinds, how an instance is made and freed) and hand them to `Entry` from the
// `entry_symbol` of the library. GDScript then calls the methods; they are Odin procedures on plain values (an int, a bool, a String as UTF-8 bytes, a PackedByteArray as bytes).
//
//     @(export)
//     my_entry :: proc "c" (get: gdextension.GetProcAddress, library: gdextension.Library, initialization: ^gdextension.Initialization) -> u8 {
//         return gdextension.Entry(get, library, initialization, {&my_class})
//     }
//
//     my_class: gdextension.Class = {
//         name = "Counter", parent = "RefCounted",
//         create = proc() -> rawptr { return new(int) },
//         destroy = proc(instance: rawptr) { free(instance) },
//         methods = {
//             {"add", {.INT}, .INT, proc(instance: rawptr, a: []gdextension.Value) -> gdextension.Value {
//                 counter: ^int = cast(^int)instance
//                 counter^ += int(a[0].number)
//                 return {kind = .INT, number = i64(counter^)}
//             }},
//         },
//     }
//
// Godot calls a method in two ways: with Variants (untyped GDScript, `call_func`) and with the native types (typed code, `ptrcall_func`); both are made from the same row. Callbacks run
// with a default context whose temp allocator is freed after each call: a `Value.text` that a method returns has to live that long (a string of the instance, or temp memory).
//
// Signals, properties, virtual methods and other argument kinds are not here yet (TODO.md). The structs follow `gdextension_interface.h` of Godot 4.4 and later; see interface.odin.

import "base:runtime"

Library :: GdLibrary
Initialization :: GdInitialization
InitializationLevel :: GdInitializationLevel

ValueKind :: enum u8 {
    NONE,
    BOOL,
    INT,
    STRING,
    BYTES,                  // a PackedByteArray (the bytes are in `text`)
}

// An argument or a result. A string is UTF-8 bytes in `text`; a bool is `number` 0 or 1.
Value :: struct {
    kind: ValueKind,
    number: i64,
    text: []u8,
}

MAX_ARGUMENTS :: 6
ARGUMENT_TEXT :: 1 << 17        // the biggest String argument

Method :: struct {
    name: cstring,
    arguments: []ValueKind,
    result: ValueKind,
    call: proc(instance: rawptr, arguments: []Value) -> Value,
}

Class :: struct {
    name: cstring,
    parent: cstring,
    methods: []Method,
    create: proc() -> rawptr,       // the instance that goes with a new object (what the methods receive)
    destroy: proc(instance: rawptr),
    // made by Register
    name_id, parent_id: GdStringName,
    method_names: []GdStringName,
    method_infos: []GdMethodInfo,
    property_infos: [][MAX_ARGUMENTS + 1]GdPropertyInfo,
}

@(private)
registered: []^Class
@(private)
empty_name: GdStringName
@(private)
empty_string: GdString              // the hint of every property: Godot reads it, so it has to be a real String
@(private)
metadata: [MAX_ARGUMENTS]u32

@(private)
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
    answer: Value = method.call(instance, values[:len(method.arguments)])
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
    answer: Value = method.call(instance, values[:len(method.arguments)])
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
createInstance :: proc "c" (class_userdata: rawptr, notify_postinitialize: GdBool) -> GdObject {
    context = defaultContext()
    class: ^Class = cast(^Class)class_userdata
    object: GdObject = gd.construct_object(&class.parent_id)
    gd.object_set_instance(object, &class.name_id, class.create())
    return object
}

@(private)
freeInstance :: proc "c" (class_userdata: rawptr, instance: GdInstance) {
    context = defaultContext()
    class: ^Class = cast(^Class)class_userdata
    class.destroy(instance)
}

@(private)
registerClass :: proc "c" (class: ^Class) {
    context = defaultContext()
    class.name_id = stringName(class.name)
    class.parent_id = stringName(class.parent)
    info: GdClassInfo4 = {
        is_exposed = 1,
        create_instance_func = createInstance,
        free_instance_func = freeInstance,
        class_userdata = class,
    }
    gd.register_class(gd.library, &class.name_id, &class.parent_id, &info)
    count: int = len(class.methods)
    class.method_names = make([]GdStringName, count)
    class.method_infos = make([]GdMethodInfo, count)
    class.property_infos = make([][MAX_ARGUMENTS + 1]GdPropertyInfo, count)
    for &method, i in class.methods {
        assert(len(method.arguments) <= MAX_ARGUMENTS)
        class.method_names[i] = stringName(method.name)
        for kind, a in method.arguments {
            class.property_infos[i][a + 1] = {type = variantTypeOf(kind), name = &empty_name, class_name = &empty_name, hint_string = &empty_string, usage = 6}
        }
        class.property_infos[i][0] = {type = variantTypeOf(method.result), name = &empty_name, class_name = &empty_name, hint_string = &empty_string, usage = 6}
        class.method_infos[i] = {
            name = &class.method_names[i],
            method_userdata = &method,
            call_func = callMethod,
            ptrcall_func = ptrCallMethod,
            method_flags = 1,                                   // normal
            has_return_value = 1 if method.result != .NONE else 0,
            return_value_info = &class.property_infos[i][0] if method.result != .NONE else nil,
            argument_count = u32(len(method.arguments)),
            arguments_info = &class.property_infos[i][1] if len(method.arguments) > 0 else nil,
            arguments_metadata = raw_data(metadata[:]) if len(method.arguments) > 0 else nil,
        }
        gd.register_method(gd.library, &class.name_id, &class.method_infos[i])
    }
}

@(private)
initialize :: proc "c" (userdata: rawptr, level: GdInitializationLevel) {
    if level != .SCENE { return }
    context = defaultContext()
    empty_name = stringName("")
    gd.string_new_utf8(&empty_string, "")
    for class in registered { registerClass(class) }
}

@(private)
deinitialize :: proc "c" (userdata: rawptr, level: GdInitializationLevel) {
    if level != .SCENE { return }
    for class in registered { gd.unregister_class(gd.library, &class.name_id) }
}

// The body of the `entry_symbol` function: looks the interface up, and registers the classes when Godot reaches the scene level. Returns 1 (true) when the library can work with this Godot.
// `classes` has to live as long as the library (globals).
Entry :: proc "c" (get_proc_address: GetProcAddress, library: Library, initialization: ^Initialization, classes: []^Class) -> GdBool {
    if !interfaceLoad(get_proc_address, library) { return 0 }
    registered = classes
    initialization.minimum_initialization_level = .SCENE
    initialization.initialize = initialize
    initialization.deinitialize = deinitialize
    return 1
}

_ :: runtime
