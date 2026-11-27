package gdextension

// A GDExtension in a few lines: describe classes (a name, a parent, methods with their argument and result kinds, how an instance is made and freed) and hand them to `Entry` from the
// `entry_symbol` of the library. GDScript then calls the methods; they are Odin procedures on plain values (an int, a bool, a float, a String as UTF-8 bytes, a PackedByteArray as bytes, Vector2 and Vector3 as f64s).
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
// Signals: a class lists `signals` (a name and the kinds of the arguments); GDScript connects to them as to any signal (`obj.connected.connect(f)`). The class tells the engine with
// `Emit(object, "name", {values})`; it gets its `object` from `bind`, called once when the object is made (keep it in the instance). Emit runs the connected callables at once, on the
// calling thread, and the engine allows it from the thread of a method call (the main thread in GDScript).
//
// Virtual methods: `virtuals = {{"_process", proc(instance: rawptr, delta: f64) {...}}}` with a Node as `parent`: the engine calls them (a class that updates itself, no script that polls). A
// class can be made twice from one table of methods, once under RefCounted and once under Node (see `godot_spacetimedb/lobby.odin`).
//
// Objects and the engine: an OBJECT value is the engine's pointer, `Call(object, "Node", "get_child_count", 894402480, {})` calls an engine method (the hash is in extension_api.json). Properties: `properties = {{"total", .INT, "get", "set_total"}}` over methods of the class (see the template). Argument kinds: bool, Object (see Call), int, float, String, PackedByteArray, Vector2, Vector3, PackedInt64Array, PackedFloat64Array, PackedStringArray, Array and Dictionary (flat: their elements are bool, int, float or String; a Dictionary has String keys). Objects are not here yet (TODO.md). The structs follow `gdextension_interface.h` of Godot 4.4 and later; see interface.odin.

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
    FLOAT,                  // a float (`real[0]`, 64 bit)
    VECTOR2,                // `real[0..1]` (32 bit floats in the engine)
    VECTOR3,                // `real[0..2]`
    ARRAY,                  // `items`: bool, int, float and String elements (other elements come as NONE)
    OBJECT,                 // an Object of the engine (a Node, a Resource ...): `object`, nil for null
    PACKED_INTS,            // a PackedInt64Array: `ints`
    PACKED_FLOATS,          // a PackedFloat64Array: `floats`
    PACKED_STRINGS,         // a PackedStringArray: `items` (kind STRING each)
    DICTIONARY,             // `keys` (Strings) and `items`, same length: bool, int, float and String values
    PACKED_INT32S,          // a PackedInt32Array: `ints32`
    PACKED_FLOAT32S,        // a PackedFloat32Array: `floats32`
    PACKED_VECTOR2S,        // a PackedVector2Array: `floats32`, x and y of every element one after the other
    PACKED_VECTOR3S,        // a PackedVector3Array: `floats32`, x, y, z
    PACKED_COLORS,          // a PackedColorArray: `floats32`, r, g, b, a
}

// An argument or a result. A string is UTF-8 bytes in `text`; a bool is `number` 0 or 1.
Value :: struct {
    kind: ValueKind,
    number: i64,
    text: []u8,
    real: [4]f64,
    items: []Value,             // an ARRAY, or the values of a DICTIONARY
    keys: []Value,              // the keys of a DICTIONARY (kind STRING)
    object: rawptr,             // OBJECT: the engine's pointer; it stays the engine's, keep it only as long as the engine keeps the object
    ints: []i64,                // PACKED_INTS
    floats: []f64,              // PACKED_FLOATS
    ints32: []i32,              // PACKED_INT32S
    floats32: []f32,            // PACKED_FLOAT32S, PACKED_VECTOR2S, PACKED_VECTOR3S, PACKED_COLORS: the components of the elements one after the other (32 bit floats, as the engine has them)
}

// The results of a method, one line each: `ValueText` keeps the bytes of the string until the call ends (a string of the instance or temp memory)
ValueText :: proc "contextless" (text: string) -> Value {
    return {kind = .STRING, text = transmute([]u8)text}
}

ValueInt :: proc "contextless" (number: i64) -> Value {
    return {kind = .INT, number = number}
}

