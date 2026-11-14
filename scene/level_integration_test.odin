#+build !js
// One level file with everything a level editor saves: the entities (prefab instances with overrides), the tilemap layers and the
// Box2D bodies of the characters and the ground. Written the way an editor writes it, loaded the way a game loads it.
// This test depends on the tilemap and box2d_odin libraries, the scene library itself does not.
package scene

import "core:testing"
import b2 "vendor:box2d"
import box2d "../box2d_odin"
import "../serial"
import "../tilemap"

@(private="file")
Character :: struct {
    speed: f32,
    health: f32,
    name: string,
}

@(private="file")
PLAYER_ID :: u32(1)
@(private="file")
ZOMBIE_ID :: u32(2)

// What the editor has: entities, tilemap layers, a physics description. The id of an entity is the user_id of its body.
@(private="file")
EditorData :: struct {
    entities: [4]EntityRecord,
    patches: [4]PatchRecord,
    ground_cells: [24]tilemap.TileID,
    wall_cells: [24]tilemap.TileID,
    bodies: [8]box2d.PhysicsBodyDesc,
    shapes: [8]box2d.PhysicsShapeDesc,
    joints: [1]box2d.PhysicsJointDesc,
    physics: box2d.PhysicsDesc,
}

@(private="file")
asset_names: [1]string = {"tiles"}

// the memory the game loads the level into
@(private="file")
GameStorage :: struct {
    asset_names: [4]string,
    asset_ids: [4]AssetId,
    entities: [8]EntityRecord,
    patches: [8]PatchRecord,
}

@(private="file")
game_storage_of :: proc(storage: ^GameStorage) -> LevelStorage {
    return {asset_names = storage.asset_names[:], asset_ids = storage.asset_ids[:], entities = storage.entities[:], patches = storage.patches[:]}
}

@(private="file")
build_editor_level :: proc(editor: ^EditorData) -> (level: Level, ground: tilemap.Tilemap, walls: tilemap.Tilemap) {
    // entities
    editor.patches[0], _ = PatchRecordMake(Character, "speed", f32(9))
    editor.entities[0] = {id = PLAYER_ID, prefab = "player", position = {2, 3}, scale = {1, 1}, patch_start = 0, patch_count = 1}
    editor.entities[1] = {id = ZOMBIE_ID, parent = 0, prefab = "zombie", position = {6, 3}, scale = {1, 1}}
    level = {name = "graveyard", asset_names = asset_names[:], entities = editor.entities[:2], patches = editor.patches[:1]}

    // tilemap layers
    ground = tilemap.TilemapInit({0, 0}, {6, 4}, {16, 16}, editor.ground_cells[:])
    tilemap.TilemapSetTileIdBlock(&ground, 0, 3, 6, 1, 4)                           // a floor on the bottom row
    walls = tilemap.TilemapInit({0, 0}, {6, 4}, {16, 16}, editor.wall_cells[:])
    tilemap.TilemapSetTile(&walls, {0, 2}, 9)
    tilemap.TilemapSetTile(&walls, {5, 2}, 9)

    // physics: the ground and a body for each character, linked to the entities by id
    editor.physics = {bodies = editor.bodies[:], shapes = editor.shapes[:], joints = editor.joints[:]}
    floor, _ := box2d.PhysicsAddBody(&editor.physics, .staticBody, {0, 0})
    box2d.PhysicsAddChain(&editor.physics, floor, {{12, 0}, {0, 0}})                 // solid on top: right to left
    for entity in ([]EntityRecord{editor.entities[0], editor.entities[1]}) {
        body, _ := box2d.PhysicsAddBody(&editor.physics, .dynamicBody, entity.position, 0, entity.id)
        editor.physics.bodies[body].fixed_rotation = true
        box2d.PhysicsAddCapsule(&editor.physics, body, {0, -0.4}, {0, 0.4}, 0.3).user_id = entity.id
    }
    return
}

