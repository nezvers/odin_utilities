# font

Vector fonts drawn from their outlines at any size. Two GPU methods that you pick per atlas, and an exact CPU rasterizer that is also the reference the GPU methods are tested against.

| Method | Idea | Cost |
|---|---|---|
| `.SLUG` | Eric Lengyel's Slug: the curves of a glyph are sorted into horizontal and vertical bands; a pixel looks at the curves of its two bands and counts where a ray to the right and a ray upwards cross them | a few curves per ray, exact roots |
| `.SCANLINE` | The Scanline Sweeper (Rook & Possum): a pixel adds up the signed area that every monotonic curve sweeps to the right inside of it; no winding numbers, no glancing hits | the curves of a stripe, plain arithmetic, anti-aliasing is the area itself |

Neither needs a texture of glyph pictures: text is sharp at 8 pixels and at 800, under scale, and with no mip levels. Hinting is not applied (the methods work from the outline).

```
font/
├── font.odin          Font (stb_truetype in the bytes you give), metrics in em units, glyph advance and kerning, Method
├── outline.odin       the outline of a glyph as quadratic Bezier curves (cubics are cut, lines get a middle point), monotonic pieces
├── raster.odin        exact coverage of a pixel on the CPU: CurveSweepArea, CurvesCoverage, CurvesRasterize
├── atlas.odin         the glyph data for the GPU in one array of 4 float texels: baked when a glyph is first asked for, dirty rows for the upload
├── slug.odin          the Slug data and SlugCoverage (the CPU model of the pixel shader)
├── scanline.odin      the Scanline Sweeper data and ScanlineCoverage
├── layout.odin        text to quads: advance, kerning, new lines, tabs, wrapping at spaces, TextMeasure
├── shaders/           GLSL 330 (raylib, the OpenGL backend of Karl2D) and HLSL (the Direct3D 11 backend of Karl2D), for both methods
├── glue_raylib/       font_raylib: Renderer (shader + float texture), DrawText
├── glue_karl2d/       font_karl2d: Renderer, DrawText (the WebGL backend is not supported)
├── demo_common/       the demo `font`: both methods side by side at six sizes, scaled with the keys; text.odin is the hook for the framework
├── demo_raylib/, demo_karl2d/   `odin run font/demo_raylib`, `odin run font/demo_karl2d` (from odin_utilities)
└── tool/preview/, tool/preview_karl2d/   a window with both methods, `-- --shot out.png` saves a picture and exits
```

## Use

```odin
face: font.Font
font.FontInit(&face, #load("Roboto.ttf"))                    // the bytes have to live as long as the font

texels := make([]f32, 4 * font.ATLAS_WIDTH * 32)             // 4096 x 32 texels = 8 MB: thousands of glyphs
slots := make([]i32, face.glyph_count)
atlas: font.Atlas
font.AtlasInit(&atlas, &face, .SLUG, texels, slots)          // .SCANLINE for the other method

renderer: font_raylib.Renderer                               // or font_karl2d.Renderer
font_raylib.RendererInit(&renderer, &atlas)                  // after the window exists
font_raylib.DrawText(&renderer, "Hello", {20, 100}, 32, rl.WHITE)    // the baseline starts at (20, 100), 32 pixels to the em
```

- Everything is in em units (the em square is 1 by 1, y up, the baseline at 0): `FontAdvance`, `FontKerning`, `FontGlyphBox`, `FontLineHeight`, and `TextMeasure(&face, text, pixels_per_em)` give the size of a text.
- `TextQuads(&atlas, text, origin, pixels_per_em, vertices)` is what the glue calls: six vertices per visible glyph (position in pixels, coordinates in the em square, slot of the glyph). `TextOptions` has `wrap_width`, `line_spacing`, `tab_columns`. A different framework needs only a shader and a draw of these quads (the glue is about 100 lines).
- No hidden allocations: the atlas array, the slot table and the vertex buffer of a renderer are yours (`RendererInit(&renderer, &atlas, make([]font.TextVertex, 6 * 2048))`), a glyph is baked when it is first asked for. A glyph has at most `ATLAS_MAX_CURVES` curves.
- The glue makes one float texture as tall as the array (`AtlasCapacityRows`) and uploads the rows that changed (`AtlasTakeDirty`). The slot of a glyph travels in the red and green bytes of the vertex color and the index of its color in the blue one (the colors are a palette row of the texture, `AtlasColor`), so text of any number of colors is one batch.
- `DrawText` draws at once; with `renderer.deferred = true` it adds to the batch and `RendererFlush` draws it, so a program that draws other things in between flushes first to keep the order.
- An atlas that is full is cleared and filled again (`AtlasClear`, after the batch was drawn), a palette that is full the same (`AtlasClearColors`): the text keeps working with more glyphs than the atlas holds at once, at the cost of baking them again.
- `TextOptions`: `rotation` (radians, clockwise, around the origin of the text), `snap_to_pixels` (the baseline and every glyph start on a whole pixel: the outlines are not hinted, and this keeps the stems of a line alike), `wrap_width`, `line_spacing`, `tab_columns`. `renderer.weight` is an exponent on the coverage (under 1 makes light text on a dark ground heavier). The shaders take the size of a pixel in the em square from the derivatives of the coordinates, so a turned quad is anti-aliased right.

## For a user interface
`font_raylib.TextSystem` / `font_karl2d.TextSystem` bundle the face, an atlas, a renderer and their memory (`TextSystemInit(&system, bytes, .SLUG)`, the allocator is yours) and place text by a **box**: `TextSystemDraw(&system, text, top_left, line_height, color)` and `TextSystemMeasure(&system, text, line_height)`, where the size is the height of the line (`font.TextBox` gives the pixels to the em and the baseline for it). The `ui` library uses it through `PainterUseVectorText`; `demo_kit` can run every demo with it (`-define:DEMO_VECTOR_TEXT=slug`).

## What is tested
`odin test font` (13 tests): the outline against the bitmap of stb_truetype and against a grid of points on the flattened curves, the data of each method read back by its CPU model against the exact coverage (Slug: mean difference under 4 of 255; the Scanline Sweeper: under 0.5, also at 7 pixels where a pixel reaches over two stripes), the atlas (baked once, dirty rows, full), the layout. `odin test font/demo_common` plays the script of the demo headless; the screenshots of both frameworks are in `demo_common/captures` (`odin run demo_kit/tool/captures -- font`, `-- --karl2d font`).

## Credits and licenses
- The Slug method: Eric Lengyel, *GPU-Centered Font Rendering Directly from Glyph Outlines*, JCGT 6(4), 2017. The patent is dedicated to the public domain; the reference shaders (https://github.com/EricLengyel/Slug) are MIT licensed, Copyright 2017 by Eric Lengyel, and the Slug shaders of this library are translations of them to this data layout: credit is given here and in the shader files.
- The Scanline Sweeper: Scuff3D Rook, *The Scanline Sweeper: A Glyph Rendering Algorithm*, Rook & Possum, 2026. The shaders and the CPU code here are written from the description in the paper and do not copy its listings (which are under the Mozilla Public License 2.0); the Unreal plugin that uses it (https://github.com/nicholas477/ScanlineFontRenderer) is a reference checkout only.
- Outlines are read by stb_truetype (public domain / MIT, `vendor:stb/truetype`).
