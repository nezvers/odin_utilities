#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// Remembering a sign in between runs: the REFRESH token of the login (and what is needed to find the account again) in one small file of the user, so that the person signs in once.
//
// A refresh token is a credential, so it is never stored as plain text. The whole content (token, provider, issuer, client id, name) is ENCRYPTED by the operating system with a key of the logged in user:
// on Windows DPAPI (protect_windows.odin). A copy of the file, a backup, a sync folder or a stolen disk gives nothing: it cannot be decrypted on another computer or under another account. What this does not
// stop is a program that runs as the same user on the same computer (it can ask Windows to decrypt, like it could read the memory of this program). Where the system has no such protection (macOS and Linux have one in protect_other.odin, untested there; a system without its tool) NOTHING is stored: `StoreAvailable` is false, `StoreWrite` is false, and the person signs in at every start. A file of the earlier plain text format is overwritten and deleted when
// it is found. The file is in the per user configuration folder, never in a project; it holds no ID token, no access token and no client secret; the buffers that held the token are wiped after use; a new
// refresh token replaces the old one when the provider rotates it; it is deleted when the person signs out or the provider says no. No hidden allocation: the caller gives the buffer that the strings of what
// was read point into (wipe it when done: `StoreWipe`).
//
//     if StoreAvailable() {
//         path, _ := StorePath("my_game")                          // <config folder>/my_game/signin.txt
//         StoreWrite(path, {provider = "Google", issuer = ..., client_id = ..., name = "Ada", refresh_token = tokens.refresh_token})
//         stored, found := StoreRead(path, buffer[:])              // next run
//         StoreWipe(buffer[:])
//         StoreRemove(path)                                        // sign out
//     }

import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

STORE_MAGIC :: "oidc-store-2\n"                 // the only plain part of the file: it says whose it is
STORE_LEGACY :: "oidc-store-1"                  // the first format, plain text: refused, overwritten and deleted
STORE_ENTROPY :: "odin_utilities.oidc.store.2"  // an extra secret of the library for the protection
STORE_MAX_SIZE :: 4096                          // the plain content
STORE_FILE_MAX :: 8192                          // the file (encrypted content is bigger)

Stored :: struct {
    provider: string,           // what the person chose (a label of the program's)
    issuer: string,
    client_id: string,
    name: string,               // how the program shows the person
    refresh_token: string,
}

// Can this system keep a sign in safely: false means that nothing is stored (see above)
StoreAvailable :: proc() -> bool {
    return protectionAvailable()
}

// Overwrites a buffer with zeros so that the compiler does not drop it (a token must not stay in memory that is reused)
StoreWipe :: proc(buffer: []u8) {
    mem.zero_explicit(raw_data(buffer), len(buffer))
}

// <the configuration folder of the user>/<app>/signin.txt (the folder is not the roaming one: a credential does not follow the person to other computers). Temp memory.
StorePath :: proc(app: string) -> (path: string, ok: bool) {
    if app == "" || strings.contains_any(app, "/\\:") { return "", false }
    folder, error := os.user_config_dir(context.temp_allocator)
    if error != nil || folder == "" { return "", false }
    return strings.concatenate({strings.trim_right(folder, "/\\"), "/", app, "/signin.txt"}, context.temp_allocator), true
}

