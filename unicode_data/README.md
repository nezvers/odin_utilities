# unicode_data

What a text program needs to know about a code point, generated from the Unicode Character Database (Unicode 18.0.0): how many cells it takes, whether its width is
ambiguous, whether a variation selector turns it into an emoji, and where the boundaries of grapheme clusters are. One set of rules for the cell screen of the `ui` library and the text of
the `font` library. Pure Odin, no allocation, builds for js_wasm32.

```odin
unicode_data.RuneWidth('a')                    // 1
unicode_data.RuneWidth('中')               // 2: East Asian Width W and F, the regional indicators
unicode_data.RuneWidth('́')               // 0: the general categories Mn, Me, Cf, Cc and the Hangul vowels and finals
unicode_data.RuneAmbiguous('α')           // true: East Asian Width A (wide in an East Asian locale)
unicode_data.RuneEmojiText('❤')           // true: a heart is narrow until a variation selector 16 follows
unicode_data.ClusterWidth(0x2764, 0xFE0F)      // 2

state: unicode_data.GraphemeState
for character in text {
    if unicode_data.GraphemeBreak(&state, character) { /* a new cluster starts here */ }
}
```

- A lookup is two array reads in a table of blocks of 256 code points (`tables.odin`: 129 distinct blocks, 74 KB; equal blocks are stored once).
- The grapheme rules are UAX #29 of Unicode 18 with the emoji sequences (GB11), the flags (GB12, GB13) and the Indic conjuncts (GB9c as that version states it). `testdata/GraphemeBreakTest.txt`, the official
  test file of Unicode (about 1900 lines), is run by the tests and passes.
- `tables.odin` is generated: `odin run unicode_data/tool/gen -- <folder> unicode_data/tables.odin`. The folder has `EastAsianWidth.txt`, `DerivedGeneralCategory.txt`, `emoji-data.txt`,
  `GraphemeBreakProperty.txt` and `DerivedCoreProperties.txt` from https://www.unicode.org/Public/UCD/latest/ucd/ (the tool looks for the base names). A new version of Unicode is a run of the tool, a new copy of
  the test file, and a look at the diff of the tables.

## Limits
The width of a cluster is the width of its first code point (`ClusterWidth`: a variation selector 16 on a text-default emoji makes it 2); no locale (ambiguous characters are narrow unless the caller asks
with `RuneAmbiguous`); no validation of emoji sequences (any pictograph can follow a joiner, as the standard says); code points above U+10FFFF and surrogates are width 1 and class Other; no normalization,
no case, no scripts, no bidirectional classes: this is the part that a grid of cells and a line layout need.

## License
The Unicode data files and the test file are © Unicode, Inc. and distributed under the Unicode License v3 (https://www.unicode.org/terms_of_use.html); `tables.odin` is derived from them.
