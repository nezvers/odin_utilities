package oidc

// A JWT (RFC 7519) read without allocation: `header.payload.signature`, each part base64url. This file is pure (no OS, no crypto, no allocation) so a SpacetimeDB module can read the claims of the
// JWT that its callers connected with (module.Jwt) and decide who may in. Verifying the signature is verify.odin, for programs that have crypto.
//
//     claims, ok := JwtClaimsRead(token, scratch[:])         // scratch: where the payload is decoded; the strings of `claims` point into it
//     if ok && claims.issuer == "https://auth.example.com" && JwtAudienceHas(claims, "my-game") { ... }

Jwt :: struct {
    header: string,             // the three parts as they are in the token (base64url text)
    payload: string,
    signature: string,
    signing_input: string,      // `header.payload`: what the signature is over
}

// The three parts of a token. False when it is not `a.b.c` (an unsigned token with an empty third part has `signature == ""` and is accepted here: verification refuses it)
JwtSplit :: proc(token: string) -> (jwt: Jwt, ok: bool) {
    first: int = -1
    second: int = -1
    for i in 0 ..< len(token) {
        if token[i] == '.' {
            if first < 0 { first = i } else if second < 0 { second = i } else { return {}, false }
        }
    }
    if first <= 0 || second < 0 || second == first + 1 { return {}, false }
    return {header = token[:first], payload = token[first + 1:second], signature = token[second + 1:], signing_input = token[:second]}, true
}

JwtHeader :: struct {
    algorithm: string,          // "ES256", "RS256", ... "none"
    key_id: string,
    type: string,
}

// The header of a token. `scratch` holds the decoded JSON; the strings point into it.
JwtHeaderRead :: proc(token: string, scratch: []u8) -> (header: JwtHeader, ok: bool) {
    jwt: Jwt = JwtSplit(token) or_return
    json, decoded := Base64UrlDecode(jwt.header, scratch)
    if !decoded { return {}, false }
    text: string = string(json)
    header.algorithm, _ = JsonString(text, "alg")
    header.key_id, _ = JsonString(text, "kid")
    header.type, _ = JsonString(text, "typ")
    return header, header.algorithm != ""
}

JwtClaims :: struct {
    payload: string,            // the JSON of the payload (all the claims: look up the others with JsonString / JsonInt)
    issuer: string,             // iss
    subject: string,            // sub
    audience: string,           // aud when it is one string (see JwtAudienceHas for a list)
    nonce: string,
    expires: i64,               // exp, seconds since the Unix epoch; 0: none
    issued: i64,                // iat
    not_before: i64,            // nbf
    has_expires: bool,
}

// The claims of a token (the signature is NOT looked at). `scratch` holds the decoded payload; the strings of the result point into it, so it has to live as long as they are used.
JwtClaimsRead :: proc(token: string, scratch: []u8) -> (claims: JwtClaims, ok: bool) {
    jwt: Jwt = JwtSplit(token) or_return
    return JwtPayloadClaims(jwt.payload, scratch)
}

// The same for the payload alone: base64url text (a token's second part), or, when it starts with `{`, the JSON itself (what `module.Jwt` gives: the host hands over the payload JSON)
JwtPayloadClaims :: proc(payload: string, scratch: []u8) -> (claims: JwtClaims, ok: bool) {
    json: string
    if len(payload) > 0 && payload[0] == '{' {
        json = payload
    } else {
        bytes, decoded := Base64UrlDecode(payload, scratch)
        if !decoded { return {}, false }
        json = string(bytes)
    }
    claims.payload = json
    claims.issuer, _ = JsonString(json, "iss")
    claims.subject, _ = JsonString(json, "sub")
    claims.audience, _ = JsonString(json, "aud")
    claims.nonce, _ = JsonString(json, "nonce")
    claims.expires, claims.has_expires = JsonInt(json, "exp")
    claims.issued, _ = JsonInt(json, "iat")
    claims.not_before, _ = JsonInt(json, "nbf")
    return claims, claims.issuer != "" && claims.subject != ""
}

// Is `wanted` the audience: `aud` is one string or an array of strings
JwtAudienceHas :: proc(claims: JwtClaims, wanted: string) -> bool {
    return JsonHasString(claims.payload, "aud", wanted)
}

