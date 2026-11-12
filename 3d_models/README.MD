# 3D models
Engine and framework agnostic glTF 2.0 / GLB loading, skeletal animation and skinning, plus a raylib glue and demo. `gltf.odin` converts the glTF file into plain Odin structs (vertices, indices, nodes, skins, animations, materials), a glue package draws them with your engine.    

`odin run demo_raylib` / `odin test .`    
Demo: Adventurer.glb (skinned character with many animations), left mouse drag orbits, wheel zooms, SPACE pause, LEFT/RIGHT or buttons select the animation.    

```odin
import m3d "3d_models"
import glue "3d_models/raylib"

model, ok := m3d.ModelLoadGltf("../assets/gltf/Adventurer.glb", arena_allocator)   // .gltf or .glb
textures := make([]rl.Texture2D, len(model.images), arena_allocator)
glue.LoadTextures(&model, textures)

// every frame
m3d.ModelAnimate(&model, animation_index, time)     // poses nodes, updates world matrices
glue.DrawModel(&model, textures)                    // CPU skinning, immediate mode drawing
```

## Parts
- `gltf.odin` (package `models3d`) - `Model` with `Mesh/Primitive/Vertex`, `Material`, `Image`, `Node`, `Skin`, `Animation`. `ModelLoadGltf`, `ModelLoadGltfBytes` (for `#load`), `ModelUpdateNodes`, `ModelAnimate` (linear, step and cubic spline, looping), `ModelSkinMatrices` + `VertexSkinPosition/Normal` for skinning, `ModelComputeBounds`. Missing normals are computed.
- `glTF2/` - glTF2 parser by Pawel82S (MIT, see `glTF2/LICENSE`, copied from `third_party/gltf` and patched for the current `core:os`/`core:encoding/base64`). `vendor:cgltf` can't be used together with raylib on Windows, because raylib already contains the same symbols.
- `raylib/models3d_raylib.odin` - `LoadTextures`, `UnloadTextures`, `DrawModel` (Lambert shading, CPU skinning, double sided materials), `ModelBoundingBox`.
- `assets/gltf/` (shared assets folder) - Adventurer.glb by Quaternius (CC0) from poly.pizza, also used by the glTF example.

## Memory
All slices and strings of a `Model` are allocated with the allocator you pass, so a `mem.Arena` per scene works well, `arena_free_all` releases everything (the demo does this). Without an arena call `ModelDestroy`. The parser needs temporary memory from `context.allocator` while loading and frees it before returning. Animation, skinning and drawing don't allocate.    

## Limits
No morph targets (weights channels are ignored), no sparse accessors, only triangle lists/indexed triangles, interleaved buffers are supported (byte stride). Textures are loaded from embedded image bytes (GLB), images referenced by uri are only reported in `Image.uri`.
