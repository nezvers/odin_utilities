#+build !js
// Certificate checking for the TLS client (tls13.odin): is the chain the server sent signed by an authority we trust, valid today,
// issued for the name we asked for, and does the server hold the key of its certificate (CertificateVerify)? All of it comes from
// core:crypto/x509 (chain, hostname, signatures: RSA PKCS#1 / PSS, ECDSA P-256 / P-384, Ed25519) and core:encoding/pem.
//
// Trust anchors, loaded once on the first connection:
//   1. two roots built in (ISRG Root X1 and X2, the authority of Let's Encrypt, which signs the certificates of the Tailscale relays and of a
//      relay run with derper): the relays work on a machine with no root store at all, and these two are enough for them;
//   2. the root store of the system: Windows (CryptoAPI "ROOT"), Linux and macOS (the usual PEM bundle files);
//   2b. an authority that is missing from all of these, but that the system vouches for: on Windows the chain is handed to CryptoAPI, which
//      fetches the root from Microsoft's program when it trusts it (the store only holds the roots that were used before), and the root
//      it ends at is used as one more anchor for this one check;
//   3. what the person adds: the file named by P2P_CA_FILE or SSL_CERT_FILE (PEM, may hold several certificates), for example the certificate
//      of a relay with a private authority or a self-signed certificate of a derper of your own.
// P2P_TLS_VERIFY=off switches the checking off (a relay with a certificate nobody can vouch for, or a clock that cannot be corrected).
//
// Not checked: revocation (no OCSP / CRL), as the x509 package says too. The clock of the computer matters: a certificate is valid between two
// dates, and a computer that thinks it is another year refuses every server.
package p2p

import "core:crypto/ecdsa"
import "core:crypto/ed25519"
import "core:crypto/hash"
import "core:crypto/rsa"
import "base:runtime"
import "core:crypto/x509"
import "core:encoding/pem"
import "core:fmt"
import "core:net"
import "core:os"

import "core:sync"
import "core:testing"
import "core:time"

ISRG_ROOT_X1 :: #load("trust/isrg_root_x1.pem")
ISRG_ROOT_X2 :: #load("trust/isrg_root_x2.pem")

TLS_CHAIN_MAX :: 8                       // certificates taken from the server's list (leaf first)
TLS_LEAF_MAX :: 4096                     // bytes of the leaf certificate, kept for the CertificateVerify check

TlsRoots :: struct {
    ders: [dynamic][]byte,
    certs: [dynamic]x509.Certificate,
    pointers: [dynamic]^x509.Certificate,
    built_in: int,
    from_files: int,
    from_system: int,
}

@(private)
tls_roots: TlsRoots
@(private)
tls_roots_once: sync.Once

// Is the checking on? (P2P_TLS_VERIFY=off turns it off)
TlsVerifyEnabled :: proc() -> bool {
    return os.get_env("P2P_TLS_VERIFY", context.temp_allocator) != "off"
}

// What the trust store holds: for diagnostics and tests.
TlsRootsSummary :: proc() -> (built_in: int, from_files: int, from_system: int) {
    TlsRootsEnsure()
    return tls_roots.built_in, tls_roots.from_files, tls_roots.from_system
}

@(private)
TlsRootsEnsure :: proc() {
    sync.once_do(&tls_roots_once, TlsRootsLoad)
}

@(private)
TlsRootsAddDer :: proc(roots: ^TlsRoots, der: []byte) -> bool {
    cert, error := x509.parse(der)
    if error != .None {
        return false
    }
    append(&roots.ders, der)
    append(&roots.certs, cert)
    return true
}

// Every CERTIFICATE block of a PEM text. The blocks stay allocated: the parsed certificates are views into them.
@(private)
TlsRootsAddPem :: proc(roots: ^TlsRoots, data: []byte) -> (added: int) {
    remaining: []byte = data
    for len(remaining) > 0 {
        block, rest, error := pem.decode(remaining)
        if error != nil || block == nil {
            break
        }
        remaining = rest
        if block.label == pem.LABEL_CERTIFICATE && TlsRootsAddDer(roots, block.data[:]) {
            added += 1
        }
    }
    return
}

