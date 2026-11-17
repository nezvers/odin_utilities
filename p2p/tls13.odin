// A small TLS 1.3 client, because public DERP relays (and most of the internet) only speak TLS and Odin has no TLS in core. Same code on
// Windows, Linux and macOS: X25519 key exchange, TLS_AES_128_GCM_SHA256 or TLS_CHACHA20_POLY1305_SHA256, all from core:crypto.
//
// The server certificate IS checked (tls_verify.odin): the chain must end at a root we trust, be valid today and be issued for the name that
// was asked for, and the server must prove with its CertificateVerify signature that it holds the key of the certificate. Roots: two built
// in, the system store, and what P2P_CA_FILE adds; P2P_TLS_VERIFY=off switches the checking off. Not checked: revocation. With the check
// off (or in the RFC 8448 test, whose certificate nobody trusts) the handshake is still authenticated by its Finished messages but anybody in
// the middle can pose as the server; inside DERP everything of value is sealed end to end anyway. It is a client for what this library needs,
// for anything else use a platform TLS (SChannel, Security.framework, OpenSSL).
//
// Layout: pure pieces first (key schedule, record protection, the handshake as a message driven state machine, all tested against the
// RFC 8448 trace), then the socket part (TlsConnect, TlsRead, TlsWrite). Fixed buffers, no allocation. Not thread safe, one owner.
package p2p

import "core:crypto"
import "core:crypto/aead"
import "core:crypto/hash"
import "core:crypto/hkdf"
import "core:crypto/hmac"
import "core:crypto/sha2"
import "core:crypto/x25519"
import "core:net"
import "core:testing"
import "core:time"

TLS_RECORD_MAX :: 16384
TLS_INPUT_MAX :: 5 + TLS_RECORD_MAX + 256
TLS_HANDSHAKE_MAX :: 20000
TLS_HASH :: hash.Algorithm.SHA256
TLS_HASH_SIZE :: 32

TLS_SUITE_AES_128_GCM :: u16(0x1301)
TLS_SUITE_CHACHA20_POLY1305 :: u16(0x1303)

TLS_TYPE_ALERT :: u8(21)
TLS_TYPE_HANDSHAKE :: u8(22)
TLS_TYPE_APPLICATION :: u8(23)
TLS_TYPE_CHANGE_CIPHER_SPEC :: u8(20)

TlsHash :: [TLS_HASH_SIZE]byte

// ---------------------------------------------------------------------------------------------------------------- key schedule

// HKDF-Expand-Label (RFC 8446 7.1): info = length, "tls13 " + label, context.
TlsExpandLabel :: proc(output: []byte, secret: []byte, label: string, context_bytes: []byte) {
    info: [2 + 1 + 6 + 16 + 1 + TLS_HASH_SIZE]byte
    assert(len(label) <= 16 && len(context_bytes) <= TLS_HASH_SIZE)
    info[0] = u8(len(output) >> 8)
    info[1] = u8(len(output))
    info[2] = u8(6 + len(label))
    copy(info[3:], "tls13 ")
    copy(info[9:], label)
    at: int = 9 + len(label)
    info[at] = u8(len(context_bytes))
    copy(info[at + 1:], context_bytes)
    hkdf.expand(TLS_HASH, secret, info[:at + 1 + len(context_bytes)], output)
}

TlsDeriveSecret :: proc(secret: []byte, label: string, transcript_hash: []byte) -> (output: TlsHash) {
    TlsExpandLabel(output[:], secret, label, transcript_hash)
    return
}

// The write key (16 or 32 bytes) and the 12 byte iv of a traffic secret.
TlsTrafficKeys :: proc(secret: []byte, key_length: int) -> (key: [32]byte, iv: [12]byte) {
    TlsExpandLabel(key[:key_length], secret, "key", nil)
    TlsExpandLabel(iv[:], secret, "iv", nil)
    return
}

// early secret -> derived -> handshake secret (from the shared X25519 value) and the two handshake traffic secrets.
TlsHandshakeSecrets :: proc(ecdhe: []byte, transcript_hello: []byte) -> (handshake_secret, client, server: TlsHash) {
    zero: TlsHash
    early: TlsHash
    hkdf.extract(TLS_HASH, zero[:], zero[:], early[:])
    empty_hash: TlsHash
    TlsHashOfNothing(&empty_hash)
    derived: TlsHash = TlsDeriveSecret(early[:], "derived", empty_hash[:])
    hkdf.extract(TLS_HASH, derived[:], ecdhe, handshake_secret[:])
    client = TlsDeriveSecret(handshake_secret[:], "c hs traffic", transcript_hello)
    server = TlsDeriveSecret(handshake_secret[:], "s hs traffic", transcript_hello)
    return
}

// handshake secret -> derived -> master secret, and the two application traffic secrets (transcript through the server Finished).
TlsApplicationSecrets :: proc(handshake_secret: []byte, transcript_server_finished: []byte) -> (client, server: TlsHash) {
    empty_hash: TlsHash
    TlsHashOfNothing(&empty_hash)
    derived: TlsHash = TlsDeriveSecret(handshake_secret, "derived", empty_hash[:])
    zero: TlsHash
    master: TlsHash
    hkdf.extract(TLS_HASH, derived[:], zero[:], master[:])
    client = TlsDeriveSecret(master[:], "c ap traffic", transcript_server_finished)
    server = TlsDeriveSecret(master[:], "s ap traffic", transcript_server_finished)
    return
}

