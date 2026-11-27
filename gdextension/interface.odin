package gdextension

// The part of the GDExtension C interface (godot_api/gdextension_interface.h, written by `godot --dump-gdextension-interface`) that this library uses: a class registered with methods that
// GDScript calls, strings and integers in both directions. Godot hands the extension one function, `get_proc_address`, and everything else is looked up by name from it. Only the handful of
// functions below are looked up; the layouts of the structs are those of the header of Godot 4.4 and later (the class is registered with `classdb_register_extension_class4`, which every
// version since 4.4 keeps).

import "base:runtime"

GdBool :: u8
GdInt :: i64
GdObject :: rawptr
GdInstance :: rawptr
GdLibrary :: rawptr
GdVariant :: [3]u64                 // a Variant is 24 bytes
GdString :: [1]u64                  // a String and a StringName are one pointer
GdBytes :: [2]u64                   // a PackedByteArray is a pointer and a reference count
GdStringName :: [1]u64
GdArray :: [1]u64                   // an Array and a Dictionary are one pointer

VARIANT_TYPE_COUNT :: 40

GdVariantType :: enum u32 {
    NIL = 0,
    BOOL = 1,
    INT = 2,
    FLOAT = 3,
    STRING = 4,
    VECTOR2 = 5,
    VECTOR2I = 6,
    RECT2 = 7,
    RECT2I = 8,
    VECTOR3 = 9,
    VECTOR3I = 10,
    TRANSFORM2D = 11,
    VECTOR4 = 12,
    VECTOR4I = 13,
    PLANE = 14,
    QUATERNION = 15,
    AABB = 16,
    BASIS = 17,
    TRANSFORM3D = 18,
    PROJECTION = 19,
    COLOR = 20,
    STRING_NAME = 21,
    NODE_PATH = 22,
    OBJECT = 24,
    DICTIONARY = 27,
    ARRAY = 28,
    PACKED_BYTE_ARRAY = 29,
    PACKED_INT32_ARRAY = 30,
    PACKED_INT64_ARRAY = 31,
    PACKED_FLOAT32_ARRAY = 32,
    PACKED_FLOAT64_ARRAY = 33,
    PACKED_STRING_ARRAY = 34,
    PACKED_VECTOR2_ARRAY = 35,
    PACKED_VECTOR3_ARRAY = 36,
    PACKED_COLOR_ARRAY = 37,
}

GdCallErrorType :: enum i32 {
    OK = 0,
    INVALID_METHOD = 1,
    INVALID_ARGUMENT = 2,
    TOO_MANY_ARGUMENTS = 3,
    TOO_FEW_ARGUMENTS = 4,
    INSTANCE_IS_NULL = 5,
    METHOD_NOT_CONST = 6,
}

GdCallError :: struct {
    error: GdCallErrorType,
    argument: i32,
    expected: i32,
}

GdPropertyInfo :: struct {
    type: GdVariantType,
    name: ^GdStringName,
    class_name: ^GdStringName,
    hint: u32,
    hint_string: ^GdString,
    usage: u32,
}

GdInitializationLevel :: enum u32 {
    CORE = 0,
    SERVERS = 1,
    SCENE = 2,
    EDITOR = 3,
}

GdInitialization :: struct {
    minimum_initialization_level: GdInitializationLevel,
    userdata: rawptr,
    initialize: proc "c" (userdata: rawptr, level: GdInitializationLevel),
    deinitialize: proc "c" (userdata: rawptr, level: GdInitializationLevel),
}

GdMethodCall :: #type proc "c" (method_userdata: rawptr, instance: GdInstance, args: [^]rawptr, argument_count: GdInt, result: ^GdVariant, error: ^GdCallError)
GdMethodPtrCall :: #type proc "c" (method_userdata: rawptr, instance: GdInstance, args: [^]rawptr, result: rawptr)

GdMethodInfo :: struct {
    name: ^GdStringName,
    method_userdata: rawptr,
    call_func: GdMethodCall,
    ptrcall_func: GdMethodPtrCall,
    method_flags: u32,
    has_return_value: GdBool,
    return_value_info: ^GdPropertyInfo,
    return_value_metadata: u32,
    argument_count: u32,
    arguments_info: [^]GdPropertyInfo,
    arguments_metadata: [^]u32,
    default_argument_count: u32,
    default_arguments: [^]^GdVariant,
}

GdClassInfo4 :: struct {
    is_virtual: GdBool,
    is_abstract: GdBool,
    is_exposed: GdBool,
    is_runtime: GdBool,
    icon_path: rawptr,
    set_func: rawptr,
    get_func: rawptr,
    get_property_list_func: rawptr,
    free_property_list_func: rawptr,
    property_can_revert_func: rawptr,
    property_get_revert_func: rawptr,
    validate_property_func: rawptr,
    notification_func: rawptr,
    to_string_func: rawptr,
    reference_func: rawptr,
    unreference_func: rawptr,
    create_instance_func: proc "c" (class_userdata: rawptr, notify_postinitialize: GdBool) -> GdObject,
    free_instance_func: proc "c" (class_userdata: rawptr, instance: GdInstance),
    recreate_instance_func: rawptr,
    get_virtual_func: rawptr,
    get_virtual_call_data_func: proc "c" (class_userdata: rawptr, name: ^GdStringName, hash: u32) -> rawptr,
    call_virtual_with_data_func: proc "c" (instance: GdInstance, name: ^GdStringName, call_data: rawptr, args: [^]rawptr, result: rawptr),
    class_userdata: rawptr,
}

// What one packed array type needs (each type has its own `size` and `resize` functions: the ones of PackedByteArray do not work on the others)
PackedOps :: struct {
    type: GdVariantType,
    size: proc "c" (array: rawptr, args: [^]rawptr, result: rawptr, count: i32),
    resize: proc "c" (array: rawptr, args: [^]rawptr, result: rawptr, count: i32),
    construct: proc "c" (array: rawptr, args: [^]rawptr),
    destroy: proc "c" (array: rawptr),
    from: proc "c" (variant: ^GdVariant, value: rawptr),
    to: proc "c" (value: rawptr, variant: ^GdVariant),
    index: proc "c" (array: rawptr, index: GdInt) -> rawptr,
    index_const: proc "c" (array: rawptr, index: GdInt) -> rawptr,
}

