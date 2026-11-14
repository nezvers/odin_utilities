package scene

// Levels as data: what a level editor saves and a game loads. A level is a list of entities, each one an instance of a prefab with
// a transform and overrides, a list of assets, and chunks of other libraries in the same file (tilemaps, box2d bodies, see ../serial).
//
//   - Prefabs are referred to by NAME and assets by NAME, never by id or index, so a level file survives code that is changed,
//     assets that are reordered and prefabs that are added.
//   - An override is the PATH of a field ("max_speed", "health.value") and the new bytes, not an offset. Offsets change when a struct
//     does. The paths are resolved to offsets once (LevelResolvePatches, when the scene starts), spawning then applies plain
//     FieldPatch values: a few memcpy calls, like any prefab override.
//   - A patch whose field is gone, or has another size now, is rejected and counted, the rest of the level still loads.
//   - An entity has an id that other data refers to: the user_id of a box2d body (see ../box2d_odin/physics_serial.odin) is the id of
//     the entity that owns it. Entities can have a parent entity (an id), like a node tree.
//
// Loading fills storage the user provides and reads names as views into the file data (the data has to stay alive while the level is
// used). Nothing allocates. A file with anything inconsistent is refused as a whole: finite numbers, ids unique, parents that exist
// and no loops, counts within limits.
//
// Writing and reading of a whole file, an editor saving a level with a tilemap and physics:
//     serial.FileBegin(&writer); LevelWrite(&writer, level); tilemap.TilemapSerialWrite(...); PhysicsDescWrite(...); serial.FileEnd(&writer)
//     level, ok := LevelOpen(bytes, storage)   // then tilemap.TilemapSerialRead(level.file, 0, ...), PhysicsDescRead(level.file, ...)
// This package builds for js_wasm32, the tests are in level_test.odin.

import "base:runtime"
import "../serial"

LEVEL_TAG :: #force_inline proc "contextless" () -> serial.Tag { return serial.MakeTag('L', 'E', 'V', 'L') }
LEVEL_CHUNK_VERSION :: u16(1)

// What a file may claim
LEVEL_MAX_ENTITIES :: 1 << 14
LEVEL_MAX_ASSETS :: 1 << 10
LEVEL_MAX_PATCHES_PER_ENTITY :: 32
LEVEL_MAX_PATH :: 64

// An override as it is saved: the path of a field and the new bytes
PatchRecord :: struct {
    path: string,                   // a view into the file data
    size: u8,
    bytes: [PATCH_BYTES]u8,
}

// An instance of a prefab
EntityRecord :: struct {
    id: u32,                        // unique in the level, not 0
    parent: u32,                    // id of the parent entity, 0 - none
    prefab: string,                 // name of the prefab (a view into the file data)
    position: [2]f32,
    rotation: f32,
    scale: [2]f32,
    patch_start: u32,               // its overrides are Level.patches[patch_start:patch_start + patch_count]
    patch_count: u32,
    prefab_id: PrefabId,            // set by LevelResolve
}

Level :: struct {
    name: string,
    asset_names: []string,          // assets that the level uses directly (tile atlas texture, music ...)
    asset_ids: []AssetId,           // set by LevelResolve, same order. ASSET_NONE for a name that is not in the asset table
    entities: []EntityRecord,
    patches: []PatchRecord,
    file: serial.Reader,            // the whole file, to read the chunks of other libraries
}

// The memory a Level is read into, the user provides it. The length of each slice is the capacity.
LevelStorage :: struct {
    asset_names: []string,
    asset_ids: []AssetId,
    entities: []EntityRecord,
    patches: []PatchRecord,
}

// --- Saving ---

@(private)
PatchRecordValid :: proc(record: PatchRecord) -> bool {
    return len(record.path) > 0 && len(record.path) <= LEVEL_MAX_PATH && record.size > 0 && int(record.size) <= PATCH_BYTES
}

// Generic procs are not checked until they are used, so the import is used here for them
@(private)
CopyValue :: proc "contextless" (destination: rawptr, source: rawptr, size: int) {
    runtime.mem_copy(destination, source, size)
}

// An override for a field of T, by path, checked against the type now: the field has to exist and the value has to have its size
PatchRecordMake :: proc($T: typeid, $path: string, value: $V) -> (record: PatchRecord, ok: bool) {
    _, size, found := FindFieldOffset(type_info_of(T), path)
    if !found || size != size_of(V) || size_of(V) > PATCH_BYTES || len(path) > LEVEL_MAX_PATH { return }
    record.path = path
    record.size = u8(size_of(V))
    value_copy: V = value
    CopyValue(&record.bytes[0], &value_copy, size_of(V))
    return record, true
}

