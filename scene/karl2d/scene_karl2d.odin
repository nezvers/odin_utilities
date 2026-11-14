package scene_karl2d

// karl2d part of the scene system: loaders for the asset kinds, typed reads that give a placeholder until the asset is ready,
// and the cover of the transition. Loading creates GPU and audio resources, so it runs on the main thread, a few items per frame
// (see scene.LoaderUpdate).

import "base:runtime"
import "core:image"
// registers the decoders that TextureDecode depends on, they are looked up by file type
import _ "core:image/png"
import _ "core:image/jpeg"
import "../../karl2d"
import scene ".."

KIND_TEXTURE :: scene.AssetKind(0)
KIND_AUDIO_CLIP :: scene.AssetKind(1)
KIND_AUDIO_STREAM :: scene.AssetKind(2)
KIND_FONT :: scene.AssetKind(3)

// AssetDef.flags of a texture
FLAG_PREMULTIPLY_ALPHA :: u32(1)

// Index with AssetKind: pass to SceneSystemInit
loaders: [4]scene.AssetLoader = {
    KIND_TEXTURE = {decode = TextureDecode, finish = TextureFinish, unload = TextureUnload},
    KIND_AUDIO_CLIP = {load = AudioClipLoad, unload = AudioClipUnload},
    KIND_AUDIO_STREAM = {load = AudioStreamLoad, unload = AudioStreamUnload},
    KIND_FONT = {load = FontLoad, unload = FontUnload},
}

// karl2d handles are 8 bytes (or an int), they travel in the first word of an AssetValue
@(private)
Pack :: proc(handle: $T) -> scene.AssetValue where size_of(T) <= 8 {
    packed: u64
    handle_copy: T = handle
    runtime.mem_copy(&packed, &handle_copy, size_of(T))
    return {handle = packed}
}

@(private)
Unpack :: proc(value: scene.AssetValue, $T: typeid) -> T where size_of(T) <= 8 {
    packed: u64 = value.handle
    result: T
    runtime.mem_copy(&result, &packed, size_of(T))
    return result
}

// A texture loads in two steps, the same ones karl2d.load_texture_from_bytes does inside. The decode (unpacking the image, premultiplying
// the alpha) is pure CPU work, so it can run on a worker thread, into the memory of that worker. The finish creates the GPU texture and
// runs on the main thread.
TextureDecode :: proc(def: ^scene.AssetDef, memory: runtime.Allocator) -> (decoded: rawptr, ok: bool) {
    options: image.Options = {.alpha_add_if_missing}
    if def.flags & FLAG_PREMULTIPLY_ALPHA != 0 {
        options += {.alpha_premultiply}
    }
    img, error := image.load_from_bytes(def.source, options = options, allocator = memory)
    if error != nil { return }
    return img, true
}

TextureFinish :: proc(def: ^scene.AssetDef, decoded: rawptr) -> (value: scene.AssetValue, ok: bool) {
    img: ^image.Image = cast(^image.Image)decoded
    texture, texture_ok := karl2d.load_texture_from_bytes_raw(img.pixels[:], img.width, img.height, .RGBA_8_Norm)
    if !texture_ok { return }
    return Pack(texture), true
}

// Both steps on the calling thread, for a loader that wraps the texture loader
TextureLoad :: proc(def: ^scene.AssetDef, scratch: runtime.Allocator) -> (value: scene.AssetValue, ok: bool) {
    decoded := TextureDecode(def, scratch) or_return
    return TextureFinish(def, decoded)
}

TextureUnload :: proc(def: ^scene.AssetDef, value: scene.AssetValue) {
    karl2d.destroy_texture(Unpack(value, karl2d.Texture))
}

AudioClipLoad :: proc(def: ^scene.AssetDef, scratch: runtime.Allocator) -> (value: scene.AssetValue, ok: bool) {
    clip, clip_ok := karl2d.load_audio_clip_from_bytes(def.source)
    if !clip_ok { return }
    return Pack(clip), true
}

AudioClipUnload :: proc(def: ^scene.AssetDef, value: scene.AssetValue) {
    karl2d.destroy_audio_clip(Unpack(value, karl2d.Audio_Clip))
}

// A stream keeps reading the source bytes while it plays, they have to stay alive: embedded bytes (#load) do
AudioStreamLoad :: proc(def: ^scene.AssetDef, scratch: runtime.Allocator) -> (value: scene.AssetValue, ok: bool) {
    stream, stream_ok := karl2d.load_audio_stream_from_bytes(def.source)
    if !stream_ok { return }
    return Pack(stream), true
}

