# oidc

OpenID Connect for programs written in Odin: sign a person in with any provider that speaks OIDC (SpacetimeAuth, Auth0, Keycloak, Google, a provider of your own), check the token that comes back, and renew it. No hidden allocation: caller buffers and fixed storage, nothing to free.

```odin
login: ^oidc.Login = new(oidc.Login)
oidc.LoginBegin(login, {issuer = "https://auth.example.com", client_id = "my-client"})   // discovers the provider, listens on 127.0.0.1, builds login.url
oidc.LoginOpenBrowser(login)                                                              // or show oidc.LoginUrl(login)
for oidc.LoginPoll(login) == .WAITING { /* a frame of the program */ }                    // no thread: the browser's request is accepted without blocking
if login.state == .DONE { use(login.tokens.id_token, login.claims.subject) }              // the ID token is verified: signature, issuer, audience, expiry, nonce
```
This is the flow that RFC 8252 asks of native apps: the authorization code flow with PKCE (RFC 7636) and a redirect to a loopback port. The program never sees a password; the provider's login page does everything (and can send the person through Google, a magic link, Steam ...). Register `http://127.0.0.1:<port>/callback` as a redirect URI of the client at the provider; `ClientConfig.redirect_port` fixes the port.

## What is here
| File | |
|---|---|
| `base64url.odin`, `jwt.odin` | **pure** (no OS, no crypto, no allocation, builds for `freestanding_wasm32`): split a JWT, read its header and claims (`iss`, `sub`, `aud`, `exp`, `nonce`, any field with `JsonString`/`JsonInt`), `JwtAudienceHas`. A SpacetimeDB module uses it to read the claims of its callers. |
| `verify.odin` | `JwksParse` (EC P-256 and RSA keys of a JWKS), `JwtVerify`: ES256 and RS256 only (what providers and SpacetimeDB use); `none` and the shared secret algorithms are refused; checks issuer, audience, expiry (60 s leeway), not before, nonce. |
| `sign.odin` | `JwtSignEs256` / `JwtSignRs256`, `JwkOfEs256` / `JwkOfRs256`: for a provider of your own, and the tests. |
| `provider.odin` | `Discover` (the issuer document, which must name the issuer that was asked), `FetchKeys`, `ExchangeCode`, `Refresh`, `Userinfo`, the device flow (`DeviceStart`, `DevicePoll`, RFC 8628, for a console or a TV), PKCE helpers. |
| `login.odin`, `browser.odin` | `Login` (the state machine above), `BrowserOpen` (no shell: the address is an argument). A request to the callback with another `state` is ignored (nobody can end your login from another site). |
| `http.odin` | the little HTTP(S) client (https through the TLS 1.3 client of p2p, the certificate is checked). `HttpIdle` steps another party in the same thread while a request waits (tests). |
| `mock/` | a provider that runs inside of a test (ES256 or RS256, the code flow with PKCE, refresh, device flow, `fault` to make it cheat). |

## Used by
- `odin_utilities/spacetimedb`: `AuthSession` / `AuthToken` / `AuthRefresh` hand the ID token to a connection (`spacetimedb/auth.odin`); a module reads and checks the claims of its callers with `module.Claims` / `module.RequireClaims` (`spacetimedb/module/jwt.odin`, example `module/example/auth`).

## Tests
`odin test oidc -strict-style -vet` (base64url, claims, signing and verifying with both algorithms and every way of being wrong) and `odin test oidc/mock -strict-style -vet` (a whole login against the mock provider, a provider that cheats in six ways, a forged redirect, PKCE, refresh, user info, the device flow). The test with a real SpacetimeDB server is `odin test spacetimedb` (`auth_test.odin`).

Limits and the list of what comes next: TODO.md.
