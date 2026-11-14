package tilemap
import "core:testing"



// Generate from seed state.
// Generating a batch starting with the same number should produce same results
rnd :: proc(seed: ^u32)->u32{
    /* Taken from OneLoneCoder: https://github.com/OneLoneCoder/Javidx9/blob/0c8ec20a9ed3b2daf76a925034ac5e7e6f4096e0/PixelGameEngine/SmallerProjects/OneLoneCoder_PGE_ProcGen_Universe.cpp#L183 */
    seed^ += 0xe120fc15
    tmp:u64 = cast(u64)(seed^ * 0x4a39b70d)
    m1:u32 = cast(u32)((tmp >> 32) ~ tmp)
    tmp = cast(u64)(m1 * 0x12fad5c9)
    m2:u32 = cast(u32)((tmp >> 32) ~ tmp)
    return m2
}

// Random number from min up to, but not including, max
rnd_int :: proc(seed: ^u32, min:int, max:int)->int{
    assert(max > min)
    num:u32 = rnd(seed)
    result:int = cast(int)(num % cast(u32)(max - min)) + min
    return result
}

// Generation thats repeatable with same inputs
cash :: proc(seed:u32, x:int, y:int)->u32 {
    /* https://stackoverflow.com/a/37221804 */
    h:u32 = seed + cast(u32)x * 374761393 + cast(u32)y * 668265263 //all constants are prime
    h = (h ~ (h >> 13)) * 1274126177
    result:u32 = h ~ (h >> 16)
    return result
}

// --- Tests ---

@(test)
test_rnd_is_repeatable :: proc(t: ^testing.T) {
    a, b: u32 = 42, 42
    for _ in 0 ..< 16 { testing.expect_value(t, rnd(&a), rnd(&b)) }
    testing.expect_value(t, a, b)
    testing.expect(t, a != 42, "the seed is advanced")

    first, second: u32 = 1, 2
    testing.expect(t, rnd(&first) != rnd(&second), "different seeds, different numbers")
}

@(test)
test_rnd_int_range :: proc(t: ^testing.T) {
    seed: u32 = 7
    counts: [5]int
    for _ in 0 ..< 1000 {
        value: int = rnd_int(&seed, 2, 7)
        testing.expect(t, value >= 2 && value < 7, "the maximum is exclusive")
        counts[value - 2] += 1
    }
    for count in counts { testing.expect(t, count > 100, "every value shows up often") }
}

@(test)
test_cash_hash :: proc(t: ^testing.T) {
    testing.expect_value(t, cash(5, 1, 2), cash(5, 1, 2))
    testing.expect(t, cash(5, 1, 2) != cash(5, 2, 1))
    testing.expect(t, cash(5, 1, 2) != cash(6, 1, 2))
    testing.expect(t, cash(5, 1, 2) != cash(5, 1, 3))
}
