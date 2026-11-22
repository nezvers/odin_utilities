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
| `provider.odin` | `Discover` (the issuer document, which must name the issuer that was asked: a multi tenant `common` endpoint of Microsoft names `{tenantid}` and is refused, use the tenant's own), `FetchKeys`, `ExchangeCode`, `Refresh`, `ClientCredentials`, `Userinfo`, the device flow (`DeviceStart`, `DevicePoll`, RFC 8628, for a console or a TV), PKCE helpers. |
| `login.odin`, `browser.odin` | `Login` (the state machine above), `BrowserOpen` (no shell: the address is an argument). A request to the callback with another `state` is ignored (nobody can end your login from another site). |
| `http.odin` | the little HTTP(S) client (https through the TLS 1.3 client of p2p, the certificate is checked). `HttpIdle` steps another party in the same thread while a request waits (tests). |
| `presets.odin`, `providers/` | settings for Google, Discord, GitHub (device flow, OAuth 2.0 only) and SpacetimeAuth (`PresetConfig`), a settings file reader (`ClientConfigRead`), and the setup steps per provider (`providers/README.md`, `providers.example.txt`). |
| `mock/` | a provider that runs inside of a test (ES256 or RS256, the code flow with PKCE, refresh, device flow, `fault` to make it cheat). |

## Getting a client id (Discord, Google, GitHub)
A client id is what the provider gives an application you register with it. It is public (it is in the login address), so it may be shared and committed; a client secret and any token may not. Full steps with the exact menus: [providers/README.md](providers/README.md).

1. **Discord:** https://discord.com/developers/applications > New Application > OAuth2 > Redirects: add `http://127.0.0.1:48217/callback` and press Save > copy the **Client ID**. No secret needed for the login (refreshing a token needs it).
2. **Google:** https://console.cloud.google.com > APIs and Services > OAuth consent screen (External, add yourself as a test user) > Credentials > Create credentials > OAuth client ID > **Desktop app** > copy the **Client ID** (`....apps.googleusercontent.com`). Any loopback port works, nothing to register.
3. **GitHub:** https://github.com/settings/developers > OAuth Apps > New OAuth App (callback `http://127.0.0.1:48217/callback`) > tick **Enable Device Flow** > copy the **Client ID** (`Ov23...`). GitHub is OAuth 2.0 only: an access token, no ID token.
4. **Put them in a file that stays out of git:** copy `providers/providers.example.txt` to `providers/providers.local.txt` (git ignored at any depth) and fill in `discord.client_id = ...`, `google.client_id = ...`, `github.client_id = ...`. A secret, when a provider insists on one, goes only into that file (`google.client_secret`), never into a committed one.
5. **Try it:** `odin run oidc/tool/login -- discord|google|github|spacetimeauth` (add `--no-browser` to print the address and paste it into a browser yourself). It prints the verified claims, or the provider's error.
6. **Use it in code:** `PresetConfig(.DISCORD, client_id)` (or `ClientConfigRead(text, "discord", ...)` for the file) gives the `ClientConfig` for `LoginBegin`; GitHub uses `PresetMetadataGithub` and `DeviceStart`.

## Used by
- `odin_utilities/spacetimedb/arena`: the start screen has Sign in (the `ui` library, `signin.odin`): the name and the identity of the player are the ones of the account.
- `odin_utilities/spacetimedb`: `AuthSession` / `AuthToken` / `AuthRefresh` hand the ID token to a connection (`spacetimedb/auth.odin`); a module reads and checks the claims of its callers with `module.Claims` / `module.RequireClaims` (`spacetimedb/module/jwt.odin`, example `module/example/auth`).

## Tests
`OIDC_LIVE=1 odin test oidc` also talks to real providers (Google, Microsoft, SpacetimeAuth, the Duende demo server: discovery, keys, and a real token verified). `odin test oidc -strict-style -vet` (base64url, claims, signing and verifying with both algorithms and every way of being wrong) and `odin test oidc/mock -strict-style -vet` (a whole login against the mock provider, a provider that cheats in six ways, a forged redirect, PKCE, refresh, user info, the device flow). The test with a real SpacetimeDB server is `odin test spacetimedb` (`auth_test.odin`). The tools are tested too: `odin test oidc/tool/login` (a whole login, a wrong audience, a refresh that needs the secret, the device flow, a timeout, every usage error, never a token in the output) and `odin test spacetimedb/tool/auth_live` (a person with a token of the mock provider gets into the module on a real local server).

Limits and the list of what comes next: TODO.md.
