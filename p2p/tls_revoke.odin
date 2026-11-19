#+build !js
// Revocation of the certificates of a server (tls_verify.odin asks after the chain itself is good): has the authority withdrawn a certificate
// of the chain before its end date? Done with CRLs, because that is what the relays have: Let's Encrypt switched its OCSP service off in 2025
// and publishes lists. The certificate names the lists it is on ("CRL distribution points", an http:// address); the list is fetched, its
// signature is checked against the certificate of the authority that issued the certificate, its dates are checked, and the serial number of
// the certificate is looked for in it.
//
// Which certificates: the server's certificate and every intermediate above it (not the root we trust: nobody revokes that for us, the store
// is updated instead). A certificate that lives at most 10 days is not checked (it expires sooner than a list would be published, the rule
// of the browsers). A list is fetched once and kept in memory until it expires (a list of an intermediate stays for months, the one for a
// leaf is about 100 KB for Let's Encrypt), and on disk between runs (see CrlDiskPath: nothing on the disk is trusted, a list that is read
// back is verified like a fresh one); a list that could not be fetched is not asked again for ten minutes.
//
// P2P_TLS_REVOCATION: "soft" (the default: a revoked certificate is refused, a list that cannot be had or read is let through, as the browsers
// do for the same reason: a down CDN must not take the relays down), "strict" (no answer = refused), "off". P2P_TLS_VERIFY=off switches
// all checking off. Only http:// lists, through the proxy of the environment if there is one (many proxies refuse port 80: soft then lets it
// pass). Not covered: OCSP (stapled or fetched), delta lists, the scope of an Issuing Distribution Point (the list is the one the certificate
// names itself), CRLite.
package p2p

import "base:runtime"
import "core:crypto/sha2"
import "core:crypto/x509"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

TlsRevocationMode :: enum {
    OFF,
    SOFT,
    STRICT,
}

CRL_SIZE_MAX :: 16 * 1024 * 1024
CRL_FETCH_MS :: 5000                              // for one list: connect, answer
CRL_RETRY_AFTER :: 10 * time.Minute
CRL_SHORT_LIVED :: 10 * 24 * time.Hour

CrlStatus :: enum {
    UNKNOWN,                                      // no list, or one that cannot be trusted
    GOOD,
    REVOKED,
}

CrlEntry :: struct {
    url: string,
    der: []byte,                                  // verified, kept until the end of the program
    next_update: time.Time,
    retry_after: time.Time,
}

@(private)
crl_cache: [dynamic]CrlEntry
@(private)
crl_mutex: sync.Mutex

// A hook for the tests: where a list comes from instead of the network.
@(private)
crl_fetch_hook: proc(url: string) -> []byte

TlsRevocationModeGet :: proc() -> TlsRevocationMode {
    switch os.get_env("P2P_TLS_REVOCATION", context.temp_allocator) {
    case "off":
        return .OFF
    case "strict":
        return .STRICT
    }
    return .SOFT
}

// ---------------------------------------------------------------------------------------------------------------- DER

// One element: tag (single byte tags only), its content, the whole element (header included), what follows it.
@(private)
DerRead :: proc(data: []byte) -> (tag: u8, content: []byte, raw: []byte, rest: []byte, ok: bool) {
    if len(data) < 2 || data[0] & 0x1f == 0x1f {
        return
    }
    tag = data[0]
    length: int = int(data[1])
    header: int = 2
    if length & 0x80 != 0 {
        count: int = length & 0x7f
        if count == 0 || count > 4 || len(data) < 2 + count {
            return
        }
        length = 0
        for i in 0 ..< count {
            length = length << 8 | int(data[2 + i])
        }
        header = 2 + count
    }
    if length < 0 || len(data) - header < length {
        return
    }
    return tag, data[header:header + length], data[:header + length], data[header + length:], true
}