@(private)
TlsRootsLoad :: proc() {
    context.allocator = runtime.heap_allocator()         // the store lives as long as the program: not for a tracking allocator to report
    roots: ^TlsRoots = &tls_roots
    roots.built_in += TlsRootsAddPem(roots, ISRG_ROOT_X1)
    roots.built_in += TlsRootsAddPem(roots, ISRG_ROOT_X2)

    for name in ([?]string{"P2P_CA_FILE", "SSL_CERT_FILE"}) {
        path: string = os.get_env(name, context.temp_allocator)
        if path != "" {
            if data, error := os.read_entire_file(path, context.allocator); error == nil {
                roots.from_files += TlsRootsAddPem(roots, data)
            }
        }
    }
    // the bundle of the system: the first of the usual places that exists (Linux distributions, macOS)
    for path in ([?]string{"/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/cert.pem", "/etc/ssl/ca-bundle.pem"}) {
        if data, error := os.read_entire_file(path, context.allocator); error == nil {
            roots.from_system += TlsRootsAddPem(roots, data)
            break
        }
    }
    roots.from_system += TlsSystemStore(roots)
    // pointers last: the array does not move any more
    for i in 0 ..< len(roots.certs) {
        append(&roots.pointers, &roots.certs[i])
    }
}

// Is `host` an address and not a name? A certificate is checked against names.
@(private)
TlsHostIsAddress :: proc(host: string) -> bool {
    return net.parse_address(host) != nil
}

// Is this chain (leaf first, DER) good for `host`? On failure `why` says what is wrong in words (allocated: it outlives the call).
// `now` is the date to check the validity at (zero = the clock of this computer; a test pins it).
TlsVerifyChain :: proc(chain: [][]byte, host: string, now: time.Time = {}) -> (why: string, ok: bool) {
    TlsRootsEnsure()
    if len(chain) == 0 {
        return "the server sent no certificate", false
    }
    if TlsHostIsAddress(host) {
        return fmt.aprintf("certificate checking needs a name, not the address %s (P2P_TLS_VERIFY=off to skip it)", host), false
    }
    count: int = min(len(chain), TLS_CHAIN_MAX)
    certs: [TLS_CHAIN_MAX]x509.Certificate
    parsed: int
    defer for i in 0 ..< parsed {
        x509.destroy(&certs[i])
    }
    // the leaf has to parse; of the rest (DERP relays send an extra certificate of their own in the list) the ones that do not are left out
    leaf_error: x509.Error
    certs[0], leaf_error = x509.parse(chain[0])
    if leaf_error != .None {
        return fmt.aprintf("the certificate of the server is malformed (%v)", leaf_error), false
    }
    parsed = 1
    intermediates: [TLS_CHAIN_MAX]^x509.Certificate
    usable: int
    for i in 1 ..< count {
        error: x509.Error
        certs[parsed], error = x509.parse(chain[i])
        if error == .None {
            intermediates[usable] = &certs[parsed]
            usable += 1
            parsed += 1
        }
    }
    options: x509.Verify_Options = {
        roots = tls_roots.pointers[:],
        intermediates = intermediates[:usable],
        current_time = time.now() if now == {} else now,
        dns_name = host,
        required_eku = .Server_Auth,
    }
    verified, error := x509.verify_chain(&certs[0], options)
    if error == .Unknown_Authority {
        // the roots we loaded do not reach this chain: the system may know the authority without having it in the store yet (Windows fetches
        // the roots it trusts on demand). It only names the root; the chain, the name and the dates are checked here all the same.
        if root_der, found := TlsSystemTrust(chain[:count]); found {
            defer delete(root_der)
            if root, root_error := x509.parse(root_der); root_error == .None {
                defer x509.destroy(&root)
                extended: []^x509.Certificate = make([]^x509.Certificate, len(tls_roots.pointers) + 1)
                defer delete(extended)
                copy(extended, tls_roots.pointers[:])
                extended[len(extended) - 1] = &root
                options.roots = extended
                verified, error = x509.verify_chain(&certs[0], options)
            }
        }
    }
    if error != .None {
        text: string
        #partial switch error {
        case .Hostname_Mismatch, .No_SAN:
            text = fmt.aprintf("the certificate is not for %s", host)
        case .Expired, .Not_Yet_Valid:
            text = fmt.aprintf("a certificate is %s: check the date and time of this computer", "expired" if error == .Expired else "not valid yet")
        case .Unknown_Authority:
            text = fmt.aprintf("the certificate is not signed by an authority this computer trusts (P2P_CA_FILE adds one, P2P_TLS_VERIFY=off skips the check)")
        case:
            text = fmt.aprintf("the certificate was refused (%v)", error)
        }
        return text, false
    }
    delete(verified)
    return "", true
}