@(private)
TlsHashOfNothing :: proc(output: ^TlsHash) {
    context_256: sha2.Context_256
    sha2.init_256(&context_256)
    sha2.final(&context_256, output[:])
}

// verify_data of a Finished message: HMAC over the transcript hash with the finished key of that side's handshake secret.
TlsFinishedVerify :: proc(base_secret: []byte, transcript_hash: []byte) -> (verify: TlsHash) {
    finished_key: TlsHash
    TlsExpandLabel(finished_key[:], base_secret, "finished", nil)
    hmac.sum(TLS_HASH, verify[:], transcript_hash, finished_key[:])
    return
}

// ---------------------------------------------------------------------------------------------------------------- record protection

TlsDirection :: struct {
    algorithm: aead.Algorithm,
    key: [32]byte,
    key_length: int,
    iv: [12]byte,
    sequence: u64,
    secret: TlsHash,
    active: bool,
}

TlsDirectionSet :: proc(direction: ^TlsDirection, algorithm: aead.Algorithm, secret: TlsHash) {
    direction.algorithm = algorithm
    direction.key_length = 16 if algorithm == .AES_GCM_128 else 32
    direction.secret = secret
    secret_copy: TlsHash = secret
    direction.key, direction.iv = TlsTrafficKeys(secret_copy[:], direction.key_length)
    direction.sequence = 0
    direction.active = true
}

@(private)
TlsNonce :: proc(direction: ^TlsDirection) -> (nonce: [12]byte) {
    nonce = direction.iv
    for i in 0 ..< 8 {
        nonce[11 - i] ~= u8(direction.sequence >> uint(8 * i))
    }
    return
}

// Seals `plaintext` with its inner content type into a complete record (header, ciphertext, tag). Returns the record length.
TlsRecordSeal :: proc(direction: ^TlsDirection, inner_type: u8, plaintext: []byte, record: []byte) -> int {
    length: int = len(plaintext) + 1 + 16
    assert(len(plaintext) <= TLS_RECORD_MAX && len(record) >= 5 + length)
    record[0] = TLS_TYPE_APPLICATION
    record[1] = 3
    record[2] = 3
    record[3] = u8(length >> 8)
    record[4] = u8(length)
    inner: [TLS_RECORD_MAX + 1]byte
    copy(inner[:], plaintext)
    inner[len(plaintext)] = inner_type
    nonce: [12]byte = TlsNonce(direction)
    key: [32]byte = direction.key
    aead.seal_oneshot(direction.algorithm, record[5:5 + len(plaintext) + 1], record[5 + len(plaintext) + 1:5 + length], key[:direction.key_length], nonce[:], record[:5], inner[:len(plaintext) + 1])
    direction.sequence += 1
    return 5 + length
}

// Opens a complete record in place. Returns the inner content type and the plaintext length (the plaintext is at record[5:]).
TlsRecordOpen :: proc(direction: ^TlsDirection, record: []byte) -> (inner_type: u8, length: int, ok: bool) {
    total: int = int(record[3]) << 8 | int(record[4])
    if total < 17 || len(record) < 5 + total || total > TLS_RECORD_MAX + 256 {
        return
    }
    body: int = total - 16
    nonce: [12]byte = TlsNonce(direction)
    key: [32]byte = direction.key
    if !aead.open_oneshot(direction.algorithm, record[5:5 + body], key[:direction.key_length], nonce[:], record[:5], record[5:5 + body], record[5 + body:5 + total]) {
        return
    }
    direction.sequence += 1
    // the real content type is the last non zero byte, zeros before it are padding
    end: int = body
    for end > 0 && record[5 + end - 1] == 0 {
        end -= 1
    }
    if end == 0 {
        return
    }
    return record[5 + end - 1], end - 1, true
}

// ---------------------------------------------------------------------------------------------------------------- handshake

TlsState :: enum {
    START,
    WAIT_SERVER_HELLO,
    WAIT_ENCRYPTED_EXTENSIONS,
    WAIT_CERTIFICATE,                    // or CertificateRequest
    WAIT_CERTIFICATE_VERIFY,
    WAIT_FINISHED,
    CONNECTED,
    FAILED,
}

TlsHandshake :: struct {
    state: TlsState,
    transcript: sha2.Context_256,
    private: [32]byte,
    public: [32]byte,
    algorithm: aead.Algorithm,
    handshake_secret: TlsHash,
    client_handshake: TlsHash,
    server_handshake: TlsHash,
    client_application: TlsHash,
    server_application: TlsHash,
    client_finished: [4 + TLS_HASH_SIZE]byte,       // the message to send once the server's Finished checked out
    failure: string,
    verify: bool,                                   // check the certificate (set by TlsConnect after the hello)
    host: [TLS_HOST_MAX]byte,                       // the name the certificate has to be for
    host_length: int,
    leaf: [TLS_LEAF_MAX]byte,                       // the server's certificate, kept for the CertificateVerify check
    leaf_length: int,
}

TLS_HOST_MAX :: 64

@(private)
TlsFail :: proc(handshake: ^TlsHandshake, why: string) -> bool {
    handshake.state = .FAILED
    handshake.failure = why
    return false
}

@(private)
TlsTranscriptHash :: proc(handshake: ^TlsHandshake) -> (digest: TlsHash) {
    copy_context: sha2.Context_256 = handshake.transcript
    sha2.final(&copy_context, digest[:])
    return
}

