# 3d_models: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `gltf.odin` (package `models3d`: `Model` structs, `ModelLoadGltf`, `ModelAnimate`, skinning helpers), `glTF2/` (copy of the glTF2 parser from third_party/gltf, MIT, patched for current Odin; don't use vendor:cgltf, it clashes with raylib's symbols), `glue_raylib/` glue (`DrawModel` CPU skinning), `gltf_test.odin` (`odin test .`). Assets in `odin_utilities/assets/gltf`.
- Allocator agnostic like atlas_packer: pass an arena to `ModelLoadGltf`, nothing allocates per frame.
- glTF color factors are LINEAR: the glue packages draw them through `ColorLinearToSrgb` (flat colored materials like the Adventurer's were near black without it). `ModelComputeBounds` skins skinned meshes (their raw vertices are 100x too small for the joints); the orbit demo frames the model from those bounds. Both were found by the window test pictures (`demo_common/captures`, one picture after the model loads).
