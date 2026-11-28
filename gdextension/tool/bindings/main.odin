package main

// `odin run gdextension/tool/bindings -- --classes Node,Node2D --out <file.odin> [--package engine] [--import ..] [--api godot_api/extension_api.json]`
//
// Writes typed Odin wrappers for the methods of engine classes, from the dump of the interface of Godot (`godot --headless --dump-extension-api`, kept in `gdextension/godot_api/`, git ignored).
// `NodeGetChildCount(node)` instead of `ge.Call(node, "Node", "get_child_count", 894402480, {})`: the hash and the kinds of the arguments are copied from the dump, not by hand. The file is
// generated: do not edit it, run the tool again (with the same class list) after a Godot update.
//
// Only what `ge.Call` can carry is written: methods of the class itself (inherited ones are in the wrappers of the parent class: pass a Node2D to `NodeGetChildCount`), not static, not virtual, not
// vararg, up to 6 arguments, and with bool, int (enums and bitfields too), float, String, StringName, NodePath, the plain structs (Vector2i, Rect2, Color, Transform3D ...), Array, Dictionary, Variant, the packed arrays and engine class types (a Node, a Resource ...) as arguments and result.
// Strings that come back live in temp memory (copy them when they are needed after the call). A wrapper returns the result and an `ok` that is false when the engine refused the call.

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

Kind :: enum {
    NONE,
    CALLABLE,           // an argument `Callable` (a result would come back as nothing)
    OBJECTS,            // an argument `typedarray::Node`: a slice of objects, sent as a typed Array of that class
    BOOL,
    INT,
    FLOAT,
    STRING,
    VECTOR2,
    VECTOR3,
    OBJECT,
    VECTOR2I,
    VECTOR3I,
    VECTOR4,
    VECTOR4I,
    RECT2,
    RECT2I,
    COLOR,
    QUATERNION,
    PLANE,
    AABB,
    TRANSFORM2D,
    BASIS,
    TRANSFORM3D,
    PROJECTION,
    ARRAY,
    DICTIONARY,
    VARIANT,
    BYTES,
    PACKED_INTS,
    PACKED_INTS32,
    PACKED_FLOATS,
    PACKED_FLOATS32,
    PACKED_STRINGS,
    PACKED_VECTOR2S,
    PACKED_VECTOR3S,
    PACKED_COLORS,
}

// The kinds whose numbers are in `Value.real` (up to four): how many, and whether they are 32 bit integers
@(private)
smallOf :: proc(kind: Kind) -> (count: int, ints: bool, ok: bool) {
    #partial switch kind {
    case .VECTOR2I: return 2, true, true
    case .VECTOR3I: return 3, true, true
    case .VECTOR4: return 4, false, true
    case .VECTOR4I: return 4, true, true
    case .RECT2: return 4, false, true
    case .RECT2I: return 4, true, true
    case .COLOR: return 4, false, true
    case .QUATERNION: return 4, false, true
    case .PLANE: return 4, false, true
    }
    return 0, false, false
}

// The name of the `ge.ValueKind` of a kind (the ones that go with a slice or a struct)
@(private)
valueKindName :: proc(kind: Kind) -> string {
    #partial switch kind {
    case .VECTOR2I: return ".VECTOR2I"
    case .VECTOR3I: return ".VECTOR3I"
    case .VECTOR4: return ".VECTOR4"
    case .VECTOR4I: return ".VECTOR4I"
    case .RECT2: return ".RECT2"
    case .RECT2I: return ".RECT2I"
    case .COLOR: return ".COLOR"
    case .QUATERNION: return ".QUATERNION"
    case .PLANE: return ".PLANE"
    case .AABB: return ".AABB"
    case .TRANSFORM2D: return ".TRANSFORM2D"
    case .BASIS: return ".BASIS"
    case .TRANSFORM3D: return ".TRANSFORM3D"
    case .PROJECTION: return ".PROJECTION"
    case .BYTES: return ".BYTES"
    case .PACKED_INTS: return ".PACKED_INTS"
    case .PACKED_INTS32: return ".PACKED_INT32S"
    case .PACKED_FLOATS: return ".PACKED_FLOATS"
    case .PACKED_FLOATS32: return ".PACKED_FLOAT32S"
    case .PACKED_STRINGS: return ".PACKED_STRINGS"
    case .PACKED_VECTOR2S: return ".PACKED_VECTOR2S"
    case .PACKED_VECTOR3S: return ".PACKED_VECTOR3S"
    case .PACKED_COLORS: return ".PACKED_COLORS"
    }
    return ""
}