// Builds the ClientHello handshake message (header included) into `out`, returns its length. `random` and `private` are given so a
// test can repeat a trace; TlsRandomHello makes them.
TlsClientHello :: proc(handshake: ^TlsHandshake, out: []byte, hostname: string, random: [32]byte, private: [32]byte) -> int {
    handshake^ = {}
    handshake.private = private
    private_copy: [32]byte = private
    x25519.scalarmult_basepoint(handshake.public[:], private_copy[:])

    at: int = 4                                       // the 4 byte handshake header is filled last
    put16 :: proc(out: []byte, at: ^int, value: int) {
        out[at^] = u8(value >> 8)
        out[at^ + 1] = u8(value)
        at^ += 2
    }
    out[at] = 3
    out[at + 1] = 3                                   // legacy_version TLS 1.2, the real one is in supported_versions
    at += 2
    random_copy: [32]byte = random
    copy(out[at:], random_copy[:])
    at += 32
    out[at] = 0                                       // legacy_session_id: empty (no middlebox compatibility mode)
    at += 1
    put16(out, &at, 4)                                // two cipher suites
    put16(out, &at, int(TLS_SUITE_AES_128_GCM))
    put16(out, &at, int(TLS_SUITE_CHACHA20_POLY1305))
    out[at] = 1                                       // compression: null only
    out[at + 1] = 0
    at += 2
    extensions_at: int = at
    at += 2
    // server_name
    put16(out, &at, 0)
    put16(out, &at, 5 + len(hostname))
    put16(out, &at, 3 + len(hostname))
    out[at] = 0
    at += 1
    put16(out, &at, len(hostname))
    copy(out[at:], hostname)
    at += len(hostname)
    // supported_groups: x25519
    put16(out, &at, 10)
    put16(out, &at, 4)
    put16(out, &at, 2)
    put16(out, &at, 0x001d)
    // signature_algorithms: what a server may sign with, and what its chain may be signed with (the same list in TLS 1.3): ECDSA P-256 / P-384,
    // RSA-PSS, Ed25519 and RSA PKCS#1 for the certificates above the leaf (all of them verified by core:crypto/x509)
    SIGNATURE_ALGORITHMS :: [?]int{0x0403, 0x0503, 0x0804, 0x0805, 0x0806, 0x0807, 0x0401, 0x0501}
    put16(out, &at, 13)
    put16(out, &at, 2 + 2 * len(SIGNATURE_ALGORITHMS))
    put16(out, &at, 2 * len(SIGNATURE_ALGORITHMS))
    for algorithm in SIGNATURE_ALGORITHMS {
        put16(out, &at, algorithm)
    }
    // supported_versions: TLS 1.3 only
    put16(out, &at, 43)
    put16(out, &at, 3)
    out[at] = 2
    at += 1
    put16(out, &at, 0x0304)
    // key_share: one x25519 share
    put16(out, &at, 51)
    put16(out, &at, 2 + 4 + 32)
    put16(out, &at, 4 + 32)
    put16(out, &at, 0x001d)
    put16(out, &at, 32)
    copy(out[at:], handshake.public[:])
    at += 32
    out[extensions_at] = u8((at - extensions_at - 2) >> 8)
    out[extensions_at + 1] = u8(at - extensions_at - 2)
    out[0] = 1                                        // ClientHello
    out[1] = u8((at - 4) >> 16)
    out[2] = u8((at - 4) >> 8)
    out[3] = u8(at - 4)
    sha2.init_256(&handshake.transcript)
    sha2.update(&handshake.transcript, out[:at])
    handshake.state = .WAIT_SERVER_HELLO
    return at
}

TlsRandomHello :: proc(handshake: ^TlsHandshake, out: []byte, hostname: string) -> int {
    random: [32]byte
    private: [32]byte
    crypto.rand_bytes(random[:])
    crypto.rand_bytes(private[:])
    return TlsClientHello(handshake, out, hostname, random, private)
}

