package ui

// A cache for the sizes of texts. Measuring is the most repeated work of a frame (every word of every wrapped text, the width of every label, the prefixes of a text field or area),
// and the same texts come back every frame, so the answer is kept: a table of UI_MEASURE_CACHE slots in the context, found by a 64 bit hash of the bytes, the length and the font size
// (a slot is overwritten by a text that lands on it: no growing, no aging). The measure proc is only called for a text the table does not hold.
//
// The answer depends on the font and on how the glue scales its text: call `UiMeasureCacheClear` when either changes (a new font, a new UI scale).

UI_MEASURE_CACHE :: #config(UI_MEASURE_CACHE, 2048)

@(private)
MeasureEntry :: struct {
    key: u64,               // 0: empty
    size: f32,
    length: u32,
    result: Vec2,
}

@(private)
MeasureCache :: struct {
    entries: [UI_MEASURE_CACHE]MeasureEntry,
    hits: u64,
    misses: u64,
    scale: f32,             // the UI scale the entries were measured at
}

// The size of `text` at `font_size`, from the cache when it has it.
@(private)
measureText :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    // FNV-1a over the bytes, the size mixed in; 0 is kept for an empty slot
    hash: u64 = 14695981039346656037
    for byte in transmute([]u8)text {
        hash ~= u64(byte)
        hash *= 1099511628211
    }
    hash ~= u64(transmute(u32)font_size)
    hash *= 1099511628211
    if hash == 0 { hash = 1 }
    cache: ^MeasureCache = &ctx.measure_cache
    entry: ^MeasureEntry = &cache.entries[hash % UI_MEASURE_CACHE]
    if entry.key == hash && entry.length == u32(len(text)) && entry.size == font_size {
        cache.hits += 1
        return entry.result
    }
    cache.misses += 1
    result: Vec2 = ctx.measure(ctx, text, font_size)
    entry^ = {key = hash, size = font_size, length = u32(len(text)), result = result}
    return result
}

// Forgets every measured size (a new font, a new UI scale).
UiMeasureCacheClear :: proc(ctx: ^Context) {
    ctx.measure_cache.entries = {}
}

// Tells the cache the UI scale of this frame (the painter's): a different one than before clears it, because a glue measures the text it draws, and the size of the same text
// at another scale is not exactly the scale times the old size (the glyphs are rounded to pixels). Call it every frame before the widgets (ui_kit.Begin does).
UiMeasureCacheScale :: proc(ctx: ^Context, scale: f32) {
    if ctx.measure_cache.scale != scale {
        ctx.measure_cache.entries = {}
        ctx.measure_cache.scale = scale
    }
}

// How many measures the cache answered and how many went to the measure proc since the context was made (the difference of two readings is a frame's).
UiMeasureCacheStats :: proc(ctx: ^Context) -> (hits: u64, misses: u64) {
    return ctx.measure_cache.hits, ctx.measure_cache.misses
}