AudioStreamUnload :: proc(def: ^scene.AssetDef, value: scene.AssetValue) {
    stream: karl2d.Audio_Stream = Unpack(value, karl2d.Audio_Stream)
    karl2d.stop_audio_stream(stream)
    karl2d.destroy_audio_stream(stream)
}

// A dynamic font keeps using the source bytes, they have to stay alive: embedded bytes (#load) do
FontLoad :: proc(def: ^scene.AssetDef, scratch: runtime.Allocator) -> (value: scene.AssetValue, ok: bool) {
    font, font_ok := karl2d.load_dynamic_font_from_bytes(def.source)
    if !font_ok { return }
    return Pack(font), true
}

FontUnload :: proc(def: ^scene.AssetDef, value: scene.AssetValue) {
    karl2d.destroy_font(Unpack(value, karl2d.Font))
}

// --- Placeholders: what a read gives until the asset is loaded ---

// A small checker texture, made once after karl2d.init and shared by every texture asset as `placeholder`
PlaceholderTexture :: proc() -> scene.AssetValue {
    pixels: [16]u8 = {70, 70, 80, 255, 110, 110, 125, 255, 110, 110, 125, 255, 70, 70, 80, 255}
    texture: karl2d.Texture = karl2d.load_texture_from_bytes_raw(pixels[:], 2, 2, .RGBA_8_Norm)
    return Pack(texture)
}

DestroyPlaceholderTexture :: proc(placeholder: scene.AssetValue) {
    karl2d.destroy_texture(Unpack(placeholder, karl2d.Texture))
}

PlaceholderFont :: proc() -> scene.AssetValue {
    return Pack(karl2d.FONT_DEFAULT)
}

// Give every asset of a kind a placeholder
SetPlaceholders :: proc(defs: []scene.AssetDef, kind: scene.AssetKind, placeholder: scene.AssetValue) {
    for &def in defs {
        if def.kind == kind { def.placeholder = placeholder }
    }
}

// --- Typed reads, always usable: the real thing, the placeholder, or an empty handle ---

TextureOf :: proc(store: ^scene.AssetStore, id: scene.AssetId) -> karl2d.Texture {
    return Unpack(scene.AssetGet(store, id), karl2d.Texture)
}

FontOf :: proc(store: ^scene.AssetStore, id: scene.AssetId) -> karl2d.Font {
    value: scene.AssetValue = scene.AssetGet(store, id)
    if value == {} { return karl2d.FONT_DEFAULT }
    return Unpack(value, karl2d.Font)
}

// Sounds have no placeholder: `ok` says whether there is something to play yet
AudioClipOf :: proc(store: ^scene.AssetStore, id: scene.AssetId) -> (clip: karl2d.Audio_Clip, ok: bool) {
    if !scene.AssetIsReady(store, id) { return }
    return Unpack(scene.AssetGet(store, id), karl2d.Audio_Clip), true
}

AudioStreamOf :: proc(store: ^scene.AssetStore, id: scene.AssetId) -> (stream: karl2d.Audio_Stream, ok: bool) {
    if !scene.AssetIsReady(store, id) { return }
    return Unpack(scene.AssetGet(store, id), karl2d.Audio_Stream), true
}

// --- The cover of a transition ---

// Draw last, over everything. A black cover that fades with the transition, and while it is fully up a loading bar
DrawTransition :: proc(system: ^scene.SceneSystem, screen_size: karl2d.Vec2) {
    transition: scene.Transition = scene.SceneTransition(system)
    if transition.phase == .NONE { return }

    karl2d.draw_rect({0, 0, screen_size.x, screen_size.y}, karl2d.Color{0, 0, 0, u8(clamp(transition.alpha, 0, 1) * 255)})
    if transition.phase != .LOADING { return }

    bar: karl2d.Rect = {screen_size.x * 0.35, screen_size.y * 0.85, screen_size.x * 0.3, screen_size.y * 0.012}
    karl2d.draw_rect(bar, karl2d.Color{60, 60, 70, 255})
    karl2d.draw_rect({bar.x, bar.y, bar.w * clamp(transition.progress, 0, 1), bar.h}, karl2d.Color{230, 230, 240, 255})
}