main :: proc() {
    classes, out: string
    package_name: string = "engine"
    import_path: string = ".."
    api: string = #directory + "../../godot_api/extension_api.json"
    arguments: []string = os.args[1:]
    for i := 0; i < len(arguments); i += 1 {
        value: ^string
        switch arguments[i] {
        case "--classes": value = &classes
        case "--out": value = &out
        case "--package": value = &package_name
        case "--import": value = &import_path
        case "--api": value = &api
        case:
            fmt.eprintln("unknown option", arguments[i])
            os.exit(2)
        }
        i += 1
        if i >= len(arguments) {
            fmt.eprintln("a value is missing")
            os.exit(2)
        }
        value^ = arguments[i]
    }
    if classes == "" || out == "" {
        fmt.eprintln("usage: odin run gdextension/tool/bindings -- --classes Node,Node2D --out <file.odin> [--package engine] [--import ..] [--api <extension_api.json>]")
        os.exit(2)
    }
    data, error := os.read_entire_file(api, context.allocator)
    if error != nil {
        fmt.eprintfln("cannot read %s (godot --headless --dump-extension-api writes it)", api)
        os.exit(1)
    }
    text, ok := Generate(data, strings.split(classes, ",", context.temp_allocator), package_name, import_path)
    if !ok {
        fmt.eprintln("the dump has no such class or cannot be read")
        os.exit(1)
    }
    if os.write_entire_file(out, transmute([]u8)text) != nil {
        fmt.eprintln("cannot write", out)
        os.exit(1)
    }
    fmt.printfln("wrote %s", out)
}

// The wrappers of `classes` from the JSON of the dump
Generate :: proc(api: []u8, classes: []string, package_name: string, import_path: string) -> (text: string, ok: bool) {
    parsed, parse_error := json.parse(api, .JSON, true, context.temp_allocator)
    if parse_error != nil { return }
    root, is_object := parsed.(json.Object)
    if !is_object { return }
    list, has_list := root["classes"].(json.Array)
    if !has_list { return }
    known: map[string]bool
    known.allocator = context.temp_allocator
    for entry in list {
        object, _ := entry.(json.Object)
        name, _ := object["name"].(json.String)
        known[name] = true
    }

    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    fmt.sbprintfln(&builder, "package %s\n", package_name)
    fmt.sbprintln(&builder, "// GENERATED by odin_utilities/gdextension/tool/bindings from the dump of the interface of Godot: do not edit, run the tool again.")
    fmt.sbprintln(&builder, "// Typed wrappers of engine methods over `ge.Call`; strings that come back live in temp memory.\n")
    fmt.sbprintfln(&builder, "import ge \"%s\"\n", import_path)
    for wanted in classes {
        found: bool
        for entry in list {
            object, _ := entry.(json.Object)
            name, _ := object["name"].(json.String)
            if name != wanted { continue }
            found = true
            writeClass(&builder, name, object, known)
        }
        if !found { return }
    }
    return strings.to_string(builder), true
}