// What is looked up from get_proc_address once, when the extension starts
Interface :: struct {
    library: GdLibrary,
    string_name_new: proc "c" (dest: ^GdStringName, chars: cstring, is_static: GdBool),
    string_new_utf8: proc "c" (dest: ^GdString, chars: cstring),
    string_new_utf8_len: proc "c" (dest: ^GdString, chars: [^]u8, size: GdInt) -> GdInt,
    string_to_utf8: proc "c" (source: ^GdString, buffer: [^]u8, max: GdInt) -> GdInt,
    variant_from_type: proc "c" (type: GdVariantType) -> proc "c" (variant: ^GdVariant, value: rawptr),
    variant_to_type: proc "c" (type: GdVariantType) -> proc "c" (value: rawptr, variant: ^GdVariant),
    variant_destructor: proc "c" (type: GdVariantType) -> proc "c" (value: rawptr),
    variant_get_type: proc "c" (variant: ^GdVariant) -> GdVariantType,
    construct_object: proc "c" (class_name: ^GdStringName) -> GdObject,
    object_set_instance: proc "c" (object: GdObject, class_name: ^GdStringName, instance: GdInstance),
    register_class: proc "c" (library: GdLibrary, class_name: ^GdStringName, parent: ^GdStringName, info: ^GdClassInfo4),
    register_method: proc "c" (library: GdLibrary, class_name: ^GdStringName, info: ^GdMethodInfo),
    unregister_class: proc "c" (library: GdLibrary, class_name: ^GdStringName),
    print_warning: proc "c" (description: cstring, function: cstring, file: cstring, line: i32, editor_notify: GdBool),
    from_bool: proc "c" (variant: ^GdVariant, value: rawptr),
    from_int: proc "c" (variant: ^GdVariant, value: rawptr),
    from_string: proc "c" (variant: ^GdVariant, value: rawptr),
    to_int: proc "c" (value: rawptr, variant: ^GdVariant),
    to_string: proc "c" (value: rawptr, variant: ^GdVariant),
    to_bool: proc "c" (value: rawptr, variant: ^GdVariant),
    destroy_string: proc "c" (value: rawptr),
    bytes_index: proc "c" (array: rawptr, index: GdInt) -> [^]u8,
    bytes_index_const: proc "c" (array: rawptr, index: GdInt) -> [^]u8,
    bytes_construct: proc "c" (array: rawptr, args: [^]rawptr),
    bytes_size: proc "c" (array: rawptr, args: [^]rawptr, result: rawptr, count: i32),
    bytes_resize: proc "c" (array: rawptr, args: [^]rawptr, result: rawptr, count: i32),
    bytes_destroy: proc "c" (array: rawptr),
    from_bytes: proc "c" (variant: ^GdVariant, value: rawptr),
    to_bytes: proc "c" (value: rawptr, variant: ^GdVariant),
    from_float: proc "c" (variant: ^GdVariant, value: rawptr),
    to_float: proc "c" (value: rawptr, variant: ^GdVariant),
    from_vector2: proc "c" (variant: ^GdVariant, value: rawptr),
    to_vector2: proc "c" (value: rawptr, variant: ^GdVariant),
    from_vector3: proc "c" (variant: ^GdVariant, value: rawptr),
    to_vector3: proc "c" (value: rawptr, variant: ^GdVariant),
    from_array: proc "c" (variant: ^GdVariant, value: rawptr),
    to_array: proc "c" (value: rawptr, variant: ^GdVariant),
    from_dictionary: proc "c" (variant: ^GdVariant, value: rawptr),
    to_dictionary: proc "c" (value: rawptr, variant: ^GdVariant),
    array_construct: proc "c" (array: rawptr, args: [^]rawptr),
    dictionary_construct: proc "c" (dictionary: rawptr, args: [^]rawptr),
    array_destroy: proc "c" (array: rawptr),
    dictionary_destroy: proc "c" (dictionary: rawptr),
    array_index: proc "c" (array: rawptr, index: GdInt) -> ^GdVariant,
    array_index_const: proc "c" (array: rawptr, index: GdInt) -> ^GdVariant,
    dictionary_index: proc "c" (dictionary: rawptr, key: ^GdVariant) -> ^GdVariant,
    dictionary_index_const: proc "c" (dictionary: rawptr, key: ^GdVariant) -> ^GdVariant,
    array_size: proc "c" (array: rawptr, args: [^]rawptr, result: rawptr, count: i32),
    array_resize: proc "c" (array: rawptr, args: [^]rawptr, result: rawptr, count: i32),
    dictionary_keys: proc "c" (dictionary: rawptr, args: [^]rawptr, result: rawptr, count: i32),
    packed_ints, packed_floats, packed_strings: PackedOps,
    packed_ints32, packed_floats32, packed_vector2s, packed_vector3s, packed_colors: PackedOps,
    type_from: [VARIANT_TYPE_COUNT]proc "c" (variant: ^GdVariant, value: rawptr),    // native value -> Variant, by Variant type: the plain structs and the names
    type_to: [VARIANT_TYPE_COUNT]proc "c" (value: rawptr, variant: ^GdVariant),
    type_destroy: [VARIANT_TYPE_COUNT]proc "c" (value: rawptr),
    string_from_name: [VARIANT_TYPE_COUNT]proc "c" (string: rawptr, args: [^]rawptr),   // String(StringName) at STRING_NAME, String(NodePath) at NODE_PATH
    name_from_string: [VARIANT_TYPE_COUNT]proc "c" (name: rawptr, args: [^]rawptr),     // StringName(String) at STRING_NAME, NodePath(String) at NODE_PATH
    from_object: proc "c" (variant: ^GdVariant, value: rawptr),
    to_object: proc "c" (value: rawptr, variant: ^GdVariant),
    from_string_name: proc "c" (variant: ^GdVariant, value: rawptr),
    destroy_string_name: proc "c" (value: rawptr),
    variant_destroy: proc "c" (variant: ^GdVariant),
    stringify: proc "c" (variant: ^GdVariant, result: ^GdString),
    register_property: proc "c" (library: GdLibrary, class_name: ^GdStringName, info: ^GdPropertyInfo, setter: ^GdStringName, getter: ^GdStringName),
    register_signal: proc "c" (library: GdLibrary, class_name: ^GdStringName, signal_name: ^GdStringName, arguments: [^]GdPropertyInfo, count: GdInt),
    get_method_bind: proc "c" (class_name: ^GdStringName, method_name: ^GdStringName, hash: GdInt) -> rawptr,
    method_bind_call: proc "c" (bind: rawptr, object: GdObject, args: [^]^GdVariant, count: GdInt, result: ^GdVariant, error: ^GdCallError),
    emit_signal_bind: rawptr,
}