ValueFloat :: proc "contextless" (number: f64) -> Value {
    return {kind = .FLOAT, real = {number, 0, 0, 0}}
}

ValueVector2 :: proc "contextless" (x, y: f64) -> Value {
    return {kind = .VECTOR2, real = {x, y, 0, 0}}
}

ValueVector3 :: proc "contextless" (x, y, z: f64) -> Value {
    return {kind = .VECTOR3, real = {x, y, z, 0}}
}

ValueArray :: proc "contextless" (items: []Value) -> Value {
    return {kind = .ARRAY, items = items}
}

ValueDictionary :: proc "contextless" (keys: []Value, items: []Value) -> Value {
    assert_contextless(len(keys) == len(items))
    return {kind = .DICTIONARY, keys = keys, items = items}
}

ValueObject :: proc "contextless" (object: rawptr) -> Value {
    return {kind = .OBJECT, object = object}
}

ValueBool :: proc "contextless" (flag: bool) -> Value {
    return {kind = .BOOL, number = 1 if flag else 0}
}

MAX_ARGUMENTS :: 6
ARGUMENT_TEXT :: 1 << 17        // the biggest String argument

Method :: struct {
    name: cstring,
    arguments: []ValueKind,
    result: ValueKind,
    call: proc(instance: rawptr, arguments: []Value) -> Value,
}

Signal :: struct {
    name: cstring,
    arguments: []ValueKind,
}

// A virtual method of the parent that the class overrides: `_ready`, `_enter_tree`, `_exit_tree` (no argument), `_process`, `_physics_process` (the delta in seconds). Only these five,
// the parent has to be a Node (or a class below it) for the engine to call them.
Virtual :: struct {
    name: cstring,
    call: proc(instance: rawptr, delta: f64),
}

// A property of the class (the inspector shows it, GDScript reads and writes it as `object.name`): its getter and setter are methods of the class, found by name (`getter` takes no argument and
// returns `kind`, `setter` takes one argument of `kind`). A property that is read only has no `setter`.
Property :: struct {
    name: cstring,
    kind: ValueKind,
    getter: cstring,
    setter: cstring,
}