@(private)
writeClass :: proc(builder: ^strings.Builder, class: string, object: json.Object, known: map[string]bool) {
    fmt.sbprintfln(&builder^, "// ---- %s ----\n", class)
    methods, _ := object["methods"].(json.Array)
    for entry in methods {
        method, _ := entry.(json.Object)
        name, _ := method["name"].(json.String)
        if is_flag(method, "is_static") || is_flag(method, "is_virtual") || is_flag(method, "is_vararg") || strings.has_prefix(name, "_") { continue }
        hash_value, has_hash := method["hash"].(json.Float)
        hash_integer, has_integer := method["hash"].(json.Integer)
        if !has_hash && !has_integer { continue }
        hash: i64 = hash_integer if has_integer else i64(hash_value)

        arguments, _ := method["arguments"].(json.Array)
        if len(arguments) > 6 { continue }
        kinds: [6]Kind
        names: [6]string
        elements: [6]string         // the class of an OBJECTS argument
        defaults: [6]string
        usable: bool = true
        for argument, i in arguments {
            fields, _ := argument.(json.Object)
            type, _ := fields["type"].(json.String)
            kind: Kind = kindOf(type, known, false)
            if strings.has_prefix(type, "typedarray::") && type[len("typedarray::"):] in known {
                // the engine checks the element type of an Array argument: ours is made typed with the class of the element
                kind = .OBJECTS
                elements[i] = type[len("typedarray::"):]
            }
            if kind == .NONE { usable = false; break }
            kinds[i] = kind
            argument_name, _ := fields["name"].(json.String)
            names[i] = safeName(argument_name)
            default_text, _ := fields["default_value"].(json.String)
            defaults[i] = defaultOf(kind, default_text)
        }
        if !usable { continue }
        result_kind: Kind
        if return_value, has_return := method["return_value"].(json.Object); has_return {
            type, _ := return_value["type"].(json.String)
            result_kind = kindOf(type, known, true)
            if result_kind == .NONE { continue }
        }

        fmt.sbprintf(&builder^, "%s%s :: proc(self: rawptr", class, pascal(name))
        for i in 0 ..< len(arguments) {
            fmt.sbprintf(&builder^, ", %s: %s", names[i], odinType(kinds[i]))
            if defaults[i] != "" { fmt.sbprintf(&builder^, " = %s", defaults[i]) }
        }
        if result_kind == .NONE {
            fmt.sbprintln(&builder^, ") -> bool {")
        } else {
            fmt.sbprintfln(&builder^, ") -> (%s, bool) {{", odinType(result_kind))
        }
        fmt.sbprintf(&builder^, "    %s ok := ge.Call(self, \"%s\", \"%s\", %d, {{", "result," if result_kind != .NONE else "_,", class, name, hash)
        for i in 0 ..< len(arguments) {
            if i > 0 { fmt.sbprint(&builder^, ", ") }
            fmt.sbprint(&builder^, toValue(kinds[i], names[i], elements[i]))
        }
        fmt.sbprintln(&builder^, "})")
        if result_kind == .NONE {
            fmt.sbprintln(&builder^, "    return ok")
        } else {
            fmt.sbprintfln(&builder^, "    return %s, ok", fromValue(result_kind))
        }
        fmt.sbprintln(&builder^, "}\n")
    }
}

@(private)
is_flag :: proc(object: json.Object, key: string) -> bool {
    value, _ := object[key].(json.Boolean)
    return bool(value)
}

// What a type of the dump is for `ge.Call`; NONE when it cannot be carried (a Callable, a Signal, an RID, a typed Array as an argument ...). A StringName or NodePath is sent as a String, and
// comes back as one. A typed Array of objects (`typedarray::Node`) is a `[]rawptr` argument, sent as a typed Array (`ge.ValueObjects`); as a result it is an Array of Values. Typed Arrays of other types (String, int, RID ...) are not carried.
@(private)
kindOf :: proc(type: string, known: map[string]bool, is_result: bool) -> Kind {
    switch type {
    case "bool": return .BOOL
    case "int": return .INT
    case "float": return .FLOAT
    case "String", "StringName", "NodePath": return .STRING
    case "Vector2": return .VECTOR2
    case "Vector3": return .VECTOR3
    case "Vector2i": return .VECTOR2I
    case "Vector3i": return .VECTOR3I
    case "Vector4": return .VECTOR4
    case "Vector4i": return .VECTOR4I
    case "Rect2": return .RECT2
    case "Rect2i": return .RECT2I
    case "Color": return .COLOR
    case "Quaternion": return .QUATERNION
    case "Plane": return .PLANE
    case "AABB": return .AABB
    case "Transform2D": return .TRANSFORM2D
    case "Basis": return .BASIS
    case "Transform3D": return .TRANSFORM3D
    case "Projection": return .PROJECTION
    case "Array": return .ARRAY
    case "Dictionary": return .DICTIONARY
    case "Variant": return .VARIANT
    case "Callable": return .CALLABLE if !is_result else .NONE
    case "PackedByteArray": return .BYTES
    case "PackedInt64Array": return .PACKED_INTS
    case "PackedInt32Array": return .PACKED_INTS32
    case "PackedFloat64Array": return .PACKED_FLOATS
    case "PackedFloat32Array": return .PACKED_FLOATS32
    case "PackedStringArray": return .PACKED_STRINGS
    case "PackedVector2Array": return .PACKED_VECTOR2S
    case "PackedVector3Array": return .PACKED_VECTOR3S
    case "PackedColorArray": return .PACKED_COLORS
    }
    if is_result && strings.has_prefix(type, "typedarray::") { return .ARRAY }
    if strings.has_prefix(type, "enum::") || strings.has_prefix(type, "bitfield::") { return .INT }
    if type in known { return .OBJECT }
    return .NONE
}

