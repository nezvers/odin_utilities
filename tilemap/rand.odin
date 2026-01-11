package tilemap

// Generate from seed state.
// Generating a batch starting with the same number should produce same results
rnd :: proc(seed: ^u32)->u32{
    /* Taken from OneLoneCoder: https://github.com/OneLoneCoder/Javidx9/blob/0c8ec20a9ed3b2daf76a925034ac5e7e6f4096e0/PixelGameEngine/SmallerProjects/OneLoneCoder_PGE_ProcGen_Universe.cpp#L170 */
    seed^ += 0xe120fc15
    tmp:u64 = cast(u64)(seed^ * 0x4a39b70d)
    m1:u32 = cast(u32)((tmp >> 32) ~ tmp)
    tmp = cast(u64)(m1 * 0x12fad5c9)
    m2:u32 = cast(u32)((tmp >> 32) ~ tmp)
    return m2
}

// Generation thats repeatable with same inputs
cash :: proc(seed:u32, x:int, y:int)->u32 {
    /* https://stackoverflow.com/a/37221804 */
    h:u32 = seed + cast(u32)x * 374761393 + cast(u32)y * 668265263 //all constants are prime
    h = (h ~ (h >> 13)) * 1274126177
    result:u32 = h ~ (h >> 16)
    return result
}

