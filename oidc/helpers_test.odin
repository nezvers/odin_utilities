#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "core:strings"
import "core:testing"
import "core:time"

// The small pieces that the login is built of, each on its own: addresses, percent encoding, forms, random text, PKCE, the JSON reader, the clock.

@(test)
test_urls_are_split_into_host_port_and_path :: proc(t: ^testing.T) {
    secure, secure_ok := UrlParse("https://auth.example.com/o/authorize?a=1&b=2")
    testing.expect(t, secure_ok && secure.secure)
    testing.expect_value(t, secure.host, "auth.example.com")
    testing.expect_value(t, secure.port, 443)
    testing.expect_value(t, secure.path, "/o/authorize?a=1&b=2")

    plain, plain_ok := UrlParse("http://127.0.0.1:48217/callback")
    testing.expect(t, plain_ok && !plain.secure)
    testing.expect_value(t, plain.host, "127.0.0.1")
    testing.expect_value(t, plain.port, 48217)
    testing.expect_value(t, plain.path, "/callback")

    bare, bare_ok := UrlParse("http://localhost")
    testing.expect(t, bare_ok)
    testing.expect_value(t, bare.port, 80)
    testing.expect_value(t, bare.path, "/")

    // an IPv6 address has colons of its own: only a port after the bracket is a port
    v6, v6_ok := UrlParse("http://[::1]:8080/x")
    testing.expect(t, v6_ok)
    testing.expect_value(t, v6.host, "[::1]")
    testing.expect_value(t, v6.port, 8080)
    v6_default, v6_default_ok := UrlParse("http://[::1]/x")
    testing.expect(t, v6_default_ok)
    testing.expect_value(t, v6_default.host, "[::1]")
    testing.expect_value(t, v6_default.port, 80)

    for bad in ([]string{"", "ftp://example.com", "example.com/path", "http://", "https:///path", "http://host:abc/", "javascript:alert(1)"}) {
        _, ok := UrlParse(bad)
        testing.expectf(t, !ok, "%q is not an address that can be requested", bad)
    }
}

@(test)
test_percent_encoding_and_forms :: proc(t: ^testing.T) {
    builder: strings.Builder
    defer strings.builder_destroy(&builder)
    UrlEncode("AZaz09-._~", &builder)
    testing.expect_value(t, strings.to_string(builder), "AZaz09-._~")
    strings.builder_reset(&builder)
    UrlEncode("a b&c=d/e?f#g+h%i", &builder)
    testing.expect_value(t, strings.to_string(builder), "a%20b%26c%3Dd%2Fe%3Ff%23g%2Bh%25i")
    strings.builder_reset(&builder)
    UrlEncode("é€", &builder)                      // UTF-8 bytes, each encoded
    testing.expect_value(t, strings.to_string(builder), "%C3%A9%E2%82%AC")
    strings.builder_reset(&builder)
    UrlEncode("", &builder)
    testing.expect_value(t, strings.builder_len(builder), 0)

    form: strings.Builder
    defer strings.builder_destroy(&form)
    FormField(&form, "grant_type", "authorization_code")
    FormField(&form, "redirect_uri", "http://127.0.0.1:1/cb")
    FormField(&form, "empty", "")
    testing.expect_value(t, strings.to_string(form), "grant_type=authorization_code&redirect_uri=http%3A%2F%2F127.0.0.1%3A1%2Fcb&empty=")
}

@(test)
test_query_values_are_found_and_decoded :: proc(t: ^testing.T) {
    out: [64]u8
    query: string = "code=ab%2Fc&state=x+y&empty=&error=access_denied&state=second"
    testing.expect_value(t, QueryValue(query, "code", out[:]), "ab/c")
    testing.expect_value(t, QueryValue(query, "state", out[:]), "x y")      // `+` is a space, and the first of two wins
    testing.expect_value(t, QueryValue(query, "empty", out[:]), "")
    testing.expect_value(t, QueryValue(query, "error", out[:]), "access_denied")
    testing.expect_value(t, QueryValue(query, "missing", out[:]), "")
    testing.expect_value(t, QueryValue(query, "cod", out[:]), "")           // a name is not a prefix match
    testing.expect_value(t, QueryValue("", "code", out[:]), "")
    // an escape that is not one stays as it is; one at the very end is decoded
    testing.expect_value(t, QueryValue("a=100%&b=%zz&c=%41", "a", out[:]), "100%")
    testing.expect_value(t, QueryValue("a=100%&b=%zz&c=%41", "b", out[:]), "%zz")
    testing.expect_value(t, QueryValue("a=100%&b=%zz&c=%41", "c", out[:]), "A")
    // the output is the caller's: a value that does not fit is cut, never written past the end
    small: [4]u8
    testing.expect_value(t, QueryValue("v=abcdefgh", "v", small[:]), "abcd")
}

@(test)
test_the_length_of_base64url_text :: proc(t: ^testing.T) {
    expected := [?]struct { bytes, length: int }{{0, 0}, {1, 2}, {2, 3}, {3, 4}, {4, 6}, {32, 43}, {64, 86}}
    for item in expected {
        testing.expect_value(t, Base64UrlLength(item.bytes), item.length)
        source := make([]u8, item.bytes)
        defer delete(source)
        text := make([]u8, Base64UrlLength(item.bytes))
        defer delete(text)
        testing.expect_value(t, len(Base64UrlEncode(source, text)), item.length)
    }
    // too small a buffer: nothing is written, the result is empty
    tiny: [3]u8
    testing.expect_value(t, len(Base64UrlEncode({1, 2, 3, 4}, tiny[:])), 0)
}