@(test)
test_a_whole_level_with_entities_tilemaps_and_physics_in_one_file :: proc(t: ^testing.T) {
    editor := new(EditorData)
    defer free(editor)
    level, ground, walls := build_editor_level(editor)

    // ---- the editor saves
    file_buffer := make([]byte, 8192)
    defer delete(file_buffer)
    writer: serial.Writer
    serial.WriterInit(&writer, file_buffer)
    serial.FileBegin(&writer)
    LevelWrite(&writer, level)
    tilemap.TilemapSerialWrite(&writer, &ground, "ground")
    tilemap.TilemapSerialWrite(&writer, &walls, "walls")
    box2d.PhysicsDescWrite(&writer, editor.physics)
    bytes: []byte = serial.FileEnd(&writer)
    testing.expect(t, bytes != nil)

    // the same file again: writing is deterministic, so files diff and merge
    second_buffer := make([]byte, 8192)
    defer delete(second_buffer)
    again: serial.Writer
    serial.WriterInit(&again, second_buffer)
    serial.FileBegin(&again)
    LevelWrite(&again, level)
    tilemap.TilemapSerialWrite(&again, &ground, "ground")
    tilemap.TilemapSerialWrite(&again, &walls, "walls")
    box2d.PhysicsDescWrite(&again, editor.physics)
    second: []byte = serial.FileEnd(&again)
    testing.expect_value(t, len(second), len(bytes))
    identical: bool = len(second) == len(bytes)
    for value, i in bytes { identical &&= second[i] == value }
    testing.expect(t, identical, "the same level is the same bytes")

    // ---- the game loads, into its own memory
    game_storage: GameStorage
    loaded, ok := LevelOpen(bytes, game_storage_of(&game_storage))
    testing.expect(t, ok)
    testing.expect_value(t, loaded.name, "graveyard")

    ground_buffer: [24]tilemap.TileID
    loaded_ground, ground_ok := tilemap.TilemapSerialReadNamed(loaded.file, "ground", ground_buffer[:])
    testing.expect(t, ground_ok)
    testing.expect_value(t, ground_buffer, editor.ground_cells)
    testing.expect_value(t, loaded_ground.tile_size, [2]i32{16, 16})
    wall_buffer: [24]tilemap.TileID
    loaded_walls, walls_ok := tilemap.TilemapSerialReadNamed(loaded.file, "walls", wall_buffer[:])
    testing.expect(t, walls_ok)
    testing.expect_value(t, tilemap.TilemapGetTile(&loaded_walls, {5, 2}), tilemap.TileID(9))
    testing.expect_value(t, tilemap.TilemapSerialCount(loaded.file), 2)

    bodies: [8]box2d.PhysicsBodyDesc
    shapes: [8]box2d.PhysicsShapeDesc
    joints: [1]box2d.PhysicsJointDesc
    physics: box2d.PhysicsDesc = {bodies = bodies[:], shapes = shapes[:], joints = joints[:]}
    testing.expect(t, box2d.PhysicsDescRead(loaded.file, &physics))
    testing.expect_value(t, physics.body_count, 3)

    // the entities become characters: the prefab value, the override and the position of the entity
    prefab_defaults: Character = {speed = 1, health = 100, name = "creature"}
    resolved: [4]FieldPatch
    player: Character = prefab_defaults
    count, rejected := LevelResolvePatches(Character, loaded, loaded.entities[0], resolved[:])
    PrefabApply(&player, resolved[:count])
    testing.expect_value(t, rejected, 0)
    testing.expect_value(t, player.speed, f32(9))
    zombie: Character = prefab_defaults
    testing.expect_value(t, zombie.speed, f32(1))

    // the physics: every entity has the body whose user id is its id, and it behaves
    world_def: b2.WorldDef = b2.DefaultWorldDef()
    world_def.gravity = {0, -10}
    world: b2.WorldId = b2.CreateWorld(world_def)
    defer b2.DestroyWorld(world)
    created: [8]b2.BodyId
    skipped, created_ok := box2d.PhysicsCreate(world, physics, created[:])
    testing.expect(t, created_ok && skipped == 0)
    for _ in 0 ..< 180 { b2.World_Step(world, 1.0 / 60, 4) }

    for entity in loaded.entities {
        found: bool
        for i in 0 ..< physics.body_count {
            if uintptr(b2.Body_GetUserData(created[i])) != uintptr(entity.id) { continue }
            found = true
            position: [2]f32 = b2.Body_GetPosition(created[i])
            testing.expectf(t, abs(position.x - entity.position.x) < 0.01, "entity %d did not slide", entity.id)
            testing.expectf(t, position.y < entity.position.y && position.y > 0.5, "entity %d fell to the ground, it is at %v", entity.id, position)
        }
        testing.expectf(t, found, "entity %d has a body", entity.id)
    }

    // ---- one changed byte anywhere and the whole file is refused: no half loaded level
    broken := make([]byte, len(bytes))
    defer delete(broken)
    refused: int
    for i in serial.FILE_HEADER_SIZE ..< len(bytes) {
        copy(broken, bytes)
        broken[i] ~= 0x10
        _, still_opens := LevelOpen(broken, game_storage_of(&game_storage))
        if !still_opens { refused += 1 }
    }
    testing.expect_value(t, refused, len(bytes) - serial.FILE_HEADER_SIZE)
}
