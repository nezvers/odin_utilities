# atlas_packer: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `atlas_packer.odin` (`AtlasPacker` of slices, `Init(packer, atlas_size, rect_capacity, allocator)`), `font.odin` (`FontInit/GetFontRects/RenderGlyph`: glyph bitmaps at one pixel height through the `font` library, its parser and its exact coverage rasterizer, no stb_truetype; `RenderGlyph(font, glyph, alpha, curves)` takes optional room for outlines of more than `GLYPH_CURVES` curves), glue `glue_raylib/` and `glue_karl2d/` (`BakeImageRects`, `CreateImage`, `BakeFontGlyphs`, `RegisterFont`), `atlas_packer_test.odin` (`odin test .`).
- Allocator agnostic: demos use `mem.Arena` over a static buffer, persistent allocations first, then `begin_arena_temp_memory` section for source images, `arena_free_all` in finit.