GetProcAddress :: #type proc "c" (name: cstring) -> rawptr

@(private)
gd: Interface

// Looks the functions up. False when one is missing (a Godot older than 4.4).
interfaceLoad :: proc "c" (get: GetProcAddress, library: GdLibrary) -> bool {
    gd.library = library
    ok: bool = true
    lookup :: proc "c" (get: GetProcAddress, name: cstring, ok: ^bool) -> rawptr {
        function: rawptr = get(name)
        if function == nil { ok^ = false }
        return function
    }
    gd.string_name_new = auto_cast lookup(get, "string_name_new_with_latin1_chars", &ok)
    gd.string_new_utf8 = auto_cast lookup(get, "string_new_with_utf8_chars", &ok)
    gd.string_new_utf8_len = auto_cast lookup(get, "string_new_with_utf8_chars_and_len2", &ok)
    gd.string_to_utf8 = auto_cast lookup(get, "string_to_utf8_chars", &ok)
    gd.variant_from_type = auto_cast lookup(get, "get_variant_from_type_constructor", &ok)
    gd.variant_to_type = auto_cast lookup(get, "get_variant_to_type_constructor", &ok)
    gd.variant_destructor = auto_cast lookup(get, "variant_get_ptr_destructor", &ok)
    gd.variant_get_type = auto_cast lookup(get, "variant_get_type", &ok)
    gd.construct_object = auto_cast lookup(get, "classdb_construct_object2", &ok)
    gd.object_set_instance = auto_cast lookup(get, "object_set_instance", &ok)
    gd.register_class = auto_cast lookup(get, "classdb_register_extension_class4", &ok)
    gd.register_method = auto_cast lookup(get, "classdb_register_extension_class_method", &ok)
    gd.unregister_class = auto_cast lookup(get, "classdb_unregister_extension_class", &ok)
    gd.variant_destroy = auto_cast lookup(get, "variant_destroy", &ok)
    gd.register_property = auto_cast lookup(get, "classdb_register_extension_class_property", &ok)
    gd.stringify = auto_cast lookup(get, "variant_stringify", &ok)
    gd.register_signal = auto_cast lookup(get, "classdb_register_extension_class_signal", &ok)
    gd.get_method_bind = auto_cast lookup(get, "classdb_get_method_bind", &ok)
    gd.method_bind_call = auto_cast lookup(get, "object_method_bind_call", &ok)
    gd.array_index = auto_cast lookup(get, "array_operator_index", &ok)
    gd.array_index_const = auto_cast lookup(get, "array_operator_index_const", &ok)
    gd.dictionary_index = auto_cast lookup(get, "dictionary_operator_index", &ok)
    gd.dictionary_index_const = auto_cast lookup(get, "dictionary_operator_index_const", &ok)
    gd.print_warning = auto_cast lookup(get, "print_warning", &ok)
    gd.bytes_index = auto_cast lookup(get, "packed_byte_array_operator_index", &ok)
    gd.bytes_index_const = auto_cast lookup(get, "packed_byte_array_operator_index_const", &ok)
    constructor: proc "c" (type: GdVariantType, index: i32) -> proc "c" (array: rawptr, args: [^]rawptr) = auto_cast lookup(get, "variant_get_ptr_constructor", &ok)
    method: proc "c" (type: GdVariantType, name: ^GdStringName, hash: GdInt) -> proc "c" (array: rawptr, args: [^]rawptr, result: rawptr, count: i32) = auto_cast lookup(get, "variant_get_ptr_builtin_method", &ok)
    if !ok { return false }
    packedLoad(&gd.packed_ints, .PACKED_INT64_ARRAY, get, "packed_int64_array", constructor, method)
    packedLoad(&gd.packed_floats, .PACKED_FLOAT64_ARRAY, get, "packed_float64_array", constructor, method)
    packedLoad(&gd.packed_strings, .PACKED_STRING_ARRAY, get, "packed_string_array", constructor, method)
    packedLoad(&gd.packed_ints32, .PACKED_INT32_ARRAY, get, "packed_int32_array", constructor, method)
    packedLoad(&gd.packed_floats32, .PACKED_FLOAT32_ARRAY, get, "packed_float32_array", constructor, method)
    packedLoad(&gd.packed_vector2s, .PACKED_VECTOR2_ARRAY, get, "packed_vector2_array", constructor, method)
    packedLoad(&gd.packed_vector3s, .PACKED_VECTOR3_ARRAY, get, "packed_vector3_array", constructor, method)
    packedLoad(&gd.packed_colors, .PACKED_COLOR_ARRAY, get, "packed_color_array", constructor, method)
    for type in ([?]GdVariantType{.VECTOR2I, .VECTOR3I, .VECTOR4, .VECTOR4I, .RECT2, .RECT2I, .COLOR, .QUATERNION, .PLANE, .AABB, .TRANSFORM2D, .BASIS, .TRANSFORM3D, .PROJECTION, .STRING_NAME, .NODE_PATH}) {
        gd.type_from[type] = gd.variant_from_type(type)
        gd.type_to[type] = gd.variant_to_type(type)
        gd.type_destroy[type] = gd.variant_destructor(type)
    }
    gd.string_from_name[GdVariantType.STRING_NAME] = constructor(.STRING, 2)
    gd.string_from_name[GdVariantType.NODE_PATH] = constructor(.STRING, 3)
    gd.name_from_string[GdVariantType.STRING_NAME] = constructor(.STRING_NAME, 2)
    gd.name_from_string[GdVariantType.NODE_PATH] = constructor(.NODE_PATH, 2)
    size_name_for_collections: GdStringName = stringName("size")
    resize_name_for_collections: GdStringName = stringName("resize")
    gd.from_bool = gd.variant_from_type(.BOOL)
    gd.from_int = gd.variant_from_type(.INT)
    gd.from_string = gd.variant_from_type(.STRING)
    gd.to_bool = gd.variant_to_type(.BOOL)
    gd.to_int = gd.variant_to_type(.INT)
    gd.to_string = gd.variant_to_type(.STRING)
    gd.destroy_string = gd.variant_destructor(.STRING)
    gd.bytes_destroy = gd.variant_destructor(.PACKED_BYTE_ARRAY)
    gd.from_float = gd.variant_from_type(.FLOAT)
    gd.to_float = gd.variant_to_type(.FLOAT)
    gd.from_vector2 = gd.variant_from_type(.VECTOR2)
    gd.to_vector2 = gd.variant_to_type(.VECTOR2)
    gd.from_vector3 = gd.variant_from_type(.VECTOR3)
    gd.to_vector3 = gd.variant_to_type(.VECTOR3)
    gd.from_array = gd.variant_from_type(.ARRAY)
    gd.to_array = gd.variant_to_type(.ARRAY)
    gd.from_dictionary = gd.variant_from_type(.DICTIONARY)
    gd.to_dictionary = gd.variant_to_type(.DICTIONARY)
    gd.array_construct = constructor(.ARRAY, 0)
    gd.dictionary_construct = constructor(.DICTIONARY, 0)
    gd.array_destroy = gd.variant_destructor(.ARRAY)
    gd.dictionary_destroy = gd.variant_destructor(.DICTIONARY)
    gd.from_object = gd.variant_from_type(.OBJECT)
    gd.to_object = gd.variant_to_type(.OBJECT)
    gd.from_string_name = gd.variant_from_type(.STRING_NAME)
    gd.destroy_string_name = gd.variant_destructor(.STRING_NAME)
    gd.from_bytes = gd.variant_from_type(.PACKED_BYTE_ARRAY)
    gd.to_bytes = gd.variant_to_type(.PACKED_BYTE_ARRAY)
    gd.bytes_construct = constructor(.PACKED_BYTE_ARRAY, 0)
    // the hashes are the ones of extension_api.json for Array and Dictionary .size, .resize, .keys
    keys_name: GdStringName = stringName("keys")
    gd.array_size = method(.ARRAY, &size_name_for_collections, 3173160232)
    gd.array_resize = method(.ARRAY, &resize_name_for_collections, 848867239)
    gd.dictionary_keys = method(.DICTIONARY, &keys_name, 4144163970)
    // the hashes are the ones of extension_api.json for PackedByteArray.size and .resize
    size_name: GdStringName = stringName("size")
    resize_name: GdStringName = stringName("resize")
    gd.bytes_size = method(.PACKED_BYTE_ARRAY, &size_name, 3173160232)
    gd.bytes_resize = method(.PACKED_BYTE_ARRAY, &resize_name, 848867239)
    // Object.emit_signal (vararg) is how an extension class tells GDScript
    object_name: GdStringName = stringName("Object")
    emit_name: GdStringName = stringName("emit_signal")
    gd.emit_signal_bind = gd.get_method_bind(&object_name, &emit_name, 4047867050)
    return gd.bytes_size != nil && gd.bytes_resize != nil && gd.emit_signal_bind != nil
}