@(private)
DerTime :: proc(tag: u8, content: []byte) -> (result: time.Time, ok: bool) {
    // UTCTime YYMMDDHHMMSSZ (tag 0x17), GeneralizedTime YYYYMMDDHHMMSSZ (0x18)
    digits: int = 12 if tag == 0x17 else 14
    if (tag != 0x17 && tag != 0x18) || len(content) != digits + 1 || content[digits] != 'Z' {
        return
    }
    value :: proc(text: []byte) -> (number: int, ok: bool) {
        for c in text {
            if c < '0' || c > '9' {
                return 0, false
            }
            number = number * 10 + int(c - '0')
        }
        return number, true
    }
    year, month, day, hour, minute, second: int
    at: int
    if tag == 0x17 {
        short, short_ok := value(content[0:2])
        year = 1900 + short if short >= 50 else 2000 + short
        ok = short_ok
        at = 2
    } else {
        year, ok = value(content[0:4])
        at = 4
    }
    parts: [5]int
    for i in 0 ..< 5 {
        part, part_ok := value(content[at + 2 * i:at + 2 * i + 2])
        parts[i] = part
        ok &&= part_ok
    }
    month, day, hour, minute, second = parts[0], parts[1], parts[2], parts[3], parts[4]
    if !ok {
        return
    }
    return time.datetime_to_time(year, month, day, hour, minute, second)
}

// ---------------------------------------------------------------------------------------------------------------- CRL

Crl :: struct {
    tbs: []byte,                                  // the signed part, header included
    issuer: []byte,                               // the issuer name, header included
    algorithm: x509.Signature_Algorithm,
    signature: []byte,
    this_update: time.Time,
    next_update: time.Time,
    revoked: []byte,                              // the content of the list of revoked certificates (empty = none)
}

// CertificateList := SEQUENCE { tbsCertList, signatureAlgorithm, signatureValue BIT STRING }. Views into `der`.
CrlParse :: proc(der: []byte) -> (crl: Crl, ok: bool) {
    tag, outer, _, trailing, outer_ok := DerRead(der)
    if !outer_ok || tag != 0x30 || len(trailing) != 0 {
        return
    }
    tbs_tag, tbs_content, tbs_raw, after_tbs, tbs_ok := DerRead(outer)
    if !tbs_ok || tbs_tag != 0x30 {
        return
    }
    algorithm_tag, algorithm_content, _, after_algorithm, algorithm_ok := DerRead(after_tbs)
    signature_tag, signature_content, _, after_signature, signature_ok := DerRead(after_algorithm)
    if !algorithm_ok || algorithm_tag != 0x30 || !signature_ok || signature_tag != 0x03 || len(after_signature) != 0 || len(signature_content) < 2 || signature_content[0] != 0 {
        return
    }
    crl.tbs = tbs_raw
    crl.signature = signature_content[1:]
    oid_tag, oid, _, _, oid_ok := DerRead(algorithm_content)
    if !oid_ok || oid_tag != 0x06 {
        return
    }
    switch string(oid) {
    case "\x2a\x86\x48\xce\x3d\x04\x03\x02":
        crl.algorithm = .ECDSA_SHA256
    case "\x2a\x86\x48\xce\x3d\x04\x03\x03":
        crl.algorithm = .ECDSA_SHA384
    case "\x2a\x86\x48\xce\x3d\x04\x03\x04":
        crl.algorithm = .ECDSA_SHA512
    case "\x2a\x86\x48\x86\xf7\x0d\x01\x01\x0b":
        crl.algorithm = .RSA_SHA256
    case "\x2a\x86\x48\x86\xf7\x0d\x01\x01\x0c":
        crl.algorithm = .RSA_SHA384
    case "\x2a\x86\x48\x86\xf7\x0d\x01\x01\x0d":
        crl.algorithm = .RSA_SHA512
    case "\x2b\x65\x70":
        crl.algorithm = .Ed25519
    case:
        return                                    // RSA-PSS and the rest: no answer (soft) rather than a guess
    }
    // tbsCertList: [version] signature issuer thisUpdate [nextUpdate] [revokedCertificates] [extensions]
    rest: []byte = tbs_content
    element_tag: u8
    content: []byte
    raw: []byte
    element_ok: bool
    element_tag, content, raw, rest, element_ok = DerRead(rest)
    if element_ok && element_tag == 0x02 {
        element_tag, content, raw, rest, element_ok = DerRead(rest)             // the version (v2 = 1) was there: on to the signature
    }
    if !element_ok || element_tag != 0x30 {
        return
    }
    element_tag, content, raw, rest, element_ok = DerRead(rest)                 // the issuer
    if !element_ok || element_tag != 0x30 {
        return
    }
    crl.issuer = raw
    element_tag, content, raw, rest, element_ok = DerRead(rest)
    if !element_ok {
        return
    }
    time_ok: bool
    crl.this_update, time_ok = DerTime(element_tag, content)
    if !time_ok {
        return
    }
    element_tag, content, raw, rest, element_ok = DerRead(rest)
    if !element_ok || (element_tag != 0x17 && element_tag != 0x18) {
        return                                    // without a next update nobody can say how long the list is good
    }
    crl.next_update, time_ok = DerTime(element_tag, content)
    if !time_ok {
        return
    }
    element_tag, content, raw, rest, element_ok = DerRead(rest)
    if element_ok && element_tag == 0x30 {
        crl.revoked = content
    }
    return crl, true
}

