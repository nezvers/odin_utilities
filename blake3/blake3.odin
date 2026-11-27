// BLAKE3 (https://github.com/BLAKE3-team/BLAKE3-specs): a portable implementation of the reference algorithm, with no allocation and no dependency on the operating system, so it also builds
// for the web. It is one pass, scalar code: about the speed of the reference implementation, not of the SIMD ones (see README.md for when that matters).
//
//     digest: [32]u8
//     blake3.Blake3Hash(data, digest[:])                          // one call
//
//     hasher: blake3.Blake3Hasher                                 // or in pieces
//     blake3.Blake3Init(&hasher)
//     blake3.Blake3Update(&hasher, first_part)
//     blake3.Blake3Update(&hasher, second_part)
//     blake3.Blake3Final(&hasher, digest[:])                      // any length: an extendable output; the hasher can go on after it
//
// `Blake3InitKeyed` makes a MAC with a 32 byte key, `Blake3InitDeriveKey` derives keys from a context string and key material (the context has to be hardcoded and globally unique, see the spec).
package blake3

BLAKE3_OUT_LEN :: 32
BLAKE3_KEY_LEN :: 32
BLAKE3_BLOCK_LEN :: 64
BLAKE3_CHUNK_LEN :: 1024

// The deepest tree of 2^64 bytes of input needs 54 chaining values on the stack (the number of chunks is a u64 and a chunk is 2^10 bytes)
@(private)
MAX_DEPTH :: 54

@(private)
CHUNK_START: u32 : 1 << 0
@(private)
CHUNK_END: u32 : 1 << 1
@(private)
PARENT: u32 : 1 << 2
@(private)
ROOT: u32 : 1 << 3
@(private)
KEYED_HASH: u32 : 1 << 4
@(private)
DERIVE_KEY_CONTEXT: u32 : 1 << 5
@(private)
DERIVE_KEY_MATERIAL: u32 : 1 << 6

@(private)
IV: [8]u32 = {0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19}

// The order in which the message words are taken in the next round
@(private)
MESSAGE_PERMUTATION: [16]u8 = {2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8}

// The state of one chunk (up to 1024 bytes, the leaves of the tree)
@(private)
ChunkState :: struct {
    chain_value: [8]u32,
    chunk_counter: u64,
    block: [BLAKE3_BLOCK_LEN]u8,
    block_len: u8,
    blocks_compressed: u8,
    flags: u32,
}

// Incremental hashing. A plain value (about 2 KB): put it on the stack or in a struct, nothing to free
Blake3Hasher :: struct {
    chunk_state: ChunkState,
    key: [8]u32,
    cv_stack: [MAX_DEPTH][8]u32,        // the chaining values of the finished subtrees that wait for their right neighbour
    cv_stack_len: u8,
    flags: u32,
}

// What a node of the tree hands to its parent (a chaining value) or, at the root, what the output is made of
@(private)
Output :: struct {
    input_chain_value: [8]u32,
    block_words: [16]u32,
    counter: u64,
    block_len: u32,
    flags: u32,
}

@(private)
rotateRight :: #force_inline proc(x: u32, n: u32) -> u32 {
    return (x >> n) | (x << (32 - n))
}

@(private)
quarterRound :: #force_inline proc(state: ^[16]u32, a: int, b: int, c: int, d: int, mx: u32, my: u32) {
    state[a] = state[a] + state[b] + mx
    state[d] = rotateRight(state[d] ~ state[a], 16)
    state[c] = state[c] + state[d]
    state[b] = rotateRight(state[b] ~ state[c], 12)
    state[a] = state[a] + state[b] + my
    state[d] = rotateRight(state[d] ~ state[a], 8)
    state[c] = state[c] + state[d]
    state[b] = rotateRight(state[b] ~ state[c], 7)
}

@(private)
round :: #force_inline proc(state: ^[16]u32, m: ^[16]u32) {
    // columns
    quarterRound(state, 0, 4, 8, 12, m[0], m[1])
    quarterRound(state, 1, 5, 9, 13, m[2], m[3])
    quarterRound(state, 2, 6, 10, 14, m[4], m[5])
    quarterRound(state, 3, 7, 11, 15, m[6], m[7])
    // diagonals
    quarterRound(state, 0, 5, 10, 15, m[8], m[9])
    quarterRound(state, 1, 6, 11, 12, m[10], m[11])
    quarterRound(state, 2, 7, 8, 13, m[12], m[13])
    quarterRound(state, 3, 4, 9, 14, m[14], m[15])
}

@(private)
permute :: #force_inline proc(m: ^[16]u32) {
    permuted: [16]u32
    for i in 0 ..< 16 { permuted[i] = m[MESSAGE_PERMUTATION[i]] }
    m^ = permuted
}