@(private)
packedLoad :: proc "c" (ops: ^PackedOps, type: GdVariantType, get: GetProcAddress, prefix: cstring, constructor: proc "c" (type: GdVariantType, index: i32) -> proc "c" (array: rawptr, args: [^]rawptr), method: proc "c" (type: GdVariantType, name: ^GdStringName, hash: GdInt) -> proc "c" (array: rawptr, args: [^]rawptr, result: rawptr, count: i32)) {
    context = runtime.default_context()
    size_name: GdStringName = stringName("size")
    resize_name: GdStringName = stringName("resize")
    ops.type = type
    ops.size = method(type, &size_name, 3173160232)
    ops.resize = method(type, &resize_name, 848867239)
    ops.construct = constructor(type, 0)
    ops.destroy = gd.variant_destructor(type)
    ops.from = gd.variant_from_type(type)
    ops.to = gd.variant_to_type(type)
    ops.index = auto_cast get(fmt_name(prefix, "_operator_index"))
    ops.index_const = auto_cast get(fmt_name(prefix, "_operator_index_const"))
}

// "packed_int64_array" + "_operator_index" as a C string in a small static buffer (only used while loading, one at a time)
@(private)
name_buffer: [96]u8

@(private)
fmt_name :: proc "contextless" (prefix: cstring, suffix: string) -> cstring {
    at: int
    text: [^]u8 = cast([^]u8)prefix
    for i := 0; text[i] != 0; i += 1 {
        name_buffer[at] = text[i]
        at += 1
    }
    for b in transmute([]u8)suffix {
        name_buffer[at] = b
        at += 1
    }
    name_buffer[at] = 0
    return cstring(raw_data(name_buffer[:]))
}

stringName :: proc "c" (text: cstring) -> GdStringName {
    name: GdStringName
    gd.string_name_new(&name, text, 0)
    return name
}

// The text of a String as UTF-8 in `buffer` (cut when it does not fit); the length
stringRead :: proc "c" (value: ^GdString, buffer: []u8) -> int {
    return int(gd.string_to_utf8(value, raw_data(buffer), GdInt(len(buffer))))
}

// A Variant that holds a String made from `text`
variantString :: proc "c" (result: ^GdVariant, text: []u8) {
    value: GdString
    gd.string_new_utf8_len(&value, raw_data(text), GdInt(len(text)))
    gd.from_string(result, &value)
    gd.destroy_string(&value)
}

variantInt :: proc "c" (result: ^GdVariant, value: i64) {
    number: i64 = value
    gd.from_int(result, &number)
}

// Vectors are 32 bit floats in the engine (the usual build); the library hands them out as f64
variantFloat :: proc "c" (result: ^GdVariant, value: f64) {
    number: f64 = value
    gd.from_float(result, &number)
}

variantVector2 :: proc "c" (result: ^GdVariant, v: [4]f64) {
    native: [2]f32 = {f32(v[0]), f32(v[1])}
    gd.from_vector2(result, &native)
}

variantVector3 :: proc "c" (result: ^GdVariant, v: [4]f64) {
    native: [3]f32 = {f32(v[0]), f32(v[1]), f32(v[2])}
    gd.from_vector3(result, &native)
}

// Arrays and Dictionaries inside each other are read down to this depth; deeper (or an Array that holds itself) comes as NONE, so no cycle can run away
MAX_NESTING :: 8