// The ServerHello message (header included). On success the handshake traffic keys can be taken from the handshake.
TlsServerHello :: proc(handshake: ^TlsHandshake, message: []byte) -> bool {
    if handshake.state != .WAIT_SERVER_HELLO || len(message) < 4 + 2 + 32 + 1 || message[0] != 2 {
        return TlsFail(handshake, "unexpected message instead of ServerHello")
    }
    reader: []byte = message[4:]
    at: int = 2 + 32                                  // version, random
    hello_retry: [32]byte = {
        0xCF, 0x21, 0xAD, 0x74, 0xE5, 0x9A, 0x61, 0x11, 0xBE, 0x1D, 0x8C, 0x02, 0x1E, 0x65, 0xB8, 0x91,
        0xC2, 0xA2, 0x11, 0x16, 0x7A, 0xBB, 0x8C, 0x5E, 0x07, 0x9E, 0x09, 0xE2, 0xC8, 0xA8, 0x33, 0x9C,
    }
    if string(reader[2:34]) == string(hello_retry[:]) {
        return TlsFail(handshake, "the server asked for another key exchange group (HelloRetryRequest)")
    }
    session_length: int = int(reader[at])
    at += 1 + session_length
    if len(reader) < at + 2 + 1 + 2 {
        return TlsFail(handshake, "ServerHello too short")
    }
    suite: u16 = u16(reader[at]) << 8 | u16(reader[at + 1])
    at += 2 + 1                                       // suite, compression
    switch suite {
    case TLS_SUITE_AES_128_GCM:
        handshake.algorithm = .AES_GCM_128
    case TLS_SUITE_CHACHA20_POLY1305:
        handshake.algorithm = .CHACHA20POLY1305
    case:
        return TlsFail(handshake, "the server chose a cipher suite that was not offered")
    }
    extensions_length: int = int(reader[at]) << 8 | int(reader[at + 1])
    at += 2
    if at + extensions_length > len(reader) {
        return TlsFail(handshake, "ServerHello extensions are cut off")
    }
    version_ok: bool
    server_share: []byte
    end: int = at + extensions_length
    for at + 4 <= end {
        kind: int = int(reader[at]) << 8 | int(reader[at + 1])
        size: int = int(reader[at + 2]) << 8 | int(reader[at + 3])
        body: []byte = reader[at + 4:min(at + 4 + size, end)]
        at += 4 + size
        if kind == 43 && len(body) == 2 && body[0] == 3 && body[1] == 4 {
            version_ok = true
        } else if kind == 51 && len(body) == 2 + 2 + 32 && body[0] == 0 && body[1] == 0x1d && body[2] == 0 && body[3] == 32 {
            server_share = body[4:]
        }
    }
    if !version_ok {
        return TlsFail(handshake, "the server does not speak TLS 1.3")
    }
    if server_share == nil {
        return TlsFail(handshake, "no X25519 key share from the server")
    }
    sha2.update(&handshake.transcript, message)
    shared: [32]byte
    private: [32]byte = handshake.private
    x25519.scalarmult(shared[:], private[:], server_share)
    transcript: TlsHash = TlsTranscriptHash(handshake)
    handshake.handshake_secret, handshake.client_handshake, handshake.server_handshake = TlsHandshakeSecrets(shared[:], transcript[:])
    handshake.state = .WAIT_ENCRYPTED_EXTENSIONS
    return true
}

// One handshake message (header included) that came in encrypted: EncryptedExtensions, Certificate, CertificateVerify, Finished.
// With `handshake.verify` the Certificate is checked against the trust store and the name, and CertificateVerify against its key. After the
// server Finished the application secrets are ready and `client_finished` holds the message to send.
TlsServerMessage :: proc(handshake: ^TlsHandshake, message: []byte) -> bool {
    if len(message) < 4 {
        return TlsFail(handshake, "handshake message too short")
    }
    kind: u8 = message[0]
    switch handshake.state {
    case .WAIT_ENCRYPTED_EXTENSIONS:
        if kind != 8 {
            return TlsFail(handshake, "expected EncryptedExtensions")
        }
        handshake.state = .WAIT_CERTIFICATE
    case .WAIT_CERTIFICATE:
        if kind == 13 {
            return TlsFail(handshake, "the server wants a client certificate")
        }
        if kind != 11 {
            return TlsFail(handshake, "expected Certificate")
        }
        if handshake.verify && !TlsCheckCertificate(handshake, message) {
            return false
        }
        handshake.state = .WAIT_CERTIFICATE_VERIFY
    case .WAIT_CERTIFICATE_VERIFY:
        if kind != 15 {
            return TlsFail(handshake, "expected CertificateVerify")
        }
        if handshake.verify {
            // the transcript so far ends with the Certificate message: that is what the server signed
            if len(message) < 8 || int(message[6]) << 8 | int(message[7]) != len(message) - 8 {
                return TlsFail(handshake, "CertificateVerify is malformed")
            }
            transcript: TlsHash = TlsTranscriptHash(handshake)
            why, ok := TlsVerifyCertificateSignature(handshake.leaf[:handshake.leaf_length], u16(message[4]) << 8 | u16(message[5]), message[8:], transcript[:])
            if !ok {
                return TlsFail(handshake, why)
            }
        }
        handshake.state = .WAIT_FINISHED
    case .WAIT_FINISHED:
        if kind != 20 || len(message) != 4 + TLS_HASH_SIZE {
            return TlsFail(handshake, "expected Finished")
        }
        before: TlsHash = TlsTranscriptHash(handshake)
        expected: TlsHash = TlsFinishedVerify(handshake.server_handshake[:], before[:])
        if crypto.compare_constant_time(message[4:], expected[:]) != 1 {
            return TlsFail(handshake, "the server Finished does not verify")
        }
        sha2.update(&handshake.transcript, message)
        through_server: TlsHash = TlsTranscriptHash(handshake)
        handshake.client_application, handshake.server_application = TlsApplicationSecrets(handshake.handshake_secret[:], through_server[:])
        verify: TlsHash = TlsFinishedVerify(handshake.client_handshake[:], through_server[:])
        handshake.client_finished[0] = 20
        handshake.client_finished[3] = TLS_HASH_SIZE
        copy(handshake.client_finished[4:], verify[:])
        sha2.update(&handshake.transcript, handshake.client_finished[:])
        handshake.state = .CONNECTED
        return true
    case .START, .WAIT_SERVER_HELLO, .CONNECTED, .FAILED:
        return TlsFail(handshake, "handshake message at the wrong time")
    }
    sha2.update(&handshake.transcript, message)
    return true
}