Class :: struct {
    name: cstring,
    parent: cstring,
    methods: []Method,
    signals: []Signal,
    properties: []Property,
    virtuals: []Virtual,
    bind: proc(instance: rawptr, object: rawptr),   // optional: gets the engine object of a new instance, for `Emit`
    create: proc() -> rawptr,       // the instance that goes with a new object (what the methods receive)
    destroy: proc(instance: rawptr),
    // made by Register
    name_id, parent_id: GdStringName,
    method_names: []GdStringName,
    method_infos: []GdMethodInfo,
    signal_names: []GdStringName,
    property_names: []GdStringName,    // name, getter, setter of each property: three entries
    virtual_names: []GdStringName,
    signal_infos: [][MAX_ARGUMENTS]GdPropertyInfo,
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
    case .FLOAT: return .FLOAT
    case .VECTOR2: return .VECTOR2
    case .VECTOR3: return .VECTOR3
    case .ARRAY: return .ARRAY
    case .DICTIONARY: return .DICTIONARY
    case .OBJECT: return .OBJECT
    case .PACKED_INTS: return .PACKED_INT64_ARRAY
    case .PACKED_FLOATS: return .PACKED_FLOAT64_ARRAY
    case .PACKED_STRINGS: return .PACKED_STRING_ARRAY
    case .PACKED_INT32S: return .PACKED_INT32_ARRAY
    case .PACKED_FLOAT32S: return .PACKED_FLOAT32_ARRAY
    case .PACKED_VECTOR2S: return .PACKED_VECTOR2_ARRAY
    case .PACKED_VECTOR3S: return .PACKED_VECTOR3_ARRAY
    case .PACKED_COLORS: return .PACKED_COLOR_ARRAY
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
        case .FLOAT:
            gd.to_float(&values[i].real[0], variant)
        case .VECTOR2:
            native: [2]f32
            gd.to_vector2(&native, variant)
            values[i].real = {f64(native[0]), f64(native[1]), 0, 0}
        case .VECTOR3:
            native: [3]f32
            gd.to_vector3(&native, variant)
            values[i].real = {f64(native[0]), f64(native[1]), f64(native[2]), 0}
        case .ARRAY:
            array: GdArray
            gd.to_array(&array, variant)
            values[i].items = readArray(&array, context.temp_allocator)
            gd.array_destroy(&array)
        case .DICTIONARY:
            dictionary: GdArray
            gd.to_dictionary(&dictionary, variant)
            values[i].keys, values[i].items = readDictionary(&dictionary, context.temp_allocator)
            gd.dictionary_destroy(&dictionary)
        case .OBJECT:
            gd.to_object(&values[i].object, variant)
        case .PACKED_INTS:
            array: GdBytes
            gd.packed_ints.to(&array, variant)
            values[i].ints = readPackedInts(&array, context.temp_allocator)
            gd.packed_ints.destroy(&array)
        case .PACKED_FLOATS:
            array: GdBytes
            gd.packed_floats.to(&array, variant)
            values[i].floats = readPackedFloats(&array, context.temp_allocator)
            gd.packed_floats.destroy(&array)
        case .PACKED_STRINGS:
            array: GdBytes
            gd.packed_strings.to(&array, variant)
            values[i].items = readPackedStrings(&array, context.temp_allocator)
            gd.packed_strings.destroy(&array)
        case .PACKED_INT32S, .PACKED_FLOAT32S, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS:
            ops, _ := packedOpsOf(kind)
            array: GdBytes
            ops.to(&array, variant)
            values[i] = readPackedNumeric(kind, &array, context.temp_allocator)
            ops.destroy(&array)
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
    case .FLOAT: variantFloat(result, answer.real[0])
    case .VECTOR2: variantVector2(result, answer.real)
    case .VECTOR3: variantVector3(result, answer.real)
    case .ARRAY: variantArray(result, answer.items)
    case .DICTIONARY: variantDictionary(result, answer.keys, answer.items)
    case .OBJECT: variantObject(result, answer.object)
    case .PACKED_INTS: variantPackedInts(result, answer.ints)
    case .PACKED_FLOATS: variantPackedFloats(result, answer.floats)
    case .PACKED_STRINGS: variantPackedStrings(result, answer.items)
    case .PACKED_INT32S, .PACKED_FLOAT32S, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS: variantPackedNumeric(result, method.result, answer)
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
        case .FLOAT: values[i].real[0] = (cast(^f64)args[i])^
        case .VECTOR2:
            native: ^[2]f32 = cast(^[2]f32)args[i]
            values[i].real = {f64(native[0]), f64(native[1]), 0, 0}
        case .VECTOR3:
            native: ^[3]f32 = cast(^[3]f32)args[i]
            values[i].real = {f64(native[0]), f64(native[1]), f64(native[2]), 0}
        case .ARRAY: values[i].items = readArray(args[i], context.temp_allocator)
        case .DICTIONARY: values[i].keys, values[i].items = readDictionary(args[i], context.temp_allocator)
        case .OBJECT: values[i].object = (cast(^rawptr)args[i])^
        case .PACKED_INTS: values[i].ints = readPackedInts(args[i], context.temp_allocator)
        case .PACKED_FLOATS: values[i].floats = readPackedFloats(args[i], context.temp_allocator)
        case .PACKED_STRINGS: values[i].items = readPackedStrings(args[i], context.temp_allocator)
        case .PACKED_INT32S, .PACKED_FLOAT32S, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS: values[i] = readPackedNumeric(kind, args[i], context.temp_allocator)
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
    case .FLOAT: (cast(^f64)result)^ = answer.real[0]
    case .VECTOR2: (cast(^[2]f32)result)^ = {f32(answer.real[0]), f32(answer.real[1])}
    case .VECTOR3: (cast(^[3]f32)result)^ = {f32(answer.real[0]), f32(answer.real[1]), f32(answer.real[2])}
    case .ARRAY:
        gd.array_construct(result, nil)
        writeArray(result, answer.items)
    case .DICTIONARY:
        gd.dictionary_construct(result, nil)
        writeDictionary(result, answer.keys, answer.items)
    case .OBJECT: (cast(^rawptr)result)^ = answer.object
    case .PACKED_INTS:
        gd.packed_ints.construct(result, nil)
        writePackedInts(result, answer.ints)
    case .PACKED_FLOATS:
        gd.packed_floats.construct(result, nil)
        writePackedFloats(result, answer.floats)
    case .PACKED_STRINGS:
        gd.packed_strings.construct(result, nil)
        writePackedStrings(result, answer.items)
    case .PACKED_INT32S, .PACKED_FLOAT32S, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS:
        ops, _ := packedOpsOf(method.result)
        ops.construct(result, nil)
        writePackedNumeric(method.result, result, answer)
    }
    free_all(context.temp_allocator)
}

