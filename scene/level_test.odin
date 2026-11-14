#+build !js
// Tests of level.odin. They are in their own file because the scene system is imported by games with a web build, and core:testing does not compile for js_wasm32.
package scene

import "base:runtime"
import "core:hash"
import "core:math"
import "core:testing"
import "../serial"

@(private="file")
LevelStats :: struct {
    speed: f32,
    health: f32,
}

// the prefab type of the tests
@(private="file")
LevelUnit :: struct {
    using stats: LevelStats,
    name: string,
    tint: [4]u8,
    count: int,
}

// the same prefab after the code changed: fields reordered, one retyped, one removed, one added
@(private="file")
LevelUnitNewer :: struct {
    count: int,
    extra: [2]f32,
    tint: [4]u8,
    using stats: LevelStats,
    name: u32,              // was a string
}

@(private="file")
test_storage :: struct {
    asset_names: [8]string,
    asset_ids: [8]AssetId,
    entities: [16]EntityRecord,
    patches: [32]PatchRecord,
}

@(private="file")
storage_of :: proc(storage: ^test_storage) -> LevelStorage {
    return {asset_names = storage.asset_names[:], asset_ids = storage.asset_ids[:], entities = storage.entities[:], patches = storage.patches[:]}
}

// static: the slice inside of a returned level has to outlive the call
@(private="file")
level_asset_names: [2]string = {"tiles", "music"}

// A level that an editor would make: three entities, one is the child of another, with overrides
@(private="file")
make_test_level :: proc(entities: []EntityRecord, patches: []PatchRecord) -> Level {
    speed, _ := PatchRecordMake(LevelUnit, "speed", f32(7.5))
    health, _ := PatchRecordMake(LevelUnit, "stats.health", f32(25))
    tint, _ := PatchRecordMake(LevelUnit, "tint", [4]u8{9, 8, 7, 6})
    patches[0] = speed
    patches[1] = health
    patches[2] = tint
    entities[0] = {id = 1, prefab = "zombie", position = {10, 20}, rotation = 0.5, scale = {1, 1}, patch_start = 0, patch_count = 2}
    entities[1] = {id = 2, parent = 1, prefab = "plumber", position = {-3, 4}, scale = {2, 2}}
    entities[2] = {id = 7, parent = 2, prefab = "zombie", position = {0, 0}, scale = {1, 1}, patch_start = 2, patch_count = 1}
    return {
        name = "forest",
        asset_names = level_asset_names[:],
        entities = entities[:3],
        patches = patches[:3],
    }
}

@(private="file")
save_level :: proc(level: Level, buffer: []byte, extra_chunk: bool = false) -> []byte {
    writer: serial.Writer
    serial.WriterInit(&writer, buffer)
    serial.FileBegin(&writer)
    if extra_chunk {
        serial.ChunkBegin(&writer, serial.MakeTag('X', 'T', 'R', 'A'), 5)       // another library's chunk before the level
        serial.WriteU32(&writer, 12345)
        serial.ChunkEnd(&writer)
    }
    LevelWrite(&writer, level)
    if extra_chunk {
        serial.ChunkBegin(&writer, serial.MakeTag('Y', 'T', 'R', 'A'), 1)
        serial.WriteString(&writer, "after")
        serial.ChunkEnd(&writer)
    }
    return serial.FileEnd(&writer)
}

