# simd: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md (it also holds the kernel rules: four accumulators, one procedure per level, no shared `#force_inline` helper across features, `fma` only with the feature).

Dispatch by instruction set, from the research of odin_plug's `dsp`.

## Levels and CPU
- `simd.odin`: `Level` ladder SCALAR, SSE2, SSE3, SSSE3, SSE41, SSE42, AVX, AVX2, AVX512 and NEON, SIMD128; `LevelFromName`, `LevelClamp`, `FEATURES_*` for `@(enable_target_feature)` with `-slow-unaligned-mem-32`, `LevelBuild()`.
- `cpu.odin` + `cpu_x86.odin` (CPUID, XGETBV, vendor, brand) + `cpu_other.odin` (a `when`, not a build tag: "everything but x86" cannot be one) + `cpu_env.odin` (`SIMD_LEVEL`, `#+build !js`).

## Selection
- `table.odin`: `Table($P)`, `TablePick`, `TableUseful`, `TableSetRange`, `TablePickSized`.
- `manager.odin` `Manager`: clients with priority, wide slots in a queue, `ManagerFavor`, `ManagerRelease/ManagerAcquire`, `ManagerSelect`, a generation counter. Throttling rule: `Cpu.throttles`, `Policy.allow_throttling`.

## Kernels
- `text.odin` + `text_vector.odin` + `text_vector_x86.odin`: text kernels per level, maximal subpart UTF-8 rules. Tables are filled by an `@(init)` before any thread, never lazily. Kernels with 256/512 bit vectors load inline: no helper without the target feature.
- `example/`: a dot product kernel per level (tested at -o:none, minimal, speed).

## Tools and tests
- `odin run simd/tool/info -o:speed -- --bench [--data <folder>]`; `tool/gen` writes fixed seed data files for the text benchmarks.
- `odin run tool/test -- --levels` runs the packages that use simd at every level.
- `simd_test.odin` builds synthetic `Cpu` records with `CpuFromFeatures`: never test the manager through the global CPU.
- wasm: the 16 byte text kernels (`text_vector.odin`) need `-target-features:simd128`; without it `textFillPortable` returns early so nothing refers to them (LLVM otherwise stops with "Do not know how to split the result of this operator!") and the levels stay SCALAR. `WebBuild` passes the flag.
- `web_check/`: the text kernels of SIMD128 against the scalar ones and the standard library in a real browser (`text_web_check.odin`, `#+build js`): `odin run simd/web_check/build_web -- --build-only`, serve `simd/web_check/game/bin/web` (`odin run web_serve/tool -- <dir>`) and read it with `chrome --headless=new --virtual-time-budget=60000 --dump-dom <url>`; the title says "SIMD128 PASS: 0 of N checks failed, simd128 kernels ran". Passed in Chrome and Edge (45885 checks, 2026-11-28). `odin run simd/web_check/build_web -- --headless` does all of it (build, serve, headless Chrome or Edge, verdict, exit code 0/1, 3 without a browser) and `odin run tool/test -- --browser` runs it with the tests. Run it after changing a kernel.
