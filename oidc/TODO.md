# oidc: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- oidc` prints the open ones.

- [x] JWT reading (pure, wasm), ES256/RS256 verification and signing, JWKS, discovery, token endpoint, refresh, user info, loopback login with PKCE, device flow, a mock provider; tested with a real SpacetimeDB server
- [x] Against real providers (`OIDC_LIVE=1 odin test oidc`): discovery and keys of Google (2 RSA keys), Microsoft (7), SpacetimeAuth (1) and Duende demo (1), and a real RS256 access token of the Duende demo client (`m2m`) verified, tampering and foreign keys refused
- [ ] (high) A whole login with a person at a real provider (needs a client id: SpacetimeAuth project, Google client, Auth0 application): write down the redirect URI and scope settings that worked
- [ ] (high) A login window in the arena example with the `ui` library: sign in, show the name from the claims, keep the refresh token (where: a file in the folder of the program, readable by the user only)
- [ ] (medium) Cache the keys with an expiry and fetch them again when a token names a `kid` that is not in the set (a provider rotates keys)
- [ ] (medium) `end_session_endpoint` (log out at the provider), token revocation, `userinfo` into a struct
- [ ] (medium) Client credentials flow for services (a dedicated server that talks to a database as itself)
- [ ] (medium) The identity of a login without a connection: blake3 (`iss|sub`) is needed (Odin's core has none)
- [ ] (low) ES384/PS256/EdDSA verification (Auth0 and Keycloak can be set to ES256/RS256: all that is needed now)
- [ ] (low) Dynamic client registration (RFC 7591) and the OIDC session management
- [x] `tool/login` (`odin run oidc/tool/login -- <discord|google|github|spacetimeauth>`): a whole login from providers.local.txt; Discord tried live (ID token verified; refresh needs the secret)
- [x] Google tried live with the tool (ID token verified, name and email claims, user info, refresh works)
- [x] GitHub tried live with the tool (device flow, user from api.github.com)
- [x] A SpacetimeDB login with a real Google ID token (`spacetimedb/tool/auth_live -- google`): the server verified it, the module's policy let the person in and refused anonymous
- [x] SpacetimeAuth tried live with tool/login (login, refresh with offline_access) and with `spacetimedb/tool/auth_live -- spacetimeauth` (a real local SpacetimeDB server accepted the token, the module let the person in)
- [ ] (medium) Discord with auth_live
- [x] Google and GitHub again live (2026-11-25): Google through the new browser launcher (ID token verified, refresh, user info); GitHub through `tool/login github` (device flow approved, user read from api.github.com). Found: after `slow_down` the old poll schedule was kept, so every poll was early and the approval was never seen (`deviceSchedule`, `--verbose` shows the answers)
- [ ] (medium) The arena: a sign-in window with the `ui` library (name from the claims) and the choice of provider
- [ ] (low) `JsonString` returns escapes as written (`\\"` in a name): add a decoding variant that writes into a buffer
- [ ] (medium) `BrowserOpen` gives no sign when Firefox starts slowly (about 10 s cold): print the address always
- [ ] (medium) GitHub inside the browser flow (OAuth 2.0 without an ID token: `Login` expects one)
- [ ] (high) Protect the stored sign in on macOS (Keychain, `SecItemAdd` / `security`) and Linux (Secret Service: libsecret or `secret-tool` through stdin); until then nothing is stored there. Needs the systems to test on.
- [ ] (medium) Hardening on Windows against a program of the same user: an optional prompt or Windows Hello before the token is released (`CRYPTPROTECT_PROMPT_ON_UNPROTECT` is UI, the TPM backed `NCrypt` is the stronger way)
