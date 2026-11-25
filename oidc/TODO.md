# oidc: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- oidc` prints the open ones.

- [x] JWT reading (pure, wasm), ES256/RS256 verification and signing, JWKS, discovery, token endpoint, refresh, user info, loopback login with PKCE, device flow, a mock provider; tested with a real SpacetimeDB server
- [x] Against real providers (`OIDC_LIVE=1 odin test oidc`): discovery and keys of Google (2 RSA keys), Microsoft (7), SpacetimeAuth (1) and Duende demo (1), and a real RS256 access token of the Duende demo client (`m2m`) verified, tampering and foreign keys refused
- [ ] (high) A whole login with a person at a real provider (needs a client id: SpacetimeAuth project, Google client, Auth0 application): write down the redirect URI and scope settings that worked
- [x] A login window in the arena example with the `ui` library (`spacetimedb/arena/demo_common/signin.odin`, `screens.odin`): sign in, the name from the claims, the refresh token kept encrypted per provider (DPAPI on Windows); Google, Discord and SpacetimeAuth are offered when the settings file has a client id; GitHub is not (its access token is not an ID token, SpacetimeDB cannot take it)
- [x] Cache the keys with an expiry and fetch them again when a token does not fit them (`key_cache.odin`: `KeyCache`, `KeyCacheVerify`, min gap between fetches; `AuthSession` and `LoginPoll` still fetch once per login, a long running verifier uses the cache)
- [x] Token revocation (`Revoke`, RFC 7009), the end session address (`EndSessionUrl`, the program opens it in the browser), `UserinfoParse` into `UserinfoFields`; the arena Sign out revokes the refresh token (best effort). Not live checked at Google/Discord yet; GitHub has no revocation endpoint in this form
- [ ] (medium) Client credentials flow for services (a dedicated server that talks to a database as itself)
- [ ] (medium) The identity of a login without a connection: blake3 (`iss|sub`) is needed (Odin's core has none)
- [ ] (low) ES384/PS256/EdDSA verification (Auth0 and Keycloak can be set to ES256/RS256: all that is needed now)
- [ ] (low) Dynamic client registration (RFC 7591) and the OIDC session management
- [x] `tool/login` (`odin run oidc/tool/login -- <discord|google|github|spacetimeauth>`): a whole login from providers.local.txt; Discord tried live (ID token verified; refresh needs the secret)
- [x] Google tried live with the tool (ID token verified, name and email claims, user info, refresh works)
- [x] GitHub tried live with the tool (device flow, user from api.github.com)
- [x] A SpacetimeDB login with a real Google ID token (`spacetimedb/tool/auth_live -- google`): the server verified it, the module's policy let the person in and refused anonymous
- [x] SpacetimeAuth tried live with tool/login (login, refresh with offline_access) and with `spacetimedb/tool/auth_live -- spacetimeauth` (a real local SpacetimeDB server accepted the token, the module let the person in)
- [x] Discord with auth_live (2026-11-25, live): the real local server fetched Discord's keys, accepted the ID token of the person, the module trusted only that issuer and audience, an anonymous player was refused
- [x] Google and GitHub again live (2026-11-25): Google through the new browser launcher (ID token verified, refresh, user info); GitHub through `tool/login github` (device flow approved, user read from api.github.com). Found: after `slow_down` the old poll schedule was kept, so every poll was early and the approval was never seen (`deviceSchedule`, `--verbose` shows the answers)
- [x] The arena: a sign-in window with the `ui` library (name from the claims) and the choice of provider (see the item above)
- [ ] (low) `JsonString` returns escapes as written (`\\"` in a name): add a decoding variant that writes into a buffer
- [ ] (medium) `BrowserOpen` gives no sign when Firefox starts slowly (about 10 s cold): print the address always
- [x] GitHub inside the browser flow (2026-11-25, live): `ClientConfig.oauth_only` (set by the GitHub preset) skips the nonce and the ID token, takes the access token and names the person from the user info; needs `github.client_secret` and the callback `http://127.0.0.1:48217/callback` at the OAuth App; `tool/login github` uses it when a secret is set (`--device` keeps the code flow)
- [ ] (high) Protect the stored sign in on macOS (Keychain, `SecItemAdd` / `security`) and Linux (Secret Service: libsecret or `secret-tool` through stdin); until then nothing is stored there. Needs the systems to test on.
- [ ] (medium) Hardening on Windows against a program of the same user: an optional prompt or Windows Hello before the token is released (`CRYPTPROTECT_PROMPT_ON_UNPROTECT` is UI, the TPM backed `NCrypt` is the stronger way)
