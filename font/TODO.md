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

- [x] Where the 70 ns went, measured (`odin run font/tool/measure_bench -o:speed`, 4 KB of English, 13 px, ns per character): the kerning of a pair through GPOS is 57 ns for Inter (4 for
      Fira Code, which has few pairs), the cmap lookup 12, the advance 2. Now: glyph and advance of the 128 ASCII characters in tables made by `FontInit`, and the kerning of the ASCII
      pairs in a table of 128 x 128 numbers made a row at a time on first use (`font/ascii_cache.odin`, 34 KB per Font): TextMeasure 70 -> 0.92 (Inter), 17 -> 0.92 (Fira Code), with a wrap width
      125 -> 2.8 and 31 -> 2.7. A test compares every character and every pair with the plain procedures bit for bit, and TextMeasure on 400 random texts (with accents, CJK, emoji, bad bytes,
      tabs, newlines) with and without a wrap on four fonts against the per character loop of before
- [x] An ASCII run fast path: `TextMeasure` takes a run of printable ASCII (`simd_utils.AsciiRun`) through the tables with no decode, no cmap lookup and no switch; `TextQuads`, `wordWidth`, `AtlasReserveText` and the rich text reader decode ASCII with one comparison (`fontNext`)
- [x] (not needed) A monospace fast path: measured, the table path costs the same for Fira Code and for Inter (0.92 ns a character both), the float additions in order are the floor. A rune count (`simd_utils.RuneCount`) would give the width of text in a monospace face without any loop, but the sum would differ in the last bit from the per character one (the layout is compared bit for bit); `RuneCount` is there for the cell screen and for callers that want columns, not widths
- [x] One rule for invalid UTF-8 everywhere: the maximal subpart of the Unicode standard, one RUNE_ERROR (one missing glyph box, or U+FFFD where the font has it) per bad part, from `simd_utils.Utf8Next` in `TextMeasure`, `TextQuads`, `wordWidth`, `AtlasReserveText`, `FontCountMissing`, the rich text reader and the cell screen (before: one box per bad byte). A test: a cut sequence and a stray byte are the same width, two stray bytes are two parts
- [x] Text from outside is checked once, at the edge: the paste of the text field and area goes through `simd_utils.Utf8Clean` (a bad part becomes U+FFFD), so a widget buffer holds well formed UTF-8 (a test pastes a cut character and a stray byte). The validator itself is the SIMD lookup method (20 to 25 GB/s on mixed text). A file or a message read by a program is the program's edge: it calls `Utf8Valid` / `Utf8Clean`
- [x] `AtlasReserveText` bakes each ASCII character once (a set of 128 bits) and decodes only the rest
- [x] Streaming: `simd_utils.Utf8Decoder` / `Utf8DecoderPush` keeps the few bytes of a character that a piece ended in the middle of (the same rule as Utf8Next: valid so far waits, invalid is an error at once; a test feeds 3000 damaged texts a byte at a time and compares with Utf8Next); the cell screen uses it

## From the reading of ghostty (`references/ghostty/src/simd/codepoint_width.cpp`, `src/terminal/stream.zig`)
- [x] The width and the class of a code point from the Unicode data, not by hand: the `unicode_data` library (`tool/gen` makes `tables.odin` from EastAsianWidth, DerivedGeneralCategory, emoji-data, GraphemeBreakProperty and DerivedCoreProperties of Unicode 18.0.0; `RuneWidth`, `RuneAmbiguous`, `RuneEmojiText`, `ClusterWidth`), the cell screen of the `ui` library uses it
- [x] The lookup: a two stage table (74 KB, 129 distinct blocks of 256 code points), two array reads per code point, instead of a chain of ranges or range vectors (the vector range kernel of ghostty is not needed: the table is faster for every class and is exact by construction)
- [x] Grapheme clusters by the break classes of GraphemeBreakProperty.txt, with GB9c, GB11, GB12 and GB13 (`unicode_data.GraphemeBreak`; the official GraphemeBreakTest.txt of Unicode, 1900 lines, passes: it showed that Unicode 18's GB9c needs no consonant before the linker). The cell screen joins clusters by it (Indic conjuncts, Hangul syllables, flags, families, Thai)

## Not taken from simdutf8
- The `compat` flavor falls back to the standard library's `from_utf8` to find the error position: Odin's `core:unicode/utf8` `valid_string` can play that part for the exact position.
- Its inputs shorter than 64 bytes go to the standard library: a text of a label is shorter than that, so the table path (above), not a vector path, is the one that matters here.
- ARMv7 and the macros that generate one algorithm per target: the `simd` library's tables and `enable_target_feature` kernels do that job.