@(test)
test_a_level_round_trips_with_names_ids_and_overrides :: proc(t: ^testing.T) {
    entities: [16]EntityRecord
    patches: [32]PatchRecord
    level: Level = make_test_level(entities[:], patches[:])
    buffer: [2048]byte
    bytes: []byte = save_level(level, buffer[:])
    testing.expect(t, bytes != nil)

    storage: test_storage
    loaded, ok := LevelOpen(bytes, storage_of(&storage))
    testing.expect(t, ok)
    testing.expect_value(t, loaded.name, "forest")
    testing.expect_value(t, len(loaded.asset_names), 2)
    testing.expect_value(t, loaded.asset_names[1], "music")
    testing.expect_value(t, len(loaded.entities), 3)
    testing.expect_value(t, loaded.entities[0].prefab, "zombie")
    testing.expect_value(t, loaded.entities[0].position, [2]f32{10, 20})
    testing.expect_value(t, loaded.entities[0].rotation, f32(0.5))
    testing.expect_value(t, loaded.entities[1].parent, u32(1))
    testing.expect_value(t, loaded.entities[1].scale, [2]f32{2, 2})
    testing.expect_value(t, loaded.entities[2].id, u32(7))
    testing.expect_value(t, len(loaded.patches), 3)
    testing.expect_value(t, loaded.patches[0].path, "speed")
    testing.expect_value(t, loaded.patches[1].path, "stats.health")
    testing.expect_value(t, loaded.entities[0].patch_count, u32(2))
    testing.expect_value(t, loaded.entities[2].patch_start, u32(2))
    testing.expect_value(t, LevelFindEntity(loaded, 7), 2)
    testing.expect_value(t, LevelFindEntity(loaded, 99), -1)

    // the names are views into the file, not copies
    data_start: uintptr = uintptr(raw_data(bytes))
    name_start: uintptr = uintptr(raw_data(loaded.name))
    testing.expect(t, name_start >= data_start && name_start < data_start + uintptr(len(bytes)), "no copy of the strings")
}

@(test)
test_chunks_of_other_libraries_sit_next_to_the_level :: proc(t: ^testing.T) {
    entities: [16]EntityRecord
    patches: [32]PatchRecord
    level: Level = make_test_level(entities[:], patches[:])
    buffer: [2048]byte
    bytes: []byte = save_level(level, buffer[:], true)

    storage: test_storage
    loaded, ok := LevelOpen(bytes, storage_of(&storage))
    testing.expect(t, ok, "chunks before and after are skipped")
    testing.expect_value(t, len(loaded.entities), 3)

    version, payload, found := LevelChunk(loaded, serial.MakeTag('X', 'T', 'R', 'A'))
    testing.expect(t, found)
    testing.expect_value(t, version, u16(5))
    testing.expect_value(t, serial.ReadU32(&payload), u32(12345))
    _, after, after_found := LevelChunk(loaded, serial.MakeTag('Y', 'T', 'R', 'A'))
    testing.expect(t, after_found)
    testing.expect_value(t, serial.ReadString(&after), "after")
    _, _, missing := LevelChunk(loaded, serial.MakeTag('N', 'O', 'N', 'E'))
    testing.expect(t, !missing)
}

@(test)
test_overrides_are_resolved_once_and_applied_as_plain_patches :: proc(t: ^testing.T) {
    entities: [16]EntityRecord
    patches: [32]PatchRecord
    level: Level = make_test_level(entities[:], patches[:])
    buffer: [2048]byte
    storage: test_storage
    loaded, _ := LevelOpen(save_level(level, buffer[:]), storage_of(&storage))

    resolved: [8]FieldPatch
    count, rejected := LevelResolvePatches(LevelUnit, loaded, loaded.entities[0], resolved[:])
    testing.expect_value(t, count, 2)
    testing.expect_value(t, rejected, 0)

    base: LevelUnit = {stats = {speed = 1, health = 100}, name = "grunt", count = 3}
    spawned: [3]LevelUnit
    for &unit in spawned { unit = base }                                             // a spawn is a struct copy
    PrefabApply(&spawned[1], resolved[:count])                                       // and the overrides of this entity a few memcpy
    testing.expect_value(t, spawned[1].speed, f32(7.5))                              // found through `using`
    testing.expect_value(t, spawned[1].health, f32(25))                              // found through the full path
    testing.expect_value(t, spawned[1].name, "grunt")                                // the rest is the prefab
    testing.expect_value(t, spawned[0].speed, f32(1))                                // other instances are not touched

    third, _ := LevelResolvePatches(LevelUnit, loaded, loaded.entities[2], resolved[:])
    testing.expect_value(t, third, 1)
    PrefabApply(&spawned[2], resolved[:third])
    testing.expect_value(t, spawned[2].tint, [4]u8{9, 8, 7, 6})
}

