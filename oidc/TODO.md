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
- [ ] (high) `tool/login`: `odin run oidc/tool/login -- <discord|google|github|spacetimeauth>` reads providers.local.txt and runs a whole login (browser flow, device flow for GitHub), prints the claims
- [ ] (medium) GitHub inside the browser flow (OAuth 2.0 without an ID token: `Login` expects one)