// Is the serial number (the content of the DER integer) one of the revoked ones?
CrlHas :: proc(crl: ^Crl, serial: []byte) -> bool {
    rest: []byte = crl.revoked
    for len(rest) > 0 {
        entry_tag, entry, _, after, entry_ok := DerRead(rest)
        if !entry_ok || entry_tag != 0x30 {
            return false
        }
        number_tag, number, _, _, number_ok := DerRead(entry)
        if number_ok && number_tag == 0x02 && string(number) == string(serial) {
            return true
        }
        rest = after
    }
    return false
}

// Is this list really the one of `issuer`, signed by it, and good at `now`? (the signature is the x509 package's)
CrlVerify :: proc(crl: ^Crl, issuer: ^x509.Certificate, now: time.Time) -> bool {
    if string(crl.issuer) != string(issuer.raw_subject) {
        return false
    }
    if issuer.has_key_usage && .CRL_Sign not_in issuer.key_usage {
        return false
    }
    if time.diff(crl.this_update, now) < -time.Hour || time.diff(now, crl.next_update) < 0 {
        return false                              // from the future (an hour of clock slack), or past its next update
    }
    stand_in: x509.Certificate = {
        raw_tbs = crl.tbs,
        signature = crl.signature,
        signature_algorithm = crl.algorithm,
    }
    return x509.verify_signature(&stand_in, issuer) == .None
}

// ---------------------------------------------------------------------------------------------------------------- disk cache

// Where the lists are kept between runs: P2P_CACHE_DIR/crl if set ("off" = nowhere), else %LOCALAPPDATA%\p2p\crl on Windows,
// $XDG_CACHE_HOME/p2p/crl or ~/.cache/p2p/crl elsewhere. One file per list, named by the sha256 of its address. "" = no cache.
CrlDiskPath :: proc(url: string, allocator := context.temp_allocator) -> string {
    base: string = os.get_env("P2P_CACHE_DIR", context.temp_allocator)
    if base == "off" {
        return ""
    }
    if base == "" {
        when ODIN_OS == .Windows {
            base = os.get_env("LOCALAPPDATA", context.temp_allocator)
            if base != "" {
                base = fmt.tprintf("%s/p2p", base)
            }
        } else {
            base = os.get_env("XDG_CACHE_HOME", context.temp_allocator)
            if base == "" {
                if home := os.get_env("HOME", context.temp_allocator); home != "" {
                    base = fmt.tprintf("%s/.cache", home)
                }
            }
            if base != "" {
                base = fmt.tprintf("%s/p2p", base)
            }
        }
    }
    if base == "" {
        return ""
    }
    digest: [32]byte
    context_256: sha2.Context_256
    sha2.init_256(&context_256)
    sha2.update(&context_256, transmute([]byte)url)
    sha2.final(&context_256, digest[:])
    hex: [64]byte
    digits: string = "0123456789abcdef"
    for b, i in digest {
        hex[2 * i] = digits[b >> 4]
        hex[2 * i + 1] = digits[b & 15]
    }
    return fmt.aprintf("%s/crl/%s.crl", strings.trim_right(base, "/\\"), string(hex[:]), allocator = allocator)
}

// The list kept for `url` when it is good: the right issuer, a good signature, not past its next update. Heap allocated. Whatever is on
// the disk could have been put there by anybody: it is checked exactly like a fetched list.
@(private)
CrlDiskLoad :: proc(url: string, issuer: ^x509.Certificate, now: time.Time) -> (der: []byte, ok: bool) {
    path: string = CrlDiskPath(url)
    if path == "" {
        return
    }
    data, read_error := os.read_entire_file(path, runtime.heap_allocator())
    if read_error != nil {
        return
    }
    crl, parsed := CrlParse(data)
    if !parsed || !CrlVerify(&crl, issuer, now) {
        delete(data, runtime.heap_allocator())
        return
    }
    return data, true
}