CERTIFICATE_VERIFY_CONTEXT :: "TLS 1.3, server CertificateVerify"

// The signature of the server's CertificateVerify message (RFC 8446 4.4.3): it proves that the server holds the private key of the
// certificate it sent, over the transcript of the handshake so far.
TlsVerifyCertificateSignature :: proc(leaf_der: []byte, scheme: u16, signature: []byte, transcript_hash: []byte) -> (why: string, ok: bool) {
    cert, error := x509.parse(leaf_der)
    if error != .None {
        return "the certificate of the server is malformed", false
    }
    defer x509.destroy(&cert)
    content: [64 + len(CERTIFICATE_VERIFY_CONTEXT) + 1 + 64]byte
    length: int
    for _ in 0 ..< 64 {
        content[length] = 0x20
        length += 1
    }
    length += copy(content[length:], CERTIFICATE_VERIFY_CONTEXT)
    content[length] = 0
    length += 1
    length += copy(content[length:], transcript_hash)
    message: []byte = content[:length]

    verified: bool
    switch scheme {
    case 0x0403, 0x0503:                                   // ecdsa_secp256r1_sha256, ecdsa_secp384r1_sha384
        curve: ecdsa.Curve = .SECP256R1 if scheme == 0x0403 else .SECP384R1
        wanted: x509.Public_Key_Algorithm = .ECDSA_P256 if scheme == 0x0403 else .ECDSA_P384
        if cert.public_key_algorithm != wanted {
            return "the signature does not fit the key of the certificate", false
        }
        public: ecdsa.Public_Key
        verified = ecdsa.public_key_set_bytes(&public, curve, cert.ec_point) && ecdsa.verify_asn1(&public, .SHA256 if scheme == 0x0403 else .SHA384, message, signature)
    case 0x0804, 0x0805, 0x0806:                           // rsa_pss_rsae_sha256 / 384 / 512
        if cert.public_key_algorithm != .RSA {
            return "the signature does not fit the key of the certificate", false
        }
        algorithm: hash.Algorithm = .SHA256
        salt: int = 32
        if scheme == 0x0805 {
            algorithm, salt = .SHA384, 48
        } else if scheme == 0x0806 {
            algorithm, salt = .SHA512, 64
        }
        public: rsa.Public_Key
        verified = rsa.public_key_set_bytes(&public, cert.rsa_n, cert.rsa_e) && rsa.verify_pss(&public, algorithm, salt, message, signature, mgf1_algo = algorithm)
    case 0x0807:                                           // ed25519
        if cert.public_key_algorithm != .Ed25519 {
            return "the signature does not fit the key of the certificate", false
        }
        public: ed25519.Public_Key
        verified = ed25519.public_key_set_bytes(&public, cert.ec_point) && ed25519.verify(&public, message, signature)
    case:
        return fmt.aprintf("the server signs with a scheme this client does not know (0x%04x)", scheme), false
    }
    if !verified {
        return "the server did not prove that it holds the key of its certificate", false
    }
    return "", true
}

