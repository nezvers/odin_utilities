package oidc

// base64url (RFC 4648 section 5, no padding): what a JWT is made of. Pure: caller buffers, no allocation, builds for every target (a SpacetimeDB module reads the claims of its callers with it).

@(private)
ALPHABET :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

// The size of the base64url text of `bytes` bytes
Base64UrlLength :: proc(bytes: int) -> int {
    return (bytes * 4 + 2) / 3
}

// Writes the base64url of `source` into `destination` (it needs Base64UrlLength(len(source)) bytes); returns the text, a slice of destination. Empty when it does not fit.
Base64UrlEncode :: proc(source: []u8, destination: []u8) -> string {
    if len(destination) < Base64UrlLength(len(source)) { return "" }
    alphabet: string = ALPHABET
    at: int
    i: int
    for ; i + 3 <= len(source); i += 3 {
        value: u32 = u32(source[i]) << 16 | u32(source[i + 1]) << 8 | u32(source[i + 2])
        destination[at], destination[at + 1], destination[at + 2], destination[at + 3] = alphabet[value >> 18 & 63], alphabet[value >> 12 & 63], alphabet[value >> 6 & 63], alphabet[value & 63]
        at += 4
    }
    switch len(source) - i {
    case 1:
        value: u32 = u32(source[i]) << 16
        destination[at], destination[at + 1] = alphabet[value >> 18 & 63], alphabet[value >> 12 & 63]
        at += 2
    case 2:
        value: u32 = u32(source[i]) << 16 | u32(source[i + 1]) << 8
        destination[at], destination[at + 1], destination[at + 2] = alphabet[value >> 18 & 63], alphabet[value >> 12 & 63], alphabet[value >> 6 & 63]
        at += 3
    }
    return string(destination[:at])
}

@(private)
sextet :: proc "contextless" (c: u8) -> (value: u32, ok: bool) {
    switch c {
    case 'A' ..= 'Z': return u32(c - 'A'), true
    case 'a' ..= 'z': return u32(c - 'a' + 26), true
    case '0' ..= '9': return u32(c - '0' + 52), true
    case '-': return 62, true
    case '_': return 63, true
    }
    return 0, false
}

// The bytes of a base64url text (padding with `=` is tolerated) into `destination`: the part that was written. `ok` is false for a letter that is not in the alphabet or a destination that is too small.
Base64UrlDecode :: proc(text: string, destination: []u8) -> (decoded: []u8, ok: bool) {
    length: int = len(text)
    for length > 0 && text[length - 1] == '=' { length -= 1 }
    if length % 4 == 1 { return nil, false }
    if len(destination) < length * 3 / 4 { return nil, false }
    at: int
    bits: u32
    count: int
    for i in 0 ..< length {
        value, valid := sextet(text[i])
        if !valid { return nil, false }
        bits = bits << 6 | value
        count += 1
        if count == 4 {
            destination[at], destination[at + 1], destination[at + 2] = u8(bits >> 16), u8(bits >> 8), u8(bits)
            at += 3
            bits, count = 0, 0
        }
    }
    switch count {
    case 2: destination[at] = u8(bits >> 4); at += 1
    case 3: destination[at], destination[at + 1] = u8(bits >> 10), u8(bits >> 2); at += 2
    }
    return destination[:at], true
}