// Writes a list that was verified (to a file of its own first, then renamed: a program that stops in the middle leaves no half list).
@(private)
CrlDiskStore :: proc(url: string, der: []byte) {
    path: string = CrlDiskPath(url)
    if path == "" {
        return
    }
    if slash := strings.last_index_byte(path, '/'); slash > 0 {
        os.make_directory_all(path[:slash])
    }
    temporary: string = fmt.tprintf("%s.%d.tmp", path, os.get_pid())
    if os.write_entire_file(temporary, der) != nil {
        return
    }
    if os.rename(temporary, path) != nil {
        os.remove(temporary)
    }
}

// ---------------------------------------------------------------------------------------------------------------- fetch

// The http:// addresses of the lists a certificate is on (CRLDistributionPoints, 2.5.29.31). Views into the certificate.
CrlUrls :: proc(cert: ^x509.Certificate, urls: []string) -> (count: int) {
    for extension in cert.extensions {
        if string(extension.oid) != "\x55\x1d\x1f" {
            continue
        }
        // SEQUENCE OF DistributionPoint { [0] DistributionPointName { [0] GeneralNames { [6] uri } } ... }
        _, points, _, _, points_ok := DerRead(extension.value)
        for points_ok && len(points) > 0 {
            point_tag, point, _, after_point, ok := DerRead(points)
            if !ok {
                break
            }
            points = after_point
            if point_tag != 0x30 {
                continue
            }
            name_tag, name, _, _, name_ok := DerRead(point)
            if !name_ok || name_tag != 0xa0 {
                continue
            }
            full_tag, names, _, _, full_ok := DerRead(name)
            if !full_ok || full_tag != 0xa0 {
                continue
            }
            for len(names) > 0 {
                general_tag, general, _, after_general, general_ok := DerRead(names)
                if !general_ok {
                    break
                }
                names = after_general
                if general_tag == 0x86 && strings.has_prefix(string(general), "http://") && count < len(urls) {
                    urls[count] = string(general)
                    count += 1
                }
            }
        }
    }
    return
}

// GET of a plain http:// address (through the proxy of the environment, as everything here): the body, Content-Length or chunked or until the
// connection ends. Allocated.
CrlFetch :: proc(url: string) -> (body: []byte, ok: bool) {
    if crl_fetch_hook != nil {
        body = crl_fetch_hook(url)
        return body, body != nil
    }
    rest: string = url[len("http://"):]
    path: string = "/"
    if slash := strings.index_byte(rest, '/'); slash >= 0 {
        path = rest[slash:]
        rest = rest[:slash]
    }
    host: string = rest
    port: int = 80
    if colon := strings.last_index_byte(rest, ':'); colon >= 0 {
        number, number_ok := strconv.parse_int(rest[colon + 1:])
        if !number_ok {
            return
        }
        host, port = rest[:colon], number
    }
    socket, dial_error, dial_ok := TcpDial(host, port)
    if !dial_ok {
        delete(dial_error)
        return
    }
    defer net.close(socket)
    net.set_option(socket, .Receive_Timeout, time.Millisecond * CRL_FETCH_MS)
    net.set_option(socket, .Send_Timeout, time.Millisecond * CRL_FETCH_MS)
    request: string = fmt.tprintf("GET %s HTTP/1.1\r\nHost: %s\r\nAccept: application/pkix-crl\r\nConnection: close\r\n\r\n", path, host)
    if _, send_error := net.send_tcp(socket, transmute([]byte)request); send_error != nil {
        return
    }
    received: [dynamic]byte
    defer delete(received)
    chunk: [16384]byte
    deadline: time.Tick = time.tick_now()
    end: int = -1
    for {
        if time.tick_since(deadline) > time.Millisecond * CRL_FETCH_MS * 3 || len(received) > CRL_SIZE_MAX {
            return
        }
        count, receive_error := net.recv_tcp(socket, chunk[:])
        if receive_error != nil || count <= 0 {
            break
        }
        append(&received, ..chunk[:count])
        if end < 0 {
            end = strings.index(string(received[:]), "\r\n\r\n")
        }
        if end >= 0 {
            // everything is here when the length that was promised has arrived
            lengths: [1]string
            if ProxyHeaders(string(received[:end]), "content-length", lengths[:]) == 1 {
                if wanted, wanted_ok := strconv.parse_int(lengths[0]); wanted_ok && len(received) >= end + 4 + wanted {
                    break
                }
            }
        }
    }
    if end < 0 || DerpHttpStatus(received[:end + 4]) != 200 {
        return
    }
    head: string = string(received[:end])
    payload: []byte = received[end + 4:]
    encodings: [1]string
    if ProxyHeaders(head, "transfer-encoding", encodings[:]) == 1 && strings.contains(strings.to_lower(encodings[0], context.temp_allocator), "chunked") {
        decoded: [dynamic]byte
        decoded.allocator = runtime.heap_allocator()
        for len(payload) > 0 {
            line_end: int = strings.index(string(payload), "\r\n")
            if line_end < 0 {
                delete(decoded)
                return
            }
            size, size_ok := strconv.parse_int(string(payload[:line_end]), 16)
            if !size_ok || size < 0 || line_end + 2 + size > len(payload) {
                delete(decoded)
                return
            }
            if size == 0 {
                return decoded[:], true
            }
            append(&decoded, ..payload[line_end + 2:line_end + 2 + size])
            payload = payload[min(line_end + 2 + size + 2, len(payload)):]
        }
        delete(decoded)
        return
    }
    lengths: [1]string
    if ProxyHeaders(head, "content-length", lengths[:]) == 1 {
        if wanted, wanted_ok := strconv.parse_int(lengths[0]); wanted_ok {
            if wanted > len(payload) {
                return
            }
            payload = payload[:wanted]
        }
    }
    body = make([]byte, len(payload), runtime.heap_allocator())
    copy(body, payload)
    return body, len(body) > 0
}

