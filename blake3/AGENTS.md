# blake3: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `blake3.odin` is the whole library: the reference algorithm (compress, chunk state, parent nodes, a stack of 54 chaining values for the tree, extendable output from the root), written straight after the BLAKE3 specification so it can be compared with it line by line. `Blake3Hasher` is a plain value: no allocator anywhere.
- A full block (or chunk) is compressed only when more input follows: the last block of a chunk has to carry CHUNK_END and the last chunk may be the root. That is the one thing a rewrite breaks first; the vector lengths 64, 1024, 1025 are there for it.
- `Blake3Final` does not change the hasher (it works on a copy of the root output), so it can be called again, with another length, or after more input.
- `blake3_test.odin` (built only on desktop targets, because it reads the official vectors with `core:encoding/json`) is the check; `testdata/test_vectors.json` is the file of the BLAKE3 repository unchanged. Run `odin test blake3` (or `odin test .` inside). Mutation check done: a changed rotation constant fails 421 expectations.
- Scalar only (about 600 MB/s). A SIMD path (4 or 8 chunks at once, AVX2 with `core:simd`) is possible behind `Blake3Update` but nothing needs it yet; do not add it without a measured user.
- Used by `oidc/identity.odin` (SpacetimeDB identities).