@(test)
test_a_level_survives_the_prefab_type_changing :: proc(t: ^testing.T) {
    // the file was saved against LevelUnit, the code now has LevelUnitNewer: other offsets, a retyped field, a missing field
    entities: [16]EntityRecord
    patches: [32]PatchRecord
    level: Level = make_test_level(entities[:], patches[:])
    buffer: [2048]byte
    storage: test_storage
    loaded, _ := LevelOpen(save_level(level, buffer[:]), storage_of(&storage))

    resolved: [8]FieldPatch
    count, rejected := LevelResolvePatches(LevelUnitNewer, loaded, loaded.entities[0], resolved[:])
    testing.expect_value(t, count, 2)                                                // speed and stats.health are still there, at other offsets
    testing.expect_value(t, rejected, 0)
    unit: LevelUnitNewer
    PrefabApply(&unit, resolved[:count])
    testing.expect_value(t, unit.speed, f32(7.5))
    testing.expect_value(t, unit.health, f32(25))

    // a patch for a field that is gone, and one whose size changed
    gone: PatchRecord = {path = "removed_field", size = 4}
    resized: PatchRecord = {path = "name", size = 16}                                // was a string (16 bytes), is a u32 now
    entity: EntityRecord = {patch_start = 0, patch_count = 3}
    records: [3]PatchRecord = {gone, resized, patches[0]}
    custom: Level = {patches = records[:]}
    count, rejected = LevelResolvePatches(LevelUnitNewer, custom, entity, resolved[:])
    testing.expect_value(t, count, 1)
    testing.expect_value(t, rejected, 2)                                             // counted, the good one still applies

    tiny: [1]FieldPatch
    records = {patches[0], patches[1], patches[2]}
    count, rejected = LevelResolvePatches(LevelUnit, custom, entity, tiny[:])
    testing.expect_value(t, count, 1)
    testing.expect_value(t, rejected, 2)                                             // the ones that did not fit the output
}

@(test)
test_patch_record_make_checks_the_field_and_the_size :: proc(t: ^testing.T) {
    _, ok := PatchRecordMake(LevelUnit, "speed", f32(1))
    testing.expect(t, ok)
    _, nested := PatchRecordMake(LevelUnit, "stats.health", f32(1))
    testing.expect(t, nested)
    _, no_field := PatchRecordMake(LevelUnit, "wings", f32(1))
    testing.expect(t, !no_field, "no such field")
    _, wrong_size := PatchRecordMake(LevelUnit, "speed", 1)
    testing.expect(t, !wrong_size, "an int is not a f32")
    _, too_big := PatchRecordMake(LevelUnit, "name", "x")
    testing.expect(t, too_big, "a string is 16 bytes and fits")
}

// --- Names to ids ---

@(private="file", thread_local)
level_log: [16]AssetId
@(private="file", thread_local)
level_load_count: int

@(private="file")
level_load :: proc(def: ^AssetDef, scratch: runtime.Allocator) -> (AssetValue, bool) {
    level_load_count += 1
    return {handle = 100 + u64(def.flags)}, true
}

@(private="file")
LevelWorld :: struct {
    scenes: [2]SceneDef,
    defs: [7]AssetDef,
    loaders: [1]AssetLoader,
    storage: AssetStorage(7),
    system: SceneSystem,
}

@(private="file")
level_world_init :: proc(world_pointer: rawptr) {
    world: ^LevelWorld = cast(^LevelWorld)world_pointer
    level_load_count = 0
    // 0 none, 1 tiles, 2 music, 3 zombie texture, 4 plumber texture, 5 other, 6 unused
    for name, i in ([7]string{"none", "tiles", "music", "zombie texture", "plumber texture", "other", "unused"}) {
        world.defs[i] = {name = name, flags = u32(i)}
    }
    world.loaders[0] = {load = level_load}
    world.scenes = {{name = "menu"}, {name = "level"}}
    SceneSystemInit(&world.system, {}, world.scenes[:], world.defs[:], world.loaders[:], &world.storage)
    PrefabRegisterNamed(&world.system, "zombie", {3})
    PrefabRegisterNamed(&world.system, "plumber", {4})
}