// ---------------------------------------------------------------------------------------------------------------- the check

// The status of `cert` on the list at `url` (cached), `issuer` being the authority that issued it.
CrlStatusOf :: proc(url: string, cert: ^x509.Certificate, issuer: ^x509.Certificate, now: time.Time) -> CrlStatus {
    der: []byte
    sync.mutex_lock(&crl_mutex)
    for entry in crl_cache {
        if entry.url == url {
            if entry.der != nil && time.diff(now, entry.next_update) > 0 {
                der = entry.der
            } else if entry.der == nil && time.diff(now, entry.retry_after) > 0 {
                sync.mutex_unlock(&crl_mutex)
                return .UNKNOWN                   // asked a moment ago and got nothing: not again now
            }
            break
        }
    }
    sync.mutex_unlock(&crl_mutex)

    crl: Crl
    parsed: bool
    if der != nil {
        crl, parsed = CrlParse(der)
    } else {
        fetched, fetch_ok := CrlDiskLoad(url, issuer, now)
        from_disk: bool = fetch_ok
        if !fetch_ok {
            fetched, fetch_ok = CrlFetch(url)
        }
        if fetch_ok {
            crl, parsed = CrlParse(fetched)
            if parsed && !CrlVerify(&crl, issuer, now) {
                parsed = false
            }
            if parsed {
                der = fetched
                if !from_disk {
                    CrlDiskStore(url, fetched)
                }
            } else {
                delete(fetched, runtime.heap_allocator())
            }
        }
        // remember the answer (or that there was none) for everybody
        context.allocator = runtime.heap_allocator()
        sync.mutex_lock(&crl_mutex)
        replaced: bool
        for &entry in crl_cache {
            if entry.url == url {
                entry.der = der
                entry.next_update = crl.next_update
                entry.retry_after = time.time_add(now, CRL_RETRY_AFTER)
                replaced = true
            }
        }
        if !replaced {
            append(&crl_cache, CrlEntry{url = strings.clone(url), der = der, next_update = crl.next_update, retry_after = time.time_add(now, CRL_RETRY_AFTER)})
        }
        sync.mutex_unlock(&crl_mutex)
    }
    if !parsed {
        return .UNKNOWN
    }
    return .REVOKED if CrlHas(&crl, cert.serial) else .GOOD
}