@(private)
odinType :: proc(kind: Kind) -> string {
    switch kind {
    case .BOOL: return "bool"
    case .INT: return "i64"
    case .FLOAT: return "f64"
    case .STRING: return "string"
    case .VECTOR2: return "[2]f64"
    case .VECTOR3: return "[3]f64"
    case .OBJECT: return "rawptr"
    case .OBJECTS: return "[]rawptr"
    case .CALLABLE: return "[2]u64"
    case .ARRAY, .PACKED_STRINGS: return "[]ge.Value"
    case .DICTIONARY, .VARIANT: return "ge.Value"
    case .BYTES: return "[]u8"
    case .PACKED_INTS: return "[]i64"
    case .PACKED_INTS32: return "[]i32"
    case .PACKED_FLOATS: return "[]f64"
    case .AABB, .TRANSFORM2D, .BASIS, .TRANSFORM3D, .PROJECTION, .PACKED_FLOATS32, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS: return "[]f32"
    case .VECTOR2I, .VECTOR3I, .VECTOR4, .VECTOR4I, .RECT2, .RECT2I, .COLOR, .QUATERNION, .PLANE:
        count, ints, _ := smallOf(kind)
        return fmt.tprintf("[%d]%s", count, "i64" if ints else "f64")
    case .NONE: return ""
    }
    return ""
}

@(private)
toValue :: proc(kind: Kind, name: string, element: string = "") -> string {
    switch kind {
    case .OBJECTS: return fmt.tprintf("ge.ValueObjects(%s, \"%s\")", name, element)
    case .CALLABLE: return fmt.tprintf("ge.Value{{kind = .CALLABLE, callable = %s}}", name)
    case .BOOL: return fmt.tprintf("ge.ValueBool(%s)", name)
    case .INT: return fmt.tprintf("ge.ValueInt(%s)", name)
    case .FLOAT: return fmt.tprintf("ge.ValueFloat(%s)", name)
    case .STRING: return fmt.tprintf("ge.ValueText(%s)", name)
    case .VECTOR2: return fmt.tprintf("ge.ValueVector2(%s[0], %s[1])", name, name)
    case .VECTOR3: return fmt.tprintf("ge.ValueVector3(%s[0], %s[1], %s[2])", name, name, name)
    case .OBJECT: return fmt.tprintf("ge.ValueObject(%s)", name)
    case .ARRAY: return fmt.tprintf("ge.ValueArray(%s)", name)
    case .DICTIONARY, .VARIANT: return name
    case .PACKED_STRINGS: return fmt.tprintf("ge.Value{{kind = .PACKED_STRINGS, items = %s}}", name)
    case .BYTES: return fmt.tprintf("ge.Value{{kind = .BYTES, text = %s}}", name)
    case .PACKED_INTS: return fmt.tprintf("ge.Value{{kind = .PACKED_INTS, ints = %s}}", name)
    case .PACKED_INTS32: return fmt.tprintf("ge.Value{{kind = .PACKED_INT32S, ints32 = %s}}", name)
    case .PACKED_FLOATS: return fmt.tprintf("ge.Value{{kind = .PACKED_FLOATS, floats = %s}}", name)
    case .AABB, .TRANSFORM2D, .BASIS, .TRANSFORM3D, .PROJECTION, .PACKED_FLOATS32, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS:
        return fmt.tprintf("ge.Value{{kind = %s, floats32 = %s}}", valueKindName(kind), name)
    case .VECTOR2I, .VECTOR3I, .VECTOR4, .VECTOR4I, .RECT2, .RECT2I, .COLOR, .QUATERNION, .PLANE:
        count, ints, _ := smallOf(kind)
        parts: [4]string
        for i in 0 ..< count { parts[i] = fmt.tprintf("f64(%s[%d])", name, i) if ints else fmt.tprintf("%s[%d]", name, i) }
        return fmt.tprintf("ge.Value{{kind = %s, real = {{%s}}}}", valueKindName(kind), strings.join(parts[:count], ", ", context.temp_allocator))
    case .NONE: return ""
    }
    return ""
}

