#+build !windows
#+build !js
package p2p

// Linux and macOS read the PEM bundle of the system (tls_verify.odin), there is no store to enumerate here.
@(private)
TlsSystemStore :: proc(roots: ^TlsRoots) -> (added: int) {
    return 0
}