// Revocation of the certificates of a verified chain (leaf first, the last one is the trust anchor and is not asked about).
// `why` says what is wrong when `ok` is false.
TlsRevocationCheck :: proc(chain: []^x509.Certificate, now: time.Time, mode: TlsRevocationMode) -> (why: string, ok: bool) {
    if mode == .OFF {
        return "", true
    }
    for i in 0 ..< len(chain) - 1 {
        cert, issuer: ^x509.Certificate = chain[i], chain[i + 1]
        if time.diff(cert.not_before, cert.not_after) <= CRL_SHORT_LIVED {
            continue
        }
        urls: [4]string
        count: int = CrlUrls(cert, urls[:])
        status: CrlStatus = .UNKNOWN
        for url in urls[:count] {
            status = CrlStatusOf(url, cert, issuer, now)
            if status != .UNKNOWN {
                break
            }
        }
        name: string = "the certificate of the server" if i == 0 else "a certificate above it"
        if status == .REVOKED {
            return fmt.aprintf("%s was revoked by its authority (listed in %s; P2P_TLS_REVOCATION=off skips the check)", name, urls[0]), false
        }
        if status == .UNKNOWN && count > 0 && mode == .STRICT {
            return fmt.aprintf("cannot tell whether %s was revoked: the list %s could not be had or is not good (P2P_TLS_REVOCATION=soft lets it pass)", name, urls[0]), false
        }
    }
    return "", true
}

// ---------------------------------------------------------------------------------------------------------------- tests

REVOKE_TEST_CHAIN :: #load("trust/revoke_test_chain.pem")
REVOKE_TEST_CRL :: #load("trust/revoke_test.crl")
@(private)
revoke_crl_bytes: []byte = REVOKE_TEST_CRL
ISRG_X2_REAL_CRL :: #load("trust/isrg_x2_real.crl")

@(private)
revoke_test_serves: int

// The hook, the cache and the counter are global and the test runner is multi threaded: every test that fetches a list takes this lock.
// Without it CrlFetchTest got the list of the hook instead of asking its own server, whose thread then waited in accept forever.
@(private)
crl_test_lock: sync.Mutex

@(private)
RevokeTestServe :: proc(url: string) -> []byte {
    revoke_test_serves += 1
    copy_of: []byte = make([]byte, len(REVOKE_TEST_CRL), runtime.heap_allocator())
    copy(copy_of, REVOKE_TEST_CRL)
    return copy_of
}