@(private)
createInstance :: proc "c" (class_userdata: rawptr, notify_postinitialize: GdBool) -> GdObject {
    context = defaultContext()
    class: ^Class = cast(^Class)class_userdata
    object: GdObject = gd.construct_object(&class.parent_id)
    instance: rawptr = class.create()
    gd.object_set_instance(object, &class.name_id, instance)
    if class.bind != nil { class.bind(instance, object) }
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
        get_virtual_call_data_func = getVirtualData if len(class.virtuals) > 0 else nil,
        call_virtual_with_data_func = callVirtual if len(class.virtuals) > 0 else nil,
        free_instance_func = freeInstance,
        class_userdata = class,
    }
    gd.register_class(gd.library, &class.name_id, &class.parent_id, &info)
    class.virtual_names = make([]GdStringName, len(class.virtuals))
    for virtual, i in class.virtuals { class.virtual_names[i] = stringName(virtual.name) }
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
    class.property_names = make([]GdStringName, len(class.properties) * 3)
    for property, i in class.properties {
        class.property_names[i * 3] = stringName(property.name)
        class.property_names[i * 3 + 1] = stringName(property.getter)
        class.property_names[i * 3 + 2] = stringName(property.setter if property.setter != nil else "")
        info: GdPropertyInfo = {type = variantTypeOf(property.kind), name = &class.property_names[i * 3], class_name = &empty_name, hint_string = &empty_string, usage = 6}
        gd.register_property(gd.library, &class.name_id, &info, &class.property_names[i * 3 + 2], &class.property_names[i * 3 + 1])
    }
    class.signal_names = make([]GdStringName, len(class.signals))
    class.signal_infos = make([][MAX_ARGUMENTS]GdPropertyInfo, len(class.signals))
    for signal, i in class.signals {
        assert(len(signal.arguments) <= MAX_ARGUMENTS)
        class.signal_names[i] = stringName(signal.name)
        for kind, a in signal.arguments {
            class.signal_infos[i][a] = {type = variantTypeOf(kind), name = &empty_name, class_name = &empty_name, hint_string = &empty_string, usage = 6}
        }
        gd.register_signal(gd.library, &class.name_id, &class.signal_names[i], raw_data(class.signal_infos[i][:]), GdInt(len(signal.arguments)))
    }
}

// Calls a method of an engine object: `class` is the class that declares the method ("Node"), `hash` the one of extension_api.json for that method. The arguments and the result are Values
// (a result of another kind than the ones of ValueKind comes back as NONE); the text of a result lives in the temp allocator. Method binds are looked up once and kept (64 of them): the
// strings `class` and `method` should be literals (the cache compares their addresses). False when the engine refused the call (wrong argument kinds, a freed object).
Call :: proc(object: rawptr, class: cstring, method: cstring, hash: i64, arguments: []Value) -> (result: Value, ok: bool) {
    assert(len(arguments) <= MAX_ARGUMENTS)
    bind: rawptr = methodBind(class, method, hash)
    if bind == nil { return {}, false }
    variants: [MAX_ARGUMENTS]GdVariant
    pointers: [MAX_ARGUMENTS]^GdVariant
    for value, i in arguments {
        valueToVariant(&variants[i], value)
        pointers[i] = &variants[i]
    }
    answer: GdVariant
    error: GdCallError
    gd.method_bind_call(bind, object, raw_data(pointers[:]), GdInt(len(arguments)), &answer, &error)
    result = variantToValue(&answer, context.temp_allocator)
    gd.variant_destroy(&answer)
    for i in 0 ..< len(arguments) { gd.variant_destroy(&variants[i]) }
    return result, error.error == .OK
}

