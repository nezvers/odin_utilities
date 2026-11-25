# Soft edges: how other projects do it, and what `ui` does

## What Nota (odin_plug/references/nota) does
Nota draws nothing itself: it is an Avalonia 12 / .NET application, and every line, curve, rounded box and widget goes through Avalonia's `DrawingContext` (`StreamGeometry`, `BezierSegment`, `Border` with `CornerRadius`), which Avalonia gives to Skia. The only rendering knobs in the sources are `RenderOptions.SetBitmapInterpolationMode` for pictures and `RenderTransform` for scaling. So the technique is Skia's: analytic coverage on the CPU rasterizer, and on the GPU backend a tessellated fringe or MSAA. Nothing in Nota is reusable as code; the useful reference is what Skia and the C++ plugin GUIs under it do.

## NanoVG (iPlug2/Dependencies/IGraphics/NanoVG/src/nanovg.c, nanovg_gl.h)
The classic small renderer, used by iPlug2 and Rack, and the model for this library:
- A path is flattened to points (`nvg__tesselateBezier`: recursive subdivision until `d2 + d3` squared is under `tessTol` times the chord squared, tolerance 0.25 px).
- **Fill**: the inside is one triangle fan, and a "fringe" band of quads (`nvg__expandFill`) goes from half a pixel inside to half a pixel outside the edge (`fringeWidth` = 1 px); the shader gets the coverage from the vertex.
- **Stroke**: a triangle strip, `nvg__expandStroke`, with 2 vertices per point of the line and joins (miter, round, bevel) and caps made of extra vertices; the texture coordinate `u` runs across the stroke, and the shader makes the anti-aliasing from it: `min(1, (1 - abs(u * 2 - 1)) * strokeMult) * min(1, v)`, with `strokeMult = (width + fringe) / (2 * fringe)`.
- A stroke thinner than a pixel is drawn one pixel wide with its alpha scaled (`strokeWidth < fringeWidth`).
- Everything of a frame is one vertex buffer and a few draw calls; there is no MSAA.

## What `ui` does (ui/aa.odin)
The same fringe, but the coverage is in the vertex alpha: **no shader, no texture, no state change**. A shape is a triangle list whose edge vertices have coverage 0 and whose inner vertices have 1 (`AaVertex`); the glue draws it with the color of the shape and the alpha scaled by the coverage, through the ordinary alpha blended triangle path (Karl2D `draw_colored_triangles`, raylib `rlgl.Begin(TRIANGLES)`, demo_kit `DrawTriangles`). So a whole window of soft shapes joins the batch of the rectangles and text around it: one draw call.
- `AaFillConvex`, `AaRounded`, `AaRoundedRing`, `AaDisc`: inside fan inset by half a pixel, ring of quads out to half a pixel outside.
- `AaStroke(points, closed, width, pixel, cap)`: cross sections of 4 vertices (outside, inside, inside, outside), mitered joins limited by `AA_MITER_LIMIT`, butt, square or round ends with a soft tip, a stroke under a pixel is a pixel wide and fainter.
- `AaFlattenCubic` / `AaFlattenRoute`: the number of pieces of a Bezier from Wang's formula (`sqrt(0.75 * bend / tolerance)`), so a long cable has as many pieces as its curvature needs and a straight one two points.
- The mesh storage is the caller's (`Painter.mesh`), a full mesh drops the rest and sets `overflow`.
- `ui_default.Polyline`, `Bezier`, `RouteLine`, `Disc`, `PolygonSmooth`; `FillRounded`, `RingRounded`, `Line` (not along the grid), `ArrowShape`, graph cables and tie heads use them when the painter has a mesh storage (`SmoothReady`), and keep their old drawing when it has none.

## Why not a shader (SDF) instead
A signed distance function per pixel (a rounded box or a cable segment in the fragment shader) is exact at any zoom and needs one quad per shape, but it needs its own shader: Karl2D and raylib switch draw calls when the shader changes, so it breaks the batch with the text and the rectangles each time. The fringe costs a few more vertices per shape (a rounded rectangle is about 60 triangles) and keeps everything in the batch; the vertices are cheap compared with a state change. A shader can come later for shapes drawn in bulk (thousands of cables).

## Limits
- Shapes that overlap each other inside one mesh are drawn one mesh per shape, so a translucent stroke that crosses itself shows the crossing darker (the same as any alpha blended path).
- A joint sharper than about 135 degrees is cut by the miter limit, not bevelled.
- A convex fill smaller than a pixel in any direction is clamped (its inset is half a pixel).
- Lines that run along the pixel grid (horizontal, vertical) stay plain rectangles: sharper than a soft edge.
