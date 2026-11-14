#+build !js
// Tests of scene_karl2d.odin. They are in their own file because the scene system is imported by games with a web build, and core:testing does not compile for js_wasm32.
package scene_karl2d

import "core:testing"
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
