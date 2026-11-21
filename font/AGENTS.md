# font: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

Vector fonts from outlines, two GPU methods (`Method` = `.SLUG` or `.SCANLINE`).

## Parser and outlines
- `font.odin`: `Font` over the bytes of a TrueType/OpenType file or collection, metrics in em units.
- `sfnt.odin` + `truetype.odin` + `cff.odin`: pure Odin port of stb_truetype 1.28; reads a glyph into the caller buffer through `OutlineSink`, no allocation, bounds checked. Keep it bit for bit equal to stb_truetype (`parser_test.odin` compares every glyph).
- `outline.odin`: `FontGlyphCurves` (quadratic curves in a caller buffer), `CurvesMonotonic`.
- `raster.odin`: exact CPU coverage, the reference (`CurvesCoverage`, `CurvesRasterize`).

## Atlas and methods
- `atlas.odin` `Atlas` over a caller array of 4 float texels: header rows for the glyph table and a color palette; `AtlasGlyph` bakes on demand, `AtlasReserveText`, `AtlasClear`, `AtlasTakeDirty` gives the rows to upload. `atlas_file.odin`: bake ahead, `AtlasWrite/AtlasRead`.
- `slug.odin` + `scanline.odin`: data of each method and the CPU models of the shaders (`SlugCoverage`, `ScanlineCoverage`). `special.odin`: missing-character box, solid glyph.
- Slug shaders are translations of the MIT reference (credit in README and shader files); Scanline Sweeper is written from the paper, not from its MPL listings.

## Text layout
- `glyph.odin`: `GlyphInstance`, `EmitGlyph`, `EmitRect`. `layout.odin`: `TextQuads` (six vertices per glyph with slot and palette index), `TextOptions` (rotation, snap, wrap), `TextMeasure`.
- `rich.odin`: `RichParse`, `RichLayout(&rich, &atlas.faces, ...)`, `RichDraw`: BBCode-like tags and effects; bold/italic faces via `AtlasAddFace`, struck/slanted when a face is missing.
- `ascii_cache.odin`: ASCII tables (`ascii_glyph`, `ascii_advance`, `ascii_kern`) made on first use; a `Font` is 34 KB bigger, kerning rows are written when first used: call `FontKerningWarm` before sharing a font between threads. Layout loops read characters with `fontNext` (ASCII fast path, else `simd_utils.Utf8Next`) and use `fontMetrics`/`fontPairKerning`, never `utf8.decode_rune_in_string`. `tool/measure_bench`.

## Rendering and glue
- `shaders/`: GLSL 330 (raylib, Karl2D GL) and HLSL (Karl2D D3D11); keep each pair the same. D3D11: read every texture through a sampler of the same register (Karl2D checks it); `point` is reserved in HLSL.
- `glue_raylib/`, `glue_karl2d/`: `Renderer` over a caller vertex buffer, `DrawText`, `DrawRich`, `RendererFlush` with `deferred`, `RendererDraw` of a list, `TextMesh` (a VBO on raylib).
- `TextSystem` + `TextBox`: ui places text by a line box (ui `PainterUseVectorText`, kit `-define:DEMO_VECTOR_TEXT=slug|scanline`, pictures in `captures/<backend>_<method>`).
- Demo `font`: demo_common has a `TextDrawer` hook that demo_raylib and demo_karl2d set. `tool/preview`, `tool/preview_karl2d` (`-- --shot out.png`).

## Tests
- `odin test font -strict-style -vet` (34 tests, ~0.4 s), `odin test font/demo_common`.
- `FONT_TEST_FILES=<a.otf;b.ttc>` compares more fonts with stb_truetype (no CFF font in the repo: run it with one after changing `cff.odin`).
- `vendor:stb/truetype` of Odin dev-2026-11 has a `fontinfo` 8 bytes shorter than the C struct (`vhea`, `vmtx` missing): tests pad it (`StbInfo`).
- Shaders are not unit tested: CPU models are (against the exact rasterizer); screenshots of both frameworks check the shaders.
