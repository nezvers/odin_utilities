package box2d_odin

// Deterministic random numbers for the samples, same generator as the C++ samples (shared/utils.h)

RAND_LIMIT :: 32767
RAND_SEED :: 12345

@(private="file")
random_seed: u32 = RAND_SEED

RandomReset :: proc() {
    random_seed = RAND_SEED
}

// XorShift32, value in range [0, RAND_LIMIT]
RandomInt :: proc() -> i32 {
    x: u32 = random_seed
    x ~= x << 13
    x ~= x >> 17
    x ~= x << 5
    random_seed = x
    return i32(x % (RAND_LIMIT + 1))
}

// Random integer in range [low, high]
RandomIntRange :: proc(low: i32, high: i32) -> i32 {
    return low + RandomInt() % (high - low + 1)
}

// Random number in range [-1, 1]
RandomFloat :: proc() -> f32 {
    r: f32 = f32(RandomInt() & RAND_LIMIT)
    r /= RAND_LIMIT
    return 2 * r - 1
}

// Random number in range [low, high]
RandomFloatRange :: proc(low: f32, high: f32) -> f32 {
    r: f32 = f32(RandomInt() & RAND_LIMIT)
    r /= RAND_LIMIT
    return (high - low) * r + low
}

RandomVec2 :: proc(low: f32, high: f32) -> Vec2 {
    return {RandomFloatRange(low, high), RandomFloatRange(low, high)}
}
