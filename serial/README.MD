# Serial

Binary files for level editors and saves. A small writer and reader, chunks, and a file frame. Builds for js_wasm32 (the tests are in `serial_test.odin`).

```
file  = header (magic, format version, flags, size, crc32 of everything after the header) + chunks
chunk = tag (4 letters) + version + length + payload
```
- **Chunks** have their own version and a length: a reader skips chunks it does not know, a newer file opens in an older program. Every library writes and reads its own chunks (`tilemap`, `box2d_odin`, `scene` levels) and one file holds them all.
- **Portable**: little endian whatever the machine, written field by field (no struct memcpy, no padding, no pointers).
- **Memory**: the writer fills a buffer you provide (`WriterInitCounting` runs the same code to tell the size to provide), the reader works on a byte slice you loaded. Strings and byte runs that are read are views into that slice.
- **Safe on untrusted data**: every read is bounds checked, a failed read sets a sticky flag and gives zeros, counts are checked against limits and against the data left (`ReadCount`) before anything is sized from them. `FileOpen` refuses another kind of file, a newer format, a wrong size and any changed byte (crc32). Check `ReaderOk` when you are done reading, not after every value.
- **`RleWrite` / `RleRead`**: run length encoding for bytes that repeat (tile ids).

```odin
writer: serial.Writer
serial.WriterInit(&writer, buffer)
serial.FileBegin(&writer)
    serial.ChunkBegin(&writer, serial.MakeTag('M', 'Y', 'D', 'T'), 1)
    serial.WriteString(&writer, "name"); serial.WriteF32(&writer, 1.5)
    serial.ChunkEnd(&writer)
bytes := serial.FileEnd(&writer)                       // nil if anything failed (buffer too small ...)

file, flags, ok := serial.FileOpen(bytes)
version, payload, found := serial.ChunkFind(file, serial.MakeTag('M', 'Y', 'D', 'T'))
name := serial.ReadString(&payload); value := serial.ReadF32(&payload)
```

## The level file
One file composes the chunks of several libraries, this is what a level editor saves:
```odin
serial.FileBegin(&writer)
scene.LevelWrite(&writer, level)                              // entities (prefab instances with overrides), asset names
tilemap.TilemapSerialWrite(&writer, &ground, "ground")        // tilemap layers, run length encoded; atlas and tileset too
box2d.PhysicsDescWrite(&writer, physics)                      // bodies, shapes and hinges of characters and level geometry
serial.FileEnd(&writer)

level, ok := scene.LevelOpen(bytes, storage)                  // then, from the same file:
tilemap.TilemapSerialReadNamed(level.file, "ground", buffer)
box2d.PhysicsDescRead(level.file, &physics); box2d.PhysicsCreate(world, physics, bodies)
```
- Prefabs and assets are referred to by **name**, overrides by the **path** of a field (`"stats.health"`), so a file survives code that changes, assets that are reordered and structs that are reordered. What no longer fits is rejected and counted, the rest of the level loads.
- The id of an entity is the `user_id` of the box2d body that belongs to it, that is the link between the two.
- `scene.LevelAttach(system, scene_id, &level)` makes the assets and the prefab assets of a level part of that scene: prefetched when the scene is expected, waited for behind the transition when it was not, unloaded when it is left.
- A file with anything inconsistent (a NaN, an id twice, a parent that does not exist or leads back to itself, a count over the limit) is refused as a whole, never half loaded.
- `scene/level_integration_test.odin` is the whole pipeline: entities, two tilemap layers and box2d characters in one file, saved, loaded and simulated.