@(private)
fromValue :: proc(kind: Kind) -> string {
    switch kind {
    case .BOOL: return "result.number != 0"
    case .INT: return "result.number"
    case .FLOAT: return "result.real[0]"
    case .STRING: return "string(result.text)"
    case .VECTOR2: return "[2]f64{result.real[0], result.real[1]}"
    case .VECTOR3: return "[3]f64{result.real[0], result.real[1], result.real[2]}"
    case .OBJECT: return "result.object"
    case .ARRAY, .PACKED_STRINGS: return "result.items"
    case .DICTIONARY, .VARIANT: return "result"
    case .BYTES: return "result.text"
    case .PACKED_INTS: return "result.ints"
    case .PACKED_INTS32: return "result.ints32"
    case .PACKED_FLOATS: return "result.floats"
    case .AABB, .TRANSFORM2D, .BASIS, .TRANSFORM3D, .PROJECTION, .PACKED_FLOATS32, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS: return "result.floats32"
    case .VECTOR2I, .VECTOR3I, .VECTOR4, .VECTOR4I, .RECT2, .RECT2I, .COLOR, .QUATERNION, .PLANE:
        count, ints, _ := smallOf(kind)
        parts: [4]string
        for i in 0 ..< count { parts[i] = fmt.tprintf("i64(result.real[%d])", i) if ints else fmt.tprintf("result.real[%d]", i) }
        return fmt.tprintf("%s{{%s}}", odinType(kind), strings.join(parts[:count], ", ", context.temp_allocator))
    case .NONE, .OBJECTS, .CALLABLE: return ""
    }
    return ""
}

// A default that Odin can write for the plain kinds; anything else (null, Vector2(0, 0), []) has none: the caller passes it
@(private)
defaultOf :: proc(kind: Kind, text: string) -> string {
    switch kind {
    case .BOOL: if text == "true" || text == "false" { return text }
    case .INT:
        if text == "" { return "" }
        for c, i in text {
            if !(c >= '0' && c <= '9') && !(i == 0 && c == '-') { return "" }
        }
        return text
    case .FLOAT:
        if text == "" { return "" }
        for c, i in text {
            if !(c >= '0' && c <= '9') && c != '.' && !(i == 0 && c == '-') { return "" }
        }
        return text if strings.contains(text, ".") else fmt.tprintf("%s.0", text)
    case .STRING: if text == `""` { return text }
    case .VECTOR2, .VECTOR3, .OBJECT, .OBJECTS, .CALLABLE, .NONE:
    case .VECTOR2I, .VECTOR3I, .VECTOR4, .VECTOR4I, .RECT2, .RECT2I, .COLOR, .QUATERNION, .PLANE, .AABB, .TRANSFORM2D, .BASIS, .TRANSFORM3D, .PROJECTION:
    case .ARRAY, .DICTIONARY, .VARIANT, .BYTES, .PACKED_INTS, .PACKED_INTS32, .PACKED_FLOATS, .PACKED_FLOATS32, .PACKED_STRINGS, .PACKED_VECTOR2S, .PACKED_VECTOR3S, .PACKED_COLORS:
    }
    return ""
}

