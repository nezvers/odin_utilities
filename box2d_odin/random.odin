package box2d_odin
import "core:sync"
import "core:testing"

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

// --- Tests ---

@(test)
test_random_is_deterministic_and_in_range :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    RandomReset()
    first: [8]i32
    for &value in first { value = RandomInt() }
    RandomReset()
    for value in first { testing.expect_value(t, RandomInt(), value) }                     // the same sequence after a reset

    for _ in 0 ..< 2000 {
        value: i32 = RandomInt()
        testing.expect(t, value >= 0 && value <= RAND_LIMIT)
        ranged: i32 = RandomIntRange(-3, 4)
        testing.expect(t, ranged >= -3 && ranged <= 4)
        unit: f32 = RandomFloat()
        testing.expect(t, unit >= -1 && unit <= 1)
        spread: f32 = RandomFloatRange(2, 5)
        testing.expect(t, spread >= 2 && spread <= 5)
        point: Vec2 = RandomVec2(-1, 1)
        testing.expect(t, point.x >= -1 && point.x <= 1 && point.y >= -1 && point.y <= 1)
    }

    RandomReset()
    seen: map[i32]bool
    defer delete(seen)
    for _ in 0 ..< 500 { seen[RandomIntRange(1, 6)] = true }
    testing.expect_value(t, len(seen), 6)                                                  // every face of the die shows up
    RandomReset()
}
