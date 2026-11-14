#+build !js
// Tests of scene_karl2d.odin. They are in their own file because the scene system is imported by games with a web build, and core:testing does not compile for js_wasm32.
package scene_karl2d

import "core:image"
import "core:log"
import "core:mem"
import "core:sync"
import "core:testing"
import "core:thread"
import "../../karl2d"
import scene ".."

// The CPU side only: nothing here needs a window or a GPU.

@(test)
test_handles_survive_packing :: proc(t: ^testing.T) {
    texture: karl2d.Texture = {idx = 12, gen = 3}
    testing.expect_value(t, Unpack(Pack(texture), karl2d.Texture), texture)
    clip: karl2d.Audio_Clip = {idx = 5, gen = 9}
    testing.expect_value(t, Unpack(Pack(clip), karl2d.Audio_Clip), clip)
    font: karl2d.Font = 7
    testing.expect_value(t, Unpack(Pack(font), karl2d.Font), font)
    testing.expect_value(t, Pack(texture).extra, u64(0))
}

@(private="file")
test_defs :: proc() -> [4]scene.AssetDef {
    return {
        {name = "none"},
        {name = "a", kind = KIND_TEXTURE},
        {name = "b", kind = KIND_FONT},
        {name = "c", kind = KIND_TEXTURE},
    }
}

@(test)
test_placeholders_by_kind :: proc(t: ^testing.T) {
    defs: [4]scene.AssetDef = test_defs()
    SetPlaceholders(defs[:], KIND_TEXTURE, Pack(karl2d.Texture{idx = 1, gen = 1}))
    testing.expect(t, defs[1].placeholder != {} && defs[3].placeholder != {})
    testing.expect_value(t, defs[2].placeholder, scene.AssetValue{})                 // other kinds are not touched
}

@(test)
test_reads_without_a_loaded_asset :: proc(t: ^testing.T) {
    defs: [4]scene.AssetDef = test_defs()
    SetPlaceholders(defs[:], KIND_TEXTURE, Pack(karl2d.Texture{idx = 1, gen = 1}))
    storage: scene.AssetStorage(4)
    store: scene.AssetStore
    scene.AssetStoreInit(&store, defs[:], loaders[:], &storage)

    testing.expect_value(t, TextureOf(&store, 1), karl2d.Texture{idx = 1, gen = 1})  // not loaded: the placeholder
    testing.expect_value(t, TextureOf(&store, scene.ASSET_NONE), karl2d.Texture{})   // the null asset: an empty handle
    testing.expect_value(t, FontOf(&store, 2), karl2d.FONT_DEFAULT)                  // no font loaded: the default one
    _, clip_ok := AudioClipOf(&store, 1)
    testing.expect(t, !clip_ok, "nothing to play before it is loaded")
    _, stream_ok := AudioStreamOf(&store, 1)
    testing.expect(t, !stream_ok)
}

@(private="file")
DecodeJob :: struct {
    def: scene.AssetDef,
    memory: [512 * 1024]byte,
    decoded: rawptr,
    ok: bool,
    thread_id: int,
}

@(private="file")
decode_on_thread :: proc(self: ^thread.Thread) {
    job: ^DecodeJob = cast(^DecodeJob)self.data
    arena: mem.Arena
    mem.arena_init(&arena, job.memory[:])
    job.decoded, job.ok = TextureDecode(&job.def, mem.arena_allocator(&arena))
    job.thread_id = sync.current_thread_id()
    // copy what the test looks at before the arena goes away
    if job.ok {
        img: ^image.Image = cast(^image.Image)job.decoded
        job.def.flags = u32(img.width)
        job.def.placeholder = {handle = u64(img.height), extra = u64(img.channels)}
        job.def.persistent = len(img.pixels) > 0
    }
}

@(test)
test_texture_decode_is_thread_safe_and_needs_no_framework :: proc(t: ^testing.T) {
    @(static) png := #load("../../assets/textures/player_sheet.png")
    jobs := new([4]DecodeJob)       // 2 MB, too big for the stack
    defer free(jobs)
    threads: [4]^thread.Thread
    for i in 0 ..< 4 {
        jobs[i].def = {name = "player", kind = KIND_TEXTURE, source = png}
        if i % 2 == 1 { jobs[i].def.flags = FLAG_PREMULTIPLY_ALPHA }
        threads[i] = thread.create(decode_on_thread)
        threads[i].data = &jobs[i]
        thread.start(threads[i])
    }
    main_thread: int = sync.current_thread_id()
    for i in 0 ..< 4 {
        thread.join(threads[i])
        thread.destroy(threads[i])
        testing.expect(t, jobs[i].ok, "decoded without a window or a GPU")
        testing.expect(t, jobs[i].thread_id != main_thread)
        testing.expect(t, jobs[i].def.flags > 0 && jobs[i].def.placeholder.handle > 0, "an image with a size")
        testing.expect_value(t, jobs[i].def.placeholder.extra, u64(4))                      // alpha is added when missing
        testing.expect(t, jobs[i].def.persistent, "it has pixels")
    }
}

@(test)
test_decode_fails_cleanly_on_bad_data :: proc(t: ^testing.T) {
    memory: [4096]byte
    arena: mem.Arena
    mem.arena_init(&arena, memory[:])
    garbage: [64]byte
    def: scene.AssetDef = {name = "garbage", kind = KIND_TEXTURE, source = garbage[:]}
    context.logger = log.nil_logger()
    decoded, ok := TextureDecode(&def, mem.arena_allocator(&arena))
    testing.expect(t, !ok && decoded == nil, "not an image")
}