// The file of one provider next to the base path: `.../signin.txt` becomes `.../signin_<key>.txt`, the key being the label in lower case letters and digits (any other run of characters is one `_`).
// Two windows of the program that are signed in with different accounts then keep their own files: the one that signs in last does not replace the other's. Temp memory.
StoreVariant :: proc(path: string, label: string) -> string {
    key: strings.Builder
    strings.builder_init(&key, context.temp_allocator)
    pending_separator: bool
    for c in transmute([]u8)label {
        switch c {
        case 'a' ..= 'z', '0' ..= '9':
            if pending_separator && strings.builder_len(key) > 0 { strings.write_byte(&key, '_') }
            pending_separator = false
            strings.write_byte(&key, c)
        case 'A' ..= 'Z':
            if pending_separator && strings.builder_len(key) > 0 { strings.write_byte(&key, '_') }
            pending_separator = false
            strings.write_byte(&key, c + 32)
        case:
            pending_separator = true
        }
    }
    name: string = strings.to_string(key) if strings.builder_len(key) > 0 else "default"
    dot: int = strings.last_index_byte(path, '.')
    slash: int = strings.last_index_byte(path, '/')
    if dot > slash && dot >= 0 { return strings.concatenate({path[:dot], "_", name, path[dot:]}, context.temp_allocator) }
    return strings.concatenate({path, "_", name}, context.temp_allocator)
}

// When the file was written last (the program restores the account that was used last)
StoreModified :: proc(path: string) -> (modified: time.Time, ok: bool) {
    info, error := os.stat(path, context.temp_allocator)
    if error != nil { return {}, false }
    return info.modification_time, true
}

@(private)
lineSafe :: proc(text: string) -> bool {
    return !strings.contains_any(text, "\r\n")
}

// Writes the file, encrypted (the folder is made when it is missing). False when nothing can be kept safely here (no protection), a field has a line break (the content is one value per line), there is
// no refresh token, or the file cannot be written. Nothing is written in those cases.
StoreWrite :: proc(path: string, stored: Stored) -> bool {
    if !StoreAvailable() { return false }
    if stored.refresh_token == "" || stored.issuer == "" || stored.client_id == "" { return false }
    for field in ([]string{stored.provider, stored.issuer, stored.client_id, stored.name, stored.refresh_token}) {
        if !lineSafe(field) { return false }
    }
    plain: string = strings.concatenate({"provider=", stored.provider, "\nissuer=", stored.issuer, "\nclient_id=", stored.client_id, "\nname=", stored.name, "\nrefresh_token=", stored.refresh_token, "\n"}, context.temp_allocator)
    defer StoreWipe(transmute([]u8)plain)
    if len(plain) > STORE_MAX_SIZE { return false }
    cipher_buffer: [STORE_FILE_MAX]u8
    cipher, protected := protect(transmute([]u8)plain, STORE_ENTROPY, cipher_buffer[:])
    if !protected { return false }
    slash: int = strings.last_index_byte(path, '/')
    if slash > 0 && os.make_directory_all(path[:slash]) != nil && !os.exists(path[:slash]) { return false }
    file := make([]u8, len(STORE_MAGIC) + len(cipher), context.temp_allocator)
    copy(file, STORE_MAGIC)
    copy(file[len(STORE_MAGIC):], cipher)
    _ = os.remove(path)                                   // a shorter file written over a longer one must not keep the tail of it
    return os.write_entire_file(path, file, {.Read_User, .Write_User}) == nil
}

// Reads and decrypts it: the strings of the result point into `buffer`. False when there is no file, it is not one of ours, it was made under another account or computer, it was changed, `buffer` is too
// small, or the content lacks the issuer, the client id or the token. A file of the first (plain text) format is overwritten and deleted: it is a credential that was left readable.
StoreRead :: proc(path: string, buffer: []u8) -> (stored: Stored, ok: bool) {
    data, error := os.read_entire_file(path, context.temp_allocator)
    if error != nil || len(data) == 0 || len(data) > len(STORE_MAGIC) + STORE_FILE_MAX { return {}, false }
    if strings.has_prefix(string(data), STORE_LEGACY) {
        scrub(path, len(data))
        return {}, false
    }
    if !strings.has_prefix(string(data), STORE_MAGIC) || len(data) == len(STORE_MAGIC) { return {}, false }
    plain, unprotected := unprotect(data[len(STORE_MAGIC):], STORE_ENTROPY, buffer)
    if !unprotected { return {}, false }
    rest: string = string(plain)
    for line in strings.split_lines_iterator(&rest) {
        trimmed: string = strings.trim_right(line, "\r")
        equals: int = strings.index_byte(trimmed, '=')
        if equals < 0 { continue }
        value: string = trimmed[equals + 1:]
        switch trimmed[:equals] {
        case "provider": stored.provider = value
        case "issuer": stored.issuer = value
        case "client_id": stored.client_id = value
        case "name": stored.name = value
        case "refresh_token": stored.refresh_token = value
        }
    }
    return stored, stored.issuer != "" && stored.client_id != "" && stored.refresh_token != ""
}

