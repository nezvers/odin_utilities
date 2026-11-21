package spacetimedb

// The REST side of a SpacetimeDB server (references/SpacetimeDB/docs/docs/00300-resources/00200-http-api): make an identity, publish and delete a database, run SQL, call a reducer, read the log.
// Every call is one HttpRequest into a buffer of the caller; the answers are JSON, read by `JsonString` (the value of a key of an object, no allocation). A token is a bearer token: the
// `token` of `IdentityCreate` identifies the same client again and owns what it publishes.

import "core:fmt"
import "core:strings"

// The value of the string `key` in a JSON text (the first object that has it): `ok` false when there is none. No unescaping: the values of these answers (identities, tokens, names, ops)
// have no escapes.
JsonString :: proc(json: string, key: string) -> (value: string, ok: bool) {
    pattern: string = fmt.tprintf("\"%s\"", key)
    at: int = strings.index(json, pattern)
    for at >= 0 {
        rest: string = json[at + len(pattern):]
        rest = strings.trim_left_space(rest)
        if len(rest) > 0 && rest[0] == ':' {
            rest = strings.trim_left_space(rest[1:])
            if len(rest) > 0 && rest[0] == '"' {
                end: int = strings.index_byte(rest[1:], '"')
                if end >= 0 { return rest[1:1 + end], true }
            }
            return "", false
        }
        next: int = strings.index(json[at + len(pattern):], pattern)
        if next < 0 { break }
        at += len(pattern) + next
    }
    return "", false
}

// A new identity and its token (`POST /v1/identity`): both are views into `response`
IdentityCreate :: proc(endpoint: Endpoint, response: []u8) -> (identity: string, token: string, ok: bool) {
    result: HttpResult = HttpRequest(endpoint, .POST, "/v1/identity", nil, nil, response)
    if !result.ok || result.status != 200 { return }
    json: string = string(result.body)
    identity = JsonString(json, "identity") or_return
    token = JsonString(json, "token") or_return
    return identity, token, true
}

@(private)
bearer :: proc(token: string) -> [1]HttpHeader {
    return {{"Authorization", fmt.tprintf("Bearer %s", token)}}
}

// Publishes the module (the bytes of a .wasm) under `name`, a new database or an update of the one that has the name (`PUT /v1/database/<name>`); `clear` deletes the data of an existing one.
// The answer is JSON (`JsonString(body, "database_identity")`, "op").
DatabasePublish :: proc(endpoint: Endpoint, name: string, module: []u8, token: string, response: []u8, clear: bool = false) -> HttpResult {
    headers: [2]HttpHeader = {{"Content-Type", "application/octet-stream"}, bearer(token)[0]}
    path: string = fmt.tprintf("/v1/database/%s%s", name, "?clear=true" if clear else "")
    return HttpRequest(endpoint, .PUT, path, headers[:], module, response)
}

DatabaseDelete :: proc(endpoint: Endpoint, name: string, token: string, response: []u8) -> HttpResult {
    headers: [1]HttpHeader = bearer(token)
    return HttpRequest(endpoint, .DELETE, fmt.tprintf("/v1/database/%s", name), headers[:], nil, response)
}

// The schema of a database as JSON (`GET /v1/database/<name>/schema?version=9`: the tables with their columns, the reducers with their arguments)
DatabaseSchema :: proc(endpoint: Endpoint, name: string, token: string, response: []u8) -> HttpResult {
    headers: [1]HttpHeader = bearer(token)
    return HttpRequest(endpoint, .GET, fmt.tprintf("/v1/database/%s/schema?version=9", name), headers[:], nil, response)
}

// A SQL query (`POST /v1/database/<name>/sql`): the answer is JSON, an array with a result for each statement (its `schema` and its `rows`)
DatabaseSql :: proc(endpoint: Endpoint, name: string, query: string, token: string, response: []u8) -> HttpResult {
    headers: [1]HttpHeader = bearer(token)
    return HttpRequest(endpoint, .POST, fmt.tprintf("/v1/database/%s/sql", name), headers[:], transmute([]u8)query, response)
}

// A reducer by HTTP (`POST /v1/database/<name>/call/<reducer>`): the arguments are a JSON array (`["Ada"]`). For a client that is not connected; a connected one calls with ConnectionCallReducer.
DatabaseCall :: proc(endpoint: Endpoint, name: string, reducer: string, json_arguments: string, token: string, response: []u8) -> HttpResult {
    headers: [2]HttpHeader = {{"Content-Type", "application/json"}, bearer(token)[0]}
    return HttpRequest(endpoint, .POST, fmt.tprintf("/v1/database/%s/call/%s", name, reducer), headers[:], transmute([]u8)json_arguments, response)
}

// The last lines of the log of a database (`GET /v1/database/<name>/logs?num_lines=<n>`): what its module wrote with `log`
DatabaseLogs :: proc(endpoint: Endpoint, name: string, lines: int, token: string, response: []u8) -> HttpResult {
    headers: [1]HttpHeader = bearer(token)
    return HttpRequest(endpoint, .GET, fmt.tprintf("/v1/database/%s/logs?num_lines=%d", name, lines), headers[:], nil, response)
}
