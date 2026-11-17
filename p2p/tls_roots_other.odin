#+build !windows
#+build !js
package p2p

// Linux and macOS read the PEM bundle of the system (tls_verify.odin), there is no store to enumerate here.
@(private)
TlsSystemStore :: proc(roots: ^TlsRoots) -> (added: int) {
    return 0
}

// Only Windows keeps roots it fetches on demand: there is nobody to ask here.
@(private)
TlsSystemTrust :: proc(chain: [][]byte) -> (root: []byte, ok: bool) {
    return nil, false
}
