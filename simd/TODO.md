# simd

Tasks; a task starts with `(high)`, `(medium)` (the default) or `(low)`; tick it when it is done, verified and committed.

## From the reading of simdutf8 (`references/simdutf8`)
- [ ] (medium) Text kernels as the second example of the library, and for `font` and `ui` (see `font/TODO.md`): `AsciiPrefix(bytes) -> int` (the length of the ASCII start: SCALAR 8
      bytes at a time with a mask, SSE2 and NEON a 16 byte move mask, AVX2 32, AVX-512 64), `RuneCount(bytes) -> int` (the bytes that are not continuation bytes: a vector compare
      and a population count) and `Utf8Valid(bytes) -> bool`, each a `Table` with a kernel per level and a test against the portable one at every length (0, 1, 15, 16, 17, 63, 64, 65
      and the tails) and on unaligned slices. `Utf8Valid` is the three lookup method (nibble tables for `pshufb` / `vpshufb` / NEON `tbl` / SIMD128 swizzle, an incomplete-sequence
      carry between blocks, a check of the last block with a padded copy): SSSE3 is the first level that has it, the SCALAR level is a state machine or `core:unicode/utf8`. Use the
      test inputs of simdutf8 (`tests/tests.rs`: overlong forms, surrogates, above U+10FFFF, cuts at the end of a block) as cases, written out again here.
- [ ] (medium) The AVX-512 throttling rule: simdutf8 selects its 512 bit kernel only on CPUs with VBMI2 (Ice Lake and later) because the earlier ones lower the clock of the core while
      they run 512 bit instructions. Add `Feature.AVX512VBMI2` (CPUID 7, ECX bit 6) and, for the manager, a way to say "wide, but only where it does not throttle": a `Policy` field
      `wide_needs: Features` (default `{.AVX512VBMI2}` when the vendor is Intel, nothing on AMD Zen 4 and later, which does not throttle) so that on a Skylake-X the AVX-512 level goes to
      a client only when its slot rules say so and everyone else gets AVX2 without configuration. Measure before trusting the list: the dev machine is a Zen 5 and cannot show it.
- [ ] (low) A `prefetch` hint (`intrinsics.prefetch_read_data`) in the long block loops of the examples: simdutf8 uses it on AVX2 for a few Intel CPUs and found it helped on synthetic
      benchmarks only; measure before keeping it.
- [ ] (low) `LevelBuild()` and a note in the README on how simdutf8 treats a build that targets the wide level (`-C target-cpu=native` there, `-microarch:native` here): the run time
      selection is off in that case. For the table this means a kernel of the build's level needs no `enable_target_feature` and no run time check.

## From the reading of ghostty (`references/ghostty/src/simd`)
- [ ] (high) `IndexOfByte(bytes, needle)` and `IndexOfAny(bytes, set of up to 4)` kernels (SCALAR with a word at a time, SSE2 and NEON 16 bytes, AVX2 32, AVX-512 64; compare, move
      mask, count trailing zeros), as `Table`s: the base of every "find the next ESC / newline / space" loop in `ui` (cell screen, text wrap) and `font` (wordWidth). Tests at every
      length, at the first and the last byte, in the tail, with the needle not there, on unaligned slices.
- [ ] (medium) The stop-at-control kernel: `ScanText(bytes, stop) -> (length, ascii: bool)`: the length up to the first byte that is `stop` (ESC) or 0x80 and above, and whether the whole
      scanned part is ASCII, in one pass (compare, signed compare, OR, find first set). A consumer generic over `u8` and `u32` runs so ASCII is never widened (ghostty's
      `DecodeUTF8UntilControlSeq`). Used by `AnsiScreenWrite` (see `ui/TODO.md`).
- [ ] (medium) `RuneWidthRanges`: the width of a codepoint by range vectors (starts and ends in two aligned arrays of u16 and u32, the codepoint broadcast, a compare of a vector of ranges
      per step, frequent classes first, a constant min and max per table to reject early), with the exhaustive test against a reference over every codepoint (run it with the table;
      keep it in the test file under a `FULL` flag, not commented out). The tables come from the Unicode data files by a tool (see `font/TODO.md`).
- [ ] (low) A `Lanes($T)` helper: twice the native vector length (the number of lanes for a hot loop at the level, `LevelLanes` / size of T times two) so the loops of one level are written once for
      the element type.
- [ ] (low) The maximal subpart decoder as a library piece (`Utf8Next(bytes, at) -> (rune, size)` and `Utf8TrimPartial(bytes) -> int` that trims only a valid-so-far tail), used by `font`, `ui`
      and `AnsiScreenWrite`; one rule, one set of tests (see `font/TODO.md`).
- [ ] (low) A benchmark convention for the library: a generator tool that writes inputs to files with a fixed seed, and a bench tool that reads them, so two revisions run the same bytes
      (`tool/info --bench` makes its data in the process: fine for a screen, not for a comparison).

## The library
- [ ] (medium) `dsp` of odin_plug could use `Cpu`, `Table` and the manager instead of its own `Cpu_Level` (four steps) and `DSP_LEVEL`; that is a task for that repository (the
      level names differ: its `BASELINE` is `SSE2` here; its `AVX` kernels are generated by `tools/avxgen`).
- [ ] (medium) `ManagerSelect` for kernels that have a measured rank rather than a ladder (an algorithm where AVX2 beats AVX-512 below 8192 points: a `useful` that depends on the size).
      A `TablePickSized(table, level, size)` with a per kernel size limit, or the caller builds two tables.
- [ ] (low) SVE and the dot product extensions of ARM, F16C / BF16 / VNNI levels for the kernels that use them (features are detected on x86 already).
- [ ] (low) A test run per level: `SIMD_LEVEL` for every level in `tool/test`, so a kernel of a lower level runs on the dev machine in the same command.