@(test)
test_random_text_is_random_url_safe_and_the_right_length :: proc(t: ^testing.T) {
    first: [128]u8
    second: [128]u8
    a: string = RandomText(32, first[:])
    b: string = RandomText(32, second[:])
    testing.expect_value(t, len(a), 43)
    testing.expect(t, a != b, "two draws differ")
    for c in transmute([]u8)a {
        ok: bool = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_'
        testing.expectf(t, ok, "%c is url safe", c)
    }
    // more than the 64 bytes that one draw gives is clamped
    big: [256]u8
    testing.expect_value(t, len(RandomText(500, big[:])), 86)
    testing.expect_value(t, len(RandomText(0, big[:])), 0)
}

@(test)
test_pkce_follows_rfc_7636 :: proc(t: ^testing.T) {
    // the example of RFC 7636 appendix B
    out: [64]u8
    testing.expect_value(t, PkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", out[:]), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    // a verifier is 43 characters (32 random bytes), within the 43..128 that the RFC allows, and is different every time
    one: [64]u8
    two: [64]u8
    v1: string = PkceVerifier(one[:])
    v2: string = PkceVerifier(two[:])
    testing.expect(t, len(v1) >= 43 && len(v1) <= 128)
    testing.expect(t, v1 != v2)
    testing.expect_value(t, len(PkceChallenge(v1, out[:])), 43)
}

@(test)
test_the_header_of_a_token :: proc(t: ^testing.T) {
    scratch: [256]u8
    encoded: [256]u8
    header_json: string = `{"alg":"RS256","kid":"key-1","typ":"JWT"}`
    token: string = strings.concatenate({Base64UrlEncode(transmute([]u8)header_json, encoded[:]), ".e30.sig"}, context.temp_allocator)
    header, ok := JwtHeaderRead(token, scratch[:])
    testing.expect(t, ok)
    testing.expect_value(t, header.algorithm, "RS256")
    testing.expect_value(t, header.key_id, "key-1")
    testing.expect_value(t, header.type, "JWT")

    // without `alg` it is not a usable header; a header that is not base64url is not either; a token with no dots has no header
    no_alg: string = `{"kid":"k"}`
    token = strings.concatenate({Base64UrlEncode(transmute([]u8)no_alg, encoded[:]), ".e30.sig"}, context.temp_allocator)
    _, ok = JwtHeaderRead(token, scratch[:])
    testing.expect(t, !ok)
    _, ok = JwtHeaderRead("!!!.e30.sig", scratch[:])
    testing.expect(t, !ok)
    _, ok = JwtHeaderRead("nodots", scratch[:])
    testing.expect(t, !ok)
    // a decoded header that does not fit the scratch is refused, not cut
    tiny: [4]u8
    _, ok = JwtHeaderRead(strings.concatenate({Base64UrlEncode(transmute([]u8)header_json, encoded[:]), ".e30.sig"}, context.temp_allocator), tiny[:])
    testing.expect(t, !ok)
}

@(test)
test_the_json_reader_for_numbers_and_lists :: proc(t: ^testing.T) {
    json: string = `{"exp": 1893456000, "neg": -5, "frac": 1700000000.75, "text": "12", "aud": ["a", "b c", "d"], "one": "solo", "nested": {"exp": 7}}`
    exp, has_exp := JsonInt(json, "exp")
    testing.expect(t, has_exp)
    testing.expect_value(t, exp, 1893456000)                // the top level one, not the one in `nested`
    neg, _ := JsonInt(json, "neg")
    testing.expect_value(t, neg, -5)
    frac, has_frac := JsonInt(json, "frac")
    testing.expect(t, has_frac)
    testing.expect_value(t, frac, 1700000000)               // read up to the point
    _, has_text := JsonInt(json, "text")
    testing.expect(t, !has_text, "a string is not a number")
    _, has_missing := JsonInt(json, "missing")
    testing.expect(t, !has_missing)

    testing.expect(t, JsonHasString(json, "aud", "a"))
    testing.expect(t, JsonHasString(json, "aud", "b c"))
    testing.expect(t, JsonHasString(json, "aud", "d"))
    testing.expect(t, !JsonHasString(json, "aud", "b"), "a part of an element is not an element")
    testing.expect(t, !JsonHasString(json, "aud", "x"))
    testing.expect(t, JsonHasString(json, "one", "solo"))
    testing.expect(t, !JsonHasString(json, "one", "sol"))
    testing.expect(t, !JsonHasString(json, "exp", "1893456000"), "a number is not a string")
    testing.expect(t, !JsonHasString(json, "missing", "a"))
    testing.expect(t, !JsonHasString("not json", "aud", "a"))
}

@(test)
test_the_clock_of_the_library_is_the_clock :: proc(t: ^testing.T) {
    now: i64 = NowUnix()
    expected: i64 = time.to_unix_seconds(time.now())
    testing.expect(t, now >= expected - 2 && now <= expected + 2)
    testing.expect(t, now > 1_700_000_000, "after 2023")
}
