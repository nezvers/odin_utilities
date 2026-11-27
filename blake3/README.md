# blake3

BLAKE3 for Odin: the reference algorithm in portable code. Hashing, keyed hashing (MAC), key derivation, an incremental API and output of any length. No allocation, no operating system, no dependency (`core:encoding/hex` and `core:encoding/json` only in the test), so it builds for the web too. Odin's `core:crypto` has no BLAKE3.

```odin
import "odin_utilities/blake3"

digest: [32]u8
blake3.Blake3HashString("hello", digest[:])
```

In pieces (a file, a stream), the usual digest is 32 bytes, any other length is an extendable output:

```odin
hasher: blake3.Blake3Hasher                 // a plain value of about 2 KB, nothing to free
blake3.Blake3Init(&hasher)
blake3.Blake3Update(&hasher, part_one)
blake3.Blake3Update(&hasher, part_two)
blake3.Blake3Final(&hasher, digest[:])      // does not change the hasher: update and final again if you like
```

A MAC and a key derivation:

```odin
blake3.Blake3InitKeyed(&hasher, key[:])                           // 32 byte key, then Update and Final
blake3.Blake3InitDeriveKey(&hasher, "my-app 2026-01-01 session keys")   // a hardcoded, globally unique context, then the key material
```

## Correct

`odin test blake3` runs the official test vectors of the BLAKE3 team (`testdata/test_vectors.json`): 35 input lengths from 0 to 102400 bytes, each for the hash, the keyed hash and the derived key, 131 bytes of output each. Every length is also fed in pieces of 1, 7, 63, 64, 65, 1023, 1024, 1025 and 4096 bytes, so that the block and chunk borders are crossed in every way.

## Speed

One thread, scalar: about 600 MB/s on one core of a Ryzen at `-o:speed` (a 64 MiB buffer), 116 ns for a hash of 64 bytes. The SIMD implementations of the BLAKE3 team are several times faster on big inputs (they hash 4 to 16 chunks at once); this one is for what is small or not on the critical path: identities, content ids, keys, checksums. If a program ever hashes gigabytes, a SIMD path belongs behind the same API (`Blake3Update` could take whole chunks in groups).

## Used by

`oidc`: the identity of a login is `blake3(issuer | subject)` (see `oidc/identity.odin`).
