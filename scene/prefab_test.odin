#+build !js
// Tests of prefab.odin. They are in their own file because the scene system is imported by games with a web build, and core:testing does not compile for js_wasm32.
package scene

import "core:testing"

@(private="file")
Stats :: struct {
    speed: f32,
    health: f32,
}

@(private="file")
Unit :: struct {
    using stats: Stats,
    name: string,
    position: [2]f32,
    tint: [4]u8,
    count: int,
}

@(test)
test_patch_finds_fields_through_using_and_nesting :: proc(t: ^testing.T) {
    unit: Unit
    PrefabApply(&unit, {PatchField(Unit, "speed", f32(2.5)), PatchField(Unit, "health", f32(40))})   // inside of `using`
    testing.expect_value(t, unit.speed, f32(2.5))
    testing.expect_value(t, unit.health, f32(40))

    PrefabApply(&unit, {PatchField(Unit, "stats.speed", f32(9))})                                       // by the full path
    testing.expect_value(t, unit.speed, f32(9))

    PrefabApply(&unit, {PatchField(Unit, "tint", [4]u8{1, 2, 3, 4}), PatchField(Unit, "count", 7), PatchField(Unit, "name", "boss")})
    testing.expect_value(t, unit.tint, [4]u8{1, 2, 3, 4})
    testing.expect_value(t, unit.count, 7)
    testing.expect_value(t, unit.name, "boss")                                                          // a string is two words, it fits
    testing.expect_value(t, unit.health, f32(40))                                                       // other fields are not touched
}

@(test)
test_patch_a_vector_component :: proc(t: ^testing.T) {
    unit: Unit
    PrefabApply(&unit, {PatchField(Unit, "position", [2]f32{3, 4})})
    testing.expect_value(t, unit.position, [2]f32{3, 4})
}

@(test)
test_prefab_chain_overrides_in_order :: proc(t: ^testing.T) {
    root: PrefabDef(Unit) = {
        value = {stats = {speed = 1, health = 100}, name = "grunt", tint = {255, 255, 255, 255}},
        assets = {3, 4},
    }
    fast: PrefabDef(Unit) = {base = &root, patches = {PatchField(Unit, "speed", f32(5))}, assets = {4, 5}}
    fast_and_tough: PrefabDef(Unit) = {
        base = &fast,
        patches = {PatchField(Unit, "health", f32(300)), PatchField(Unit, "speed", f32(6))},   // the last patch wins
        assets = {6},
    }

    resolved: Unit
    PrefabResolve(&fast_and_tough, &resolved)
    testing.expect_value(t, resolved.speed, f32(6))
    testing.expect_value(t, resolved.health, f32(300))
    testing.expect_value(t, resolved.name, "grunt")                                                     // inherited from the root
    testing.expect_value(t, resolved.tint, [4]u8{255, 255, 255, 255})

    PrefabResolve(&root, &resolved)
    testing.expect_value(t, resolved.speed, f32(1))                                                     // the base is not changed by its children
    PrefabResolve(&fast, &resolved)
    testing.expect_value(t, resolved.speed, f32(5))

    buffer: [8]AssetId
    assets: []AssetId = PrefabAssets(&fast_and_tough, buffer[:])
    testing.expect_value(t, len(assets), 4)                                                             // 6, 4, 5, 3: no repeats
    for wanted in ([]AssetId{3, 4, 5, 6}) {
        found: bool
        for id in assets { found ||= id == wanted }
        testing.expectf(t, found, "asset %d is a dependency", wanted)
    }
    tiny: [2]AssetId
    testing.expect_value(t, len(PrefabAssets(&fast_and_tough, tiny[:])), 2)                             // a short buffer does not overflow
}

@(test)
test_instance_override_costs_a_copy :: proc(t: ^testing.T) {
    root: PrefabDef(Unit) = {value = {stats = {speed = 1, health = 100}}}
    resolved: Unit
    PrefabResolve(&root, &resolved)                                                                     // once, for example when the scene starts

    overrides: [1]FieldPatch = {PatchField(Unit, "health", f32(10))}
    spawned: [3]Unit
    for &unit, i in spawned {
        unit = resolved                                                                                 // the spawn: a struct copy
        if i == 1 { PrefabApply(&unit, overrides[:]) }                                                  // one instance overridden
    }
    testing.expect_value(t, spawned[0].health, f32(100))
    testing.expect_value(t, spawned[1].health, f32(10))
    testing.expect_value(t, spawned[2].health, f32(100))
}
