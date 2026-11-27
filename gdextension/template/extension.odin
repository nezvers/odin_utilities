package gdextension_template

// The template: one class, `Counter`, that shows each kind of argument and result the library supports (int, bool, String, PackedByteArray). Copy this folder, rename the package, the class and
// the entry symbol (`template_entry`, also in godot_project/template.gdextension), replace the methods with yours.

import "core:strings"
import ge "../../gdextension"

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