// The compression function: 7 rounds over a state of the chaining value, the first four IV words, the counter, the block length and the flags. Returns all 16 words (the first 8 are the new
// chaining value, all 16 are output bytes at the root).
@(private)
compress :: proc(chain_value: ^[8]u32, block_words: ^[16]u32, counter: u64, block_len: u32, flags: u32) -> [16]u32 {
    state: [16]u32 = {
        chain_value[0], chain_value[1], chain_value[2], chain_value[3],
        chain_value[4], chain_value[5], chain_value[6], chain_value[7],
        IV[0], IV[1], IV[2], IV[3],
        u32(counter), u32(counter >> 32), block_len, flags,
    }
    block: [16]u32 = block_words^
    for index in 0 ..< 7 {
        round(&state, &block)
        if index < 6 { permute(&block) }
    }
    for i in 0 ..< 8 {
        state[i] ~= state[i + 8]
        state[i + 8] ~= chain_value[i]
    }
    return state
}

@(private)
wordsFromBytes :: proc(bytes: []u8, words: []u32) {
    for i in 0 ..< len(words) {
        words[i] = u32(bytes[i * 4]) | u32(bytes[i * 4 + 1]) << 8 | u32(bytes[i * 4 + 2]) << 16 | u32(bytes[i * 4 + 3]) << 24
    }
}

@(private)
outputChainValue :: proc(output: ^Output) -> [8]u32 {
    words: [16]u32 = compress(&output.input_chain_value, &output.block_words, output.counter, output.block_len, output.flags)
    return {words[0], words[1], words[2], words[3], words[4], words[5], words[6], words[7]}
}

// The bytes of the root: the root node is compressed again with a growing counter, 64 bytes each, which is what makes the output extendable
@(private)
outputRootBytes :: proc(output: ^Output, out: []u8) {
    output_block_counter: u64
    offset: int
    for offset < len(out) {
        words: [16]u32 = compress(&output.input_chain_value, &output.block_words, output_block_counter, output.block_len, output.flags | ROOT)
        for word in words {
            for byte_index in 0 ..< 4 {
                if offset >= len(out) { return }
                out[offset] = u8(word >> u32(8 * byte_index))
                offset += 1
            }
        }
        output_block_counter += 1
    }
}

@(private)
chunkStateInit :: proc(key: [8]u32, chunk_counter: u64, flags: u32) -> ChunkState {
    return {chain_value = key, chunk_counter = chunk_counter, flags = flags}
}

@(private)
chunkStateLen :: proc(state: ^ChunkState) -> int {
    return BLAKE3_BLOCK_LEN * int(state.blocks_compressed) + int(state.block_len)
}

@(private)
chunkStateStartFlag :: proc(state: ^ChunkState) -> u32 {
    return CHUNK_START if state.blocks_compressed == 0 else 0
}

@(private)
chunkStateUpdate :: proc(state: ^ChunkState, input: []u8) {
    input: []u8 = input
    for len(input) > 0 {
        // a full block is only compressed when more input follows: the last block of a chunk has to carry CHUNK_END
        if int(state.block_len) == BLAKE3_BLOCK_LEN {
            block_words: [16]u32
            wordsFromBytes(state.block[:], block_words[:])
            words: [16]u32 = compress(&state.chain_value, &block_words, state.chunk_counter, BLAKE3_BLOCK_LEN, state.flags | chunkStateStartFlag(state))
            state.chain_value = {words[0], words[1], words[2], words[3], words[4], words[5], words[6], words[7]}
            state.blocks_compressed += 1
            state.block = {}
            state.block_len = 0
        }
        want: int = BLAKE3_BLOCK_LEN - int(state.block_len)
        take: int = min(want, len(input))
        copy(state.block[state.block_len:], input[:take])
        state.block_len += u8(take)
        input = input[take:]
    }
}

@(private)
chunkStateOutput :: proc(state: ^ChunkState) -> Output {
    block_words: [16]u32
    wordsFromBytes(state.block[:], block_words[:])
    return {
        input_chain_value = state.chain_value,
        block_words = block_words,
        counter = state.chunk_counter,
        block_len = u32(state.block_len),
        flags = state.flags | chunkStateStartFlag(state) | CHUNK_END,
    }
}

@(private)
parentOutput :: proc(left: [8]u32, right: [8]u32, key: [8]u32, flags: u32) -> Output {
    block_words: [16]u32
    for i in 0 ..< 8 {
        block_words[i] = left[i]
        block_words[i + 8] = right[i]
    }
    return {input_chain_value = key, block_words = block_words, counter = 0, block_len = BLAKE3_BLOCK_LEN, flags = PARENT | flags}
}

