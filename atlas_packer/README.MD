# Runtime texture packing
Bake sprites, tiles and fonts into a single texture for draw call optimization.    
Use case: for each scene collect relevant textures, sprites, fonts, pack them once, free everything when the scene ends.    
Current limitation is one-shot packing - pre-allocate rectangle capacity for one texture, can't overflow to multiple textures.    

`odin run demo_raylib` / `odin run demo_karl2d` / `odin test .`    

## Arena allocator
The library never allocates by itself, all memory comes from the allocator given to `Init`. Use `core:mem` `Arena` over a pre-allocated buffer:
persistent data (packer, atlas pixels, rectangle slices) is allocated first, everything that is only needed for baking (decoded source images, glyph bitmaps)
goes into a temporary section that is rolled back right after baking. `arena_free_all` releases the scene.    

```odin
arena_buffer: [4 * mem.Megabyte]byte
arena: mem.Arena
mem.arena_init(&arena, arena_buffer[:])
scene := mem.arena_allocator(&arena)

packer.Init(&atlas_packer, 512, 256, scene)              // atlas size, rectangle capacity
atlas_image, _ := glue.CreateImage(512, scene)           // karl2d glue, pixels from the arena

temp := mem.begin_arena_temp_memory(&arena)              // only allocate persistent data before this
source, _ := glue.LoadImageFromBytes(bytes, {.alpha_premultiply}, scene)
rects, _ := packer.GetRects(&atlas_packer, count)        // fill rects[i].zw with sizes
packer.Pack(&atlas_packer)                               // rects[i].xy are positions now
glue.BakeImageRects(source, &atlas_image, source_rects, rects)
mem.end_arena_temp_memory(temp)                          // source image is released

// scene end
mem.arena_free_all(&arena)
```
Raylib images (`rl.Image`) are allocated by raylib, so only the packer and rectangle data live in the arena there.    

## Font packing
- `FontInit` - TTF (`[]byte`, not copied) at one pixel height. `GetFontRects` measures letters (missing characters are skipped) and gives rectangles with padding. `RenderGlyph` renders one glyph into a caller buffer, `GlyphsMaxBytes` sizes that buffer.
- Raylib: `init_packed_font` builds an `rl.Font` from the packed rectangles.
- Karl2D: `BakeFontGlyphs` writes glyphs into the atlas image, `RegisterFont` makes a static `karl2d.Font` that draws from the same atlas texture, so text and sprites share one draw call. Karl2D frees the glyph data, so call `karl2d.destroy_font(font)` (it also destroys the atlas texture) instead of destroying the texture.
