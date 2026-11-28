package gdextension_template

// The template: one class, `Counter`, that shows each kind of argument and result the library supports (int, bool, String, PackedByteArray). Copy this folder, rename the package, the class and
// the entry symbol (`template_entry`, also in godot_project/template.gdextension), replace the methods with yours.

import "core:strings"
import ge "../../gdextension"
import "../../gdextension/engine"

// The state of one Counter object: what `create` returns is what every method receives as `instance`
TEMPLATE_VERSION :: #config(TEMPLATE_VERSION, 1)

Counter :: struct {
    object: rawptr,         // the engine object, from `bind`: what `Emit` needs
    total: int,
    mode: int,
    gain: f64,
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
        {"mode", .INT, "get_mode", "set_mode"},
        {"gain", .FLOAT, "get_gain", "set_gain"},
    },
    statics = {"twice"},        // callable on the class: Counter.twice(21)
    // an enum: GDScript reads Counter.Mode.HIGH (and Counter.HIGH); the property `mode` shows the same names
    constants = {
        {"Mode", "OFF", 0, false},
        {"Mode", "LOW", 5, false},
        {"Mode", "HIGH", 10, false},
        {"", "LIMIT", 99, false},
    },
    // sections of the inspector: "Mixer" starts at `mode` and holds `mode` and `gain`
    groups = {
        {"mode", "Mixer", "", false},
    },
    // how the inspector edits them: a dropdown and a slider
    hints = {
        {"mode", .ENUM, "Off,Low:5,High:10"},
        {"gain", .RANGE, "0,1,0.05"},
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
        {"twice", {.INT}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueInt(a[0].number * 2) }},      // static: `instance` is nil
        {"get_mode", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueInt(i64((cast(^Counter)instance).mode)) }},
        {"set_mode", {.INT}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            (cast(^Counter)instance).mode = int(a[0].number)
            return {}
        }},
        {"get_gain", {}, .FLOAT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return ge.ValueFloat((cast(^Counter)instance).gain) }},
        {"set_gain", {.FLOAT}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            (cast(^Counter)instance).gain = a[0].real[0]
            return {}
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
        // which build of the extension answers: the hot reload test builds it twice with another value (`-define:TEMPLATE_VERSION=2`)
        {"version", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return ge.ValueInt(TEMPLATE_VERSION)
        }},
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
        // The plain structs of the engine, one method each (the numbers of the small ones are in `real`, of AABB, Transform2D, Basis, Transform3D, Projection in `floats32`)
        {"step_cell", {.VECTOR2I}, .VECTOR2I, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .VECTOR2I, real = {a[0].real[0] + 1, a[0].real[1] - 1, 0, 0}}
        }},
        {"step_cell3", {.VECTOR3I}, .VECTOR3I, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .VECTOR3I, real = {a[0].real[0] + 1, a[0].real[1] + 2, a[0].real[2] + 3, 0}}
        }},
        {"sum4", {.VECTOR4}, .FLOAT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .FLOAT, real = {a[0].real[0] + a[0].real[1] + a[0].real[2] + a[0].real[3], 0, 0, 0}}
        }},
        {"reverse4", {.VECTOR4I}, .VECTOR4I, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .VECTOR4I, real = {a[0].real[3], a[0].real[2], a[0].real[1], a[0].real[0]}}
        }},
        // the position moves by (10, 10), the size doubles
        {"move_rect", {.RECT2}, .RECT2, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .RECT2, real = {a[0].real[0] + 10, a[0].real[1] + 10, a[0].real[2] * 2, a[0].real[3] * 2}}
        }},
        {"grow_rect", {.RECT2I}, .RECT2I, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .RECT2I, real = {a[0].real[0] - 1, a[0].real[1] - 1, a[0].real[2] + 2, a[0].real[3] + 2}}
        }},
        {"invert_color", {.COLOR}, .COLOR, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .COLOR, real = {1 - a[0].real[0], 1 - a[0].real[1], 1 - a[0].real[2], a[0].real[3]}}
        }},
        {"conjugate", {.QUATERNION}, .QUATERNION, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .QUATERNION, real = {-a[0].real[0], -a[0].real[1], -a[0].real[2], a[0].real[3]}}
        }},
        {"flip_plane", {.PLANE}, .PLANE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .PLANE, real = {-a[0].real[0], -a[0].real[1], -a[0].real[2], -a[0].real[3]}}
        }},
        // the box keeps its position and doubles its size
        {"grow_box", {.AABB}, .AABB, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []f32 = make([]f32, 6, context.temp_allocator)
            copy(out, a[0].floats32)
            for i in 3 ..< 6 { out[i] *= 2 }
            return {kind = .AABB, floats32 = out}
        }},
        // the origin (the last two numbers) moves by (5, 6)
        {"slide", {.TRANSFORM2D}, .TRANSFORM2D, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []f32 = make([]f32, 6, context.temp_allocator)
            copy(out, a[0].floats32)
            out[4] += 5
            out[5] += 6
            return {kind = .TRANSFORM2D, floats32 = out}
        }},
        {"double_basis", {.BASIS}, .BASIS, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []f32 = make([]f32, 9, context.temp_allocator)
            for i in 0 ..< min(9, len(a[0].floats32)) { out[i] = a[0].floats32[i] * 2 }
            return {kind = .BASIS, floats32 = out}
        }},
        // the origin (the last three numbers) goes up by one
        {"lift", {.TRANSFORM3D}, .TRANSFORM3D, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []f32 = make([]f32, 12, context.temp_allocator)
            copy(out, a[0].floats32)
            out[10] += 1
            return {kind = .TRANSFORM3D, floats32 = out}
        }},
        {"double_projection", {.PROJECTION}, .PROJECTION, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            out: []f32 = make([]f32, 16, context.temp_allocator)
            for i in 0 ..< min(16, len(a[0].floats32)) { out[i] = a[0].floats32[i] * 2 }
            return {kind = .PROJECTION, floats32 = out}
        }},
        {"shout_name", {.STRING_NAME}, .STRING_NAME, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .STRING_NAME, text = transmute([]u8)strings.to_upper(string(a[0].text), context.temp_allocator)}
        }},
        {"shout_path", {.NODE_PATH}, .NODE_PATH, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .NODE_PATH, text = transmute([]u8)strings.to_upper(string(a[0].text), context.temp_allocator)}
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
        // the generated wrappers with the other kinds: a Color in and out, a Rect2 out, an Array of Objects out, a Variant in and out
        {"tint", {.OBJECT, .COLOR}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return ge.ValueBool(engine.CanvasItemSetModulate(a[0].object, a[1].real))
        }},
        {"tint_of", {.OBJECT}, .COLOR, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            color, _ := engine.CanvasItemGetModulate(a[0].object)
            return {kind = .COLOR, real = color}
        }},
        {"rect_of", {.OBJECT}, .RECT2, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            rect, _ := engine.ControlGetRect(a[0].object)
            return {kind = .RECT2, real = rect}
        }},
        {"children_of", {.OBJECT}, .ARRAY, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            children, _ := engine.NodeGetChildren(a[0].object)
            return ge.ValueArray(children)
        }},
        // stores any value as metadata of the object and reads it back
        {"keep_meta", {.OBJECT, .STRING, .VARIANT}, .VARIANT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            engine.ObjectSetMeta(a[0].object, string(a[1].text), a[2])
            value, _ := engine.ObjectGetMeta(a[0].object, string(a[1].text), {})
            return value
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
