# simd

Which vector instructions this machine runs, which of them each library of a program may use, and which kernel it runs. The dispatch layer that the audio library
of `odin_plug` (`dsp`) grew by hand (CPUID, a `level` stored in every plan, an environment variable to compare levels), made reusable, plus a manager for programs
that have several libraries competing for the same vector units. Builds for js_wasm32 and arm64 (tests are in `simd_test.odin`, `#+build !js`).

| File | What |
|---|---|
| `simd.odin` | `Level` (the ladder), `LevelFromName`, `LevelClamp`, the `FEATURES_*` strings for `@(enable_target_feature)`, `LevelBuild()` |
| `cpu.odin`, `cpu_x86.odin`, `cpu_other.odin`, `cpu_env.odin` | `Cpu`: features, level, vendor and brand, found once at start up; `SIMD_LEVEL=avx2` and `CpuForce` lower it |
| `table.odin` | `Table($P)`: one kernel per level, `TablePick` takes the best at or below a level, `TableUseful` caps an algorithm where width stops paying |
| `manager.odin` | `Manager`: clients with a priority, a policy for the wide level, a queue, `ManagerSelect` |
| `example/` | a dot product with a kernel per level, tests that every level agrees, written to be copied |
| `tool/info` | `odin run simd/tool/info -- --bench`: the machine, the ladder, a manager scenario, a timing per level |

## The ladder

`SCALAR` (portable code, also the x87 only builds), `SSE2` (every x86-64), `SSE3`, `SSSE3`, `SSE4.1`, `SSE4.2`, `AVX` (256 bit floats, no FMA: Sandy Bridge, Ivy Bridge,
Bulldozer), `AVX2` (256 bit integers and FMA: Haswell, Zen), `AVX512` (F, DQ, BW and VL: Skylake-X, Zen 4). arm64 has `NEON`, the web has `SIMD128` (only when the build
turns it on: WebAssembly has no run time check). A CPU that has a level has all the levels under it; a level a kernel does not have runs the next one below.
Detection applies the operating system's part (XGETBV): a CPU with AVX whose system does not save the YMM registers is reported without AVX. MMX is not a level: it is
integer arithmetic on the x87 registers, nothing in float code can use it (the answer for 486 and Pentium MMX targets is the `SCALAR` level on an x87 build).

```odin
cpu := simd_utils.CpuGet()                           // cpu.level, cpu.features, simd_utils.CpuBrand(cpu)
simd_utils.CpuLevel()                                // the level programs use: the best, unless SIMD_LEVEL or CpuForce lowered it
```

## Kernels per level

```odin
sum_table: simd_utils.Table(SumProc)
simd_utils.TableSet(&sum_table, .SCALAR, sumScalar)   // the reference every other kernel is tested against
simd_utils.TableSet(&sum_table, .SSE2, sumSse2)       // core:simd 4 lanes: baseline code, also what NEON and SIMD128 run
simd_utils.TableSet(&sum_table, .AVX2, sumAvx2)       // @(enable_target_feature = simd_utils.FEATURES_AVX2)
kernel, level, ok := simd_utils.TablePick(&sum_table, simd_utils.CpuLevel())     // at plan time: keep the kernel in the plan
```

`TableUseful(&table, level)` says where more width stops paying. Measure it, and write the measurement where you call it: the gather kernel of the odin_plug resampler was
15 to 20 percent slower than four scalar sums, the radix 8 passes of its AVX-512 FFT lose above 8192 points (16 power of two strides alias in L1).

## Text kernels

`text.odin`: `AsciiPrefix`, `AsciiRun`, `IndexOfByte`, `IndexOfAny`, `ScanText`, `RuneCount`, `Utf8Valid`, `Utf8ValidUpTo`, and the scalar pieces `Utf8Next` (the character at a place; a bad
sequence is ONE error the size of its maximal subpart, as in the Unicode standard, table 3-7), `Utf8Decode`, `Utf8SequenceLength`, `Utf8ContinuationOk` (the pieces of a byte at a time decoder), `Utf8TrimPartial` (where a chunk of a stream can be cut) and `Utf8Clean` (a copy with U+FFFD
for every bad subpart). A kernel per level (`TextLevel(level)` gives the table of a level, the plain procedures use `CpuLevel()` and follow `CpuForce` and `SIMD_LEVEL`): 16 bytes for SSE2, NEON
and SIMD128 from one source of `core:simd`, 32 for AVX2, 64 for AVX-512; the UTF-8 validator is the lookup method of Keiser and Lemire (nibble tables and a byte shuffle, 16 byte vectors, ASCII
groups skipped with one test, the exact place of an error from the scalar rule). 40 to 170 GB/s for the scans and 20 to 25 GB/s for the validator on mixed text (4 to 5 times the scalar one).
`odin run simd/tool/info -o:speed -- --bench` prints them per level.

## The manager

