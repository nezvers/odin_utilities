# p2p: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md (limits and measured free servers are there). Not for js (core:net). No demo_kit demo: it needs a real network and two programs.

## Connection core (serverless, pasted codes)
- `stun.odin`: RFC 5389 + CHANGE-REQUEST, pure.
- `code.odin` `Invite`: candidates incl. one IPv6, NAT facts; text = Crockford base32 + crc32 over a `serial` Writer. `Invite.secret` seals every packet (`PeerSeal/PeerOpen` in link.odin, replay window).
- `link.odin` `Link`: IPv4+IPv6 sockets or a `Transport`, STUN gathering, NAT mapping/filtering measurement, hole punching, port guessing for symmetric NATs, selective repeat reliable channel, events, inbox. Fixed capacities, ~320 KB, heap or global; `now_ms` is a parameter.
- `portmap.odin`: PCP, NAT-PMP, UPnP IGD, blocking and time bounded.

## Relays
- `turn.odin`: TURN client, long term credentials, non blocking from `LinkUpdate`.
- `derp.odin` + `derp_link.odin`: free Tailscale DERP relays; failure kinds + advice, reconnect with backoff, custom relay by name in invites, SIGNAL packets so the guest reply needs no pasting, direct-path upgrade. A relay that stays down is replaced along `DERP_FALLBACK`. `tool/derp diagnose|map`.
- `nacl.odin`: box, verified against the derpnet C code (`references/derpnet`).
- `relay_find.odin` `RelayFind`: which TURN servers answer from here (unauthenticated Allocate), candidates with free-tier sign-up links.
- `channel_probe.odin`: is another member the host of a relay channel too.

## TLS and proxies
- `tls13.odin`: minimal TLS 1.3 client, verified against RFC 8448.
- `tls_verify.odin`: chain, name, dates, CertificateVerify via core:crypto/x509. Roots: two built in (`trust/`), system store (Windows CryptoAPI / PEM bundles), `P2P_CA_FILE`; on Windows a root missing from the store is looked up through CryptoAPI; `P2P_TLS_VERIFY=off`.
- `tls_revoke.odin`: CRL of the chain, `P2P_TLS_REVOCATION=soft|strict|off`.
- `proxy.odin`, `proxy_ntlm.odin`, `proxy_sspi_*.odin`, `proxy_tunnel.odin`: http, https, socks5, socks4 via HTTPS_PROXY / ALL_PROXY; Basic, NTLM, Windows SSPI Negotiate.

## WireGuard
- `wireguard/` (own package): optional encrypted tunnel, keys with core:crypto x25519; installs WireGuard on request (official signed installer on Windows / package manager on Linux), every step logged first, needs administrator rights; Windows and Linux only.

## Tools
- `odin run p2p/tool/<name>`: `chat`, `probe`, `portmap`, `turn`, `multi`. `multi [n] [chat flags]` starts a host and n-1 guests (up to 8), passes the codes, merges output with timestamps, exit 0/1. chat flags: `--find-relay`, `--wireguard [--yes]`, `--wireguard-dry` (whole key exchange without touching the system, used by tests).

## Tests
- `odin test p2p -strict-style -vet` (64 tests, ~3 s; `P2P_LIVE=1` adds a live relay test), `odin test p2p/wireguard -strict-style -vet` (4), `odin check p2p/tool/<name> -strict-style -vet`.
- `sim_test.odin`: simulated internet (NATs of every mapping/filtering kind, LANs, IPv6 firewalls, STUN with a second address, TURN server); the NAT pair matrix and relay/IPv6 scenarios run there. `sim_derp_test.odin`: fake relay in it. The simulation needs no sleep; real-socket tests sleep 1 ms per pump.
- `Link` and `PortMapState` are too big for a stack: `new(...)` in tests.

## Findings
- A real STUN server drops a request whose datagram is longer than its header says: send `request[:length]`.
- A pipe handed to a child on Windows keeps the child waiting for end of input: give `clip` a temp file as stdin.
- The CHANGE-REQUEST result includes the PC firewall.
