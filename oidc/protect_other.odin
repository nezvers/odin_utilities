#+build linux, darwin, freebsd, openbsd, netbsd
package oidc

// Not Windows: there is no protection of the stored sign in yet (the keychain of macOS, the Secret Service of Linux are the ways, they are not written and tested). A credential in a plain file is not
// acceptable, so nothing is stored here: `StoreWrite` is false, the person signs in again at every start. See TODO.md.

protectionAvailable :: proc() -> bool {
    return false
}

@(private)
protect :: proc(plain: []u8, entropy: string, out: []u8) -> (cipher: []u8, ok: bool) {
    return nil, false
}

@(private)
unprotect :: proc(cipher: []u8, entropy: string, out: []u8) -> (plain: []u8, ok: bool) {
    return nil, false
}
