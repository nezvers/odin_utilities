package oidc

import "../blake3"

// The identity that SpacetimeDB gives to a login (`Identity::from_claims` in crates/lib/src/identity.rs): blake3 of "issuer|subject", 26 bytes of it behind a prefix 0xc2 0x00 and a 4 byte
// checksum (the first bytes of blake3 over the prefix and those 26 bytes). Computed without a connection, so a program knows who a player is before the server says so.
// The result is in the order of the hex text (big endian, starts with c200): `spacetimedb.IdentityFromClaims` gives the same as an `Identity` (the wire order is the reverse).
// The text is hashed in pieces, so any length of issuer and subject works and nothing is allocated.
IdentityBytesFromClaims :: proc(issuer: string, subject: string) -> [32]u8 {
    hasher: blake3.Blake3Hasher
    blake3.Blake3Init(&hasher)
    blake3.Blake3Update(&hasher, transmute([]u8)issuer)
    blake3.Blake3Update(&hasher, transmute([]u8)string("|"))
    blake3.Blake3Update(&hasher, transmute([]u8)subject)
    first: [32]u8
    blake3.Blake3Final(&hasher, first[:])

    checksum_input: [28]u8
    checksum_input[0] = 0xc2
    copy(checksum_input[2:], first[:26])
    checksum: [32]u8
    blake3.Blake3Hash(checksum_input[:], checksum[:])

    result: [32]u8
    result[0] = 0xc2
    copy(result[2:6], checksum[:4])
    copy(result[6:], first[:26])
    return result
}

// True when the first 6 bytes of an identity in hex order are a prefix and a checksum that fit the rest
IdentityBytesValid :: proc(identity: [32]u8) -> bool {
    identity: [32]u8 = identity
    if identity[0] != 0xc2 || identity[1] != 0x00 { return false }
    checksum_input: [28]u8
    checksum_input[0] = 0xc2
    copy(checksum_input[2:], identity[6:])
    checksum: [32]u8
    blake3.Blake3Hash(checksum_input[:], checksum[:])
    return checksum[0] == identity[2] && checksum[1] == identity[3] && checksum[2] == identity[4] && checksum[3] == identity[5]
}