// A Variant as a Value: bool, int, float, String (also StringName and NodePath, as their text), Vector2, Vector3, Object, Array and Dictionary (their elements the same way, down to MAX_NESTING levels)
// and the packed arrays; anything else is NONE. Texts and arrays live in `allocator`.
variantToValue :: proc "c" (variant: ^GdVariant, allocator: runtime.Allocator, depth: int = 0) -> Value {
    context = runtime.default_context()
    switch gd.variant_get_type(variant) {
    case .BOOL:
        flag: GdBool
        gd.to_bool(&flag, variant)
        return {kind = .BOOL, number = i64(flag)}
    case .INT:
        number: i64
        gd.to_int(&number, variant)
        return {kind = .INT, number = number}
    case .FLOAT:
        number: f64
        gd.to_float(&number, variant)
        return {kind = .FLOAT, real = {number, 0, 0, 0}}
    case .STRING_NAME, .NODE_PATH:
        // a StringName and a NodePath come back as the String of their text
        text: GdString
        gd.stringify(variant, &text)
        length: int = int(gd.string_to_utf8(&text, nil, 0))
        buffer: []u8 = make([]u8, length, allocator)
        if length > 0 { gd.string_to_utf8(&text, raw_data(buffer), GdInt(length)) }
        gd.destroy_string(&text)
        return {kind = .STRING, text = buffer}
    case .STRING:
        text: GdString
        gd.to_string(&text, variant)
        length: int = int(gd.string_to_utf8(&text, nil, 0))
        buffer: []u8 = make([]u8, length, allocator)
        if length > 0 { gd.string_to_utf8(&text, raw_data(buffer), GdInt(length)) }
        gd.destroy_string(&text)
        return {kind = .STRING, text = buffer}
    case .VECTOR2:
        native: [2]f32
        gd.to_vector2(&native, variant)
        return {kind = .VECTOR2, real = {f64(native[0]), f64(native[1]), 0, 0}}
    case .VECTOR3:
        native: [3]f32
        gd.to_vector3(&native, variant)
        return {kind = .VECTOR3, real = {f64(native[0]), f64(native[1]), f64(native[2]), 0}}
    case .OBJECT:
        object: rawptr
        gd.to_object(&object, variant)
        return {kind = .OBJECT, object = object}
    case .ARRAY:
        if depth >= MAX_NESTING { return {} }
        array: GdArray
        gd.to_array(&array, variant)
        items: []Value = readArray(&array, allocator, depth + 1)
        gd.array_destroy(&array)
        return {kind = .ARRAY, items = items}
    case .DICTIONARY:
        if depth >= MAX_NESTING { return {} }
        dictionary: GdArray
        gd.to_dictionary(&dictionary, variant)
        keys, items := readDictionary(&dictionary, allocator, depth + 1)
        gd.dictionary_destroy(&dictionary)
        return {kind = .DICTIONARY, keys = keys, items = items}
    case .PACKED_BYTE_ARRAY:
        array: GdBytes
        gd.to_bytes(&array, variant)
        text: []u8 = readBytes(&array, allocator)
        gd.bytes_destroy(&array)
        return {kind = .BYTES, text = text}
    case .PACKED_INT64_ARRAY:
        array: GdBytes
        gd.packed_ints.to(&array, variant)
        numbers: []i64 = readPackedInts(&array, allocator)
        gd.packed_ints.destroy(&array)
        return {kind = .PACKED_INTS, ints = numbers}
    case .PACKED_FLOAT64_ARRAY:
        array: GdBytes
        gd.packed_floats.to(&array, variant)
        numbers: []f64 = readPackedFloats(&array, allocator)
        gd.packed_floats.destroy(&array)
        return {kind = .PACKED_FLOATS, floats = numbers}
    case .PACKED_STRING_ARRAY:
        array: GdBytes
        gd.packed_strings.to(&array, variant)
        items: []Value = readPackedStrings(&array, allocator)
        gd.packed_strings.destroy(&array)
        return {kind = .PACKED_STRINGS, items = items}
    case .PACKED_INT32_ARRAY: return readPackedVariant(variant, .PACKED_INT32S, allocator)
    case .PACKED_FLOAT32_ARRAY: return readPackedVariant(variant, .PACKED_FLOAT32S, allocator)
    case .PACKED_VECTOR2_ARRAY: return readPackedVariant(variant, .PACKED_VECTOR2S, allocator)
    case .PACKED_VECTOR3_ARRAY: return readPackedVariant(variant, .PACKED_VECTOR3S, allocator)
    case .PACKED_COLOR_ARRAY: return readPackedVariant(variant, .PACKED_COLORS, allocator)
    case .VECTOR2I, .VECTOR3I, .VECTOR4, .VECTOR4I, .RECT2, .RECT2I, .COLOR, .QUATERNION, .PLANE, .AABB, .TRANSFORM2D, .BASIS, .TRANSFORM3D, .PROJECTION:
        return variantToPod(variant, podKindOf(gd.variant_get_type(variant)), allocator)
    case .NIL:
    }
    return {}
}

// Writes a scalar Value into an uninitialized Variant (a NONE becomes nil)
valueToVariant :: proc "c" (variant: ^GdVariant, value: Value) {
    switch value.kind {
    case .BOOL: variantBool(variant, value.number != 0)
    case .INT: variantInt(variant, value.number)
    case .FLOAT: variantFloat(variant, value.real[0])
    case .STRING: variantString(variant, value.text)
    case .VECTOR2: variantVector2(variant, value.real)
    case .VECTOR3: variantVector3(variant, value.real)
    case .BYTES: variantBytes(variant, value.text)
    case .OBJECT:
        object: rawptr = value.object
        gd.from_object(variant, &object)
    case .ARRAY: variantArray(variant, value.items)
    case .DICTIONARY: variantDictionary(variant, value.keys, value.items)
    case .PACKED_INTS: variantPackedInts(variant, value.ints)
    case .PACKED_FLOATS: variantPackedFloats(variant, value.floats)
    case .PACKED_STRINGS: variantPackedStrings(variant, value.items)
    case .PACKED_INT32S, .PACKED_FLOAT32S, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS: variantPackedNumeric(variant, value.kind, value)
    case .VECTOR2I, .VECTOR3I, .VECTOR4, .VECTOR4I, .RECT2, .RECT2I, .COLOR, .QUATERNION, .PLANE, .AABB, .TRANSFORM2D, .BASIS, .TRANSFORM3D, .PROJECTION: podToVariant(variant, value.kind, value)
    case .STRING_NAME, .NODE_PATH: nameToVariant(variant, value.kind, value.text)
    case .VARIANT, .NONE:
    }
}