// The chunk of the level. Entities carry their overrides inline. Writes nothing wrong: asserts on what the editor must not produce
LevelWrite :: proc(writer: ^serial.Writer, level: Level) {
    serial.ChunkBegin(writer, LEVEL_TAG(), LEVEL_CHUNK_VERSION)
    serial.WriteString(writer, level.name)

    serial.WriteU32(writer, u32(len(level.asset_names)))
    for name in level.asset_names { serial.WriteString(writer, name) }

    serial.WriteU32(writer, u32(len(level.entities)))
    for entity in level.entities {
        serial.WriteU32(writer, entity.id)
        serial.WriteU32(writer, entity.parent)
        serial.WriteString(writer, entity.prefab)
        serial.WriteF32(writer, entity.position.x)
        serial.WriteF32(writer, entity.position.y)
        serial.WriteF32(writer, entity.rotation)
        serial.WriteF32(writer, entity.scale.x)
        serial.WriteF32(writer, entity.scale.y)
        serial.WriteU8(writer, u8(entity.patch_count))
        for i in 0 ..< int(entity.patch_count) {
            record: PatchRecord = level.patches[int(entity.patch_start) + i]
            assert(PatchRecordValid(record))
            serial.WriteString(writer, record.path)
            serial.WriteU8(writer, record.size)
            serial.WriteBytes(writer, record.bytes[:record.size])
        }
    }
    serial.ChunkEnd(writer)
}

// --- Loading ---

@(private)
FiniteFloat :: proc(value: f32) -> bool {
    return value == value && value - value == 0         // not NaN, not infinite
}

// Open a whole file and read its level chunk into `storage`. The data has to stay alive while the level is used.
LevelOpen :: proc(data: []byte, storage: LevelStorage) -> (level: Level, ok: bool) {
    file, _, opened := serial.FileOpen(data)
    if !opened { return }
    return LevelRead(file, storage)
}

// Read the level chunk of a file that is open already
LevelRead :: proc(file: serial.Reader, storage: LevelStorage) -> (level: Level, ok: bool) {
    version, payload, found := serial.ChunkFind(file, LEVEL_TAG())
    if !found || version > LEVEL_CHUNK_VERSION { return }

    level.file = file
    level.name = serial.ReadString(&payload)

    asset_count: int = serial.ReadCount(&payload, min(LEVEL_MAX_ASSETS, len(storage.asset_names)), 2)
    if int(asset_count) > len(storage.asset_ids) { return }
    for i in 0 ..< asset_count {
        storage.asset_names[i] = serial.ReadString(&payload)
        storage.asset_ids[i] = ASSET_NONE
    }
    level.asset_names = storage.asset_names[:asset_count]
    level.asset_ids = storage.asset_ids[:asset_count]

    entity_count: int = serial.ReadCount(&payload, min(LEVEL_MAX_ENTITIES, len(storage.entities)), 31)
    patch_total: int
    for i in 0 ..< entity_count {
        entity: EntityRecord
        entity.id = serial.ReadU32(&payload)
        entity.parent = serial.ReadU32(&payload)
        entity.prefab = serial.ReadString(&payload)
        entity.position = {serial.ReadF32(&payload), serial.ReadF32(&payload)}
        entity.rotation = serial.ReadF32(&payload)
        entity.scale = {serial.ReadF32(&payload), serial.ReadF32(&payload)}
        patch_count: int = int(serial.ReadU8(&payload))
        if !serial.ReaderOk(&payload) || patch_count > LEVEL_MAX_PATCHES_PER_ENTITY || patch_total + patch_count > len(storage.patches) { return }
        entity.patch_start = u32(patch_total)
        entity.patch_count = u32(patch_count)
        entity.prefab_id = PREFAB_NONE
        for _ in 0 ..< patch_count {
            record: PatchRecord
            record.path = serial.ReadString(&payload)
            record.size = serial.ReadU8(&payload)
            if int(record.size) > PATCH_BYTES { return }
            bytes: []byte = serial.ReadBytes(&payload, int(record.size))
            copy(record.bytes[:], bytes)
            if !serial.ReaderOk(&payload) || !PatchRecordValid(record) { return }
            storage.patches[patch_total] = record
            patch_total += 1
        }
        finite: bool = FiniteFloat(entity.position.x) && FiniteFloat(entity.position.y) && FiniteFloat(entity.rotation)
        finite &&= FiniteFloat(entity.scale.x) && FiniteFloat(entity.scale.y)
        if entity.id == 0 || !finite || len(entity.prefab) == 0 { return }
        storage.entities[i] = entity
    }
    if !serial.ReaderOk(&payload) { return }
    level.entities = storage.entities[:entity_count]
    level.patches = storage.patches[:patch_total]

    // ids are unique and a parent exists and does not lead back to the entity itself
    for i in 0 ..< entity_count {
        for j in i + 1 ..< entity_count {
            if level.entities[i].id == level.entities[j].id { return }
        }
    }
    for i in 0 ..< entity_count {
        current: u32 = level.entities[i].parent
        for step in 0 ..= entity_count {
            if current == 0 { break }
            if step == entity_count { return }          // longer than the number of entities: a loop
            parent_index: int = LevelFindEntity(level, current)
            if parent_index < 0 { return }
            current = level.entities[parent_index].parent
        }
    }
    return level, true
}