// The Certificate message: [11][len 3][context len 1 + context][list len 3]{[cert len 3][DER][extensions len 2 + extensions]}...
// The chain is checked now (the name, the dates, the authority), the first certificate is kept for the CertificateVerify.
@(private)
TlsCheckCertificate :: proc(handshake: ^TlsHandshake, message: []byte) -> bool {
    at: int = 4
    if len(message) < at + 1 {
        return TlsFail(handshake, "Certificate is malformed")
    }
    at += 1 + int(message[at])
    if len(message) < at + 3 {
        return TlsFail(handshake, "Certificate is malformed")
    }
    list_end: int = at + 3 + (int(message[at]) << 16 | int(message[at + 1]) << 8 | int(message[at + 2]))
    at += 3
    if list_end != len(message) {
        return TlsFail(handshake, "Certificate is malformed")
    }
    chain: [TLS_CHAIN_MAX][]byte
    count: int
    for at < list_end {
        if at + 3 > list_end {
            return TlsFail(handshake, "Certificate is malformed")
        }
        size: int = int(message[at]) << 16 | int(message[at + 1]) << 8 | int(message[at + 2])
        at += 3
        if at + size + 2 > list_end || size == 0 {
            return TlsFail(handshake, "Certificate is malformed")
        }
        if count < TLS_CHAIN_MAX {
            chain[count] = message[at:at + size]
            count += 1
        }
        at += size
        at += 2 + (int(message[at]) << 8 | int(message[at + 1]))        // the extensions of this entry (OCSP, timestamps): not used
    }
    if count == 0 || len(chain[0]) > TLS_LEAF_MAX {
        return TlsFail(handshake, "the server sent no usable certificate")
    }
    why, ok := TlsVerifyChain(chain[:count], string(handshake.host[:handshake.host_length]))
    if !ok {
        return TlsFail(handshake, why)
    }
    copy(handshake.leaf[:], chain[0])
    handshake.leaf_length = len(chain[0])
    return true
}

// ---------------------------------------------------------------------------------------------------------------- connection

Tls :: struct {
    socket: net.TCP_Socket,
    open: bool,
    read: TlsDirection,
    write: TlsDirection,
    input: [TLS_INPUT_MAX]byte,
    input_length: int,
    plain: [TLS_RECORD_MAX]byte,
    plain_length: int,
    plain_offset: int,
    handshake_buffer: [TLS_HANDSHAKE_MAX]byte,
    handshake_length: int,
    failure: string,
}

// The first bytes of the next record in the input buffer are a complete record?
@(private)
TlsRecordReady :: proc(tls: ^Tls) -> (size: int, ready: bool) {
    if tls.input_length < 5 {
        return
    }
    size = 5 + (int(tls.input[3]) << 8 | int(tls.input[4]))
    if size > TLS_INPUT_MAX {
        tls.failure = "record too big"
        return -1, false
    }
    return size, tls.input_length >= size
}

// Reads from the socket into the input buffer. wait: block (up to the socket's receive timeout). Returns false when the connection
// ended or failed; `got` tells whether any byte arrived.
@(private)
TlsFill :: proc(tls: ^Tls, wait: bool) -> (alive: bool, got: bool) {
    if tls.input_length >= TLS_INPUT_MAX {
        return true, false
    }
    count, error := net.recv_tcp(tls.socket, tls.input[tls.input_length:])
    if error == .Would_Block || error == .Timeout {
        if wait && error == .Timeout {
            tls.failure = "the server stopped answering"
            return false, false
        }
        return true, false
    }
    if error != nil || count <= 0 {
        tls.failure = "the connection was closed"
        return false, false
    }
    tls.input_length += count
    return true, true
}

@(private)
TlsConsumeRecord :: proc(tls: ^Tls, size: int) {
    copy(tls.input[:tls.input_length - size], tls.input[size:tls.input_length])
    tls.input_length -= size
}

// The next record: its outer type, and its payload decrypted in place (plaintext at tls.input[5:5+length]). The caller must call
// TlsConsumeRecord(size) when done with the payload. Returns ready=false when no complete record is there yet.
@(private)
TlsNextRecord :: proc(tls: ^Tls, wait: bool) -> (kind: u8, length: int, size: int, ready: bool, alive: bool) {
    for {
        record_size, complete := TlsRecordReady(tls)
        if record_size < 0 {
            return 0, 0, 0, false, false
        }
        if complete {
            kind = tls.input[0]
            if kind == TLS_TYPE_APPLICATION && tls.read.active {
                inner: u8
                ok: bool
                inner, length, ok = TlsRecordOpen(&tls.read, tls.input[:record_size])
                if !ok {
                    tls.failure = "a record failed to decrypt"
                    return 0, 0, 0, false, false
                }
                return inner, length, record_size, true, true
            }
            return kind, record_size - 5, record_size, true, true
        }
        got: bool
        alive, got = TlsFill(tls, wait)
        if !alive {
            return 0, 0, 0, false, false
        }
        if !got && !wait {
            return 0, 0, 0, false, true
        }
    }
}

// Sends all of `data` (the socket may be non blocking by now: wait a little when its buffer is full).
@(private)
TlsSendAll :: proc(tls: ^Tls, data: []byte) -> bool {
    sent: int
    waited: int
    for sent < len(data) {
        count, error := net.send_tcp(tls.socket, data[sent:])
        if error == .Would_Block || error == .Timeout {
            waited += 1
            if waited > 5000 {
                return false
            }
            time.sleep(time.Millisecond)
            continue
        }
        if error != nil || count <= 0 {
            return false
        }
        sent += count
        waited = 0
    }
    return true
}

