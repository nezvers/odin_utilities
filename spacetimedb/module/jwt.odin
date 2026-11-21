package spacetimedb_module

// Who a caller is, as the provider that signed its token says: the host keeps the JWT of every connection and hands its payload to a reducer (`get_jwt`). SpacetimeDB checks the signature and the
// expiry when the client connects, accepts a token of ANY provider that serves the discovery document, and does not check `aud`: a module that cares about who may in checks `iss` and `aud` itself,
// in `identity_connected` (docs: authentication/usage). `RequireClaims` is that check; `Claims` gives the claims to a module that wants more (a name, an email, a role).
// The reading of the JSON is odin_utilities/oidc (its pure part, which builds for wasm).

import "../../oidc"
import "../bsatn"

@(private)
jwt_buffer: [4096]u8
@(private)
jwt_scratch: [4096]u8

// The claims of the token that `connection` was made with. `ok` is false when there is none (a connection that the host made itself) or it cannot be read. The strings point into a buffer of the
// module: good until the next call.
Claims :: proc(connection: bsatn.ConnectionId) -> (claims: oidc.JwtClaims, ok: bool) {
    connection := connection
    source: BytesSource
    if host_get_jwt(raw_data(connection[:]), &source) != 0 || source == 0 { return {}, false }
    length: int
    for {
        count: uint = uint(len(jwt_buffer) - length)
        if count == 0 { return {}, false }
        result: i16 = host_bytes_source_read(source, raw_data(jwt_buffer[length:]), &count)
        length += int(count)
        if result == -1 { break }
        if result != 0 { return {}, false }
    }
    return oidc.JwtPayloadClaims(string(jwt_buffer[:length]), jwt_scratch[:])
}

// "" when the caller's token comes from an issuer in `issuers` (an empty list: any) and is for `audience` ("": any), else the text of the refusal. Call it first in `identity_connected` and return its
// text: the connection is refused. A connection that has no token claims (the server's own anonymous identities carry the server as issuer) passes only when `issuers` is empty.
RequireClaims :: proc(ctx: ^ReducerContext, issuers: []string, audience: string = "") -> string {
    claims, ok := Claims(ctx.connection)
    if !ok { return "" if len(issuers) == 0 && audience == "" else "no token claims" }
    if len(issuers) > 0 {
        allowed: bool
        for issuer in issuers { if claims.issuer == issuer { allowed = true } }
        if !allowed { return "the issuer of the token is not trusted here" }
    }
    if audience != "" && !oidc.JwtAudienceHas(claims, audience) { return "the token is for another application" }
    return ""
}
