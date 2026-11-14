package scene

// Prefabs as data. A prefab is a value of your own struct (an actor, a weapon, a projectile ...) plus the assets it needs.
// A prefab can be based on another one and override fields, like a Godot inherited scene:
//
//     zombie_fast := scene.PrefabDef(Actor){base = &zombie, patches = {scene.PatchField(Actor, "max_speed", f32(60))}}
//
// An override is a patch: the offset of the field and the new bytes, found once when the patch is made. Resolving a prefab copies
// the root value and applies the patches in order, which is a few memcpy calls done ONCE (for example when a scene is entered).
// Spawning is then a plain struct copy, an instance override is a few more memcpy calls. No per-frame cost, no allocation, no reflection
// at runtime.

import "base:runtime"

PATCH_BYTES :: 32
PREFAB_CHAIN_MAX :: 8

// New bytes for one field of a prefab struct
FieldPatch :: struct {
    offset: u32,
    size: u8,
    bytes: [PATCH_BYTES]u8,
}

PrefabDef :: struct($T: typeid) {
    base: ^PrefabDef(T),
    value: T,                   // used by the root of a chain, the others only patch it
    patches: []FieldPatch,
    assets: []AssetId,          // what this prefab needs, added to what the bases need
}

// Find a field by name, also through `using` fields and nested structs ("health.value"). Returns the offset and the size of the field.
// Contextless, so patches can be made in package level tables (no allocation, no strings library)
@(private)
FindFieldOffset :: proc "contextless" (info: ^runtime.Type_Info, path: string) -> (offset: uintptr, size: int, ok: bool) {
    current: ^runtime.Type_Info = info
    start: int
    for i in 0 ..= len(path) {
        if i < len(path) && path[i] != '.' { continue }
        found: bool
        offset_in_struct: uintptr
        offset_in_struct, current, found = FindInStruct(current, path[start:i])
        if !found { return }
        offset += offset_in_struct
        start = i + 1
    }
    return offset, current.size, true
}

// One name inside of one struct, looking through `using` fields
@(private)
FindInStruct :: proc "contextless" (info: ^runtime.Type_Info, name: string) -> (offset: uintptr, field_type: ^runtime.Type_Info, ok: bool) {
    base: ^runtime.Type_Info = runtime.type_info_base(info)
    variant, is_struct := base.variant.(^runtime.Type_Info_Struct)
    if !is_struct { return }
    for i in 0 ..< int(variant.field_count) {
        if variant.names[i] == name {
            return variant.offsets[i], variant.types[i], true
        }
    }
    for i in 0 ..< int(variant.field_count) {
        if !variant.usings[i] { continue }
        inner_offset, inner_type, inner_ok := FindInStruct(variant.types[i], name)
        if inner_ok {
            return variant.offsets[i] + inner_offset, inner_type, true
        }
    }
    return
}

@(private)
PatchFail :: proc "contextless" (message: string, field: string) -> ! {
    runtime.print_string("PatchField: ")
    runtime.print_string(message)
    runtime.print_string(": ")
    runtime.print_string(field)
    runtime.print_string("\n")
    runtime.trap()
}

// A patch for `field` of T. The field is looked up here, once, and the size of the value has to match the field:
//     PatchField(Actor, "max_speed", f32(60))        // not 60, that is an int
// Contextless: it works in package level tables, where the prefabs live. A wrong field or size stops the program at startup.
PatchField :: proc "contextless" ($T: typeid, $field: string, value: $V) -> (patch: FieldPatch) {
    offset, size, ok := FindFieldOffset(type_info_of(T), field)
    if !ok { PatchFail("no such field", field) }
    if size != size_of(V) { PatchFail("the value has another size than the field, give it the type of the field", field) }
    if size_of(V) > PATCH_BYTES { PatchFail("the field is bigger than a patch can hold", field) }
    patch.offset = u32(offset)
    patch.size = u8(size_of(V))
    value_copy: V = value
    runtime.mem_copy(&patch.bytes[0], &value_copy, size_of(V))
    return
}

// Write patches into a value. Used by PrefabResolve and for the overrides of one instance
PrefabApply :: proc(value: ^$T, patches: []FieldPatch) {
    base: [^]u8 = cast([^]u8)value
    for &patch in patches {
        assert(int(patch.offset) + int(patch.size) <= size_of(T))
        runtime.mem_copy(&base[patch.offset], &patch.bytes[0], int(patch.size))
    }
}

// The finished value: the root value of the chain with all the patches of the chain applied, root first
PrefabResolve :: proc(def: ^PrefabDef($T), out: ^T) {
    chain: [PREFAB_CHAIN_MAX]^PrefabDef(T)
    count: int
    for current := def; current != nil; current = current.base {
        assert(count < PREFAB_CHAIN_MAX, "PrefabResolve: the chain of bases is too long or loops")
        chain[count] = current
        count += 1
    }
    out^ = chain[count - 1].value
    for i := count - 1; i >= 0; i -= 1 {
        PrefabApply(out, chain[i].patches)
    }
}

// The assets of the whole chain without repeats, written into `buffer`. Returns what fits
PrefabAssets :: proc(def: ^PrefabDef($T), buffer: []AssetId) -> []AssetId {
    count: int
    for current := def; current != nil; current = current.base {
        for id in current.assets {
            known: bool
            for i in 0 ..< count {
                if buffer[i] == id { known = true; break }
            }
            if !known && count < len(buffer) {
                buffer[count] = id
                count += 1
            }
        }
    }
    return buffer[:count]
}
