package godot_spacetimedb

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

GdVariantType :: enum u32 {
    NIL = 0,
    BOOL = 1,
    INT = 2,
    FLOAT = 3,
    STRING = 4,
    PACKED_BYTE_ARRAY = 29,
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
    get_virtual_call_data_func: rawptr,
    call_virtual_with_data_func: rawptr,
    class_userdata: rawptr,
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
    gd.print_warning = auto_cast lookup(get, "print_warning", &ok)
    gd.bytes_index = auto_cast lookup(get, "packed_byte_array_operator_index", &ok)
    gd.bytes_index_const = auto_cast lookup(get, "packed_byte_array_operator_index_const", &ok)
    constructor: proc "c" (type: GdVariantType, index: i32) -> proc "c" (array: rawptr, args: [^]rawptr) = auto_cast lookup(get, "variant_get_ptr_constructor", &ok)
    method: proc "c" (type: GdVariantType, name: ^GdStringName, hash: GdInt) -> proc "c" (array: rawptr, args: [^]rawptr, result: rawptr, count: i32) = auto_cast lookup(get, "variant_get_ptr_builtin_method", &ok)
    if !ok { return false }
    gd.from_bool = gd.variant_from_type(.BOOL)
    gd.from_int = gd.variant_from_type(.INT)
    gd.from_string = gd.variant_from_type(.STRING)
    gd.to_bool = gd.variant_to_type(.BOOL)
    gd.to_int = gd.variant_to_type(.INT)
    gd.to_string = gd.variant_to_type(.STRING)
    gd.destroy_string = gd.variant_destructor(.STRING)
    gd.bytes_destroy = gd.variant_destructor(.PACKED_BYTE_ARRAY)
    gd.from_bytes = gd.variant_from_type(.PACKED_BYTE_ARRAY)
    gd.to_bytes = gd.variant_to_type(.PACKED_BYTE_ARRAY)
    gd.bytes_construct = constructor(.PACKED_BYTE_ARRAY, 0)
    // the hashes are the ones of extension_api.json for PackedByteArray.size and .resize
    size_name: GdStringName = stringName("size")
    resize_name: GdStringName = stringName("resize")
    gd.bytes_size = method(.PACKED_BYTE_ARRAY, &size_name, 3173160232)
    gd.bytes_resize = method(.PACKED_BYTE_ARRAY, &resize_name, 848867239)
    return gd.bytes_size != nil && gd.bytes_resize != nil
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
