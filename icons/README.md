# icons

Icons as a font: the [Lucide](https://lucide.dev) set as glyphs of `lucide.ttf`, drawn like letters by whatever draws your text, in any size and color, in the same batch as the text around them.
The font is built here, in Odin, from Lucide's sprite sheet: the pictures of Lucide are lines of a width, a font wants filled shapes, so the tool walks along both sides of every line.

Framework agnostic, no allocations in the library, no C code.

```
icons/
├── icons.odin          LUCIDE_FONT (the bytes of the font), IconRune, IconText, IconFromName, the metrics of the font
├── lucide_icons.odin   generated: the Icon enum (FOLDER, CHEVRON_DOWN, ...) and ICON_NAMES
├── lucide.ttf          generated: one glyph per icon from U+E000 on
├── svg_path.odin       SvgPathParse: the path data of SVG (every command, arcs as cubics) into a slice
├── stroke.odin         StrokePath / FillPath: a line of a width with round joins and caps as filled outlines of quadratic curves
├── ttf_write.odin      FontWrite: outlines as a TrueType file (head, hhea, maxp, OS/2, hmtx, cmap, loca, glyf, name, post)
├── icons_test.odin     the tests
├── tool/build/         writes lucide.ttf and lucide_icons.odin from lucide/sprite.svg and lucide/icons.txt
└── lucide/             sprite.svg (lucide-static 1.44.0), icons.txt (the icons that go into the font), LICENSE
```

## Using the icons
```odin
import "icons"

// once: give the bytes to what draws text in your program
font := rl.LoadFontFromMemory(".ttf", raw_data(icons.LUCIDE_FONT), i32(len(icons.LUCIDE_FONT)), 32, &codepoints[0], count)   // raylib
font := karl2d.load_font_from_bytes(icons.LUCIDE_FONT)                                                                        // Karl2D
vector_font.FontInit(&face, icons.LUCIDE_FONT)                                                                                // odin_utilities/font
packer.FontInit(&bitmap_font, icons.LUCIDE_FONT, 24)                                                                          // odin_utilities/atlas_packer

// every time: an icon is one character
text, length := icons.IconText(.FOLDER_OPEN)
draw_text(font, icons.IconString(&text, length), position, size, color)
```
- The picture of an icon fills the square of the font size: at 16 pixels the line is 1.33 pixels wide (2 of 24), as on lucide.dev.
- The box of an icon is the em. Its baseline is 15 % above the bottom of the box (`ICON_ASCENT`, `ICON_DESCENT`), so an icon in a line of text stands around the middle of the capital letters. Drawn alone, put the top of the line at the top of the square.
- `IconRune(icon)` is the character (`ICON_FIRST_CHARACTER + number of the icon - 1`, in the private use area), `IconFromName("folder-open")` finds an icon by the name it has on lucide.dev.
- The `ui` library of this repository draws these icons itself (`ui.UiIcon`, buttons, rows): see ui/README.md.

## More icons, other icons
`lucide/icons.txt` lists the icons that go into the font (188 of the 1820 of the sprite: 90 KB). Add a line with the name of an icon and run

```
odin run icons/tool/build
```
New names go at the end of the list: the numbers of the enum, and so the characters, of the icons that were there stay as they are. A line `name = id` gives an icon another name in the enum than it has in the sprite (Lucide renames icons between releases).

The three parts of the tool are library procs and work for other pictures too:
- `SvgPathParse(data, out)` reads path data (`M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T`, `A`, `Z` and the relative forms, numbers without separators) into moves, lines and curves in absolute coordinates. Arcs come out as cubic curves.
- `StrokePath(path, width, room, &outline)` adds the outline of the path drawn with a line of that width, round joins and round caps. `FillPath` adds the inside of a path. The curves are quadratic (a `Segment` is a curve or a line), the contours all go around their inside the same way: where a line crosses itself or another one, the place is simply covered twice. Fill them with the nonzero rule, or with a coverage that is clamped (odin_utilities/font does that); no shapes are merged.
- `FontWrite(glyphs, description, out, points, contour_ends)` writes a TrueType file with one glyph per outline, every glyph as wide as the em, the characters from `first_character` on. The file is read by odin_utilities/font, stb_truetype, Karl2D and raylib and has the tables an operating system asks for.

All of them write into slices of the caller and say when something does not fit.

## What is tested
`odin test icons -strict-style -vet` (8 tests): path data (commands, numbers, arcs on their circle), the outline of a line, a dot, a circle and a corner (closed contours, their area, their distance to the path), the direction of filled shapes, the font file read back with the parser of odin_utilities/font (every icon has its glyph and an outline inside of its box, the pictures of minus, plus and circle are where they belong, the checksum of the file), a font of two glyphs, buffers that are too small. The font file and the two static Inter fonts were also compared glyph by glyph with stb_truetype (`FONT_TEST_FILES` of the font library).

## Limits
- One line width for the whole font (2 of 24, Lucide's own). A thinner or bolder set is another run of the tool with another `STROKE_WIDTH` and another file.
- Round joins and caps only (what Lucide uses). No dashes, no transforms, no gradients: `SvgPathParse` reads path data, not SVG files. The tool turns the basic shapes of the sprite (`circle`, `ellipse`, `rect`, `line`, `polyline`, `polygon`) into path data.
- The arcs of joins and caps are quadratic curves of 45 degrees, 0.3 % of the radius outside of the circle at their middle.

## Credits and licenses
- The icons are **Lucide**, Copyright (c) Lucide Icons and Contributors, ISC License. Some of them are derived from **Feather**, Copyright (c) 2013-present Cole Bemis, MIT License. Both texts and the list of the Feather icons are in [`lucide/LICENSE`](lucide/LICENSE); the copyright and the license are also in the `name` table of `lucide.ttf`. A program that ships the font ships that notice with it (an About box, a credits file).
- The choice of the 188 icons, and the idea of building them into a library for a ui, come from **Baldr** by Lee Fry and the Baldr contributors (https://github.com/BuLEEto/Baldr, zlib License), which compiles Lucide in as path data. No code of Baldr is in this library.
- The code of this library is written for odin_utilities and under its license.