// The elements of an Array, nested ones included (see MAX_NESTING)
readArray :: proc "c" (array: rawptr, allocator: runtime.Allocator, depth: int = 0) -> []Value {
    context = runtime.default_context()
    size: i64
    gd.array_size(array, nil, &size, 0)
    items: []Value = make([]Value, int(size), allocator)
    for i in 0 ..< int(size) { items[i] = variantToValue(gd.array_index_const(array, GdInt(i)), allocator, depth) }
    return items
}

// Fills an Array that was just constructed
writeArray :: proc "c" (array: rawptr, items: []Value) {
    if len(items) == 0 { return }
    count: i64 = i64(len(items))
    args: [1]rawptr = {&count}
    status: i64
    gd.array_resize(array, raw_data(args[:]), &status, 1)
    for item, i in items { valueToVariant(gd.array_index(array, GdInt(i)), item) }
}

// The entries of a Dictionary whose keys are Strings (an entry with another kind of key is left out), values nested down to MAX_NESTING
readDictionary :: proc "c" (dictionary: rawptr, allocator: runtime.Allocator, depth: int = 0) -> (keys: []Value, items: []Value) {
    context = runtime.default_context()
    key_array: GdArray
    gd.dictionary_keys(dictionary, nil, &key_array, 0)
    defer gd.array_destroy(&key_array)
    size: i64
    gd.array_size(&key_array, nil, &size, 0)
    keys = make([]Value, int(size), allocator)
    items = make([]Value, int(size), allocator)
    used: int
    for i in 0 ..< int(size) {
        key_variant: ^GdVariant = gd.array_index_const(&key_array, GdInt(i))
        if gd.variant_get_type(key_variant) != .STRING { continue }
        keys[used] = variantToValue(key_variant, allocator)
        items[used] = variantToValue(gd.dictionary_index_const(dictionary, key_variant), allocator, depth)
        used += 1
    }
    return keys[:used], items[:used]
}

// Fills a Dictionary that was just constructed
writeDictionary :: proc "c" (dictionary: rawptr, keys: []Value, items: []Value) {
    for key, i in keys {
        key_variant: GdVariant
        variantString(&key_variant, key.text)
        valueToVariant(gd.dictionary_index(dictionary, &key_variant), items[i])
        gd.variant_destroy(&key_variant)
    }
}

variantArray :: proc "c" (result: ^GdVariant, items: []Value) {
    array: GdArray
    gd.array_construct(&array, nil)
    writeArray(&array, items)
    gd.from_array(result, &array)
    gd.array_destroy(&array)
}

variantDictionary :: proc "c" (result: ^GdVariant, keys: []Value, items: []Value) {
    dictionary: GdArray
    gd.dictionary_construct(&dictionary, nil)
    writeDictionary(&dictionary, keys, items)
    gd.from_dictionary(result, &dictionary)
    gd.dictionary_destroy(&dictionary)
}

packedSize :: proc "c" (ops: ^PackedOps, array: rawptr) -> int {
    size: i64
    ops.size(array, nil, &size, 0)
    return int(size)
}

packedResize :: proc "c" (ops: ^PackedOps, array: rawptr, count: int) {
    number: i64 = i64(count)
    args: [1]rawptr = {&number}
    status: i64
    ops.resize(array, raw_data(args[:]), &status, 1)
}

// The numbers of a PackedInt64Array or PackedFloat64Array, copied into `allocator` memory
readPackedInts :: proc "c" (array: rawptr, allocator: runtime.Allocator) -> []i64 {
    context = runtime.default_context()
    count: int = packedSize(&gd.packed_ints, array)
    numbers: []i64 = make([]i64, count, allocator)
    if count > 0 { copy(numbers, (cast([^]i64)gd.packed_ints.index_const(array, 0))[:count]) }
    return numbers
}

readPackedFloats :: proc "c" (array: rawptr, allocator: runtime.Allocator) -> []f64 {
    context = runtime.default_context()
    count: int = packedSize(&gd.packed_floats, array)
    numbers: []f64 = make([]f64, count, allocator)
    if count > 0 { copy(numbers, (cast([^]f64)gd.packed_floats.index_const(array, 0))[:count]) }
    return numbers
}

// A PackedStringArray as String values (`kind` STRING each)
readPackedStrings :: proc "c" (array: rawptr, allocator: runtime.Allocator) -> []Value {
    context = runtime.default_context()
    count: int = packedSize(&gd.packed_strings, array)
    items: []Value = make([]Value, count, allocator)
    for i in 0 ..< count {
        text: ^GdString = cast(^GdString)gd.packed_strings.index_const(array, GdInt(i))
        length: int = int(gd.string_to_utf8(text, nil, 0))
        buffer: []u8 = make([]u8, length, allocator)
        if length > 0 { gd.string_to_utf8(text, raw_data(buffer), GdInt(length)) }
        items[i] = {kind = .STRING, text = buffer}
    }
    return items
}

// The writers fill an array that was just constructed
writePackedInts :: proc "c" (array: rawptr, numbers: []i64) {
    if len(numbers) == 0 { return }
    packedResize(&gd.packed_ints, array, len(numbers))
    copy((cast([^]i64)gd.packed_ints.index(array, 0))[:len(numbers)], numbers)
}

writePackedFloats :: proc "c" (array: rawptr, numbers: []f64) {
    if len(numbers) == 0 { return }
    packedResize(&gd.packed_floats, array, len(numbers))
    copy((cast([^]f64)gd.packed_floats.index(array, 0))[:len(numbers)], numbers)
}

writePackedStrings :: proc "c" (array: rawptr, items: []Value) {
    if len(items) == 0 { return }
    packedResize(&gd.packed_strings, array, len(items))
    for item, i in items {
        // a fresh element is an empty String (no memory to release): the new text replaces it
        gd.string_new_utf8_len(cast(^GdString)gd.packed_strings.index(array, GdInt(i)), raw_data(item.text), GdInt(len(item.text)))
    }
}

// The plain structs of the engine (32 bit build): Vector2i, Vector3i, Vector4, Vector4i, Rect2, Rect2i, Color, Quaternion, Plane (4 numbers or fewer: `real`) and AABB, Transform2D, Basis, Transform3D,
// Projection (6, 6, 9, 12, 16 numbers: `floats32`). The native memory is the numbers one after the other, so one reader and one writer serve all of them. The Rect2 is position then size, the
// Plane is normal then d, a Transform2D is three Vector2 (x axis, y axis, origin), a Basis three Vector3 (the rows), a Transform3D a Basis and the origin, a Projection four Vector4 (columns).
PodInfo :: struct {
    type: GdVariantType,
    count: int,
    ints: bool,             // 32 bit integers, else 32 bit floats
    big: bool,              // the numbers go to `floats32`, else to `real`
}

