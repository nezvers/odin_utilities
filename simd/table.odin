package simd_utils

// The kernels of one algorithm, one procedure per level. The pattern that odin_plug's dsp uses for its FFT, FIR and buffer kernels (a portable reference, then wider versions
// with `@(enable_target_feature)`), without the `if level == .AVX2` ladders in every caller:
//
//     SumProc :: #type proc "contextless" (values: []f32) -> f32
//     sum_table: simd_utils.Table(SumProc)
//
//     simd_utils.TableSet(&sum_table, .SCALAR, sumScalar)       // the reference: every other kernel is tested against it
//     simd_utils.TableSet(&sum_table, .SSE2, sumSse2)
//     simd_utils.TableSet(&sum_table, .AVX2, sumAvx2)
//
//     sum, level := simd_utils.TablePick(&sum_table, simd_utils.CpuLevel())     // at plan time, kept in the plan
//
// A level without a kernel runs the next one below it that has one: an SSE4.1 machine runs `sumSse2`, an AVX-512 machine `sumAvx2` until someone writes a 16 lane kernel.
// `TableUseful` says where more width stops paying (measure it: the gather resampler of odin_plug was slower at AVX2 than the four sums of the baseline, the radix 8 passes of
// its AVX-512 FFT lose above 8192 points): `TablePickFor` never goes above it.

Table :: struct($P: typeid) {
    procs: [Level]P,
    useful: Level,          // the highest level worth running; only when `capped`
    capped: bool,
    min_size: [Level]int,   // a kernel that is for sizes from here (0: no lower limit): see TableSetRange
    max_size: [Level]int,   // and up to here (0: no upper limit)
}

TableSet :: proc(table: ^Table($P), level: Level, kernel: P) {
    table.procs[level] = kernel
}

// A kernel for a range of sizes: an algorithm where AVX2 beats AVX-512 below 8192 points (the radix 8 passes of the AVX-512 FFT of odin_plug lose above it: strides that alias in L1) is two
// kernels, the AVX2 one for every size and the AVX-512 one for `max_size = 8192`; `TablePickSized` takes the best kernel whose range has the size
TableSetRange :: proc(table: ^Table($P), level: Level, kernel: P, min_size: int, max_size: int) {
    table.procs[level], table.min_size[level], table.max_size[level] = kernel, min_size, max_size
}

TableHas :: proc(table: ^Table($P), level: Level) -> bool {
    return table.procs[level] != nil
}

// The levels that have a kernel
TableLevels :: proc(table: ^Table($P)) -> (levels: bit_set[Level]) {
    for level in Level {
        if table.procs[level] != nil { levels += {level} }
    }
    return
}

// Says that levels above `level` are not worth it for this algorithm (a measured fact: write the reason where you call it)
TableUseful :: proc(table: ^Table($P), level: Level) {
    table.useful, table.capped = level, true
}

// The best kernel at or below `level`: the level it is for, and false when the table has nothing there (not even the portable one)
TablePick :: proc(table: ^Table($P), level: Level) -> (kernel: P, got: Level, ok: bool) {
    at: Level = level
    for {
        if table.procs[at] != nil { return table.procs[at], at, true }
        if at == .SCALAR { return }
        at = LevelBelow(at)
    }
}

// The same, never above the level the algorithm is worth running at. `level` is clamped to the machine first, so a level of another family means "the best".
TablePickFor :: proc(table: ^Table($P), level: Level) -> (kernel: P, got: Level, ok: bool) {
    target: Level = LevelClamp(level, CpuBest())
    if table.capped && LevelFamily(table.useful) == LevelFamily(target) { target = min(target, table.useful) }
    if table.capped && table.useful == .SCALAR { target = .SCALAR }
    return TablePick(table, target)
}

// The best kernel at or below `level` that is for this size (a measured rank: the kernels of the ranges that do not have it are passed over)
TablePickSized :: proc(table: ^Table($P), level: Level, size: int) -> (kernel: P, got: Level, ok: bool) {
    at: Level = level
    for {
        low: int = table.min_size[at]
        high: int = table.max_size[at]
        if table.procs[at] != nil && size >= low && (high == 0 || size <= high) { return table.procs[at], at, true }
        if at == .SCALAR { return }
        at = LevelBelow(at)
    }
}