// Runs the handshake on a connected TCP socket. Blocking: set a receive timeout first (net.set_option(.Receive_Timeout)).
// On success the connection is ready for TlsWrite / TlsRead. `verify` = check the certificate against `hostname` (see tls_verify.odin;
// P2P_TLS_VERIFY=off overrides it).
TlsConnect :: proc(tls: ^Tls, socket: net.TCP_Socket, hostname: string, verify: bool = true) -> bool {
    tls^ = {socket = socket}
    handshake: ^TlsHandshake = new(TlsHandshake)
    defer free(handshake)
    hello: [512]byte
    hello_length: int = TlsRandomHello(handshake, hello[:], hostname)
    handshake.verify = verify && TlsVerifyEnabled()
    if handshake.verify {
        if len(hostname) > TLS_HOST_MAX {
            tls.failure = "the name of the server is too long to check its certificate"
            return false
        }
        handshake.host_length = copy(handshake.host[:], hostname)
    }
    record: [5 + 512]byte
    record[0] = TLS_TYPE_HANDSHAKE
    record[1] = 3
    record[2] = 1
    record[3] = u8(hello_length >> 8)
    record[4] = u8(hello_length)
    copy(record[5:], hello[:hello_length])
    if !TlsSendAll(tls, record[:5 + hello_length]) {
        tls.failure = "cannot send the ClientHello"
        return false
    }

    // ServerHello arrives in the clear, possibly followed by a ChangeCipherSpec
    for handshake.state == .WAIT_SERVER_HELLO {
        kind, length, size, ready, alive := TlsNextRecord(tls, true)
        if !alive || !ready {
            if tls.failure == "" {
                tls.failure = "no ServerHello"
            }
            return false
        }
        switch kind {
        case TLS_TYPE_HANDSHAKE:
            if !TlsServerHello(handshake, tls.input[5:5 + length]) {
                tls.failure = handshake.failure
                return false
            }
        case TLS_TYPE_CHANGE_CIPHER_SPEC:
        case TLS_TYPE_ALERT:
            tls.failure = "the server refused the connection (alert)"
            return false
        case:
            tls.failure = "unexpected record instead of ServerHello"
            return false
        }
        TlsConsumeRecord(tls, size)
    }
    TlsDirectionSet(&tls.read, handshake.algorithm, handshake.server_handshake)

    // the rest of the server flight is encrypted: gather handshake messages until Finished
    for handshake.state != .CONNECTED {
        kind, length, size, ready, alive := TlsNextRecord(tls, true)
        if !alive || !ready {
            if tls.failure == "" {
                tls.failure = "the handshake did not finish"
            }
            return false
        }
        switch kind {
        case TLS_TYPE_HANDSHAKE:
            if tls.handshake_length + length > TLS_HANDSHAKE_MAX {
                tls.failure = "handshake messages too big"
                return false
            }
            copy(tls.handshake_buffer[tls.handshake_length:], tls.input[5:5 + length])
            tls.handshake_length += length
            TlsConsumeRecord(tls, size)
            for tls.handshake_length >= 4 && handshake.state != .CONNECTED {
                message_size: int = 4 + (int(tls.handshake_buffer[1]) << 16 | int(tls.handshake_buffer[2]) << 8 | int(tls.handshake_buffer[3]))
                if tls.handshake_length < message_size {
                    break
                }
                if !TlsServerMessage(handshake, tls.handshake_buffer[:message_size]) {
                    tls.failure = handshake.failure
                    return false
                }
                copy(tls.handshake_buffer[:tls.handshake_length - message_size], tls.handshake_buffer[message_size:tls.handshake_length])
                tls.handshake_length -= message_size
            }
        case TLS_TYPE_ALERT:
            tls.failure = "the server aborted the handshake (alert)"
            return false
        case TLS_TYPE_CHANGE_CIPHER_SPEC:
            TlsConsumeRecord(tls, size)
        case:
            tls.failure = "unexpected record in the handshake"
            return false
        }
    }

    // our Finished, protected with the client handshake keys, then everything switches to the application keys
    TlsDirectionSet(&tls.write, handshake.algorithm, handshake.client_handshake)
    sealed: [5 + 4 + TLS_HASH_SIZE + 1 + 16]byte
    sealed_length: int = TlsRecordSeal(&tls.write, TLS_TYPE_HANDSHAKE, handshake.client_finished[:], sealed[:])
    if !TlsSendAll(tls, sealed[:sealed_length]) {
        tls.failure = "cannot send Finished"
        return false
    }
    TlsDirectionSet(&tls.write, handshake.algorithm, handshake.client_application)
    TlsDirectionSet(&tls.read, handshake.algorithm, handshake.server_application)
    tls.handshake_length = 0
    tls.open = true
    return true
}

// Sends application data, split into records. False: the connection is gone.
TlsWrite :: proc(tls: ^Tls, data: []byte) -> bool {
    if !tls.open {
        return false
    }
    record: [5 + TLS_RECORD_MAX + 1 + 16]byte
    offset: int
    for offset < len(data) || offset == 0 && len(data) == 0 {
        count: int = min(TLS_RECORD_MAX, len(data) - offset)
        size: int = TlsRecordSeal(&tls.write, TLS_TYPE_APPLICATION, data[offset:offset + count], record[:])
        if !TlsSendAll(tls, record[:size]) {
            tls.open = false
            return false
        }
        offset += count
        if len(data) == 0 {
            break
        }
    }
    return true
}

