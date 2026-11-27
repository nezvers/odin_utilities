package gdextension_template

// The template: one class, `Counter`, that shows each kind of argument and result the library supports (int, bool, String, PackedByteArray). Copy this folder, rename the package, the class and
// the entry symbol (`template_entry`, also in godot_project/template.gdextension), replace the methods with yours.

import "core:strings"
import ge "../../gdextension"
import "../../gdextension/engine"

// The state of one Counter object: what `create` returns is what every method receives as `instance`
Counter :: struct {
    object: rawptr,         // the engine object, from `bind`: what `Emit` needs
    total: int,
    greeting: [256]u8,      // a result string has to live until the call ends: the instance keeps it
}

counter_class: ge.Class = {
    name = "Counter",
    parent = "RefCounted",
    create = proc() -> rawptr { return new(Counter) },
    destroy = proc(instance: rawptr) { free(instance) },
    bind = proc(instance: rawptr, object: rawptr) { (cast(^Counter)instance).object = object },
    // signals: connect from GDScript with `counter.changed.connect(callable)`
    // a property is a name that GDScript reads and writes (`counter.total = 5`): it calls the methods `get` and `set_total`
    properties = {
        {"total", .INT, "get", "set_total"},
    },
    signals = {
        {"changed", {.INT}},                    // the new total
        {"noted", {.STRING, .BOOL, .BYTES}},    // every kind of argument
        {"moved", {.FLOAT, .VECTOR2}},
        {"listed", {.ARRAY, .DICTIONARY}},
    },
    methods = {
        // int -> int
        {"add", {.INT}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            counter: ^Counter = cast(^Counter)instance
            counter.total += int(a[0].number)
            ge.Emit(counter.object, "changed", {ge.ValueInt(i64(counter.total))})
            return {kind = .INT, number = i64(counter.total)}
        }},
        // nothing -> int
        {"get", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .INT, number = i64((cast(^Counter)instance).total)}
        }},
        // int -> nothing: the setter of the property `total`
        {"set_total", {.INT}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            (cast(^Counter)instance).total = int(a[0].number)
            return {}
        }},
        // nothing -> nothing
        {"reset", {}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            (cast(^Counter)instance).total = 0
            return {}
        }},
        // int -> bool
        {"is_even", {.INT}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .BOOL, number = 1 if a[0].number % 2 == 0 else 0}
        }},
        // String -> String (UTF-8 bytes in, UTF-8 bytes out)
        {"greet", {.STRING}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            counter: ^Counter = cast(^Counter)instance
            text: string = strings.concatenate({"Hello, ", string(a[0].text), "!"}, context.temp_allocator)
            count: int = copy(counter.greeting[:], text)
            return {kind = .STRING, text = counter.greeting[:count]}
        }},
        // PackedByteArray -> PackedByteArray
        {"reverse", {.BYTES}, .BYTES, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            reversed: []u8 = make([]u8, len(a[0].text), context.temp_allocator)
            for b, i in a[0].text { reversed[len(reversed) - 1 - i] = b }
            return {kind = .BYTES, text = reversed}
        }},
        // emits `noted` with a String, a bool and bytes
        {"note", {.STRING}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            ge.Emit((cast(^Counter)instance).object, "noted", {ge.ValueText(string(a[0].text)), ge.ValueBool(true), {kind = .BYTES, text = a[0].text}})
            return {}
        }},
        // float -> float
        {"half", {.FLOAT}, .FLOAT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return ge.ValueFloat(a[0].real[0] / 2)
        }},
        // Vector2 -> Vector2, Vector3 -> float, Vector3 -> Vector3
        {"flip", {.VECTOR2}, .VECTOR2, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return ge.ValueVector2(a[0].real[1], a[0].real[0])
        }},
        {"sum3", {.VECTOR3}, .FLOAT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return ge.ValueFloat(a[0].real[0] + a[0].real[1] + a[0].real[2])
        }},
        {"rotate3", {.VECTOR3}, .VECTOR3, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return ge.ValueVector3(a[0].real[2], a[0].real[0], a[0].real[1])
        }},
        // emits `moved` with a float and a Vector2
        {"move", {.FLOAT, .VECTOR2}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            ge.Emit((cast(^Counter)instance).object, "moved", {a[0], a[1]})
            return {}
        }},
        // Array -> Array: the numbers doubled, the strings upper cased with a mark
        {"double_all", {.ARRAY}, .ARRAY, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []ge.Value = make([]ge.Value, len(a[0].items), context.temp_allocator)
            for item, i in a[0].items {
                out[i] = item
                #partial switch item.kind {
                case .INT: out[i].number = item.number * 2
                case .FLOAT: out[i].real[0] = item.real[0] * 2
                case .STRING: out[i].text = transmute([]u8)strings.concatenate({string(item.text), "!"}, context.temp_allocator)
                }
            }
            return ge.ValueArray(out)
        }},
        // Dictionary -> Dictionary: the same entries with the values of each key added to a `count` entry
        {"annotate", {.DICTIONARY}, .DICTIONARY, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            keys: []ge.Value = make([]ge.Value, len(a[0].keys) + 1, context.temp_allocator)
            items: []ge.Value = make([]ge.Value, len(a[0].keys) + 1, context.temp_allocator)
            copy(keys, a[0].keys)
            copy(items, a[0].items)
            keys[len(keys) - 1] = {kind = .STRING, text = transmute([]u8)string("count")}
            items[len(items) - 1] = ge.ValueInt(i64(len(a[0].keys)))
            return ge.ValueDictionary(keys, items)
        }},
        // emits `listed` with an Array and a Dictionary
        {"list", {.ARRAY, .DICTIONARY}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            ge.Emit((cast(^Counter)instance).object, "listed", {a[0], a[1]})
            return {}
        }},
        // PackedInt64Array, PackedFloat64Array and PackedStringArray in and out
        {"prefix_sums", {.PACKED_INTS}, .PACKED_INTS, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            sums: []i64 = make([]i64, len(a[0].ints), context.temp_allocator)
            total: i64
            for number, i in a[0].ints {
                total += number
                sums[i] = total
            }
            return {kind = .PACKED_INTS, ints = sums}
        }},
        {"halve_all", {.PACKED_FLOATS}, .PACKED_FLOATS, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            halves: []f64 = make([]f64, len(a[0].floats), context.temp_allocator)
            for number, i in a[0].floats { halves[i] = number / 2 }
            return {kind = .PACKED_FLOATS, floats = halves}
        }},
        {"shout_all", {.PACKED_STRINGS}, .PACKED_STRINGS, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []ge.Value = make([]ge.Value, len(a[0].items), context.temp_allocator)
            for item, i in a[0].items {
                out[i] = {kind = .STRING, text = transmute([]u8)strings.to_upper(string(item.text), context.temp_allocator)}
            }
            return {kind = .PACKED_STRINGS, items = out}
        }},
        // Nested Arrays and Dictionaries come in with their elements, a Variant argument takes any type and `echo` gives it back unchanged (nil stays nil)
        {"nest_depth", {.ARRAY}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            depth :: proc(items: []ge.Value) -> i64 {
                deepest: i64
                for item in items {
                    #partial switch item.kind {
                    case .ARRAY: deepest = max(deepest, depth(item.items))
                    case .DICTIONARY: deepest = max(deepest, depth(item.items))
                    }
                }
                return deepest + 1
            }
            return ge.ValueInt(depth(a[0].items))
        }},
        {"echo", {.VARIANT}, .VARIANT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return a[0]
        }},
        {"kind_of", {.VARIANT}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return ge.ValueInt(i64(a[0].kind))
        }},
        // The numeric packed arrays of the engine (32 bit): ints, floats, points, 3D points, colors
        {"double_ints32", {.PACKED_INT32S}, .PACKED_INT32S, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []i32 = make([]i32, len(a[0].ints32), context.temp_allocator)
            for number, i in a[0].ints32 { out[i] = number * 2 }
            return {kind = .PACKED_INT32S, ints32 = out}
        }},
        {"halve_floats32", {.PACKED_FLOAT32S}, .PACKED_FLOAT32S, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []f32 = make([]f32, len(a[0].floats32), context.temp_allocator)
            for number, i in a[0].floats32 { out[i] = number / 2 }
            return {kind = .PACKED_FLOAT32S, floats32 = out}
        }},
        // every point moves by (10, 20): x and y of an element lie next to each other
        {"shift_points", {.PACKED_VECTOR2S}, .PACKED_VECTOR2S, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []f32 = make([]f32, len(a[0].floats32), context.temp_allocator)
            for i := 0; i + 1 < len(out); i += 2 {
                out[i], out[i + 1] = a[0].floats32[i] + 10, a[0].floats32[i + 1] + 20
            }
            return {kind = .PACKED_VECTOR2S, floats32 = out}
        }},
        {"stretch_points", {.PACKED_VECTOR3S}, .PACKED_VECTOR3S, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []f32 = make([]f32, len(a[0].floats32), context.temp_allocator)
            for number, i in a[0].floats32 { out[i] = number * 2 }
            return {kind = .PACKED_VECTOR3S, floats32 = out}
        }},
        // the color without its alpha inverted
        {"invert_colors", {.PACKED_COLORS}, .PACKED_COLORS, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []f32 = make([]f32, len(a[0].floats32), context.temp_allocator)
            for i := 0; i + 3 < len(out); i += 4 {
                out[i], out[i + 1], out[i + 2], out[i + 3] = 1 - a[0].floats32[i], 1 - a[0].floats32[i + 1], 1 - a[0].floats32[i + 2], a[0].floats32[i + 3]
            }
            return {kind = .PACKED_COLORS, floats32 = out}
        }},
        // Objects and calls into the engine: the child count of a Node, its parent, and the position of a Node2D
        {"child_count", {.OBJECT}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            count, _ := engine.NodeGetChildCount(a[0].object)
            return ge.ValueInt(count)
        }},
        {"parent_of", {.OBJECT}, .OBJECT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            parent, _ := engine.NodeGetParent(a[0].object)
            return ge.ValueObject(parent)
        }},
        {"place", {.OBJECT, .VECTOR2}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            ok := engine.Node2DSetPosition(a[0].object, {a[1].real[0], a[1].real[1]})
            return ge.ValueBool(ok)
        }},
        // the generated wrappers (tool/bindings): a StringName result comes back as text, and a String goes in
        {"rename", {.OBJECT, .STRING}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            engine.NodeSetName(a[0].object, string(a[1].text))
            name, _ := engine.NodeGetName(a[0].object)
            counter: ^Counter = cast(^Counter)instance
            count: int = copy(counter.greeting[:], name)
            return ge.ValueText(string(counter.greeting[:count]))
        }},
        // several arguments
        {"mix", {.INT, .STRING, .BOOL}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            counter: ^Counter = cast(^Counter)instance
            text: string = strings.concatenate({string(a[1].text), "/", "yes" if a[2].number != 0 else "no", "/", number_text(a[0].number)}, context.temp_allocator)
            count: int = copy(counter.greeting[:], text)
            return {kind = .STRING, text = counter.greeting[:count]}
        }},
    },
}

number_text :: proc(number: i64) -> string {
    digits: [24]u8
    at: int = len(digits)
    value: u64 = u64(number) if number >= 0 else u64(-number)
    for {
        at -= 1
        digits[at] = u8('0' + value % 10)
        value /= 10
        if value == 0 { break }
    }
    if number < 0 {
        at -= 1
        digits[at] = '-'
    }
    return strings.clone(string(digits[at:]), context.temp_allocator)
}

classes: [1]^ge.Class = {&counter_class}

// `entry_symbol` of godot_project/template.gdextension
@(export)
template_entry :: proc "c" (get_proc_address: ge.GetProcAddress, library: ge.Library, initialization: ^ge.Initialization) -> ge.GdBool {
    return ge.Entry(get_proc_address, library, initialization, classes[:])
}