@(test)
test_prefabs_have_names_and_levels_resolve_names_to_ids :: proc(t: ^testing.T) {
    world: LevelWorld
    level_world_init(rawptr(&world))
    system: ^SceneSystem = &world.system

    id, found := PrefabFind(system, "plumber")
    testing.expect(t, found)
    testing.expect_value(t, id, PrefabId(1))
    testing.expect_value(t, PrefabName(system, id), "plumber")
    _, missing := PrefabFind(system, "dragon")
    testing.expect(t, !missing)
    _, prefix := PrefabFind(system, "plumb")
    testing.expect(t, !prefix, "whole names only")
    testing.expect_value(t, PrefabName(system, PREFAB_NONE), "")

    entities: [16]EntityRecord
    patches: [32]PatchRecord
    level: Level = make_test_level(entities[:], patches[:])
    level.asset_names = {"music", "tiles", "a removed asset"}
    buffer: [2048]byte
    storage: test_storage
    loaded, _ := LevelOpen(save_level(level, buffer[:]), storage_of(&storage))
    loaded.entities[1].prefab = "dragon"                                             // a prefab that does not exist (any more)

    missing_assets, missing_prefabs := LevelResolve(system, &loaded)
    testing.expect_value(t, missing_assets, 1)
    testing.expect_value(t, missing_prefabs, 1)
    testing.expect_value(t, loaded.asset_ids[0], AssetId(2))                         // by name, whatever the order of the table
    testing.expect_value(t, loaded.asset_ids[1], AssetId(1))
    testing.expect_value(t, loaded.asset_ids[2], ASSET_NONE)
    testing.expect_value(t, loaded.entities[0].prefab_id, PrefabId(0))
    testing.expect_value(t, loaded.entities[1].prefab_id, PREFAB_NONE)
}

@(test)
test_the_assets_of_a_level_are_the_assets_of_its_scene :: proc(t: ^testing.T) {
    world: LevelWorld
    level_world_init(rawptr(&world))
    system: ^SceneSystem = &world.system

    entities: [16]EntityRecord
    patches: [32]PatchRecord
    level: Level = make_test_level(entities[:], patches[:])                           // tiles, music, zombie x2, plumber
    buffer: [2048]byte
    storage: test_storage
    loaded, _ := LevelOpen(save_level(level, buffer[:]), storage_of(&storage))
    LevelResolve(system, &loaded)
    LevelAttach(system, 1, &loaded)

    settled, total := SceneRequiredCount(system, 1)
    testing.expect_value(t, total, 4)                                                // 2 level assets + zombie texture once + plumber texture
    testing.expect_value(t, settled, 0)
    testing.expect(t, !SceneIsReady(system, 1))
    testing.expect_value(t, SceneProgress(system, 1), f32(0))

    SceneStart(system, 0)
    for _ in 0 ..< 30 { SceneUpdate(system, 1.0 / 60) }
    SceneGoto(system, 1)                                                             // not prefetched: a transition, the assets are blocking
    testing.expect_value(t, system.transition.phase, TransitionPhase.OUT)
    testing.expect(t, AssetsHaveBlocking(&system.assets))
    for _ in 0 ..< 200 { SceneUpdate(system, 1.0 / 60) }
    testing.expect(t, system.current == 1 && system.entered, "the scene started when everything of the level was ready")
    for id in ([]AssetId{1, 2, 3, 4}) { testing.expect(t, AssetIsReady(&system.assets, id)) }
    testing.expect(t, !AssetIsReady(&system.assets, 5) && !AssetIsReady(&system.assets, 6), "and nothing else was loaded")
    testing.expect_value(t, level_load_count, 4)

    // leaving it unloads what only the level needed
    SceneGoto(system, 0)
    for _ in 0 ..< 60 { SceneUpdate(system, 1.0 / 60) }
    testing.expect(t, system.current == 0)
    testing.expect(t, !AssetIsReady(&system.assets, 1), "the level assets went with the scene")

    LevelDetach(system, 1)
    testing.expect(t, SceneIsReady(system, 1), "a scene without the level needs nothing")
}

