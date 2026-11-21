package main

// A module that decides who may connect by the token's claims (OIDC): `identity_connected` reads the claims that the host kept for the new connection (`module.Claims`), refuses a caller whose issuer
// or audience is not the trusted one (a policy set with `set_policy`), and records who came in the public table `login`. SpacetimeDB accepts a token of any provider; this is where the module says
// which providers it trusts. Build: `odin run spacetimedb/tool/build_module -- spacetimedb/module/example/auth spacetimedb/bin/auth-odin.wasm`.

import "../../../bsatn"
import "../../../../oidc"
import module "../.."

logins, policy: module.Table

@(export)
__preinit__10_define :: proc "c" () {
    module.Define(define)
}

define :: proc(m: ^module.Module) {
    // who connected, with the claims of their token (the identity is the primary key: a second connection of the same one replaces the row)
    logins = module.TableAdd(m, "login", {{"identity", .IDENTITY, nil}, {"issuer", .STRING, nil}, {"subject", .STRING, nil}, {"audience", .STRING, nil}, {"email", .STRING, nil}}, public = true, primary_key = 0)
    // the trusted issuer and audience; one row (id 1), empty: anybody
    policy = module.TableAdd(m, "policy", {{"id", .U64, nil}, {"issuer", .STRING, nil}, {"audience", .STRING, nil}}, primary_key = 0)
    module.ReducerAdd(m, "identity_connected", nil, connected, .ON_CONNECT)
    module.ReducerAdd(m, "identity_disconnected", nil, disconnected, .ON_DISCONNECT)
    module.ReducerAdd(m, "set_policy", {{"issuer", .STRING, nil}, {"audience", .STRING, nil}}, set_policy)
}

Policy :: struct {
    issuer: [128]u8,
    issuer_length: int,
    audience: [128]u8,
    audience_length: int,
}

readPolicy :: proc() -> Policy {
    result: Policy
    module.TableScan(policy, &result, proc(user: rawptr, row: ^bsatn.Reader) -> bool {
        result: ^Policy = cast(^Policy)user
        _ = bsatn.ReadU64(row)
        result.issuer_length = copy(result.issuer[:], bsatn.ReadString(row))
        result.audience_length = copy(result.audience[:], bsatn.ReadString(row))
        return false
    })
    return result
}

connected :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    trusted: Policy = readPolicy()
    issuers: [1]string = {string(trusted.issuer[:trusted.issuer_length])}
    if message := module.RequireClaims(ctx, issuers[:] if trusted.issuer_length > 0 else nil, string(trusted.audience[:trusted.audience_length])); message != "" { return message }

    claims, has_claims := module.Claims(ctx.connection)
    row: [768]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteIdentity(&writer, ctx.sender)
    bsatn.WriteString(&writer, claims.issuer if has_claims else "")
    bsatn.WriteString(&writer, claims.subject if has_claims else "")
    bsatn.WriteString(&writer, claims.audience if has_claims else "")
    email, _ := oidc.JsonString(claims.payload, "email")
    bsatn.WriteString(&writer, email)
    if bsatn.WriterFailed(&writer) { return "the claims do not fit" }
    key: [32]u8
    key_writer: bsatn.Writer = bsatn.WriterMake(key[:])
    bsatn.WriteIdentity(&key_writer, ctx.sender)
    module.TableDeleteBy(logins, {0}, bsatn.WriterBytes(&key_writer))
    return module.TableInsert(logins, bsatn.WriterBytes(&writer))
}

disconnected :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    return ""
}

set_policy :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    issuer: string = bsatn.ReadString(args)
    audience: string = bsatn.ReadString(args)
    if bsatn.ReaderFailed(args) { return "the arguments are wrong" }
    row: [320]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteU64(&writer, 1)
    bsatn.WriteString(&writer, issuer)
    bsatn.WriteString(&writer, audience)
    if bsatn.WriterFailed(&writer) { return "the policy does not fit" }
    if message := module.TableUpdate(policy, {0}, bsatn.WriterBytes(&writer)); message != "" {
        if message != "no row with that key" { return message }
        return module.TableInsert(policy, bsatn.WriterBytes(&writer))
    }
    return ""
}
