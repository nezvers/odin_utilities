#+build windows
package p2p

import win "core:sys/windows"

foreign import p2p_crypt32 "system:crypt32.lib"

// What CryptoAPI needs to build a chain (wincrypt.h, 64 bit layout; the structures are only filled as far as they are used).
@(private = "file")
CertEnhKeyUsage :: struct {
    count: win.DWORD,
    identifiers: rawptr,
}

@(private = "file")
CertUsageMatch :: struct {
    type: win.DWORD,
    usage: CertEnhKeyUsage,
}

@(private = "file")
CertChainPara :: struct {
    size: win.DWORD,
    required_usage: CertUsageMatch,
    required_issuance_policy: CertUsageMatch,
    url_timeout_ms: win.DWORD,
    check_revocation_freshness: win.BOOL,
    revocation_freshness_seconds: win.DWORD,
    cache_resync: rawptr,
    strong_sign: rawptr,
    strong_sign_flags: win.DWORD,
}

@(private = "file")
CertTrustStatus :: struct {
    error_status: win.DWORD,
    info_status: win.DWORD,
}

@(private = "file")
CertChainElement :: struct {
    size: win.DWORD,
    certificate: ^win.CERT_CONTEXT,
    trust: CertTrustStatus,
    revocation_info: rawptr,
    issuance_usage: rawptr,
    application_usage: rawptr,
    extended_error: rawptr,
}

@(private = "file")
CertSimpleChain :: struct {
    size: win.DWORD,
    trust: CertTrustStatus,
    count: win.DWORD,
    elements: [^]^CertChainElement,
}

@(private = "file")
CertChainContext :: struct {
    size: win.DWORD,
    trust: CertTrustStatus,
    chain_count: win.DWORD,
    chains: [^]^CertSimpleChain,
}

CERT_TRUST_IS_SELF_SIGNED :: 0x8
CERT_STORE_PROV_MEMORY :: 2
CERT_STORE_ADD_USE_EXISTING :: 2
X509_ASN_ENCODING :: 1

@(default_calling_convention = "system")
foreign p2p_crypt32 {
    CertCreateCertificateContext :: proc(encoding: win.DWORD, encoded: [^]byte, size: win.DWORD) -> ^win.CERT_CONTEXT ---
    CertOpenStore :: proc(provider: rawptr, encoding: win.DWORD, crypt_provider: uintptr, flags: win.DWORD, parameter: rawptr) -> win.HCERTSTORE ---
    CertAddCertificateContextToStore :: proc(store: win.HCERTSTORE, certificate: ^win.CERT_CONTEXT, disposition: win.DWORD, stored: ^^win.CERT_CONTEXT) -> win.BOOL ---
    CertGetCertificateChain :: proc(engine: rawptr, certificate: ^win.CERT_CONTEXT, time: ^win.FILETIME, additional_store: win.HCERTSTORE, parameter: ^CertChainPara, flags: win.DWORD, reserved: rawptr, chain: ^^CertChainContext) -> win.BOOL ---
    CertFreeCertificateChain :: proc(chain: ^CertChainContext) ---
}

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

// The root that Windows ends this chain (leaf first, DER) at, when Windows trusts it: the roots that the store does not hold yet are
// fetched by CryptoAPI from Microsoft's trusted root program while it builds the chain (a missing intermediate too, from the address in
// the certificate). Revocation is not asked for. The caller checks the chain itself against this root, so Windows only answers "which
// authority, and do you trust it". `root` is allocated; it can take a few seconds when something has to be fetched.
@(private)
TlsSystemTrust :: proc(chain: [][]byte) -> (root: []byte, ok: bool) {
    if len(chain) == 0 {
        return
    }
    leaf: ^win.CERT_CONTEXT = CertCreateCertificateContext(X509_ASN_ENCODING, raw_data(chain[0]), win.DWORD(len(chain[0])))
    if leaf == nil {
        return
    }
    defer win.CertFreeCertificateContext(leaf)
    // the other certificates of the server go in a store of memory so that the chain can use them
    store: win.HCERTSTORE = CertOpenStore(rawptr(uintptr(CERT_STORE_PROV_MEMORY)), 0, 0, 0, nil)
    if store == nil {
        return
    }
    defer win.CertCloseStore(store, 0)
    for i in 1 ..< len(chain) {
        extra: ^win.CERT_CONTEXT = CertCreateCertificateContext(X509_ASN_ENCODING, raw_data(chain[i]), win.DWORD(len(chain[i])))
        if extra != nil {         // the extra certificate that DERP relays add is not one
            CertAddCertificateContextToStore(store, extra, CERT_STORE_ADD_USE_EXISTING, nil)
            win.CertFreeCertificateContext(extra)
        }
    }
    parameter: CertChainPara
    parameter.size = win.DWORD(size_of(CertChainPara))
    parameter.url_timeout_ms = 8000
    chain_context: ^CertChainContext
    if !CertGetCertificateChain(nil, leaf, nil, store, &parameter, 0, nil, &chain_context) || chain_context == nil {
        return
    }
    defer CertFreeCertificateChain(chain_context)
    // not a single problem Windows sees (untrusted root, a broken signature, a date, a partial chain), and the chain ends at a root
    if chain_context.trust.error_status != 0 || chain_context.chain_count == 0 {
        return
    }
    simple: ^CertSimpleChain = chain_context.chains[0]
    if simple.count == 0 {
        return
    }
    last: ^CertChainElement = simple.elements[simple.count - 1]
    if last.trust.info_status & CERT_TRUST_IS_SELF_SIGNED == 0 || last.certificate == nil {
        return
    }
    root = make([]byte, int(last.certificate.cbCertEncoded))
    copy(root, last.certificate.pbCertEncoded[:last.certificate.cbCertEncoded])
    return root, true
}