@(test)
test_a_level_can_be_prefetched_before_it_is_entered :: proc(t: ^testing.T) {
    world: LevelWorld
    level_world_init(rawptr(&world))
    system: ^SceneSystem = &world.system
    entities: [16]EntityRecord
    patches: [32]PatchRecord
    level: Level = make_test_level(entities[:], patches[:])
    buffer: [2048]byte
    storage: test_storage
    loaded, _ := LevelOpen(save_level(level, buffer[:]), storage_of(&storage))
    LevelResolve(system, &loaded)
    LevelAttach(system, 1, &loaded)

    SceneStart(system, 0)
    for _ in 0 ..< 30 { SceneUpdate(system, 1.0 / 60) }
    SceneExpect(system, 1)                                                           // the player walks toward the door
    testing.expect(t, !AssetsHaveBlocking(&system.assets), "a hint is background work")
    for _ in 0 ..< 60 { SceneUpdate(system, 1.0 / 60) }
    testing.expect(t, SceneIsReady(system, 1))
    SceneGoto(system, 1)
    testing.expect_value(t, system.transition.phase, TransitionPhase.NONE)          // so the level starts at once
    testing.expect(t, system.current == 1)
}

// --- Bad files ---

// A file whose level chunk is written by hand, so it can contain what LevelWrite would never produce
@(private="file")
craft_level_file :: proc(buffer: []byte, entity_count: int, write_entity: proc(writer: ^serial.Writer, index: int)) -> []byte {
    writer: serial.Writer
    serial.WriterInit(&writer, buffer)
    serial.FileBegin(&writer)
    serial.ChunkBegin(&writer, LEVEL_TAG(), 1)
    serial.WriteString(&writer, "crafted")
    serial.WriteU32(&writer, 0)                                                      // no assets
    serial.WriteU32(&writer, u32(entity_count))
    for i in 0 ..< entity_count { write_entity(&writer, i) }
    serial.ChunkEnd(&writer)
    return serial.FileEnd(&writer)
}

@(private="file")
write_entity :: proc(writer: ^serial.Writer, id: u32, parent: u32, prefab: string, position: f32 = 0, patch_count: u8 = 0) {
    serial.WriteU32(writer, id)
    serial.WriteU32(writer, parent)
    serial.WriteString(writer, prefab)
    serial.WriteF32(writer, position)
    serial.WriteF32(writer, 0)
    serial.WriteF32(writer, 0)
    serial.WriteF32(writer, 1)
    serial.WriteF32(writer, 1)
    serial.WriteU8(writer, patch_count)
}

@(private="file")
opens :: proc(bytes: []byte) -> bool {
    storage: test_storage
    _, ok := LevelOpen(bytes, storage_of(&storage))
    return ok
}

@(test)
test_a_good_crafted_file_opens :: proc(t: ^testing.T) {
    buffer: [512]byte
    good: []byte = craft_level_file(buffer[:], 2, proc(writer: ^serial.Writer, index: int) {
        write_entity(writer, u32(index + 1), 1 if index == 1 else 0, "unit")
    })
    testing.expect(t, opens(good), "the crafting helper itself is fine")
}

@(test)
test_levels_that_are_inconsistent_are_refused :: proc(t: ^testing.T) {
    buffer: [1024]byte

    testing.expect(t, !opens(craft_level_file(buffer[:], 2, proc(writer: ^serial.Writer, index: int) { write_entity(writer, 5, 0, "unit") })), "two entities with the same id")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) { write_entity(writer, 0, 0, "unit") })), "id 0 means no entity")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) { write_entity(writer, 1, 77, "unit") })), "a parent that does not exist")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) { write_entity(writer, 1, 1, "unit") })), "an entity that is its own parent")
    testing.expect(t, !opens(craft_level_file(buffer[:], 3, proc(writer: ^serial.Writer, index: int) {
        parents: [3]u32 = {3, 1, 2}                                                  // 1 -> 3 -> 2 -> 1: a loop
        write_entity(writer, u32(index + 1), parents[index], "unit")
    })), "parents that lead back to themselves")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) { write_entity(writer, 1, 0, "") })), "no prefab name")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) { write_entity(writer, 1, 0, "unit", math.nan_f32()) })), "NaN position")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) { write_entity(writer, 1, 0, "unit", math.INF_F32) })), "infinite position")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) { write_entity(writer, 1, 0, "unit", 0, 200) })), "more overrides than a level may have")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) {
        write_entity(writer, 1, 0, "unit", 0, 1)
        serial.WriteString(writer, "")                                               // an override without a path
        serial.WriteU8(writer, 4)
        serial.WriteU32(writer, 0)
    })), "an empty override path")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) {
        write_entity(writer, 1, 0, "unit", 0, 1)
        serial.WriteString(writer, "speed")
        serial.WriteU8(writer, 200)                                                  // more bytes than an override can hold
    })), "an override value that is too big")
    testing.expect(t, !opens(craft_level_file(buffer[:], 1, proc(writer: ^serial.Writer, index: int) {
        write_entity(writer, 1, 0, "unit", 0, 1)
        serial.WriteString(writer, "speed")
        serial.WriteU8(writer, 4)                                                    // the file ends before the value
    })), "a truncated override")
}