// Application bytes. Returns how many were put in `out` (0: nothing yet), or -1 when the connection ended or broke.
// wait: block until something arrives (the socket's receive timeout applies).
TlsRead :: proc(tls: ^Tls, out: []byte, wait: bool) -> int {
    for tls.plain_offset >= tls.plain_length {
        tls.plain_offset = 0
        tls.plain_length = 0
        if !tls.open {
            return -1
        }
        kind, length, size, ready, alive := TlsNextRecord(tls, wait)
        if !alive {
            tls.open = false
            return -1
        }
        if !ready {
            return 0
        }
        switch kind {
        case TLS_TYPE_APPLICATION:
            copy(tls.plain[:], tls.input[5:5 + length])
            tls.plain_length = length
        case TLS_TYPE_HANDSHAKE:
            TlsPostHandshake(tls, tls.input[5:5 + length])
        case TLS_TYPE_ALERT:
            TlsConsumeRecord(tls, size)
            tls.open = false
            tls.failure = "the server closed the connection"
            return -1
        }
        TlsConsumeRecord(tls, size)
        if !tls.open {
            return -1
        }
    }
    count: int = min(len(out), tls.plain_length - tls.plain_offset)
    copy(out[:count], tls.plain[tls.plain_offset:tls.plain_offset + count])
    tls.plain_offset += count
    return count
}

// NewSessionTicket is ignored. KeyUpdate: the peer's next records use new keys, and when it asks, ours change too.
@(private)
TlsPostHandshake :: proc(tls: ^Tls, data: []byte) {
    offset: int
    for offset + 4 <= len(data) {
        size: int = 4 + (int(data[offset + 1]) << 16 | int(data[offset + 2]) << 8 | int(data[offset + 3]))
        if offset + size > len(data) {
            return
        }
        if data[offset] == 24 && size == 5 {
            next: TlsHash
            TlsExpandLabel(next[:], tls.read.secret[:], "traffic upd", nil)
            TlsDirectionSet(&tls.read, tls.read.algorithm, next)
            if data[offset + 4] == 1 {
                update: [5]byte = {24, 0, 0, 1, 0}
                record: [5 + 5 + 1 + 16]byte
                length: int = TlsRecordSeal(&tls.write, TLS_TYPE_HANDSHAKE, update[:], record[:])
                TlsSendAll(tls, record[:length])
                TlsExpandLabel(next[:], tls.write.secret[:], "traffic upd", nil)
                TlsDirectionSet(&tls.write, tls.write.algorithm, next)
            }
        }
        offset += size
    }
}

TlsClose :: proc(tls: ^Tls) {
    if tls.open {
        // close_notify, so the server does not count it as a broken connection
        alert: [2]byte = {1, 0}
        record: [5 + 2 + 1 + 16]byte
        length: int = TlsRecordSeal(&tls.write, TLS_TYPE_ALERT, alert[:], record[:])
        TlsSendAll(tls, record[:length])
        tls.open = false
    }
}

// ---------------------------------------------------------------------------------------------------------------- tests

@(private)
HexBytes :: proc(text: string) -> []byte {
    out: []byte = make([]byte, len(text) / 2, context.temp_allocator)
    FromHex(text, out)
    return out
}

