#+build windows
package p2p

import win "core:sys/windows"

// The trusted root certificates of Windows (the "ROOT" store of the current user and machine, what the browsers of the system trust).
@(private)
TlsSystemStore :: proc(roots: ^TlsRoots) -> (added: int) {
    // "ROOT" holds the roots that were installed or already used; "AuthRoot" the ones Windows fetches on demand from its trusted program
    added += TlsSystemStoreNamed(roots, cstring16(raw_data([]u16{'R', 'O', 'O', 'T', 0})))
    added += TlsSystemStoreNamed(roots, cstring16(raw_data([]u16{'A', 'u', 't', 'h', 'R', 'o', 'o', 't', 0})))
    return
}

@(private)
TlsSystemStoreNamed :: proc(roots: ^TlsRoots, name: cstring16) -> (added: int) {
    store: win.HCERTSTORE = win.CertOpenSystemStoreW(nil, name)
    if store == nil {
        return
    }
    defer win.CertCloseStore(store, 0)
    context_pointer: ^win.CERT_CONTEXT
    for {
        context_pointer = win.CertEnumCertificatesInStore(store, context_pointer)
        if context_pointer == nil {
            break
        }
        der: []byte = make([]byte, int(context_pointer.cbCertEncoded))
        copy(der, context_pointer.pbCertEncoded[:context_pointer.cbCertEncoded])
        if TlsRootsAddDer(roots, der) {
            added += 1
        } else {
            delete(der)
        }
    }
    return
}