podInfoOf :: proc "contextless" (kind: ValueKind) -> (info: PodInfo, ok: bool) {
    #partial switch kind {
    case .VECTOR2I: return {.VECTOR2I, 2, true, false}, true
    case .VECTOR3I: return {.VECTOR3I, 3, true, false}, true
    case .VECTOR4: return {.VECTOR4, 4, false, false}, true
    case .VECTOR4I: return {.VECTOR4I, 4, true, false}, true
    case .RECT2: return {.RECT2, 4, false, false}, true
    case .RECT2I: return {.RECT2I, 4, true, false}, true
    case .COLOR: return {.COLOR, 4, false, false}, true
    case .QUATERNION: return {.QUATERNION, 4, false, false}, true
    case .PLANE: return {.PLANE, 4, false, false}, true
    case .AABB: return {.AABB, 6, false, true}, true
    case .TRANSFORM2D: return {.TRANSFORM2D, 6, false, true}, true
    case .BASIS: return {.BASIS, 9, false, true}, true
    case .TRANSFORM3D: return {.TRANSFORM3D, 12, false, true}, true
    case .PROJECTION: return {.PROJECTION, 16, false, true}, true
    }
    return {}, false
}

// The kind that goes with a Variant type of the structs above (NONE when it is not one)
podKindOf :: proc "contextless" (type: GdVariantType) -> ValueKind {
    #partial switch type {
    case .VECTOR2I: return .VECTOR2I
    case .VECTOR3I: return .VECTOR3I
    case .VECTOR4: return .VECTOR4
    case .VECTOR4I: return .VECTOR4I
    case .RECT2: return .RECT2
    case .RECT2I: return .RECT2I
    case .COLOR: return .COLOR
    case .QUATERNION: return .QUATERNION
    case .PLANE: return .PLANE
    case .AABB: return .AABB
    case .TRANSFORM2D: return .TRANSFORM2D
    case .BASIS: return .BASIS
    case .TRANSFORM3D: return .TRANSFORM3D
    case .PROJECTION: return .PROJECTION
    }
    return .NONE
}

// A native struct (an argument of a native call, or the memory of a Variant conversion) as a Value
podRead :: proc "c" (kind: ValueKind, native: rawptr, allocator: runtime.Allocator) -> Value {
    context = runtime.default_context()
    info, _ := podInfoOf(kind)
    value: Value = {kind = kind}
    if info.ints {
        numbers: [^]i32 = cast([^]i32)native
        for i in 0 ..< info.count { value.real[i] = f64(numbers[i]) }
    } else if info.big {
        value.floats32 = make([]f32, info.count, allocator)
        copy(value.floats32, (cast([^]f32)native)[:info.count])
    } else {
        numbers: [^]f32 = cast([^]f32)native
        for i in 0 ..< info.count { value.real[i] = f64(numbers[i]) }
    }
    return value
}

// Writes a Value into native memory of the struct (a result of a native call). Numbers that are missing are zero.
podWrite :: proc "c" (kind: ValueKind, native: rawptr, value: Value) {
    info, _ := podInfoOf(kind)
    bytes: [^]u8 = cast([^]u8)native
    for i in 0 ..< info.count * 4 { bytes[i] = 0 }
    if info.ints {
        numbers: [^]i32 = cast([^]i32)native
        for i in 0 ..< info.count { numbers[i] = i32(value.real[i]) }
    } else if info.big {
        numbers: [^]f32 = cast([^]f32)native
        for i in 0 ..< min(info.count, len(value.floats32)) { numbers[i] = value.floats32[i] }
    } else {
        numbers: [^]f32 = cast([^]f32)native
        for i in 0 ..< info.count { numbers[i] = f32(value.real[i]) }
    }
}

podToVariant :: proc "c" (variant: ^GdVariant, kind: ValueKind, value: Value) {
    info, _ := podInfoOf(kind)
    memory: [16]u32                       // the biggest struct (Projection) is 16 numbers
    podWrite(kind, &memory, value)
    gd.type_from[info.type](variant, &memory)
}

variantToPod :: proc "c" (variant: ^GdVariant, kind: ValueKind, allocator: runtime.Allocator) -> Value {
    info, _ := podInfoOf(kind)
    memory: [16]u32
    gd.type_to[info.type](&memory, variant)
    return podRead(kind, &memory, allocator)
}

// A StringName or a NodePath (`kind` STRING_NAME or NODE_PATH) as its text. `native` is the engine's own value and stays so.
nameRead :: proc "c" (kind: ValueKind, native: rawptr, allocator: runtime.Allocator) -> Value {
    context = runtime.default_context()
    type: GdVariantType = .STRING_NAME if kind == .STRING_NAME else .NODE_PATH
    text: GdString
    arguments: [1]rawptr = {native}
    gd.string_from_name[type](&text, raw_data(arguments[:]))
    length: int = int(gd.string_to_utf8(&text, nil, 0))
    buffer: []u8 = make([]u8, length, allocator)
    if length > 0 { gd.string_to_utf8(&text, raw_data(buffer), GdInt(length)) }
    gd.destroy_string(&text)
    return {kind = kind, text = buffer}
}

// Makes a StringName or NodePath in `native` (memory for one) from text
nameWrite :: proc "c" (kind: ValueKind, native: rawptr, text: []u8) {
    type: GdVariantType = .STRING_NAME if kind == .STRING_NAME else .NODE_PATH
    string_value: GdString
    gd.string_new_utf8_len(&string_value, raw_data(text), GdInt(len(text)))
    arguments: [1]rawptr = {&string_value}
    gd.name_from_string[type](native, raw_data(arguments[:]))
    gd.destroy_string(&string_value)
}

variantToName :: proc "c" (variant: ^GdVariant, kind: ValueKind, allocator: runtime.Allocator) -> Value {
    type: GdVariantType = .STRING_NAME if kind == .STRING_NAME else .NODE_PATH
    native: GdStringName
    gd.type_to[type](&native, variant)
    value: Value = nameRead(kind, &native, allocator)
    gd.type_destroy[type](&native)
    return value
}