// ---- a small JSON reader: the fields of the top level object, nothing allocated ---------------------------------------------------------------------------------------------

@(private)
skipSpace :: proc "contextless" (text: string, at: int) -> int {
    i: int = at
    for i < len(text) && (text[i] == ' ' || text[i] == '\n' || text[i] == '\r' || text[i] == '\t') { i += 1 }
    return i
}

// The end of the string that starts at `at` (the quote): the index after the closing quote
@(private)
stringEnd :: proc "contextless" (text: string, at: int) -> int {
    i: int = at + 1
    for i < len(text) {
        if text[i] == '\\' { i += 2; continue }
        if text[i] == '"' { return i + 1 }
        i += 1
    }
    return -1
}

// The end of any value that starts at `at`
@(private)
valueEnd :: proc "contextless" (text: string, at: int) -> int {
    if at >= len(text) { return -1 }
    switch text[at] {
    case '"': return stringEnd(text, at)
    case '{', '[':
        depth: int
        i: int = at
        for i < len(text) {
            switch text[i] {
            case '"':
                i = stringEnd(text, i)
                if i < 0 { return -1 }
                continue
            case '{', '[': depth += 1
            case '}', ']':
                depth -= 1
                if depth == 0 { return i + 1 }
            }
            i += 1
        }
        return -1
    }
    i: int = at
    for i < len(text) && text[i] != ',' && text[i] != '}' && text[i] != ']' && text[i] != ' ' && text[i] != '\n' { i += 1 }
    return i
}

// The raw text of the value of `key` in the top level object of `json` (a string keeps its quotes)
@(private)
JsonValue :: proc "contextless" (json: string, key: string) -> (value: string, ok: bool) {
    i: int = skipSpace(json, 0)
    if i >= len(json) || json[i] != '{' { return "", false }
    i += 1
    for {
        i = skipSpace(json, i)
        if i >= len(json) || json[i] == '}' { return "", false }
        if json[i] == ',' { i += 1; continue }
        if json[i] != '"' { return "", false }
        name_end: int = stringEnd(json, i)
        if name_end < 0 { return "", false }
        name: string = json[i + 1:name_end - 1]
        i = skipSpace(json, name_end)
        if i >= len(json) || json[i] != ':' { return "", false }
        i = skipSpace(json, i + 1)
        end: int = valueEnd(json, i)
        if end < 0 { return "", false }
        if name == key { return json[i:end], true }
        i = end
    }
}

// A string field without escapes in it (issuers, subjects, ids, names of algorithms have none): the text between the quotes. A value with a backslash is returned as it is written.
JsonString :: proc "contextless" (json: string, key: string) -> (value: string, ok: bool) {
    raw: string = JsonValue(json, key) or_return
    if len(raw) < 2 || raw[0] != '"' { return "", false }
    return raw[1:len(raw) - 1], true
}

// An integer field (a JWT time is one; a float of whole seconds is read up to its point)
JsonInt :: proc "contextless" (json: string, key: string) -> (value: i64, ok: bool) {
    raw: string = JsonValue(json, key) or_return
    negative: bool
    i: int
    if len(raw) > 0 && raw[0] == '-' { negative, i = true, 1 }
    if i >= len(raw) || raw[i] < '0' || raw[i] > '9' { return 0, false }
    for ; i < len(raw) && raw[i] >= '0' && raw[i] <= '9'; i += 1 { value = value * 10 + i64(raw[i] - '0') }
    return -value if negative else value, true
}

// Is `wanted` the value of the string field `key`, or one of the strings of an array in it
JsonHasString :: proc "contextless" (json: string, key: string, wanted: string) -> bool {
    raw, found := JsonValue(json, key)
    if !found || len(raw) == 0 { return false }
    if raw[0] == '"' { return len(raw) >= 2 && raw[1:len(raw) - 1] == wanted }
    if raw[0] != '[' { return false }
    i: int = 1
    for i < len(raw) {
        i = skipSpace(raw, i)
        if i < len(raw) && raw[i] == '"' {
            end: int = stringEnd(raw, i)
            if end < 0 { return false }
            if raw[i + 1:end - 1] == wanted { return true }
            i = end
        } else {
            i += 1
        }
    }
    return false
}