StoreRemove :: proc(path: string) {
    _ = os.remove(path)
}

@(private = "file")
scrub :: proc(path: string, size: int) {
    zeros := make([]u8, size, context.temp_allocator)
    _ = os.write_entire_file(path, zeros)
    _ = os.remove(path)
}

@(private = "file")
testPath :: proc(name: string) -> string {
    folder, _ := os.temp_directory(context.temp_allocator)
    return strings.concatenate({strings.trim_right(folder, "/\\"), "/oidc_store_test_", name, "/signin.txt"}, context.temp_allocator)
}

@(private = "file")
testClean :: proc(path: string) {
    StoreRemove(path)
    slash: int = strings.last_index_byte(path, '/')
    _ = os.remove(path[:slash])
}

// A system without the protection stores nothing, and says so: never a plain file
@(test)
test_without_a_protection_nothing_is_stored :: proc(t: ^testing.T) {
    if StoreAvailable() { return }
    path: string = testPath("unavailable")
    defer testClean(path)
    testing.expect(t, !StoreWrite(path, {provider = "G", issuer = "https://i", client_id = "c", refresh_token = "t"}))
    testing.expect(t, !os.exists(path), "no file, and certainly no plain one")
}

@(test)
test_a_stored_login_is_written_and_read_back :: proc(t: ^testing.T) {
    if !StoreAvailable() { return }
    path: string = testPath("roundtrip")
    defer testClean(path)
    stored: Stored = {provider = "Google", issuer = "https://accounts.google.com", client_id = "id-1", name = "Ada Lovelace", refresh_token = "1//refresh-token_value"}
    testing.expect(t, StoreWrite(path, stored))
    buffer: [STORE_MAX_SIZE]u8
    read, ok := StoreRead(path, buffer[:])
    testing.expect(t, ok)
    testing.expect_value(t, read.provider, "Google")
    testing.expect_value(t, read.issuer, "https://accounts.google.com")
    testing.expect_value(t, read.client_id, "id-1")
    testing.expect_value(t, read.name, "Ada Lovelace")
    testing.expect_value(t, read.refresh_token, "1//refresh-token_value")
    StoreWipe(buffer[:])
    testing.expect_value(t, buffer[0], 0)
    // a shorter login written over it keeps nothing of the first one
    testing.expect(t, StoreWrite(path, {provider = "G", issuer = "https://i", client_id = "c", refresh_token = "t"}))
    short, short_ok := StoreRead(path, buffer[:])
    testing.expect(t, short_ok)
    testing.expect_value(t, short.refresh_token, "t")
    testing.expect_value(t, short.name, "")
    // removing it
    StoreRemove(path)
    _, gone := StoreRead(path, buffer[:])
    testing.expect(t, !gone)
    StoreRemove(path)                                       // twice is harmless
}

// The point of it all: what is on the disk says nothing
@(test)
test_the_file_on_the_disk_is_encrypted :: proc(t: ^testing.T) {
    if !StoreAvailable() { return }
    path: string = testPath("encrypted")
    defer testClean(path)
    testing.expect(t, StoreWrite(path, {provider = "Google", issuer = "https://accounts.google.com", client_id = "client-id-123", name = "Ada Lovelace", refresh_token = "1//SECRET-refresh-token-value"}))
    data, error := os.read_entire_file(path, context.temp_allocator)
    testing.expect(t, error == nil)
    text: string = string(data)
    testing.expect(t, strings.has_prefix(text, STORE_MAGIC), "it says whose it is")
    for secret in ([]string{"SECRET", "refresh-token", "refresh_token", "accounts.google.com", "client-id-123", "Ada", "Lovelace", "Google", "issuer", "client_id", "provider"}) {
        testing.expectf(t, !strings.contains(text, secret), "%q is not readable in the file", secret)
    }
    // the same content gives another file each time? (not required) but it is bigger than the magic and not the content
    testing.expect(t, len(data) > len(STORE_MAGIC) + 40)
}