// A list made with openssl for a small authority of our own (a good certificate and a revoked one), and the real list of ISRG Root X2.
@(test)
TlsRevocationTest :: proc(t: ^testing.T) {
    sync.mutex_guard(&crl_test_lock)
    context.allocator = runtime.heap_allocator()
    pinned: time.Time = time.unix(1_795_000_000, 0)                   // 2026-11-18
    os.set_env("P2P_CACHE_DIR", "off")
    defer os.unset_env("P2P_CACHE_DIR")

    authority_chain: TlsRoots
    testing.expect_value(t, TlsRootsAddPem(&authority_chain, REVOKE_TEST_CHAIN), 3)
    good, revoked, authority: x509.Certificate = authority_chain.certs[0], authority_chain.certs[1], authority_chain.certs[2]

    // the list: parsed, signed by the authority, lists the second certificate only
    crl, parsed := CrlParse(REVOKE_TEST_CRL)
    testing.expect(t, parsed)
    testing.expect(t, CrlVerify(&crl, &authority, pinned))
    testing.expect(t, !CrlHas(&crl, good.serial))
    testing.expect(t, CrlHas(&crl, revoked.serial))
    testing.expect(t, !CrlVerify(&crl, &good, pinned))                                       // not its issuer
    testing.expect(t, !CrlVerify(&crl, &authority, time.unix(2_700_000_000, 0)))             // 2055: past its next update
    testing.expect(t, !CrlVerify(&crl, &authority, time.unix(1_600_000_000, 0)))             // 2020: before it was made
    damaged: []byte = make([]byte, len(REVOKE_TEST_CRL))
    defer delete(damaged)
    copy(damaged, REVOKE_TEST_CRL)
    damaged[len(damaged) - 10] ~= 1                                                          // a byte of the signature
    broken, broken_parsed := CrlParse(damaged)
    testing.expect(t, broken_parsed && !CrlVerify(&broken, &authority, pinned))
    damaged[len(damaged) - 10] ~= 1
    damaged[60] ~= 1                                                                         // a byte of the signed part
    changed, changed_parsed := CrlParse(damaged)
    testing.expect(t, !changed_parsed || !CrlVerify(&changed, &authority, pinned))
    _, truncated_parsed := CrlParse(revoke_crl_bytes[:len(REVOKE_TEST_CRL) - 7])
    testing.expect(t, !truncated_parsed)

    // where the certificates say their list is
    urls: [4]string
    testing.expect_value(t, CrlUrls(&good, urls[:]), 1)
    testing.expect_value(t, urls[0], "http://crl.test.invalid/ca.crl")

    // the whole check through the cache, the list coming from the hook instead of the network
    crl_fetch_hook = RevokeTestServe
    defer {
        crl_fetch_hook = nil
    }
    good_chain: []^x509.Certificate = {&good, &authority}
    revoked_chain: []^x509.Certificate = {&revoked, &authority}
    why, ok := TlsRevocationCheck(good_chain, pinned, .STRICT)
    testing.expect(t, ok, why)
    testing.expect_value(t, revoke_test_serves, 1)
    why, ok = TlsRevocationCheck(revoked_chain, pinned, .SOFT)
    testing.expect(t, !ok && strings.contains(why, "revoked"))
    delete(why)
    testing.expect_value(t, revoke_test_serves, 1)                                           // the list was kept
    why, ok = TlsRevocationCheck(revoked_chain, pinned, .OFF)
    testing.expect(t, ok)

    // a list that cannot be had: let through softly, refused strictly (and not asked again at once)
    crl_fetch_hook = proc(url: string) -> []byte {
        revoke_test_serves += 1
        return nil
    }
    sync.mutex_lock(&crl_mutex)
    clear(&crl_cache)
    sync.mutex_unlock(&crl_mutex)
    before: int = revoke_test_serves
    why, ok = TlsRevocationCheck(good_chain, pinned, .SOFT)
    testing.expect(t, ok)
    why, ok = TlsRevocationCheck(good_chain, pinned, .STRICT)
    testing.expect(t, !ok && strings.contains(why, "cannot tell"))
    delete(why)
    testing.expect_value(t, revoke_test_serves, before + 1)

    // the real list of ISRG Root X2: signed by it, one revoked certificate, and not the Root YE of the captured relay chain
    x2: TlsRoots
    testing.expect_value(t, TlsRootsAddPem(&x2, ISRG_ROOT_X2), 1)
    real_crl, real_parsed := CrlParse(ISRG_X2_REAL_CRL)
    testing.expect(t, real_parsed)
    real_time: time.Time = time.unix(1_795_000_000, 0)
    testing.expect(t, CrlVerify(&real_crl, &x2.certs[0], real_time))
    superseded: []byte = {0x6F, 0x5E, 0x60, 0xE6, 0x9C, 0x3A, 0x74, 0x69, 0x90, 0x66, 0x19, 0xD5, 0x6E, 0x4F, 0x49, 0x9A}
    root_ye_serial: []byte = {0x00, 0x87, 0x21, 0x65, 0xFC, 0x34, 0xB6, 0xE5, 0xFB, 0xA8, 0xAD, 0xD5, 0xB3, 0x70, 0x5F, 0xB5, 0x3A}
    testing.expect(t, CrlHas(&real_crl, superseded))
    testing.expect(t, !CrlHas(&real_crl, root_ye_serial))

    CrlDiskCacheCheck(t)
}

CrlTestServer :: struct {
    listener: net.TCP_Socket,
    variant: int,
}

CrlTestServe :: proc(data: rawptr) {
    server: ^CrlTestServer = cast(^CrlTestServer)data
    client, _, accept_error := net.accept_tcp(server.listener)
    if accept_error != nil {
        return
    }
    defer net.close(client)
    net.set_option(client, .Receive_Timeout, time.Second * 3)
    request: [1024]byte
    length: int
    for !strings.contains(string(request[:length]), "\r\n\r\n") && length < len(request) {
        count, error := net.recv_tcp(client, request[length:])
        if error != nil || count <= 0 {
            return
        }
        length += count
    }
    switch server.variant {
    case 0:
        head: string = fmt.tprintf("HTTP/1.1 200 OK\r\nContent-Type: application/pkix-crl\r\nContent-Length: %d\r\n\r\n", len(REVOKE_TEST_CRL))
        net.send_tcp(client, transmute([]byte)head)
        net.send_tcp(client, REVOKE_TEST_CRL)
    case 1:
        // two chunks, in pieces that do not meet the boundaries of the chunks
        net.send_tcp(client, transmute([]byte)string("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"))
        half: int = len(REVOKE_TEST_CRL) / 2
        first: string = fmt.tprintf("%x\r\n", half)
        net.send_tcp(client, transmute([]byte)first)
        net.send_tcp(client, revoke_crl_bytes[:half])
        second: string = fmt.tprintf("\r\n%x\r\n", len(REVOKE_TEST_CRL) - half)
        net.send_tcp(client, transmute([]byte)second)
        net.send_tcp(client, revoke_crl_bytes[half:])
        net.send_tcp(client, transmute([]byte)string("\r\n0\r\n\r\n"))
    case:
        net.send_tcp(client, transmute([]byte)string("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"))
    }
    time.sleep(50 * time.Millisecond)
}

