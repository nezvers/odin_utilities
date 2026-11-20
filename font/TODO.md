# font

Tasks, most valuable first inside each tag. A task starts with `(high)`, `(medium)` (the default) or `(low)`; tick it when it is done, verified and committed.

## From the reading of simdutf8 (`references/simdutf8`, Rust, MIT / Apache, the method of Keiser and Lemire "Validating UTF-8 in less than one instruction per byte")
What it does: for 64 bytes at a time it first asks "is every byte below 0x80" (one move mask of the OR of the vectors) and skips the check for pure ASCII; otherwise three nibble
lookups (`pshufb`, 16 entry tables indexed by the high nibble of the byte, the low nibble of the byte and the high nibble of the byte before) AND together to flag every illegal
pair (overlong, surrogate, too large, a continuation without a start, a start without a continuation), plus a carry of "an incomplete sequence at the end of this block" into the
next one. Two APIs: one that only says valid or not (fastest on valid text), one that stops at the first failing block and finds the exact place with a scalar pass over the
last three bytes of the block before and the failing block. AVX-512 is selected only with VBMI2 (Ice Lake and later): before it the 512 bit units throttle the clock. Nothing is
copied; the technique is rewritten for the `simd` library (see `simd/TODO.md`).

Measured here before writing these (2026-11-21, 9950X, `-o:speed`, 4 KB of English text, 13 px): `TextMeasure` 70 ns per character with Inter and 125 with a wrap width, 17 and 31 with
Fira Code; a plain loop over the bytes is 0.09. The per character path (decode a rune, `FontResolve` through the cmap, `FontAdvance`, `FontKerning` for the pair) is the cost; text of a
user interface is almost all ASCII, and the ui measures text through here (`ui_default.Measure`) for every label it lays out that is not in its measure cache.

- [ ] (high) Find where the 70 ns go (`-build-mode:asm` / a counter per call: cmap lookup, advance, the kerning pair through GPOS) and cache what repeats. Likely first: a per font
      table of the glyph and the advance of the 128 ASCII characters made at `FontInit`, and a cache of the kerning of ASCII pairs (a 128 x 128 table of f32 is 64 KB per face: lazily
      per row, or a small hash of the pairs that were asked). Used by `TextMeasure`, `wordWidth`, `TextQuads` and `AtlasReserveText`, which all repeat the same lookups. Keep the output
      bit for bit what the slow path gives (a test compares them on every pair of printable ASCII for Inter, Fira Code and JetBrains Mono, with the face of each family).
- [ ] (medium) An ASCII run fast path: find the length of the ASCII prefix of a text with the `simd` library (`AsciiPrefix`: a move mask over 16, 32 or 64 bytes) and run the table
      loop over it without decoding runes; decode only at the first byte of 0x80 or more. `wordWidth` (called at every space when wrapping) and the `TextQuads` loop take the same
      path. Depends on the item above and on `AsciiPrefix` in `simd`.
- [ ] (medium) A monospace fast path: when a face has one advance for every character it is asked about and no kerning (Fira Code, JetBrains Mono as the terminal and the code
      area use them), the width of a text is its character count times the advance: count the bytes that are not continuation bytes (`(b & 0xC0) != 0x80`, a vector compare and a
      population count, 32 or 64 bytes per step) and wrapping finds the column by the same count. `AnsiScreen` and `UiTextArea` measure monospace text all the time. Needs a per face
      `monospace: bool` found at init (compare the advances of the glyphs of the ASCII table, check that the font has no kerning pair for them) and a test against `TextMeasure`.
- [ ] (medium) Say what the library does with invalid UTF-8 and make every path do it: today `utf8.decode_rune_in_string` gives `RUNE_ERROR` with width 1 per bad byte, so a bad
      three byte sequence draws three missing glyph boxes, and `ansi_screen` has its own decoder. The usual rule (the "maximal subpart" of the Unicode standard, what Go, the web and
      the simdutf8 compat error length follow) is one U+FFFD per invalid prefix. Write it once (`Utf8Next(text, at) -> (rune, size)`), use it in `layout.odin`, `rich.odin`,
      `atlas.odin`, `special.odin` and the ansi decoder, and test it on the sequences of simdutf8's tests (overlong 2, 3 and 4 byte forms, surrogates, above U+10FFFF, a continuation
      byte alone, a start byte cut at the end, a start followed by a non continuation).
- [ ] (medium) Validate text that comes from outside once, at the edge: the clipboard paste of the text widgets, a file or a message read for a text area, the markup of `RichParse`.
      A validator over the 64 byte blocks of the `simd` library (`Utf8Valid`, fast on valid text, with a `valid_up_to` for the error case found by a scalar pass over the failing block and
      the three bytes before it) and a lossy copy (`Utf8Clean(text, out)`: invalid parts become U+FFFD) for the widgets that need valid text in their buffer (a text field that holds
      invalid UTF-8 can put the cursor inside a sequence: check what `textedit.odin` does today and put a test on it).
- [ ] (low) `AtlasReserveText` resolves and bakes every character of a text, though a text repeats a few dozen: collect the ASCII characters of the text in a 128 bit set while the ASCII
      scan runs, bake each member once, and decode only the rest. The same set tells `TextQuads` that nothing is missing before it starts.
- [ ] (low) Streaming: a decoder that keeps "an incomplete sequence at the end of the last chunk" as a small carry (simdutf8 keeps a vector for it; here three bytes and a count are
      enough) so that `AnsiScreenWrite`, a log reader and the chat reader share one piece of code for text that arrives in pieces.

## From the reading of ghostty (`references/ghostty/src/simd/codepoint_width.cpp`, `src/terminal/stream.zig`)
- [x] The width and the class of a code point from the Unicode data, not by hand: the `unicode_data` library (`tool/gen` makes `tables.odin` from EastAsianWidth, DerivedGeneralCategory, emoji-data, GraphemeBreakProperty and DerivedCoreProperties of Unicode 18.0.0; `RuneWidth`, `RuneAmbiguous`, `RuneEmojiText`, `ClusterWidth`), the cell screen of the `ui` library uses it
- [x] The lookup: a two stage table (74 KB, 129 distinct blocks of 256 code points), two array reads per code point, instead of a chain of ranges or range vectors (the vector range kernel of ghostty is not needed: the table is faster for every class and is exact by construction)
- [x] Grapheme clusters by the break classes of GraphemeBreakProperty.txt, with GB9c, GB11, GB12 and GB13 (`unicode_data.GraphemeBreak`; the official GraphemeBreakTest.txt of Unicode, 1900 lines, passes: it showed that Unicode 18's GB9c needs no consonant before the linker). The cell screen joins clusters by it (Indic conjuncts, Hangul syllables, flags, families, Thai)

## Not taken from simdutf8
- The `compat` flavor falls back to the standard library's `from_utf8` to find the error position: Odin's `core:unicode/utf8` `valid_string` can play that part for the exact position.
- Its inputs shorter than 64 bytes go to the standard library: a text of a label is shorter than that, so the table path (above), not a vector path, is the one that matters here.
- ARMv7 and the macros that generate one algorithm per target: the `simd` library's tables and `enable_target_feature` kernels do that job.