@(test)
test_a_changed_or_foreign_file_does_not_decrypt :: proc(t: ^testing.T) {
    if !StoreAvailable() { return }
    path: string = testPath("tampered")
    defer testClean(path)
    testing.expect(t, StoreWrite(path, {provider = "G", issuer = "https://i", client_id = "c", refresh_token = "token"}))
    original, _ := os.read_entire_file(path, context.temp_allocator)
    buffer: [STORE_MAX_SIZE]u8
    // a changed byte anywhere in the encrypted part
    for position in ([]int{len(STORE_MAGIC), len(STORE_MAGIC) + 20, len(original) - 1}) {
        changed := make([]u8, len(original), context.temp_allocator)
        copy(changed, original)
        changed[position] ~= 0x01
        _ = os.write_entire_file(path, changed)
        _, ok := StoreRead(path, buffer[:])
        testing.expectf(t, !ok, "a changed byte at %d is refused", position)
    }
    // cut short
    _ = os.write_entire_file(path, original[:len(original) - 10])
    _, cut_ok := StoreRead(path, buffer[:])
    testing.expect(t, !cut_ok, "a truncated file is refused")
    // the program's own entropy is part of the key: the same bytes do not decrypt without it
    plain_out: [STORE_FILE_MAX]u8
    _, decrypted := unprotect(original[len(STORE_MAGIC):], "another entropy", plain_out[:])
    testing.expect(t, !decrypted, "another program of the same user does not decrypt it the plain way")
    _, right := unprotect(original[len(STORE_MAGIC):], STORE_ENTROPY, plain_out[:])
    testing.expect(t, right, "and with the entropy of the library it does")
    StoreWipe(plain_out[:])
    // a buffer that is too small for the content: refused, nothing cut
    _ = os.write_entire_file(path, original)
    small: [8]u8
    _, small_ok := StoreRead(path, small[:])
    testing.expect(t, !small_ok)
}

// The first version kept the token as plain text: such a file is not read, it is overwritten and deleted
@(test)
test_a_plain_text_file_of_the_first_format_is_scrubbed :: proc(t: ^testing.T) {
    path: string = testPath("legacy")
    defer testClean(path)
    legacy: string = "oidc-store-1\nprovider=G\nissuer=https://i\nclient_id=c\nname=Ada\nrefresh_token=PLAIN-TOKEN\n"
    os.make_directory_all(path[:strings.last_index_byte(path, '/')])
    _ = os.write_entire_file(path, legacy)
    buffer: [STORE_MAX_SIZE]u8
    _, ok := StoreRead(path, buffer[:])
    testing.expect(t, !ok, "a plain file is not accepted")
    testing.expect(t, !os.exists(path), "and it is deleted")
}