A program with an audio engine, a physics step and an image filter runs them on one core, often on two threads that share one set of vector units, and on some CPUs a few
AVX-512 instructions lower the clock of the whole core. So the program says who comes first and the manager hands the wide level out in that order.

```odin
manager: simd_utils.Manager
simd_utils.ManagerInit(&manager)
audio, _ := simd_utils.ManagerRegister(&manager, "audio", priority = 100)         // wants the best there is
physics, _ := simd_utils.ManagerRegister(&manager, "physics", priority = 10)
images, _ := simd_utils.ManagerRegister(&manager, "images", priority = 1, wants = .AVX2)
simd_utils.ManagerFavor(&manager, audio)              // one wide slot for the first, the others run the level below it

level := simd_utils.ClientLevel(&manager, physics)    // AVX2 on an AVX-512 machine; the best it has on any other (and nothing is queued there)
kernel, got, ok := simd_utils.ManagerSelect(&manager, physics, &dot_table)        // the kernel of that level, not above what the algorithm is worth
```

The rules, applied to the clients in order of priority (the first registered among equals):
1. what it asks for (`wants`, default the best there is) limited by its `ceiling`, by the CPU and by `SIMD_LEVEL`;
2. from `Policy.wide` up (default AVX-512) a level needs a slot (`Policy.slots`, 0 is no limit: with no policy everyone gets what it asks for). A client without a slot waits
   in the queue and runs `Policy.fallback` (default the level below `wide`);
3. `ManagerRelease` of a client (stopped, idle) gives its slot to the next in the queue, `ManagerAcquire` takes one back at its priority;
4. every change resolves again and counts `ManagerGeneration`: a client that keeps a level in a plan compares the generation at the start of a block and makes new plans
   when it changed. A kernel never changes level in the middle of a block and the audio thread never calls the setters.

A client that only has kernels that gain nothing above AVX2 sets `wants = .AVX2` and never takes a slot. `ManagerExplain` writes a line for a log: `physics: AVX2 + FMA
(waiting for a wide slot, place 1 in the queue)`.

## What the research of odin_plug found (write kernels this way)

From `odin_plug/docs/SIMD_LEVELS.md`, `FFT_TECHNIQUES.md` and the benchmarks of its `dsp` library, on a Ryzen 9 9950X and a Core i7 Q 720:

- **Four accumulators in every reduction.** A fused multiply add takes four cycles and two can start per cycle: one register of sums uses an eighth of the multipliers. The
  FIR block, the true peak meter, the oversampler and the sum of squares got 1.5 to 9 times faster from this alone (`example/dot.odin` does it).
- **Add `-slow-unaligned-mem-32` to the features of 256 and 512 bit kernels** (the `FEATURES_*` strings have it): the generic x86-64 tuning splits every unaligned 256 bit
  load and store into two halves, which cost 1.3 to 2.5 times.
- **At `-o:none` and `-o:minimal` a `#force_inline` helper is a call.** A 256 bit value that crosses a call into a procedure without the same target feature loses its upper
  half (and x86 intrinsic wrappers with 256 bit arguments break). Give every level its own procedure with its own attribute, use `intrinsics.unaligned_load` and `simd.*`
  inline, and run the tests at `-o:none` and `-o:minimal` too.
- **`simd.fma` without the fma feature is a libm call per lane** (`fmaf`): buffer mixing was 28 times slower, the resampler 3 to 8 times, at the baseline level. In code that
  must run without FMA use multiply and add; scan the assembly (`-build-mode:asm`) for `call fmaf`.
- **A constant splat is not a vector of constants** (`v: #simd[8]u32 = 16` fills lane 0 only): broadcast with `simd.splat`-style code and test it.
- **A kernel for a level is tested against the portable one**, at every length (0, 1, 3, the sizes around one vector, around two, a tail), on unaligned slices, at every level the
  machine runs. The level agrees with the reference to a tolerance relative to the size of the terms: the sums are in another order.
- **Vectorizing a per sample loop over a ring does not work**: a vector load that covers a sample stored a moment before as a single float cannot take it from the store buffer
  and waits (the true peak and oversampler were slower with 4 products at a time, 11 to 12 times faster as a loop over a line of samples). Make the loop one over a block.
- **Gathers do not pay** on the machines measured (a gather tap sum was 15 to 20 percent slower than four scalar sums). `TableUseful(&table, .SCALAR)` is a legitimate answer.
- **A runtime radix loop spends as much on integer index work as on floating point**: a compile time parameter (`$K`) with every index an immediate was 20 to 35 percent faster
  on every level.
- **Code layout moves a benchmark by 20 to 30 percent** between builds that differ in nothing that runs: only big gaps are real, build twice before chasing a small one.
- **Judge a level only against what runs that level**: AVX2 against libraries that run AVX2 on that machine (IPP and MKL run AVX-512 on an AVX-512 CPU), the baseline against
  baseline builds. `SIMD_LEVEL=avx2` runs a whole program at one level on a machine that has more; a real old CPU decides the lower levels (the AVX2 numbers of a 9950X forced
  down are a screen: another cache and load port layout).
