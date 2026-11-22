#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// Remembering a sign in between runs: the REFRESH token of the login (and what is needed to find the account again) in one small file of the user, so that the person signs in once. A refresh token is a
// credential: whoever has the file can get ID tokens as that person until the provider ends it (the same as the cookies of a browser). So: the file is in the per user configuration folder (never in a
// project or a repository), it is created readable by the user only (POSIX; on Windows the folder of the user is private to the user), only the refresh token is kept (no ID token, no access token, no
// client secret), a new refresh token replaces the old one when the provider rotates it, and it is deleted when the person signs out or the provider says no. No hidden allocation: the caller gives the
// buffer that the strings of what was read point into.
//
//     path, _ := StorePath("my_game")                              // <config folder>/my_game/signin.txt
//     StoreWrite(path, {provider = "Google", issuer = ..., client_id = ..., name = "Ada", refresh_token = tokens.refresh_token})
//     stored, found := StoreRead(path, buffer[:])                  // next run
//     StoreRemove(path)                                            // sign out

import "core:os"
import "core:strings"
import "core:testing"

STORE_HEADER :: "oidc-store-1"
STORE_MAX_SIZE :: 4096

Stored :: struct {
    provider: string,           // what the person chose (a label of the program's)
    issuer: string,
    client_id: string,
    name: string,               // how the program shows the person
    refresh_token: string,
}

// <the configuration folder of the user>/<app>/signin.txt (the folder is not the roaming one: a credential does not follow the person to other computers). Temp memory.
StorePath :: proc(app: string) -> (path: string, ok: bool) {
    if app == "" || strings.contains_any(app, "/\\:") { return "", false }
    folder, error := os.user_config_dir(context.temp_allocator)
    if error != nil || folder == "" { return "", false }
    return strings.concatenate({strings.trim_right(folder, "/\\"), "/", app, "/signin.txt"}, context.temp_allocator), true
}

@(private)
lineSafe :: proc(text: string) -> bool {
    return !strings.contains_any(text, "\r\n")
}

// Writes the file (the folder is made when it is missing). False when a field has a line break (the format is one value per line), there is no refresh token, or the file cannot be written.
StoreWrite :: proc(path: string, stored: Stored) -> bool {
    if stored.refresh_token == "" || stored.issuer == "" || stored.client_id == "" { return false }
    for field in ([]string{stored.provider, stored.issuer, stored.client_id, stored.name, stored.refresh_token}) {
        if !lineSafe(field) { return false }
    }
    slash: int = strings.last_index_byte(path, '/')
    if slash > 0 && os.make_directory_all(path[:slash]) != nil && !os.exists(path[:slash]) { return false }
    content: string = strings.concatenate({STORE_HEADER, "\nprovider=", stored.provider, "\nissuer=", stored.issuer, "\nclient_id=", stored.client_id, "\nname=", stored.name,
        "\nrefresh_token=", stored.refresh_token, "\n"}, context.temp_allocator)
    if len(content) > STORE_MAX_SIZE { return false }
    _ = os.remove(path)                                   // a shorter file written over a longer one must not keep the tail of it
    return os.write_entire_file(path, content, {.Read_User, .Write_User}) == nil
}

// Reads it: the strings of the result point into `buffer`. False when there is no file, it is not one of ours, it is too big or it lacks the issuer, the client id or the token.
StoreRead :: proc(path: string, buffer: []u8) -> (stored: Stored, ok: bool) {
    data, error := os.read_entire_file(path, context.temp_allocator)
    if error != nil || len(data) == 0 || len(data) > len(buffer) || len(data) > STORE_MAX_SIZE { return {}, false }
    copy(buffer, data)
    rest: string = string(buffer[:len(data)])
    first: bool = true
    for line in strings.split_lines_iterator(&rest) {
        trimmed: string = strings.trim_right(line, "\r")
        if first {
            if trimmed != STORE_HEADER { return {}, false }
            first = false
            continue
        }
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
    if first { return {}, false }
    return stored, stored.issuer != "" && stored.client_id != "" && stored.refresh_token != ""
}

StoreRemove :: proc(path: string) {
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

@(test)
test_a_stored_login_is_written_and_read_back :: proc(t: ^testing.T) {
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
    // a shorter login written over it keeps nothing of the first one
    testing.expect(t, StoreWrite(path, {provider = "G", issuer = "https://i", client_id = "c", refresh_token = "t"}))
    short, short_ok := StoreRead(path, buffer[:])
    testing.expect(t, short_ok)
    testing.expect_value(t, short.refresh_token, "t")
    testing.expect_value(t, short.name, "")
    data, _ := os.read_entire_file(path, context.temp_allocator)
    testing.expect(t, !strings.contains(string(data), "refresh-token_value") && !strings.contains(string(data), "Lovelace"), "no tail of the old file")
    // the file holds the refresh token and nothing else of the session
    testing.expect(t, !strings.contains(string(data), "eyJ") && !strings.contains(string(data), "secret"))
    // removing it
    StoreRemove(path)
    _, gone := StoreRead(path, buffer[:])
    testing.expect(t, !gone)
    StoreRemove(path)                                       // twice is harmless
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
    testing.expect(t, !os.exists(path), "nothing was written by the refused ones")
    // files that are not ours or not whole
    for content in ([]string{"", "not a store\nissuer=https://i\nclient_id=c\nrefresh_token=t\n", "oidc-store-1\nissuer=https://i\nclient_id=c\n", "oidc-store-1\nclient_id=c\nrefresh_token=t\n",
        "oidc-store-2\nissuer=https://i\nclient_id=c\nrefresh_token=t\n", "oidc-store-1\n"}) {
        os.make_directory_all(path[:strings.last_index_byte(path, '/')])
        _ = os.write_entire_file(path, content)
        _, ok := StoreRead(path, buffer[:])
        testing.expectf(t, !ok, "%q is refused", content)
    }
    // Windows line endings are fine
    _ = os.write_entire_file(path, "oidc-store-1\r\nissuer=https://i\r\nclient_id=c\r\nrefresh_token=t\r\n")
    crlf, crlf_ok := StoreRead(path, buffer[:])
    testing.expect(t, crlf_ok)
    testing.expect_value(t, crlf.refresh_token, "t")
    // a file bigger than the buffer, or than the limit, is refused (nothing is cut)
    small: [16]u8
    _, small_ok := StoreRead(path, small[:])
    testing.expect(t, !small_ok)
    huge: string = strings.repeat("a", STORE_MAX_SIZE, context.temp_allocator)
    testing.expect(t, !StoreWrite(path, {issuer = "https://i", client_id = "c", refresh_token = huge}))
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
