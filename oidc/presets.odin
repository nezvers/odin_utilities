#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// Ready made settings for the providers people ask for. Only public values are here (issuer, scopes, endpoints); the client id (and for GitHub nothing else) comes from the person who registered the
// application: see providers/README.md, and `ClientConfigRead` for a settings file that stays out of git.
//
//     config: ClientConfig = PresetConfig(.DISCORD, "123456789012345678")
//     oidc.LoginBegin(login, config)                      // Google and Discord: the browser flow (code + PKCE, loopback redirect)
//
//     metadata: Metadata
//     PresetMetadataGithub(&metadata)                     // GitHub is OAuth 2.0 and not OpenID Connect: no discovery, no ID token, no keys
//     DeviceStart(&metadata, PresetConfig(.GITHUB, id), &device)   // the device flow needs no secret; afterwards Userinfo(&metadata, access_token, ...) names the person

import "core:strings"
import "core:testing"

Preset :: enum u8 {
    GOOGLE,                     // OIDC: ID token (RS256), SpacetimeDB accepts it as it is
    DISCORD,                    // OIDC: ID token (RS256) with the `identify` scope, public clients allowed
    GITHUB,                     // OAuth 2.0 only: an access token, not a JWT: SpacetimeDB does not accept it (use a broker such as SpacetimeAuth that offers "log in with GitHub")
    SPACETIMEAUTH,              // OIDC broker: logs people in with Google, GitHub, Discord ... and gives one kind of ID token
}

// The redirect ports to register at the provider as `http://127.0.0.1:<port>/callback` (Discord and GitHub want exact addresses; Google desktop clients accept any port)
PRESET_PORT_DEFAULT :: 48217

PresetConfig :: proc(preset: Preset, client_id: string, client_secret: string = "", redirect_port: int = PRESET_PORT_DEFAULT) -> ClientConfig {
    config: ClientConfig = {client_id = client_id, client_secret = client_secret, redirect_port = redirect_port}
    switch preset {
    case .GOOGLE:
        config.issuer = "https://accounts.google.com"
        config.scopes = "openid profile email"
        config.redirect_port = 0                      // the desktop client type of Google takes any loopback port
    case .DISCORD:
        config.issuer = "https://discord.com"
        config.scopes = "openid identify email"
    case .GITHUB:
        config.issuer = "https://github.com"          // a name only: GitHub has no discovery document
        config.scopes = "read:user"
    case .SPACETIMEAUTH:
        config.issuer = "https://auth.spacetimedb.com/oidc"
        config.scopes = "openid profile email"
    }
    return config
}

// The endpoints of GitHub, written down because there is nothing to discover. `Metadata.issuer` stays the name above; `jwks_uri` is empty (no ID tokens).
PresetMetadataGithub :: proc(metadata: ^Metadata) {
    metadata^ = {}
    metadata.issuer = keep(metadata.storage[:], &metadata.used, "https://github.com")
    metadata.authorization_endpoint = keep(metadata.storage[:], &metadata.used, "https://github.com/login/oauth/authorize")
    metadata.token_endpoint = keep(metadata.storage[:], &metadata.used, "https://github.com/login/oauth/access_token")
    metadata.device_authorization_endpoint = keep(metadata.storage[:], &metadata.used, "https://github.com/login/device/code")
    metadata.userinfo_endpoint = keep(metadata.storage[:], &metadata.used, "https://api.github.com/user")
}

// ---- the settings file --------------------------------------------------------------------------------------------------------------------------------------------------------
//
// `providers.local.txt` (git ignored, copy of providers.example.txt): `provider.key = value` per line, `#` starts a comment. Keys: `client_id`, `redirect_port`, `scopes`, `issuer`, `client_secret`.
// A client id is public (it is in the login address); a secret is not: keep a secret in the environment, never in a file of the repository. The strings of the result point into `text`.
ClientConfigRead :: proc(text: string, provider: string, base: ClientConfig) -> ClientConfig {
    config: ClientConfig = base
    rest: string = text
    for line in strings.split_lines_iterator(&rest) {
        trimmed: string = strings.trim_space(line)
        if trimmed == "" || trimmed[0] == '#' { continue }
        equals: int = strings.index_byte(trimmed, '=')
        if equals < 0 { continue }
        name: string = strings.trim_space(trimmed[:equals])
        value: string = strings.trim_space(trimmed[equals + 1:])
        if !strings.has_prefix(name, provider) || len(name) <= len(provider) + 1 || name[len(provider)] != '.' { continue }
        switch name[len(provider) + 1:] {
        case "client_id": config.client_id = value
        case "client_secret": config.client_secret = value
        case "issuer": config.issuer = value
        case "scopes": config.scopes = value
        case "redirect_port":
            port: int
            for c in value {
                if c < '0' || c > '9' { port = 0; break }
                port = port * 10 + int(c - '0')
            }
            config.redirect_port = port
        }
    }
    return config
}

@(test)
test_presets_and_the_settings_file :: proc(t: ^testing.T) {
    google: ClientConfig = PresetConfig(.GOOGLE, "id-g")
    testing.expect_value(t, google.issuer, "https://accounts.google.com")
    testing.expect_value(t, google.redirect_port, 0)
    discord: ClientConfig = PresetConfig(.DISCORD, "id-d")
    testing.expect_value(t, discord.redirect_port, PRESET_PORT_DEFAULT)

    text: string = "# comment\ndiscord.client_id = 1234\ndiscord.redirect_port = 50000\ngoogle.client_id=abc.apps.googleusercontent.com\ngithubx.client_id = no\ngithub.client_id = gh\n"
    read: ClientConfig = ClientConfigRead(text, "discord", PresetConfig(.DISCORD, ""))
    testing.expect_value(t, read.client_id, "1234")
    testing.expect_value(t, read.redirect_port, 50000)
    testing.expect_value(t, read.scopes, "openid identify email")
    testing.expect_value(t, ClientConfigRead(text, "google", PresetConfig(.GOOGLE, "")).client_id, "abc.apps.googleusercontent.com")
    testing.expect_value(t, ClientConfigRead(text, "github", PresetConfig(.GITHUB, "")).client_id, "gh")    // `githubx.` is another name

    metadata: ^Metadata = new(Metadata)
    defer free(metadata)
    PresetMetadataGithub(metadata)
    testing.expect_value(t, metadata.device_authorization_endpoint, "https://github.com/login/device/code")
    testing.expect_value(t, metadata.jwks_uri, "")
}