@(test)
test_a_stored_login_that_is_not_ours_or_not_whole_is_refused :: proc(t: ^testing.T) {
    path: string = testPath("refused")
    defer testClean(path)
    buffer: [STORE_MAX_SIZE]u8
    _, found := StoreRead(path, buffer[:])
    testing.expect(t, !found, "no file")
    // a value with a line break would make a second field: refused when written
    testing.expect(t, !StoreWrite(path, {provider = "x", issuer = "https://i", client_id = "c", refresh_token = "t\nissuer=https://evil"}))
    testing.expect(t, !StoreWrite(path, {provider = "x\r", issuer = "https://i", client_id = "c", refresh_token = "t"}))
    testing.expect(t, !StoreWrite(path, {issuer = "https://i", client_id = "c"}), "no refresh token: nothing to keep")
    testing.expect(t, !StoreWrite(path, {issuer = "", client_id = "c", refresh_token = "t"}))
    huge: string = strings.repeat("a", STORE_MAX_SIZE, context.temp_allocator)
    testing.expect(t, !StoreWrite(path, {issuer = "https://i", client_id = "c", refresh_token = huge}))
    testing.expect(t, !os.exists(path), "nothing was written by the refused ones")
    // files that are not ours
    for content in ([]string{"", "not a store", "oidc-store-2\n", "oidc-store-2\nnot encrypted at all: refresh_token=t", "oidc-store-3\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}) {
        os.make_directory_all(path[:strings.last_index_byte(path, '/')])
        _ = os.write_entire_file(path, content)
        _, ok := StoreRead(path, buffer[:])
        testing.expectf(t, !ok, "%q is refused", content)
    }
    // a file that is far too big is refused without being read into the buffer
    big := make([]u8, STORE_FILE_MAX + 100, context.temp_allocator)
    copy(big, STORE_MAGIC)
    _ = os.write_entire_file(path, big)
    _, big_ok := StoreRead(path, buffer[:])
    testing.expect(t, !big_ok)
}

@(test)
test_every_provider_has_its_own_file :: proc(t: ^testing.T) {
    testing.expect_value(t, StoreVariant("a/b/signin.txt", "Google"), "a/b/signin_google.txt")
    testing.expect_value(t, StoreVariant("a/b/signin.txt", "Mock account"), "a/b/signin_mock_account.txt")
    testing.expect_value(t, StoreVariant("a/b/signin.txt", "  Space-Time Auth!! "), "a/b/signin_space_time_auth.txt")
    testing.expect_value(t, StoreVariant("a/b/signin.txt", "../../x"), "a/b/signin_x.txt")                 // the label cannot climb out of the folder
    testing.expect_value(t, StoreVariant("a/b/signin.txt", ""), "a/b/signin_default.txt")
    testing.expect_value(t, StoreVariant("a/b/signin.txt", "***"), "a/b/signin_default.txt")
    testing.expect_value(t, StoreVariant("a.b/signin", "Discord"), "a.b/signin_discord")                  // a dot in the folder is not an extension
    testing.expect(t, StoreVariant("a/signin.txt", "Google") != StoreVariant("a/signin.txt", "Discord"), "two providers, two files")
}

@(test)
test_the_time_of_the_last_write_is_known :: proc(t: ^testing.T) {
    path: string = testPath("modified")
    defer testClean(path)
    _, missing := StoreModified(path)
    testing.expect(t, !missing)
    os.make_directory_all(path[:strings.last_index_byte(path, '/')])
    _ = os.write_entire_file(path, "a")
    first, first_ok := StoreModified(path)
    testing.expect(t, first_ok)
    time.sleep(30 * time.Millisecond)
    _ = os.write_entire_file(path, "b")
    second, second_ok := StoreModified(path)
    testing.expect(t, second_ok && time.diff(first, second) > 0, "a later write is later")
}

@(test)
test_the_store_path_is_in_the_user_folder_under_the_app :: proc(t: ^testing.T) {
    path, ok := StorePath("odin_test_app")
    testing.expect(t, ok)
    testing.expect(t, strings.has_suffix(path, "/odin_test_app/signin.txt"))
    folder, _ := os.user_config_dir(context.temp_allocator)
    testing.expect(t, strings.has_prefix(path, strings.trim_right(folder, "/\\")), "inside the configuration folder of the user")
    // an app name cannot climb out of its folder or name a drive
    for bad in ([]string{"", "../x", "a/b", "a\\b", "c:x"}) {
        _, bad_ok := StorePath(bad)
        testing.expectf(t, !bad_ok, "%q is not an app name", bad)
    }
}