@(test)
test_levels_larger_than_the_storage_are_refused :: proc(t: ^testing.T) {
    entities: [16]EntityRecord
    patches: [32]PatchRecord
    level: Level = make_test_level(entities[:], patches[:])
    buffer: [2048]byte
    bytes: []byte = save_level(level, buffer[:])

    few_entities: [2]EntityRecord
    storage: test_storage
    small: LevelStorage = storage_of(&storage)
    small.entities = few_entities[:]
    _, entities_ok := LevelOpen(bytes, small)
    testing.expect(t, !entities_ok, "3 entities do not fit 2 slots")

    small = storage_of(&storage)
    small.patches = storage.patches[:2]
    _, patches_ok := LevelOpen(bytes, small)
    testing.expect(t, !patches_ok, "3 overrides do not fit 2 slots")

    small = storage_of(&storage)
    small.asset_names = storage.asset_names[:1]
    _, assets_ok := LevelOpen(bytes, small)
    testing.expect(t, !assets_ok, "2 asset names do not fit 1 slot")

    // a file with no level in it, and one with a level from the future
    empty: serial.Writer
    empty_buffer: [64]byte
    serial.WriterInit(&empty, empty_buffer[:])
    serial.FileBegin(&empty)
    testing.expect(t, !opens(serial.FileEnd(&empty)), "no level chunk")

    future_buffer: [64]byte
    serial.WriterInit(&empty, future_buffer[:])
    serial.FileBegin(&empty)
    serial.ChunkBegin(&empty, LEVEL_TAG(), LEVEL_CHUNK_VERSION + 1)
    serial.WriteString(&empty, "from the future")
    serial.ChunkEnd(&empty)
    testing.expect(t, !opens(serial.FileEnd(&empty)), "a newer level format is not read as if it were this one")
}

@(test)
test_garbage_in_the_level_chunk_never_crashes :: proc(t: ^testing.T) {
    state: u32 = 123456789
    next :: proc(state: ^u32) -> u32 {
        state^ ~= state^ << 13
        state^ ~= state^ >> 17
        state^ ~= state^ << 5
        return state^
    }
    for _ in 0 ..< 3000 {
        buffer: [600]byte
        writer: serial.Writer
        serial.WriterInit(&writer, buffer[:])
        serial.FileBegin(&writer)
        serial.ChunkBegin(&writer, LEVEL_TAG(), 1)
        length: int = int(next(&state) % 500)
        for _ in 0 ..< length { serial.WriteU8(&writer, u8(next(&state)) if length > 12 else 0) }
        serial.ChunkEnd(&writer)
        opens(serial.FileEnd(&writer))
    }

    // a real level with a few changed bytes (checksum fixed), the parser goes deep before it finds the problem
    entities: [16]EntityRecord
    patches: [32]PatchRecord
    level: Level = make_test_level(entities[:], patches[:])
    buffer: [2048]byte
    bytes: []byte = save_level(level, buffer[:])
    for _ in 0 ..< 3000 {
        copy_buffer: [2048]byte
        copy(copy_buffer[:], bytes)
        for _ in 0 ..< 1 + int(next(&state) % 3) {
            copy_buffer[serial.FILE_HEADER_SIZE + int(next(&state)) % (len(bytes) - serial.FILE_HEADER_SIZE)] = u8(next(&state))
        }
        // fix the checksum so the level parser sees the damage
        crc_fix(copy_buffer[:len(bytes)])
        opens(copy_buffer[:len(bytes)])
    }
    testing.expect(t, true, "no crash")
}

@(private="file")
crc_fix :: proc(file: []byte) {
    crc: u32 = hash.crc32(file[serial.FILE_HEADER_SIZE:])
    for i in 0 ..< 4 { file[12 + i] = u8(crc >> u32(8 * i)) }
}