- **The level is chosen when a plan or a state is made and stored in it**, never per call: no branch in the loop, no kernel changing in the middle of a block.

## What ghostty's SIMD code teaches (`references/ghostty/src/simd`, `src/terminal/stream.zig`, `Terminal.zig`; MIT; read, nothing copied)

A terminal emulator is a program whose hot loop is text: bytes in, cells out. Its SIMD layer is small (index of a byte, UTF-8 decode up to an escape, the width of a codepoint, base64)
and its rules are worth keeping:

- **One pass answers two questions.** `DecodeUTF8UntilControlSeq` scans 16, 32 or 64 bytes at a time for "an ESC, or a byte of 0x80 or more" (one compare, one signed compare, an OR, a
  find-first-set) and hands back a flag `ascii`: when everything before the stop is ASCII nothing is decoded or written, the caller reads the input bytes. Only a non-ASCII byte
  starts the real decoder. The consumers are generic over the element type (`u8` for ASCII, `u32` for decoded text) so the ASCII case is never widened.
- **The error path is separate and cold.** The common case decodes and validates in one call; on an error it decodes the valid prefix, writes ONE U+FFFD for the *maximal subpart* of the
  bad sequence (Unicode table 3-7: the longest start of a well formed sequence, else one byte), and finds the next error with the read-only validator, "several times cheaper" than a
  second decode, so every valid run is decoded once. An incomplete sequence at the end is trimmed only when it is valid so far (a partial sequence that the next chunk can finish):
  an invalid start byte (C0, C1, F5 to FF) is an error now, not a carry.
- **Width by range vectors.** `codepoint_width.cpp` keeps every class (wide, zero width, combining marks) as two aligned arrays of range starts and range ends (16 bit and 32 bit
  tables: twice the lanes for the common BMP case), broadcasts the codepoint and compares it with a whole vector of ranges at a time. Order is by frequency: below 0x100 is width 1 with
  no lookup, the few big blocks (CJK) are checked first, each table has a constant minimum and maximum that rejects most codepoints before any compare. It is checked against a
  reference over every codepoint (a slow test, commented out in debug builds with a capital letter note to run it whenever the table changes).
- **Twice the native width.** `lanes(T)` is two registers per iteration "for instruction level parallelism": the same lesson as four accumulators.
- **A scalar fallback that is still fast.** With SIMD off (wasm without simd128) the same API runs a scalar path that batches: it decodes in bulk and hands printable runs to the handler,
  "much faster than per byte dispatch". The batching, not the vector width, is most of the win. Early exit search loops are not auto vectorized by LLVM: write the vector scan by hand.
- **Check once per slice, not per character.** `printSlice` tests the modes that need per character handling (insert mode, no wraparound, single shifts) once, then runs a loop that fills a
  row; ASCII reaches it as bytes (`printSliceAscii`) and is never classified again; the hyperlink case is a compile time variant. C0 and C1 controls are told from text with one AND
  (`(cp & ~0x9F) == 0`).
- **Chunking and carry.** Input is cut into pieces that fit a 4096 codepoint buffer; a scalar decoder keeps a partial sequence across calls so a split character never breaks.
- **Memory shape.** A cell is one 64 bit word (codepoint, style id, wide flag); the style is a reference counted table entry, graphemes beyond one codepoint live in a side table. Ours
  is 36 bytes with 16 of them for extra characters that almost no cell uses.
- **Benchmark discipline** (`src/benchmark/AGENTS.md`): generate the data first and benchmark it later (never pipe the generator into the benchmark), reuse the exact files across
  revisions, fixed seeds, medians of several runs after warm ups, never two benchmarks at once on a machine, release mode only.

## Limits

x86 and x86-64 are detected completely (CPUID leaves 0, 1, 7, 0x80000002 to 4, XGETBV); arm64 is NEON by definition, the web is SIMD128 when the build says so, nothing else
is detected there (no SVE, no dot product extensions: add a feature and a level when a kernel needs one). No cache sizes, topology or frequency model: the policy is a rule
of the program (which library is more important, how many wide units are shared), not a measurement of the machine. `FEATURES_AVX512` is for CPUs with F, DQ, BW and VL (Knights
Landing has F, CD, ER and PF and runs AVX2). 32 clients. The names of clients live in the caller's memory. Set up and change on one thread; `ClientLevel` is one byte and can be
read from any. `SIMD_LEVEL` is read once at start up (a program changes the level with `CpuForce` and resolves the manager again).

The reasons behind this layout (what was measured, what was tried and dropped) are in `odin_plug/docs/SIMD_LEVELS.md`, `FFT_TECHNIQUES.md` and `SIMD_CHECKLIST.md`; nothing is copied
from there, and `dsp` does not use this library yet (it has the same `Cpu_Level` of four steps inline: moving it over is a task for that repository).
