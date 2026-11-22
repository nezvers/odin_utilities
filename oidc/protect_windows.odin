#+build windows
package oidc

// The protection of the stored sign in on Windows: DPAPI (`CryptProtectData`). The bytes are encrypted with a key that Windows keeps for the logged in user: a copy of the file is useless on another computer
// and under another account (this is what browsers do for their saved passwords). `entropy` is an extra secret of the program that the call asks for: another program of the same user does not decrypt it by
// calling DPAPI the plain way. A program that runs as the same user, on the same computer, can still ask Windows to decrypt for it: this protects the file at rest (a copy, a backup, a stolen disk, a sync
// folder), not a process of the person that is hostile. UI is forbidden (no prompt can appear).

import win "core:sys/windows"

@(private = "file")
DataBlob :: struct {
    size: u32,
    data: [^]u8,
}

@(private = "file")
CRYPTPROTECT_UI_FORBIDDEN :: 0x1

foreign import crypt32 "system:Crypt32.lib"

@(private = "file")
@(default_calling_convention = "system")
foreign crypt32 {
    CryptProtectData :: proc(data_in: ^DataBlob, description: [^]u16, entropy: ^DataBlob, reserved: rawptr, prompt: rawptr, flags: u32, data_out: ^DataBlob) -> i32 ---
    CryptUnprotectData :: proc(data_in: ^DataBlob, description: ^[^]u16, entropy: ^DataBlob, reserved: rawptr, prompt: rawptr, flags: u32, data_out: ^DataBlob) -> i32 ---
}

// Is there a protection on this system
protectionAvailable :: proc() -> bool {
    return true
}

// Encrypts `plain` into `out` (the result is a slice of it). False when it does not fit or Windows refuses.
@(private)
protect :: proc(plain: []u8, entropy: string, out: []u8) -> (cipher: []u8, ok: bool) {
    input: DataBlob = {u32(len(plain)), raw_data(plain)}
    extra: DataBlob = {u32(len(entropy)), raw_data(transmute([]u8)entropy)}
    output: DataBlob
    if CryptProtectData(&input, nil, &extra, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, &output) == 0 { return nil, false }
    defer win.LocalFree(output.data)
    if int(output.size) > len(out) { return nil, false }
    copy(out, output.data[:output.size])
    return out[:output.size], true
}

// Decrypts what `protect` made, for this user and this `entropy` (a changed byte, another user, another entropy: false). The result is a slice of `out`.
@(private)
unprotect :: proc(cipher: []u8, entropy: string, out: []u8) -> (plain: []u8, ok: bool) {
    input: DataBlob = {u32(len(cipher)), raw_data(cipher)}
    extra: DataBlob = {u32(len(entropy)), raw_data(transmute([]u8)entropy)}
    output: DataBlob
    if CryptUnprotectData(&input, nil, &extra, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, &output) == 0 { return nil, false }
    defer {
        // the plain text that Windows allocated is wiped before it is given back
        for i in 0 ..< int(output.size) { output.data[i] = 0 }
        win.LocalFree(output.data)
    }
    if int(output.size) > len(out) { return nil, false }
    copy(out, output.data[:output.size])
    return out[:output.size], true
}