nameToVariant :: proc "c" (variant: ^GdVariant, kind: ValueKind, text: []u8) {
    type: GdVariantType = .STRING_NAME if kind == .STRING_NAME else .NODE_PATH
    native: GdStringName
    nameWrite(kind, &native, text)
    gd.type_from[type](variant, &native)
    gd.type_destroy[type](&native)
}

// The five numeric packed arrays that are plain memory: PackedInt32Array (1 i32 per element) and PackedFloat32Array, PackedVector2Array, PackedVector3Array, PackedColorArray (1, 2, 3 and 4 f32
// per element). One reader and one writer serve all of them: the elements lie one after the other, so the numbers are `count * components` of one type.
packedOpsOf :: proc "contextless" (kind: ValueKind) -> (ops: ^PackedOps, components: int) {
    #partial switch kind {
    case .PACKED_INT32S: return &gd.packed_ints32, 1
    case .PACKED_FLOAT32S: return &gd.packed_floats32, 1
    case .PACKED_VECTOR2S: return &gd.packed_vector2s, 2
    case .PACKED_VECTOR3S: return &gd.packed_vector3s, 3
    case .PACKED_COLORS: return &gd.packed_colors, 4
    }
    return nil, 0
}

// A packed array that arrives inside a Variant (an element of an Array, a Variant argument): copied out and released
readPackedVariant :: proc "c" (variant: ^GdVariant, kind: ValueKind, allocator: runtime.Allocator) -> Value {
    ops, _ := packedOpsOf(kind)
    array: GdBytes
    ops.to(&array, variant)
    value: Value = readPackedNumeric(kind, &array, allocator)
    ops.destroy(&array)
    return value
}

// Copies the numbers of the array `array` of the engine into a Value of `kind` (memory of `allocator`)
readPackedNumeric :: proc "c" (kind: ValueKind, array: rawptr, allocator: runtime.Allocator) -> Value {
    context = runtime.default_context()
    ops, components := packedOpsOf(kind)
    count: int = packedSize(ops, array)
    value: Value = {kind = kind}
    if kind == .PACKED_INT32S {
        value.ints32 = make([]i32, count, allocator)
        if count > 0 { copy(value.ints32, (cast([^]i32)ops.index_const(array, 0))[:count]) }
    } else {
        value.floats32 = make([]f32, count * components, allocator)
        if count > 0 { copy(value.floats32, (cast([^]f32)ops.index_const(array, 0))[:count * components]) }
    }
    return value
}

// Fills an array that was just constructed (a vector array takes `len(floats32) / components` elements: a rest that does not fill an element is dropped)
writePackedNumeric :: proc "c" (kind: ValueKind, array: rawptr, value: Value) {
    ops, components := packedOpsOf(kind)
    if kind == .PACKED_INT32S {
        if len(value.ints32) == 0 { return }
        packedResize(ops, array, len(value.ints32))
        copy((cast([^]i32)ops.index(array, 0))[:len(value.ints32)], value.ints32)
        return
    }
    count: int = len(value.floats32) / components
    if count == 0 { return }
    packedResize(ops, array, count)
    copy((cast([^]f32)ops.index(array, 0))[:count * components], value.floats32[:count * components])
}

variantPackedNumeric :: proc "c" (result: ^GdVariant, kind: ValueKind, value: Value) {
    ops, _ := packedOpsOf(kind)
    array: GdBytes
    ops.construct(&array, nil)
    writePackedNumeric(kind, &array, value)
    ops.from(result, &array)
    ops.destroy(&array)
}

variantPackedInts :: proc "c" (result: ^GdVariant, numbers: []i64) {
    array: GdBytes
    gd.packed_ints.construct(&array, nil)
    writePackedInts(&array, numbers)
    gd.packed_ints.from(result, &array)
    gd.packed_ints.destroy(&array)
}

variantPackedFloats :: proc "c" (result: ^GdVariant, numbers: []f64) {
    array: GdBytes
    gd.packed_floats.construct(&array, nil)
    writePackedFloats(&array, numbers)
    gd.packed_floats.from(result, &array)
    gd.packed_floats.destroy(&array)
}

variantPackedStrings :: proc "c" (result: ^GdVariant, items: []Value) {
    array: GdBytes
    gd.packed_strings.construct(&array, nil)
    writePackedStrings(&array, items)
    gd.packed_strings.from(result, &array)
    gd.packed_strings.destroy(&array)
}

variantObject :: proc "c" (result: ^GdVariant, object: rawptr) {
    pointer: rawptr = object
    gd.from_object(result, &pointer)
}

variantBool :: proc "c" (result: ^GdVariant, value: bool) {
    flag: GdBool = 1 if value else 0
    gd.from_bool(result, &flag)
}

// Writes a native String (the return value of a ptrcall) from `text`
nativeString :: proc "c" (result: rawptr, text: []u8) {
    gd.string_new_utf8_len(cast(^GdString)result, raw_data(text), GdInt(len(text)))
}

defaultContext :: proc "c" () -> runtime.Context {
    return runtime.default_context()
}

// The bytes of a native PackedByteArray, copied into `allocator` memory (the array stays the engine's)
readBytes :: proc "c" (array: rawptr, allocator: runtime.Allocator) -> []u8 {
    context = runtime.default_context()
    size: i64
    gd.bytes_size(array, nil, &size, 0)
    if size <= 0 { return nil }
    copy_of: []u8 = make([]u8, int(size), allocator)
    source: [^]u8 = gd.bytes_index_const(array, 0)
    copy(copy_of, source[:size])
    return copy_of
}

// Makes a PackedByteArray in `array` (uninitialized memory of 16 bytes) holding `bytes`
makeBytes :: proc "c" (array: rawptr, bytes: []u8) {
    gd.bytes_construct(array, nil)
    if len(bytes) == 0 { return }
    count: i64 = i64(len(bytes))
    args: [1]rawptr = {&count}
    status: i64                          // resize returns an error code and writes it: the pointer has to be there
    gd.bytes_resize(array, raw_data(args[:]), &status, 1)
    destination: [^]u8 = gd.bytes_index(array, 0)
    copy(destination[:len(bytes)], bytes)
}

variantBytes :: proc "c" (result: ^GdVariant, bytes: []u8) {
    array: GdBytes
    makeBytes(&array, bytes)
    gd.from_bytes(result, &array)
    gd.bytes_destroy(&array)
}