// The index of the entity with this id, or -1
LevelFindEntity :: proc(level: Level, id: u32) -> int {
    for entity, i in level.entities {
        if entity.id == id { return i }
    }
    return -1
}

// A chunk of another library in the same file (tilemaps, physics)
LevelChunk :: proc(level: Level, tag: serial.Tag) -> (version: u16, payload: serial.Reader, ok: bool) {
    return serial.ChunkFind(level.file, tag)
}

// --- Using a level ---

// Turn the names into ids: the assets of the level by the names in the asset table, the prefabs of the entities by the names they
// were registered with. Returns what is not known (an asset that was removed, a prefab that was renamed): the level still works,
// those entities should be skipped when spawning (their prefab_id is PREFAB_NONE).
LevelResolve :: proc(system: ^SceneSystem, level: ^Level) -> (missing_assets: int, missing_prefabs: int) {
    for name, i in level.asset_names {
        level.asset_ids[i] = ASSET_NONE
        for def, index in system.assets.defs {
            if index > 0 && def.name == name {
                level.asset_ids[i] = AssetId(index)
                break
            }
        }
        if level.asset_ids[i] == ASSET_NONE { missing_assets += 1 }
    }
    for &entity in level.entities {
        id, found := PrefabFind(system, entity.prefab)
        entity.prefab_id = id
        if !found { missing_prefabs += 1 }
    }
    return
}

// The overrides of an entity as FieldPatch values for the prefab type T, resolved once (when the scene starts) and used at every
// spawn. A patch that does not fit (no such field now, another size) is rejected and counted.
LevelResolvePatches :: proc($T: typeid, level: Level, entity: EntityRecord, out: []FieldPatch) -> (count: int, rejected: int) {
    for i in 0 ..< int(entity.patch_count) {
        record: PatchRecord = level.patches[int(entity.patch_start) + i]
        offset, size, found := FindFieldOffset(type_info_of(T), record.path)
        if !found || size != int(record.size) || count >= len(out) {
            rejected += 1
            continue
        }
        patch: FieldPatch = {offset = u32(offset), size = record.size}
        copy(patch.bytes[:], record.bytes[:record.size])
        out[count] = patch
        count += 1
    }
    return
}

// --- Loading the assets of a level together with its scene (see LevelAttach) ---

// Every prefab of the level once, with a flag per prefab so its assets are not counted for each entity that uses it
@(private)
LevelRequiredCount :: proc(system: ^SceneSystem, level: ^Level) -> (settled: int, total: int) {
    for id in level.asset_ids {
        if id == ASSET_NONE { continue }
        total += 1
        if AssetIsSettled(&system.assets, id) { settled += 1 }
    }
    seen: [MAX_PREFABS]bool
    for entity in level.entities {
        if int(entity.prefab_id) >= system.prefab_count || seen[entity.prefab_id] { continue }
        seen[entity.prefab_id] = true
        for asset in PrefabAssetsOf(system, entity.prefab_id) {
            if asset == ASSET_NONE { continue }
            total += 1
            if AssetIsSettled(&system.assets, asset) { settled += 1 }
        }
    }
    return
}

@(private)
LevelRequestAssets :: proc(system: ^SceneSystem, level: ^Level, blocking: bool) {
    for id in level.asset_ids { AssetRequest(&system.assets, id, blocking) }
    seen: [MAX_PREFABS]bool
    for entity in level.entities {
        if int(entity.prefab_id) >= system.prefab_count || seen[entity.prefab_id] { continue }
        seen[entity.prefab_id] = true
        PrefabRequest(system, entity.prefab_id, blocking)
    }
}

@(private)
LevelWantAssets :: proc(system: ^SceneSystem, level: ^Level) {
    for id in level.asset_ids { AssetWant(&system.assets, id) }
    seen: [MAX_PREFABS]bool
    for entity in level.entities {
        if int(entity.prefab_id) >= system.prefab_count || seen[entity.prefab_id] { continue }
        seen[entity.prefab_id] = true
        for asset in PrefabAssetsOf(system, entity.prefab_id) { AssetWant(&system.assets, asset) }
    }
}
