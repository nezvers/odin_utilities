#+build linux, darwin, freebsd, openbsd, netbsd
package oidc

// The protection of the stored sign in where there is no DPAPI. The bytes are encrypted with a random key (ChaCha20-Poly1305, `store_aead.odin`) and the KEY is what the system keeps: the keychain of macOS
// (`security`) or the Secret Service of Linux (`secret-tool`, GNOME Keyring or KWallet). A copy of the store file is then useless without the login session of the person, like with DPAPI. Without the tool
// (a server without a desktop, a BSD) nothing is stored: `StoreAvailable` is false and the person signs in again at every start, never a plain file.
//
// NOT TESTED on macOS or Linux (written on Windows and cross checked with `odin check -target:...`; the sealing is tested everywhere, the calls of the tools are not). Known limits: on macOS the key (not the
// token) is an argument of `security add-generic-password` for a moment, so another process of the same user can see it in the process list while it is being stored (`security` cannot read a secret from a
// pipe); on Linux the key goes to `secret-tool` through its input. A program of the same user can ask the keychain for the key as well: this protects the file at rest, like DPAPI does.

import "core:crypto"
import "core:encoding/hex"
import "core:os"
import "core:strings"

@(private = "file")
KEY_SERVICE :: "odin_utilities.oidc.store"
@(private = "file")
KEY_ACCOUNT :: "store-key"

@(private = "file")
tool_checked: bool
@(private = "file")
tool_present: bool

// Is there a keychain tool that starts (checked once)
protectionAvailable :: proc() -> bool {
    if !tool_checked {
        tool_checked = true
        when ODIN_OS == .Darwin {
            tool_present = os.exists("/usr/bin/security")
        } else {
            // a lookup that finds nothing exits 1; a missing program is the error
            _, _, _, error := os.process_exec({command = {"secret-tool", "lookup", "service", KEY_SERVICE, "account", "probe"}}, context.temp_allocator)
            tool_present = error == nil
        }
    }
    return tool_present
}

// The key of the store from the keeper of the system; with `create` a new random one is stored when there is none. It is kept there as a 64 character hex text.
@(private = "file")
keyFetch :: proc(key: ^[AEAD_KEY]u8, create: bool) -> bool {
    if keyRead(key) { return true }
    if !create { return false }
    fresh: [AEAD_KEY]u8
    crypto.rand_bytes(fresh[:])
    defer crypto.zero_explicit(&fresh, size_of(fresh))
    if !keyWrite(fresh[:]) { return false }
    return keyRead(key)
}

@(private = "file")
keyRead :: proc(key: ^[AEAD_KEY]u8) -> bool {
    command: []string
    when ODIN_OS == .Darwin {
        command = {"security", "find-generic-password", "-s", KEY_SERVICE, "-a", KEY_ACCOUNT, "-w"}
    } else {
        command = {"secret-tool", "lookup", "service", KEY_SERVICE, "account", KEY_ACCOUNT}
    }
    state, output, _, error := os.process_exec({command = command}, context.temp_allocator)
    if error != nil || state.exit_code != 0 { return false }
    text: string = strings.trim_space(string(output))
    if len(text) != 2 * AEAD_KEY { return false }
    decoded, decode_error := hex.decode(transmute([]u8)text, context.temp_allocator)
    if decode_error != nil || len(decoded) != AEAD_KEY { return false }
    copy(key[:], decoded)
    return true
}

@(private = "file")
keyWrite :: proc(key: []u8) -> bool {
    text: string = string(hex.encode(key, context.temp_allocator))
    when ODIN_OS == .Darwin {
        state, _, _, error := os.process_exec({command = {"security", "add-generic-password", "-U", "-s", KEY_SERVICE, "-a", KEY_ACCOUNT, "-w", text}}, context.temp_allocator)
        return error == nil && state.exit_code == 0
    } else {
        reader, writer, pipe_error := os.pipe()
        if pipe_error != nil { return false }
        defer os.close(reader)
        _, _ = os.write_string(writer, text)                  // 64 characters: the pipe holds them until the tool reads
        os.close(writer)
        state, _, _, error := os.process_exec({command = {"secret-tool", "store", "--label=odin_utilities oidc store key", "service", KEY_SERVICE, "account", KEY_ACCOUNT}, stdin = reader}, context.temp_allocator)
        return error == nil && state.exit_code == 0
    }
}

@(private)
protect :: proc(plain: []u8, entropy: string, out: []u8) -> (cipher: []u8, ok: bool) {
    if !protectionAvailable() { return nil, false }
    key: [AEAD_KEY]u8
    defer crypto.zero_explicit(&key, size_of(key))
    if !keyFetch(&key, true) { return nil, false }
    return aeadSeal(key[:], plain, entropy, out)
}

@(private)
unprotect :: proc(cipher: []u8, entropy: string, out: []u8) -> (plain: []u8, ok: bool) {
    if !protectionAvailable() { return nil, false }
    key: [AEAD_KEY]u8
    defer crypto.zero_explicit(&key, size_of(key))
    if !keyFetch(&key, false) { return nil, false }
    return aeadOpen(key[:], cipher, entropy, out)
}
