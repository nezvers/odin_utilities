# Provider templates: Discord, Google (Gmail), GitHub

What to create at each provider, what to write into `providers.local.txt` (copy of `providers.example.txt`, git ignored), what is safe to share.

**Safe to commit:** issuer, client id, scopes, redirect address. **Never commit:** a client secret, any token, a test account's password. Nothing below needs a secret: the browser flow uses PKCE, GitHub uses the device flow.

The redirect address is `http://127.0.0.1:48217/callback` (the port is `PRESET_PORT_DEFAULT`; change it in the file and at the provider together).

## Discord (OpenID Connect)
1. https://discord.com/developers/applications > New Application.
2. OAuth2 > Redirects > add `http://127.0.0.1:48217/callback`.
3. Copy **Client ID** (General Information or OAuth2). Do not copy the Client Secret.
4. Scopes the code asks for: `openid identify email`. The ID token carries `sub` (the Discord user id), and `identify` gives the name and avatar through `Userinfo`.
5. `discord.client_id = <that number>`. Discord accepts a public client (no secret) with PKCE for the login (tried live: `odin run oidc/tool/login -- discord`, ID token verified). **Refreshing** the token is different: Discord answers `invalid_client` without the client secret, so a program with no secret asks the person to log in again when the token (7 days) ends, or goes through a broker.

SpacetimeDB accepts the Discord ID token as it is (issuer `https://discord.com`, RS256); the module must still check the audience (`module.RequireClaims`): it is the client id.

## Google / Gmail (OpenID Connect)
1. https://console.cloud.google.com > APIs and Services > OAuth consent screen (External, test users: your own addresses while it is in testing).
2. Credentials > Create credentials > OAuth client ID > application type **Desktop app**.
3. Copy the **Client ID** (`....apps.googleusercontent.com`). Google also shows a "client secret" for desktop apps and asks for it at the code exchange; Google documents that it is not confidential, but it still stays out of the repository: put it only into your git ignored `providers.local.txt` as `google.client_secret`.
4. A desktop client takes any loopback port: no redirect to register.
5. `google.client_id = <id>`. The ID token has `email` and `email_verified` when the `email` scope is asked.

## GitHub (OAuth 2.0, not OpenID Connect)
GitHub has no discovery document and no ID token for logins (`token.actions.githubusercontent.com` is for CI jobs only). Therefore: an access token and the user from `https://api.github.com/user`; SpacetimeDB cannot take that token (it is not a JWT).
1. https://github.com/settings/developers > OAuth Apps > New OAuth App (or a GitHub App).
2. Homepage: any address. Callback: `http://127.0.0.1:48217/callback`.
3. Tick **Enable Device Flow**. The device flow needs the Client ID only: no secret, no browser redirect, works on a console.
4. `github.client_id = <Client ID>` (`Ov23...`).
5. Code: `PresetMetadataGithub`, `DeviceStart`, `DevicePoll`, then `Userinfo` (id, login, avatar).

To play on a SpacetimeDB server with a GitHub identity use a broker: SpacetimeAuth (or Keycloak, Auth0) has "log in with GitHub / Google / Discord" and hands out one standard ID token. Then only the broker's client id is needed (`spacetimeauth.client_id`), and the three providers are settings in the broker's dashboard.

## Checks
`OIDC_LIVE=1 odin test oidc` reads the discovery documents of Google and Discord and the device code endpoint of GitHub (with a made up id: the refusal is the proof that the address is right). A whole login needs your client id: `odin run oidc/tool/login -- discord|google|github|spacetimeauth` (add `--no-browser` to print the address and paste it into a browser yourself).
