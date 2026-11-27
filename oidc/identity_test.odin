#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "core:testing"

@(test)
test_identity_from_claims_has_the_prefix_and_a_valid_checksum :: proc(t: ^testing.T) {
    pairs: [4][2]string = {{"https://accounts.google.com", "1234"}, {"a", "b"}, {"", ""}, {"http://127.0.0.1:5000", "user-with-a-long-subject-0123456789-0123456789-0123456789-0123456789-0123456789"}}
    seen: [4][32]u8
    for pair, index in pairs {
        identity: [32]u8 = IdentityBytesFromClaims(pair[0], pair[1])
        testing.expect(t, identity[0] == 0xc2 && identity[1] == 0x00)
        testing.expect(t, IdentityBytesValid(identity))
        seen[index] = identity
        broken: [32]u8 = identity
        broken[20] ~= 1
        testing.expect(t, !IdentityBytesValid(broken), "a changed byte breaks the checksum")
    }
    testing.expect(t, seen[0] != seen[1] && seen[1] != seen[2])
    // the separator is part of the hash: "a|" + "b" and "a" + "|b" are the same text, as in the server
    testing.expect_value(t, IdentityBytesFromClaims("a|", "b"), IdentityBytesFromClaims("a", "|b"))
}