// The whole server side of the RFC 8448 trace, through this implementation: our key schedule, our record decryption, our handshake
// state machine, our client Finished and its encryption must reproduce the published values.
@(test)
TlsRfc8448Test :: proc(t: ^testing.T) {
    handshake: ^TlsHandshake = new(TlsHandshake)
    defer free(handshake)
    client_hello: []byte = HexBytes(RFC8448_CLIENT_HELLO)
    server_hello: []byte = HexBytes(RFC8448_SERVER_HELLO)
    // the transcript starts with the ClientHello the trace used (ours differs in its extensions, the machine does not care)
    sha2.init_256(&handshake.transcript)
    sha2.update(&handshake.transcript, client_hello)
    copy(handshake.private[:], HexBytes(RFC8448_CLIENT_PRIVATE))
    handshake.state = .WAIT_SERVER_HELLO

    public: [32]byte
    x25519.scalarmult_basepoint(public[:], handshake.private[:])
    testing.expect_value(t, string(public[:]), string(HexBytes(RFC8448_CLIENT_PUBLIC)))

    testing.expect(t, TlsServerHello(handshake, server_hello))
    testing.expect_value(t, handshake.algorithm, aead.Algorithm.AES_GCM_128)
    th_sh: TlsHash = TlsTranscriptHash(handshake)
    testing.expect_value(t, string(th_sh[:]), string(HexBytes(RFC8448_TH_SH)))
    testing.expect_value(t, string(handshake.handshake_secret[:]), string(HexBytes(RFC8448_HS_SECRET)))
    testing.expect_value(t, string(handshake.client_handshake[:]), string(HexBytes(RFC8448_C_HS)))
    testing.expect_value(t, string(handshake.server_handshake[:]), string(HexBytes(RFC8448_S_HS)))

    // the server's keys for the handshake, and its encrypted flight (EncryptedExtensions, Certificate, CertificateVerify, Finished)
    server: TlsDirection
    TlsDirectionSet(&server, .AES_GCM_128, handshake.server_handshake)
    testing.expect_value(t, string(server.key[:16]), string(HexBytes(RFC8448_S_KEY)))
    testing.expect_value(t, string(server.iv[:]), string(HexBytes(RFC8448_S_IV)))
    record: []byte = HexBytes(RFC8448_SERVER_RECORD)
    inner_type, length, ok := TlsRecordOpen(&server, record)
    testing.expect(t, ok)
    testing.expect_value(t, inner_type, TLS_TYPE_HANDSHAKE)
    payload: []byte = record[5:5 + length]
    testing.expect_value(t, string(payload), string(HexBytes(RFC8448_SERVER_PAYLOAD)))
    offset: int
    leaf: []byte
    for offset < len(payload) {
        size: int = 4 + (int(payload[offset + 1]) << 16 | int(payload[offset + 2]) << 8 | int(payload[offset + 3]))
        message: []byte = payload[offset:offset + size]
        if message[0] == 11 {
            leaf = message[11:11 + (int(message[8]) << 16 | int(message[9]) << 8 | int(message[10]))]
        }
        if message[0] == 15 {
            // the signature of the trace (rsa_pss_rsae_sha256) over its transcript: our check accepts it, and refuses it damaged
            transcript: TlsHash = TlsTranscriptHash(handshake)
            scheme: u16 = u16(message[4]) << 8 | u16(message[5])
            why, signature_ok := TlsVerifyCertificateSignature(leaf, scheme, message[8:], transcript[:])
            testing.expect(t, signature_ok, why)
            damaged: [512]byte
            copy(damaged[:], message[8:])
            damaged[10] ~= 1
            _, damaged_ok := TlsVerifyCertificateSignature(leaf, scheme, damaged[:len(message) - 8], transcript[:])
            testing.expect(t, !damaged_ok)
            _, other_ok := TlsVerifyCertificateSignature(leaf, 0x0403, message[8:], transcript[:])     // a scheme that does not fit the key
            testing.expect(t, !other_ok)
            transcript[0] ~= 1
            _, replay_ok := TlsVerifyCertificateSignature(leaf, scheme, message[8:], transcript[:])    // signed over another conversation
            testing.expect(t, !replay_ok)
        }
        testing.expect(t, TlsServerMessage(handshake, message))
        offset += size
    }
    testing.expect_value(t, handshake.state, TlsState.CONNECTED)
    testing.expect_value(t, string(handshake.client_finished[4:]), string(HexBytes(RFC8448_C_FINISHED)))
    testing.expect_value(t, string(handshake.client_finished[:]), string(HexBytes(RFC8448_C_FINISHED_MSG)))
    testing.expect_value(t, string(handshake.client_application[:]), string(HexBytes(RFC8448_C_AP)))
    testing.expect_value(t, string(handshake.server_application[:]), string(HexBytes(RFC8448_S_AP)))
    app: TlsDirection
    TlsDirectionSet(&app, .AES_GCM_128, handshake.server_application)
    testing.expect_value(t, string(app.key[:16]), string(HexBytes(RFC8448_S_AP_KEY)))
    testing.expect_value(t, string(app.iv[:]), string(HexBytes(RFC8448_S_AP_IV)))

    // our encrypted client Finished is byte for byte the record of the trace
    client: TlsDirection
    TlsDirectionSet(&client, .AES_GCM_128, handshake.client_handshake)
    sealed: [128]byte
    sealed_length: int = TlsRecordSeal(&client, TLS_TYPE_HANDSHAKE, handshake.client_finished[:], sealed[:])
    testing.expect_value(t, string(sealed[:sealed_length]), string(HexBytes(RFC8448_C_RECORD)))

    // a damaged Finished is refused
    handshake.state = .WAIT_FINISHED
    bad: [4 + TLS_HASH_SIZE]byte = {20, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
    testing.expect(t, !TlsServerMessage(handshake, bad[:]))
}

@(test)
TlsClientHelloTest :: proc(t: ^testing.T) {
    handshake: ^TlsHandshake = new(TlsHandshake)
    defer free(handshake)
    hello: [512]byte
    random: [32]byte
    private: [32]byte
    for i in 0 ..< 32 {
        random[i] = u8(i)
        private[i] = u8(0x40 + i)
    }
    length: int = TlsClientHello(handshake, hello[:], "derp1.tailscale.com", random, private)
    // header: type 1 and the body length, then legacy version 3,3 and our random
    testing.expect_value(t, hello[0], u8(1))
    testing.expect_value(t, 4 + (int(hello[1]) << 16 | int(hello[2]) << 8 | int(hello[3])), length)
    testing.expect_value(t, hello[4], u8(3))
    testing.expect_value(t, hello[5], u8(3))
    testing.expect_value(t, string(hello[6:38]), string(random[:]))
    testing.expect(t, string(hello[:length]) != "")
    // the name is in the server_name extension and our public key in the key_share
    found_name: bool
    found_key: bool
    for i in 0 ..< length - 19 {
        found_name ||= string(hello[i:i + 19]) == "derp1.tailscale.com"
    }
    for i in 0 ..= length - 32 {
        found_key ||= string(hello[i:i + 32]) == string(handshake.public[:])
    }
    testing.expect(t, found_name && found_key)
    testing.expect_value(t, handshake.state, TlsState.WAIT_SERVER_HELLO)
}
