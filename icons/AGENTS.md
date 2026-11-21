# icons: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

Icons as a font. No demo (the ui demos show the icons).

## Files
- `lucide.ttf` (generated: 188 Lucide icons from U+E000) and `lucide_icons.odin` (generated: `Icon` enum, `ICON_NAMES`). `icons.odin`: `LUCIDE_FONT`, `IconRune`, `IconText/IconString`, `IconFromName`, metrics `ICON_UNITS_PER_EM/ICON_ASCENT/ICON_DESCENT` (the box of an icon is the em).
- `tool/build` (`odin run icons/tool/build`, paths by `#directory`) makes both from `lucide/sprite.svg` and `lucide/icons.txt` with three library procs: `svg_path.odin` (`SvgPathParse`: all commands, arcs as cubics), `stroke.odin` (`StrokePath/FillPath` into an `Outline` of quadratic `Segment`s: left side of every piece, round joins and caps, every contour with its inside on the right so overlaps add up under a nonzero or clamped fill, nothing merged), `ttf_write.odin` (`FontWrite`: a TrueType file with all tables an OS wants; contours reversed for font y up).
- New icons: add the name at the end of `icons.txt` (the characters of the others stay) and run the tool.
- Lucide is ISC, the Feather part MIT: `lucide/LICENSE`; the notice is in the `name` table too and has to ship with a program.
- `assets/fonts/inter/`: Inter Regular, Medium, SemiBold, Bold, Italic (static instances at opsz 14 via `fontTools.varLib.instancer`, OFL in `Inter-OFL.txt`).

## Tests
- `odin test icons -strict-style -vet` (8 tests in `icons_test.odin`, reads the font back with `../font`). After a stroker change look at pictures (render glyphs with atlas_packer `RenderGlyph` into a PNG): a wrong sign gave flat chords invisible at 32 px that the area test caught.