@(private)
parentChainValue :: proc(left: [8]u32, right: [8]u32, key: [8]u32, flags: u32) -> [8]u32 {
    output: Output = parentOutput(left, right, key, flags)
    return outputChainValue(&output)
}

@(private)
hasherInitInternal :: proc(hasher: ^Blake3Hasher, key: [8]u32, flags: u32) {
    hasher^ = {chunk_state = chunkStateInit(key, 0, flags), key = key, flags = flags}
}

// A plain hash
Blake3Init :: proc(hasher: ^Blake3Hasher) {
    hasherInitInternal(hasher, IV, 0)
}

// A keyed hash (a MAC): the key is 32 bytes
Blake3InitKeyed :: proc(hasher: ^Blake3Hasher, key: []u8) {
    assert(len(key) == BLAKE3_KEY_LEN, "a BLAKE3 key is 32 bytes")
    key_words: [8]u32
    wordsFromBytes(key, key_words[:])
    hasherInitInternal(hasher, key_words, KEYED_HASH)
}

// Key derivation: hash the context string first, then the key material with the result as the key. Feed the key material with Blake3Update and read the new key with Blake3Final.
Blake3InitDeriveKey :: proc(hasher: ^Blake3Hasher, context_string: string) {
    context_hasher: Blake3Hasher
    hasherInitInternal(&context_hasher, IV, DERIVE_KEY_CONTEXT)
    Blake3Update(&context_hasher, transmute([]u8)context_string)
    context_key: [BLAKE3_KEY_LEN]u8
    Blake3Final(&context_hasher, context_key[:])
    key_words: [8]u32
    wordsFromBytes(context_key[:], key_words[:])
    hasherInitInternal(hasher, key_words, DERIVE_KEY_MATERIAL)
}

// A finished subtree waits on the stack; when its right neighbour of the same size is done too they merge, like the carry of a binary counter (`total_chunks` is the number of chunks so far)
@(private)
hasherAddChunkChainValue :: proc(hasher: ^Blake3Hasher, chain_value: [8]u32, total_chunks: u64) {
    new_value: [8]u32 = chain_value
    total: u64 = total_chunks
    for total & 1 == 0 {
        hasher.cv_stack_len -= 1
        new_value = parentChainValue(hasher.cv_stack[hasher.cv_stack_len], new_value, hasher.key, hasher.flags)
        total >>= 1
    }
    hasher.cv_stack[hasher.cv_stack_len] = new_value
    hasher.cv_stack_len += 1
}

Blake3Update :: proc(hasher: ^Blake3Hasher, input: []u8) {
    input: []u8 = input
    for len(input) > 0 {
        // a full chunk is only closed when more input follows (the last chunk may be the root)
        if chunkStateLen(&hasher.chunk_state) == BLAKE3_CHUNK_LEN {
            output: Output = chunkStateOutput(&hasher.chunk_state)
            chain_value: [8]u32 = outputChainValue(&output)
            total_chunks: u64 = hasher.chunk_state.chunk_counter + 1
            hasherAddChunkChainValue(hasher, chain_value, total_chunks)
            hasher.chunk_state = chunkStateInit(hasher.key, total_chunks, hasher.flags)
        }
        want: int = BLAKE3_CHUNK_LEN - chunkStateLen(&hasher.chunk_state)
        take: int = min(want, len(input))
        chunkStateUpdate(&hasher.chunk_state, input[:take])
        input = input[take:]
    }
}

// Write `len(out)` bytes of the output (32 is the usual hash). The hasher is not changed: more can be added after it, and a longer or shorter output starts with the same bytes
Blake3Final :: proc(hasher: ^Blake3Hasher, out: []u8) {
    output: Output = chunkStateOutput(&hasher.chunk_state)
    remaining: int = int(hasher.cv_stack_len)
    for remaining > 0 {
        remaining -= 1
        chain_value: [8]u32 = outputChainValue(&output)
        output = parentOutput(hasher.cv_stack[remaining], chain_value, hasher.key, hasher.flags)
    }
    outputRootBytes(&output, out)
}

// Hash `data` in one call and write `len(out)` bytes (32 for the usual digest)
Blake3Hash :: proc(data: []u8, out: []u8) {
    hasher: Blake3Hasher
    Blake3Init(&hasher)
    Blake3Update(&hasher, data)
    Blake3Final(&hasher, out)
}

// The same for text
Blake3HashString :: proc(text: string, out: []u8) {
    Blake3Hash(transmute([]u8)text, out)
}