// snake_case to PascalCase: get_child_count -> GetChildCount
@(private)
pascal :: proc(name: string) -> string {
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    upper: bool = true
    for c in name {
        if c == '_' {
            upper = true
            continue
        }
        if upper && c >= 'a' && c <= 'z' {
            strings.write_rune(&builder, c - 32)
        } else {
            strings.write_rune(&builder, c)
        }
        upper = false
    }
    return strings.to_string(builder)
}

// An argument called like an Odin keyword gets an underscore
@(private)
safeName :: proc(name: string) -> string {
    switch name {
    case "in", "not_in", "context", "map", "proc", "struct", "union", "enum", "bit_set", "bit_field", "distinct", "using", "defer", "typeid", "cast", "transmute", "auto_cast", "asm", "dynamic", "fallthrough", "for", "if", "else", "when", "switch", "case", "break", "continue", "return", "import", "foreign", "package", "or_else", "or_return", "or_break", "or_continue", "where", "matrix", "type", "self", "ok", "result":
        return fmt.tprintf("%s_", name)
    }
    return name
}

@(test)
test_wrappers_are_generated_from_the_dump :: proc(t: ^testing.T) {
    api, error := os.read_entire_file(#directory + "../../godot_api/extension_api.json", context.temp_allocator)
    if error != nil { return }          // the dump is not in git: no dump, nothing to test
    text, ok := Generate(api, {"Node", "Node2D"}, "engine", "..")
    testing.expect(t, ok)
    testing.expect(t, strings.contains(text, "NodeGetChildCount :: proc(self: rawptr, include_internal: bool = false) -> (i64, bool) {"))
    testing.expect(t, strings.contains(text, `ge.Call(self, "Node", "get_child_count", 894402480, {ge.ValueBool(include_internal)})`))
    testing.expect(t, strings.contains(text, "Node2DSetPosition :: proc(self: rawptr, position: [2]f64) -> bool {"))
    testing.expect(t, strings.contains(text, "NodeGetParent :: proc(self: rawptr) -> (rawptr, bool) {"))
    testing.expect(t, strings.contains(text, "NodeGetChildren :: proc(self: rawptr, include_internal: bool = false) -> ([]ge.Value, bool) {"), "a typed Array result is an Array of Values")
    colored, colored_ok := Generate(api, {"CanvasItem", "Control", "Object"}, "engine", "..")
    testing.expect(t, colored_ok)
    testing.expect(t, strings.contains(colored, "CanvasItemSetModulate :: proc(self: rawptr, modulate: [4]f64) -> bool {"))
    testing.expect(t, strings.contains(colored, "ge.Value{kind = .COLOR, real = {modulate[0], modulate[1], modulate[2], modulate[3]}}"))
    testing.expect(t, strings.contains(colored, "ControlGetRect :: proc(self: rawptr) -> ([4]f64, bool) {"))
    testing.expect(t, strings.contains(colored, "ObjectSetMeta :: proc(self: rawptr, name: string, value: ge.Value) -> bool {"), "a Variant argument is a Value")
    testing.expect(t, strings.contains(colored, "ObjectGetMeta :: proc(self: rawptr, name: string, default: ge.Value) -> (ge.Value, bool) {"))
    timers, timers_ok := Generate(api, {"Object"}, "engine", "..")
    testing.expect(t, timers_ok)
    testing.expect(t, strings.contains(timers, "ObjectConnect :: proc(self: rawptr, signal: string, callable: [2]u64, flags: i64 = 0) -> (i64, bool) {"), "a Callable argument is 16 bytes")
    testing.expect(t, strings.contains(timers, "ge.Value{kind = .CALLABLE, callable = callable}"))
    fonts, fonts_ok := Generate(api, {"Font"}, "engine", "..")
    testing.expect(t, fonts_ok)
    testing.expect(t, strings.contains(fonts, "FontSetFallbacks :: proc(self: rawptr, fallbacks: []rawptr) -> bool {"), "a typed Array of objects is a slice of objects")
    testing.expect(t, strings.contains(fonts, `ge.ValueObjects(fallbacks, "Font")`))
    _, missing := Generate(api, {"NoSuchClass"}, "engine", "..")
    testing.expect(t, !missing)
}