// The HTTP side against a server on loopback: Content-Length, chunked, and a 404.
@(test)
CrlFetchTest :: proc(t: ^testing.T) {
    sync.mutex_guard(&crl_test_lock)
    for variant in 0 ..< 3 {
        listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = 0})
        testing.expect(t, listen_error == nil)
        endpoint, _ := net.bound_endpoint(listener)
        server: CrlTestServer = {listener, variant}
        worker: ^thread.Thread = thread.create_and_start_with_data(&server, CrlTestServe)
        body, body_ok := CrlFetch(fmt.tprintf("http://127.0.0.1:%d/x.crl", endpoint.port))
        thread.join(worker)
        thread.destroy(worker)
        net.close(listener)
        if variant == 2 {
            testing.expect(t, !body_ok)
        } else {
            testing.expectf(t, body_ok && string(body) == string(REVOKE_TEST_CRL), "variant %d", variant)
        }
        delete(body, runtime.heap_allocator())
    }
}

// A list fetched once is on the disk for the next run, is verified again when read back, and a damaged or foreign file is ignored.
// (Run from TlsRevocationTest: both use the cache and the hook, which are global, and tests run in parallel.)
@(private)
CrlDiskCacheCheck :: proc(t: ^testing.T) {
    context.allocator = runtime.heap_allocator()
    pinned: time.Time = time.unix(1_795_000_000, 0)
    folder: string = fmt.aprintf("%s/p2p_crl_%d", os.get_env("TEMP", context.temp_allocator), time.tick_now()._nsec)
    defer os.remove_all(folder)
    defer delete(folder)
    os.set_env("P2P_CACHE_DIR", folder)
    defer os.unset_env("P2P_CACHE_DIR")

    chain: TlsRoots
    testing.expect_value(t, TlsRootsAddPem(&chain, REVOKE_TEST_CHAIN), 3)
    revoked, authority: x509.Certificate = chain.certs[1], chain.certs[2]
    chain_pointers: []^x509.Certificate = {&revoked, &authority}
    url: string = "http://crl.test.invalid/ca.crl"
    clear_memory :: proc() {
        sync.mutex_lock(&crl_mutex)
        clear(&crl_cache)
        sync.mutex_unlock(&crl_mutex)
    }
    clear_memory()
    crl_fetch_hook = RevokeTestServe
    defer {
        crl_fetch_hook = nil
    }

    before: int = revoke_test_serves
    why, ok := TlsRevocationCheck(chain_pointers, pinned, .SOFT)
    testing.expect(t, !ok && strings.contains(why, "revoked"))
    delete(why)
    testing.expect_value(t, revoke_test_serves, before + 1)
    path: string = CrlDiskPath(url)
    testing.expect(t, os.is_file(path))

    // a new run: nothing in memory, the file answers, nothing is fetched
    clear_memory()
    why, ok = TlsRevocationCheck(chain_pointers, pinned, .SOFT)
    testing.expect(t, !ok && strings.contains(why, "revoked"))
    delete(why)
    testing.expect_value(t, revoke_test_serves, before + 1)

    // a file that is not a good list (a changed byte) is ignored: the list is fetched again and the file replaced
    data, _ := os.read_entire_file(path, context.allocator)
    data[len(data) - 5] ~= 1
    _ = os.write_entire_file(path, data)
    delete(data)
    clear_memory()
    why, ok = TlsRevocationCheck(chain_pointers, pinned, .SOFT)
    testing.expect(t, !ok)
    delete(why)
    testing.expect_value(t, revoke_test_serves, before + 2)
    clear_memory()
    why, ok = TlsRevocationCheck(chain_pointers, pinned, .SOFT)
    delete(why)
    testing.expect_value(t, revoke_test_serves, before + 2)                                  // the replaced file is good again

    // past its next update (2055): the file is not used
    clear_memory()
    old_serves: int = revoke_test_serves
    _, _ = TlsRevocationCheck(chain_pointers, time.unix(2_700_000_000, 0), .SOFT)
    testing.expect_value(t, revoke_test_serves, old_serves + 1)

    // no cache wanted
    os.set_env("P2P_CACHE_DIR", "off")
    testing.expect_value(t, CrlDiskPath(url), "")
}
