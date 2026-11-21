# oidc: notes for agents

What is not obvious from the code. The rules for every library are in [../AGENTS.md](../AGENTS.md); the use is in README.md.

- The pure part (`base64url.odin`, `jwt.odin`) must keep building for `freestanding_wasm32` (`odin check oidc -no-entry-point -target:freestanding_wasm32`): a SpacetimeDB module imports it. Everything with crypto, sockets or the OS has `#+build windows, linux, darwin, ...` at the top.
- Keys and tokens live in fixed storage of their structs (`KeySet`, `Metadata`, `Tokens`, `Login`): copying such a struct copies the bytes but not the string headers, which still point into the original: rebase them (`spacetimedb/auth.odin` `rebaseTokens`) or keep the struct where it is. The compiler warns when a procedure returns one by value.
- Only ES256 and RS256 are verified (SpacetimeDB accepts the same two). Never accept the algorithm the token names without checking it against the key kind (`JwtVerify` takes it from the header and picks keys of that kind only).
- `LoginPoll` is not re-entrant: its own requests step `HttpIdle`, which may poll again (`Login.busy`).
- A test that plays the browser and the provider in one thread sets `oidc.HttpIdle` (and `spacetimedb.StreamIdle` when a SpacetimeDB server must reach the provider while the client waits): see `mock/mock_test.odin` and `spacetimedb/auth_test.odin`. The tests of both set globals: they take a lock.
- SpacetimeDB fetches `{iss}/.well-known/openid-configuration` itself, also from `http://127.0.0.1:port` (that is what the tests rely on); it does not check `aud`, the module has to (`module.RequireClaims`). The identity is `blake3(iss|sub)` based: Odin's core has no blake3, so the identity is read from `InitialConnection`, not computed.
- Big locals (a `Login` is about 60 KB, `Tokens` 8 KB, `Request` buffers) go on the heap in tests: a test thread has a small stack.
- Presets (`presets.odin`): Google and Discord are normal OIDC (discovery works, checked live); GitHub is OAuth 2.0 only (no discovery, no ID token, device flow + `Userinfo` of api.github.com, whose token SpacetimeDB cannot take: a broker is the way). `providers.local.txt` is git ignored; the example file and the guide hold only public values.