// A chain the relay derp8e.tailscale.com really sent (captured 2026-11-17, with the extra certificate that DERP relays add), checked with
// the date pinned inside its validity: accepted for its name, refused for another name, after it expired, damaged, and without its
// intermediates.
TEST_CHAIN :: #load("trust/test_chain_derp8e.pem")

@(test)
TlsVerifyChainTest :: proc(t: ^testing.T) {
    context.allocator = runtime.heap_allocator()         // the certificates parsed from the fixture stay allocated to the end
    built_in, _, _ := TlsRootsSummary()
    testing.expect_value(t, built_in, 2)

    chain: TlsRoots
    testing.expect_value(t, TlsRootsAddPem(&chain, TEST_CHAIN), 5)
    ders: [dynamic][]byte
    defer delete(ders)
    for der in chain.ders {
        append(&ders, der)
    }
    pinned: time.Time = time.unix(1_795_000_000, 0)           // 2026-11-18, inside the validity of the leaf
    why, ok := TlsVerifyChain(ders[:], "derp8e.tailscale.com", pinned)
    testing.expect(t, ok, why)

    why, ok = TlsVerifyChain(ders[:], "derp1.tailscale.com", pinned)
    testing.expect(t, !ok && strings_contain(why, "not for"))
    delete(why)

    late: time.Time = time.unix(2_000_000_000, 0)             // 2033
    why, ok = TlsVerifyChain(ders[:], "derp8e.tailscale.com", late)
    testing.expect(t, !ok && strings_contain(why, "date"))
    delete(why)
    early: time.Time = time.unix(1_600_000_000, 0)            // 2020
    why, ok = TlsVerifyChain(ders[:], "derp8e.tailscale.com", early)
    testing.expect(t, !ok)
    delete(why)

    // one byte of the leaf changed: it no longer verifies
    damaged: []byte = make([]byte, len(ders[0]))
    defer delete(damaged)
    copy(damaged, ders[0])
    damaged[len(damaged) / 2] ~= 1
    broken: [dynamic][]byte
    defer delete(broken)
    append(&broken, damaged)
    for i in 1 ..< len(ders) {
        append(&broken, ders[i])
    }
    why, ok = TlsVerifyChain(broken[:], "derp8e.tailscale.com", pinned)
    testing.expect(t, !ok)
    delete(why)

    // a leaf alone cannot reach a root
    why, ok = TlsVerifyChain(ders[:1], "derp8e.tailscale.com", pinned)
    testing.expect(t, !ok && strings_contain(why, "authority"))
    delete(why)

    // an address is not a name
    why, ok = TlsVerifyChain(ders[:], "192.0.2.1", pinned)
    testing.expect(t, !ok)
    delete(why)
}

@(private)
strings_contain :: proc(text: string, part: string) -> bool {
    for i in 0 ..= len(text) - len(part) {
        if text[i:i + len(part)] == part {
            return true
        }
    }
    return false
}

// A site whose authority Windows does not keep in its store until it has used it (example.com, only when asked for: P2P_LIVE=1). Windows
// names the root, the rest is checked here. Elsewhere there is no such help, so a refusal is not a failure.
@(test)
TlsSystemTrustLiveTest :: proc(t: ^testing.T) {
    if os.get_env("P2P_LIVE", context.temp_allocator) == "" {
        return
    }
    socket, dial_error, dial_ok := TcpDial("example.com", 443)
    testing.expect(t, dial_ok, dial_error)
    if !dial_ok {
        delete(dial_error)
        return
    }
    tls: Tls
    connected: bool = TlsConnect(&tls, socket, "example.com")
    when ODIN_OS == .Windows {
        testing.expect(t, connected, tls.failure)
    }
    if connected {
        TlsClose(&tls)
    } else {
        net.close(socket)
    }
}