@(private)
BindEntry :: struct {
    class, method: cstring,
    hash: i64,
    bind: rawptr,
}

@(private)
binds: [64]BindEntry
@(private)
bind_count: int

@(private)
methodBind :: proc(class: cstring, method: cstring, hash: i64) -> rawptr {
    for i in 0 ..< bind_count {
        entry: ^BindEntry = &binds[i]
        if entry.class == class && entry.method == method && entry.hash == hash { return entry.bind }
    }
    class_name: GdStringName = stringName(class)
    method_name: GdStringName = stringName(method)
    bind: rawptr = gd.get_method_bind(&class_name, &method_name, GdInt(hash))
    if bind != nil && bind_count < len(binds) {
        binds[bind_count] = {class, method, hash, bind}
        bind_count += 1
    }
    return bind
}

// Emits a signal of an object (`object` is what `bind` gave): the connected callables run before it returns. False when the engine refused the call.
Emit :: proc(object: rawptr, signal: cstring, arguments: []Value) -> bool {
    assert(len(arguments) <= MAX_ARGUMENTS)
    name: GdStringName = stringName(signal)
    variants: [MAX_ARGUMENTS + 1]GdVariant
    pointers: [MAX_ARGUMENTS + 1]^GdVariant
    gd.from_string_name(&variants[0], &name)
    gd.destroy_string_name(&name)
    pointers[0] = &variants[0]
    for value, i in arguments {
        switch value.kind {
        case .INT: variantInt(&variants[i + 1], value.number)
        case .BOOL: variantBool(&variants[i + 1], value.number != 0)
        case .STRING: variantString(&variants[i + 1], value.text)
        case .BYTES: variantBytes(&variants[i + 1], value.text)
        case .FLOAT: variantFloat(&variants[i + 1], value.real[0])
        case .VECTOR2: variantVector2(&variants[i + 1], value.real)
        case .VECTOR3: variantVector3(&variants[i + 1], value.real)
        case .ARRAY: variantArray(&variants[i + 1], value.items)
        case .DICTIONARY: variantDictionary(&variants[i + 1], value.keys, value.items)
        case .OBJECT: variantObject(&variants[i + 1], value.object)
        case .PACKED_INTS: variantPackedInts(&variants[i + 1], value.ints)
        case .PACKED_FLOATS: variantPackedFloats(&variants[i + 1], value.floats)
        case .PACKED_STRINGS: variantPackedStrings(&variants[i + 1], value.items)
        case .PACKED_INT32S, .PACKED_FLOAT32S, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS: variantPackedNumeric(&variants[i + 1], value.kind, value)
        case .NONE:
        }
        pointers[i + 1] = &variants[i + 1]
    }
    result: GdVariant
    error: GdCallError
    gd.method_bind_call(gd.emit_signal_bind, object, raw_data(pointers[:]), GdInt(len(arguments) + 1), &result, &error)
    gd.variant_destroy(&result)
    for i in 0 ..< len(arguments) + 1 { gd.variant_destroy(&variants[i]) }
    return error.error == .OK
}

// The engine asks for a virtual by name; the Virtual row is the data it gives back when it calls. Nil: not overridden.
@(private)
getVirtualData :: proc "c" (class_userdata: rawptr, name: ^GdStringName, hash: u32) -> rawptr {
    class: ^Class = cast(^Class)class_userdata
    for i in 0 ..< len(class.virtuals) {
        if class.virtual_names[i][0] == name[0] { return &class.virtuals[i] }      // StringNames are interned: the same text is the same pointer
    }
    return nil
}

@(private)
callVirtual :: proc "c" (instance: GdInstance, name: ^GdStringName, call_data: rawptr, args: [^]rawptr, result: rawptr) {
    context = defaultContext()
    virtual: ^Virtual = cast(^Virtual)call_data
    delta: f64
    if args != nil { delta = (cast(^f64)args[0])^ }       // `_process` and `_physics_process` are the ones with an argument
    virtual.call(instance, delta)
    free_all(context.temp_allocator)
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
