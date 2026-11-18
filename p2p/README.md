# p2p

Connect two (up to eight) programs over the internet with **no server of your own, no account and no port forwarding**: one person
copies a short code, the other pastes it, the answer goes back the same way. Then the programs talk over UDP: unreliable messages
and reliable ordered ones (resent until acknowledged, only the lost ones).

```
host                                          guest
LinkInit, LinkGatherBegin                     LinkInit, LinkGatherBegin
LinkUpdate until LinkGathered                 LinkUpdate until LinkGathered
LinkHost("name")
LinkMakeInvite -> InviteEncode -> text  ───►  InviteDecode(text) -> LinkJoin(invite, "name")
                                              LinkMakeInvite -> InviteEncode -> reply text
InviteDecode(reply) -> LinkAcceptReply  ◄───
every frame: LinkUpdate, LinkPollEvent, LinkReceive, LinkSend      (same on both sides)
```

The code is about 110 characters (`0C0H2-PT5R4-4DVAC-...`; it carries the session secret, see "Encryption of the Link"), Crockford base32 with a crc: case free, dashes and spaces ignored, a typo or a half
copied code is refused before any packet is sent. The host can paste more replies at any time (up to `MAX_PEERS` = 8).

## How it gets through, in the order it is tried (all at once, the first answer wins)
1. **Local network address**: two computers on one router connect directly.
2. **Hole punching with STUN**: each program asks free public STUN servers (Google, Cloudflare, nextcloud) what address they see, from the
   same socket the game uses, and puts it in the code. Both sides then send at each other at the same time; every NAT sees outgoing traffic
   first and lets the answer in. The STUN servers only answer one small packet at the start.
3. **Port guessing for symmetric NATs**: when the NAT gives a new public port per destination but counts up (many home routers), the code
   carries the step and the last port, and the peer sprays the next ones. Works even between two such NATs.
4. **Port forwarding on request**: `LinkPortMap` asks the router (PCP, NAT-PMP, UPnP) to forward the port. The public address becomes stable
   and open, so nothing has to be punched or guessed.
5. **IPv6**: with a global IPv6 address on both sides there is no NAT, only a stateful firewall that both sides open by sending first.
6. **DERP relay (free, no account)**: `LinkDerpBegin` connects to one of Tailscale's public DERP relays (28 regions, nothing to sign up for, nothing
   to install; idea and protocol from [derpnet](https://github.com/mmozeiko/derpnet), made cross-platform here). The code then names the relay and our key
   there, the guest's reply travels through it by itself (one code goes one way, nothing is pasted back), and the relay is a candidate like any
   address: it connects even two strict NATs, and the connection moves to a direct path as soon as one works. Everything through it is sealed end to
   end (NaCl box). Relay of last resort: a detour through a data center (about 90 ms and a few hundred KB/s measured), so direct paths stay first.
7. **TURN relay**: `LinkTurnBegin` allocates a relayed address on a TURN server. Only ONE side needs it: the other just sends to the
   relayed address like to any public address. It carries every byte, so the connection moves to a direct path as soon as one packet
   arrives that way.

| situation | works with |
|---|---|
| same LAN, any NAT | 1 |
| full cone, address restricted, port restricted (cone) NATs, in any combination | 2 |
| symmetric NAT that counts up, against anything (including another one) | 3 |
| symmetric NAT with random ports (carrier and company NATs) against port restricted or symmetric | 4 (router with UPnP/PCP), 5 (IPv6 on both), 6 (DERP, free) or 7 (TURN, account) |
| both behind carrier grade NAT with no IPv6 | 6 or 7 (a relay) |

## Files
- `stun.odin`: STUN binding (RFC 5389) with CHANGE-REQUEST / OTHER-ADDRESS (RFC 5780), pure functions, the server list.
- `code.odin`: `Invite` (candidates, session, id, name, NAT facts) and its text form.
- `link.odin`: `Link`: sockets (IPv4 + IPv6), gathering, NAT measurement, punching, port guessing, reliable channel, events, inbox.
- `portmap.odin`: PCP, NAT-PMP and UPnP IGD port forwarding (blocking, time bounded).
- `derp.odin`: the DERP client (frames, handshake, send / poll, a race to find the fastest relay), `derp_link.odin`: DERP inside the Link (relay candidate,
  SIGNAL packets, short codes), `tls13.odin`: a small TLS 1.3 client (Odin has none in core; the server certificate is checked by `tls_verify.odin`, see "Certificate checking" below: fine for DERP
  because the payload is sealed end to end, not for anything else), `nacl.odin`: NaCl box (X25519 + XSalsa20 + Poly1305) checked against the derpnet C code.
- `turn.odin`: TURN client (allocation, refresh, permissions, Send/Data indications), non blocking from `LinkUpdate`.
- `relay_find.odin`: `RelayFind`, which relay (TURN) servers answer from this network, with their free sign-up pages.
- `wireguard/`: optional encrypted tunnel (separate package), see "Encryption with WireGuard" below.
- `sim_test.odin`: a simulated internet for the tests: NAT boxes with every mapping and filtering behavior, LANs, hairpin, IPv6 with
  firewalls, STUN servers with a second address, a TURN server. Deterministic, no sockets, milliseconds per scenario.
- `tool/multi`: runs many chat processes at once with one merged log and a pass/fail check (the many-peer test).
- `tool/chat`: terminal chat, the demo and the manual test. `tool/derp`: connect to every public DERP relay (time and failures), two clients through one relay, listen / send to a public key (works with the derpnet
  examples). `tool/probe`: which free servers work from this network. `tool/portmap`: can this
  router forward a port. `tool/turn`: try TURN credentials and run a chat through the relay.

## Use
```odin
link: ^p2p.Link = new(p2p.Link)               // ~320 KB of fixed storage (8 peers x two 16 KB windows, inbox, relay state): place it once
p2p.LinkInit(link)                            // opens the IPv4 socket and, when the computer has it, the IPv6 one
servers: [p2p.STUN_MAX_SERVERS]net.Endpoint
count: int = p2p.LinkResolveStun(servers[:])    // blocking DNS, do it at start
// optional, before the gathering is done:
//   server, _ := p2p.LinkResolve("relay.example.com:3478"); p2p.LinkTurnBegin(link, server, username, password, now)
p2p.LinkGatherBegin(link, servers[:count], p2p.LinkNow())
// frame loop: p2p.LinkUpdate(link, p2p.LinkNow())  until p2p.LinkGathered(link)
// optional, blocks up to a few seconds: p2p.LinkPortMap(link, portmap_state, now)
buffer: [p2p.CODE_TEXT_MAX]byte
text, _ := p2p.InviteEncode(p2p.LinkMakeInvite(link), buffer[:])   // show it, copy it with your framework (SetClipboardText ...)
p2p.LinkSend(link, peer, data, reliable = true, now)               // false: window full, try next frame
peer, length, ok := p2p.LinkReceive(link, message[:])
```
`LinkPollEvent` reports `GATHERED`, `NAT_MEASURED`, `RELAY_READY`, `RELAY_FAILED`, `PEER_CONNECTED`, `PEER_FAILED` (nobody answered in 20 s) and
`PEER_LOST` (closed, or 8 s of silence). After the gathering `link.nat_mapping` / `link.nat_filtering` say what the NAT does.
Binary messages: build them with `serial.Writer` / `Reader` (`odin_utilities/serial`, bounds checked, little endian, safe on untrusted data).

Memory: no allocation after the `Link` exists (the interface lists read at setup go through the temp allocator). Capacities are constants
(`MAX_PEERS`, `WINDOW`, `INBOX`, `MAX_PAYLOAD`), failures are returned (`LinkSend` false), never grown. Time is a parameter (`now_ms`), a
`Transport` (two procs) can replace the sockets, which is how the tests run a simulated network.

## Looking for a relay (`chat --find-relay`)
`RelayFind` sends one credential-less Allocate request to the known TURN servers and reports who answers. `chat host|join --find-relay` prints the
alive ones with the page where their free tier is made, and lets you type `host:port username password` for one you have an account at (the same as
`--turn`). An alive relay answers `401` and wants a login; a server that allocates without one would be listed as OPEN (none was found).

## Encryption of the Link
Every packet after the 10 byte header is sealed (XSalsa20-Poly1305, the NaCl code that DERP uses, `nacl.odin`), on every route: direct, through a DERP relay, through TURN.
- **The secret is in the code.** The host makes 16 random bytes and puts them in its invite (`Invite.secret`, invite format 5; a reply code carries none). Whoever does not
  hold the code cannot read, forge or replay a packet. The code is therefore a secret: pass it privately (a chat message is fine, a public page is not).
- **Keys.** One key per pair of members: `sha256("p2p-link-v1:" + secret + both ids)`. The nonce is a 64 bit packet counter plus the direction, so the two ends of a pair
  never repeat one; the counter starts at a random value.
- **Replay.** A window of 64 counters: a packet that was seen, or is more than 63 behind the newest, is dropped. The kind of the packet is also inside the seal, so
  changing it in the header (which is not covered by the tag) does nothing.
- **What an observer still learns:** who talks to whom (addresses, or the relay keys), how much, and when. A relay sees the same.
- **Cost:** 8 bytes counter + 1 byte kind + 16 bytes tag per packet, one HSalsa20 and one XSalsa20 pass; `MAX_PAYLOAD` is still 1000 bytes (a datagram stays under about 1050).
- **Not covered:** the code itself (if somebody else reads it, they can join), and a member that joined keeps being trusted as much as the host trusts it.
- Verified: `LinkSealTest` (unreadable on the wire, a flipped bit anywhere refused, a stranger's packet refused, own packet reflected back refused, the replay window), and the
  whole NAT matrix and relay simulations run sealed.

## WireGuard on top (`chat --wireguard`, optional)
The Link seals its own packets; WireGuard adds a virtual LAN (10.73.82.1 / .2) for programs that speak plain IP. It is **not a relay**: the tunnel uses the same UDP path the punch
found, so it does not get through a NAT the punch could not pass. The sequence (`tool/chat/tunnel.odin`): the chat connects as usual, then the two sides
exchange WireGuard public keys over the live Link, the Link closes and WireGuard takes over **the same UDP port** towards the address that just worked
(the NAT mapping belongs to the port, so the hole stays open), and the chat continues on a second Link whose only address is the tunnel's.
- Says first what it will do (`wireguard.Describe`) and asks; `--yes` skips the question. Every step is printed as `[wireguard] ...` before it runs.
- Windows: downloads the official `wireguard-installer.exe` from download.wireguard.com, checks its Authenticode signature (must be "WireGuard LLC"),
  runs it elevated (UAC), later creates and removes the tunnel service the same way. Linux: installs `wireguard-tools` with the package manager through
  sudo (apt, dnf, yum, pacman, zypper, apk) and uses `wg-quick`; sudo is asked once at the start. macOS: not supported.
- One guest only; not over a TURN relay (needs a direct path); keys are made in the program (core:crypto), the private key only goes into a temporary
  config file that is deleted right after the tunnel takes it. The tunnel is removed on `/quit` (closing the window by force leaves it: remove the
  service `WireGuardTunnel$p2pchat` / interface `p2pchat`).
- Verified: key derivation against RFC 7748, config text, package manager choice, and `--wireguard-dry` (both programs run the whole exchange and the
  switch, the second Link connects on loopback, the chat flows). Not verified on this machine: the installer and the real tunnel (they need administrator rights).

## DERP relay (free, `chat --derp`)
- `odin run p2p/tool/derp`: tries all 28 relays at once. From the development network 27 answered (70 ms to the nearest, the farthest 1.8 s).
- `odin run p2p/tool/chat -- host Ann --derp` picks the fastest relay (or `--derp N`), the code names it. `join Bob` with that code connects to the same
  relay by itself and the reply goes through it: no reply code to send back. `--derp-only` offers no addresses (everything through the relay, for testing or
  privacy), `--short` makes the host code without addresses, `--no-derp` ignores the relay in a code.
- In a program: `LinkDerpBegin(link, server, now)` before the gathering is done (`LinkGathered` waits up to 10 s), then `LinkMakeInvite(link, short = true)` for a
  code without addresses. Events `DERP_READY` / `DERP_FAILED`. The guest calls `LinkDerpBegin(link, int(invite.derp_server), now)` with the server number of the
  code it was given and `LinkJoin` once it is not `CONNECTING`.
- How it works: a pseudo address `fd0d:e29::slot` stands for the peer's key at the relay; `LinkSendRaw` sends such datagrams through the relay. A guest keeps
  sending its reply as a `SIGNAL` packet until connected; the host accepts it only for its own session and only from the key named inside (a forged sender
  is dropped) and answers with its full invite. A connection through a relay tries a direct punch every 2.5 s and leaves the relay when one is answered.
- Verified: the TLS client against the RFC 8448 trace (every secret, the encrypted flight, our Finished record byte for byte), the NaCl box against the derpnet
  C code, the frames, the whole Link in the simulation (all 36 NAT pairs connect through the fake relay, upgrade to direct, 150 messages over 20% loss, a relay
  that is down, forged signals), and live: two clients through the real relay, interop in BOTH directions with the derpnet C example, `chat selftest --derp-only
  --short` (200 messages each way over 20% loss through Warsaw), two `chat` processes with one code. `P2P_LIVE=1 odin test p2p` also runs a live relay test.
- Limits: relays are run by Tailscale for their own service and may change or limit use at any time; this is for connecting people, not for bulk transfer.
  The TLS to the relay checks its certificate (section "Certificate checking"); a relay still sees who talks to whom and how much, and the packets are sealed end to end
  on top of it.

## If the relays go away or change (Tailscale can do either at any time)
Nothing here depends on one company: the relay is one candidate path among others, and everything below keeps working without it.
- **What you see.** Events `DERP_FAILED` (never worked), `DERP_LOST` (a working connection ended), `DERP_READY` (back). `link.derp.failure` says what happened in words
  and `link.derp.failure_kind` classifies it: `NO_NETWORK` (no DNS / TCP), `TLS`, `TIMEOUT`, `NOT_DERP` (it answered, but not DERP: it moved, an error page, the protocol
  changed; the HTTP status is reported), `REFUSED` (DERP, but it will not take this client: for example it now only accepts its own network's devices), `CLOSED`.
  `DerpAdvice(kind)` returns the sentence to show the person: what it means and what to do. The chat and amsg print it.
- **It reconnects by itself**, same identity, no program action needed: tries every 0.5 s at first (peers talking through the relay give up after 6 to 8 s of
  silence), then slower, up to one try every 30 s, and never gives up. A short outage costs a pause: the reliable channel resends what was lost, in order
  (tested: the relay gone for 4 s in the middle of 200 messages, nothing lost, doubled or reordered). A relay that was down from the start is retried too, and codes
  made after it came up carry it. Gathering never waits for a dead relay longer than 10 s.
- **Find out what is wrong:** `odin run p2p/tool/derp -- diagnose` checks the internet first (so a dead network is not mistaken for a dead relay), probes the relays,
  gives a verdict with the reason, fetches the current list from Tailscale and lists what to do. `odin run p2p/tool/derp -- map derpmap.txt` fetches the live list
  (about 95 servers in 28 regions on 2026-11-17, several per region) with our own HTTPS client and saves it; `probe derpmap.txt` (or `probe name1 name2`) tests those.
- **Use any relay by name:** `chat --derp-host derp.example.com[:port]`, `LinkDerpBeginHost(link, "name", now)`, `amsg <channel> --derp-host name`. The code carries the
  name (invite format 4: server number 255 + name, up to 48 characters), so the other side needs nothing else. Names from the list that `map` fetched work, so a
  renamed or moved Tailscale relay is a one word change, and a server that does not use fast start (it answers `101 Switching Protocols` first) is understood.
- **A relay of your own** (free, accepts anybody by default; verified here only against the public relays, not against a self-hosted one, follow Tailscale's current
  documentation for `derper`): a small server with a domain name and ports 443 and 80 open: `go install tailscale.com/cmd/derper@latest`, then
  `derper --hostname=derp.yourdomain.example`; every member passes `--derp-host derp.yourdomain.example`. Its certificate is checked like every relay's: derper gets a Let's Encrypt one (built-in roots), a private authority or a self-signed certificate needs `P2P_CA_FILE=<its pem file>`.
- **A relay that stays down is replaced.** A relay of the built in list that has been down for 12 s is replaced by the next one of a fixed walk
  (`DERP_FALLBACK`: 4, 8, 1, 14, 22, 2, ... never the starting one), then again after 12 s, and so on; `DERP_SWITCHED` says it. Both ends of a connection do the same after the
  same time, so they meet on the same relay without being able to talk (the relay was the only way): the identities (keys) are the same on every relay. Peers that can only be
  reached through the relay are not given up for 45 s meanwhile and their silence clocks restart when the relay is back (tested: relay 8 dead for good in the middle of 200
  messages, both ends on relay 4, nothing lost). A code made before names the old relay; an invite that names the relay the session started on is still accepted.
  Limits: it assumes both sides see the same relays as down (if only one side cannot reach it, they end on different ones); a relay of your own (`--derp-host`) is never
  replaced, `LinkConfig.derp_no_failover` turns it off for the list too.
- **Behind a proxy.** The relay connection (and `derp map` / `diagnose`) goes through `HTTPS_PROXY` / `https_proxy` / `ALL_PROXY` (`NO_PROXY` respected); the scheme of the URL
  says which kind (user name and password may be percent encoded, `%5C` = backslash), `proxy.odin`:
  - `http://[user:password@]host[:3128]`: CONNECT, Basic with the first request. When the proxy asks for **NTLM** or **Negotiate** instead: with `DOMAIN\user:password` in the URL
    NTLMv2 is done by hand on every platform (`proxy_ntlm.odin`, MD4 included; checked against the MS-NLMP example and a fake proxy that verifies the response); **on Windows
    without credentials in the URL** the login of the user goes through SSPI (`proxy_sspi_windows.odin`: Negotiate = Kerberos with NTLM as the fallback, the service name is
    `HTTP/<proxy host>`; tested against this computer's accounts through `AcceptSecurityContext`, NTLM only, a real Kerberos domain was not available). Kerberos needs Windows:
    no GSSAPI is used elsewhere, there the message asks for `DOMAIN\user:password`. The login runs on one connection (the 407 bodies are read and dropped); a proxy that closes it
    after each 407 cannot be used for NTLM (the message says so).
  - `https://[user:password@]host[:443]`: the same CONNECT inside TLS to the proxy, its certificate checked like a relay's (`P2P_CA_FILE` for a company authority; the name must be
    a name, not an address). TLS goes inside TLS through a loopback pair and a thread (`proxy_tunnel.odin`): callers see an ordinary socket. Verified against a real TLS server
    (a Python proxy with its own authority): `derp diagnose` reached 17 relays through it, `chat selftest --derp-only` passed (200 messages over 20% loss), and it is refused
    without the authority with the reason. No offline test of the success path (there is no TLS server in the library), only of the failure.
  - `socks5://` / `socks5h://[user:password@]host[:1080]` (RFC 1928, no login or user name and password) and `socks4://` / `socks4a://[ident@]host[:1080]`: the name is always sent to
    the proxy (an address goes as itself in SOCKS4). Tested against fake servers.
  Not covered: PAC / WPAD, authentication schemes other than the four. UDP (STUN, hole punching) cannot pass a proxy: behind one only the relay works, which is what it is for.
- **Without any relay:** the same network works (LAN addresses), hole punching works through most home routers, pasted codes need no relay, TURN works with credentials
  (`chat --turn host:port user password`), a router with UPnP can forward the port (`--upnp`). Only the case of two strict carrier NATs needs a relay.
- **What breaks for good:** if TLS 1.3 were dropped or the DERP framing changed incompatibly, the client needs an update (the detection above tells the difference
  between "moved" and "changed protocol"). A relay that demands something this client does not have (a client certificate, a login) is not usable.

## Reliable channel
Selective repeat over a window of 16: the receiver keeps messages that arrive early and reports exactly which ones it has (next expected
sequence + a bit mask), the sender resends only the missing ones on a timer of 2x the measured round trip (doubling per resend). Messages
come out of `LinkReceive` once and in order; a peer that acknowledges nothing for 6 s is lost. 200 messages each way over 20% random loss
arrive in order in about 2 s.

## What free servers exist (measured with `tool/probe` on 2026-11-16, from one home network; run it on yours)
- **STUN**: 28 of 41 candidates answer. Google and Cloudflare are the dependable ones. Only `stun.nextcloud.com` honored CHANGE-REQUEST with
  a public second address, the others ignore it or announce a private address, so it is the one used for the filtering test.
- **TURN**: 5 of 13 alive (ExpressTURN, Twilio, Cloudflare, Metered, Xirsys), **all want a login**. There is no anonymous free TURN. The free tiers
  (Cloudflare, Metered, ExpressTURN, Xirsys) need a signup, then `LinkTurnBegin(server, username, password)`. Verified live: ExpressTURN and Xirsys
  accepted the whole handshake and refused only a wrong password; Cloudflare and Metered answer 400 to unknown credentials, so the request format
  could not be confirmed against them without an account.
- **Router forwarding**: depends on the router. The one tested (UPnP) granted a mapping in 800 ms.

## What it cannot do (be honest with players)
- **Relays**: DERP (free, no account, `--derp`) covers the last rows of the table. TURN needs an account from a provider (see above). Without either, those rows fail
  and the link says why (`link.nat_mapping`, `PEER_FAILED`).
- **Encryption** is on (section "Encryption of the Link"); the code is the secret. WireGuard (above) is optional for a virtual LAN.
- A random-port symmetric NAT against another strict NAT cannot be guessed (no birthday attack: it would need hundreds of sockets).
- The CHANGE-REQUEST test measures the router **and this computer's firewall** together (an unprogrammed Windows firewall drops unsolicited UDP,
  which is correct for security and does not stop punching, because the first outgoing packet opens it).
- A port mapping lasts 2 hours (the lease) and is removed by `LinkClose`; there is no renewal yet. Not for the web build (`core:net`).
- The simulation proves the logic, not the real world: NAT counters shared with other devices on the same router, carrier NAT quirks and
  provider TURN servers can differ. The guessing in particular assumes the NAT port counter is not touched between the measurement and the punch.

## Certificate checking (TLS to the relay)
`tls13.odin` verifies the relay the way a browser does (`tls_verify.odin`, built on `core:crypto/x509`): the chain the server sends must end at a root we trust, every
certificate must be valid today, the leaf must be issued for the name we asked for (subject alternative names, server authentication), and the server must prove with its
CertificateVerify signature (ECDSA P-256 / P-384, RSA-PSS, Ed25519) that it holds the key of that certificate, over the handshake transcript.
- **Roots:** two are built in (`trust/isrg_root_x1.pem`, `isrg_root_x2.pem`, fingerprints checked against the published ones), which is what the Tailscale relays chain to (Let's
  Encrypt, 2026: leaf, YE1, Root YE, ISRG Root X2, cross signed by X1), so the relays work on a computer without any root store; plus the store of the system: Windows
  (CryptoAPI `ROOT` and `AuthRoot`, current user; Windows fetches the rest on demand, so a rarely used authority is missing there until it was used: when our roots do not reach a chain, `TlsSystemTrust` hands the chain to CryptoAPI (`CertGetCertificateChain`, no revocation, 8 s limit), which fetches the root from the Microsoft program and says which root it ends at and whether Windows trusts it; that root is one more anchor for the one check, and the chain, name and dates are still verified here), Linux and macOS (the usual PEM bundle
  files); plus `P2P_CA_FILE` / `SSL_CERT_FILE` (a PEM file with one or more certificates: a company proxy that inspects HTTPS, a private authority, the self-signed
  certificate of your own `derper`). `P2P_TLS_VERIFY=off` switches the checking off for one run.
- **When it fails** the relay failure says why in words (`link.derp.failure`): not for this name, expired / not valid yet (**the clock of the computer must be right**), not signed
  by an authority this computer trusts, the server did not prove its key. The kind is `TLS`, with advice.
- **Verified:** a real relay chain captured on 2026-11-17 (accepted for its name, refused for another name, after expiry, one byte changed, without intermediates, for an address);
  the RFC 8448 CertificateVerify signature (accepted; refused when damaged, for the wrong scheme, and over another transcript); 27 of the 28 relays connect with the check on (the
  28th did not answer in time, as before); a Windows root store of 90 certificates loaded; `example.com` (its authority was not in the local store) is refused by our roots alone
  and accepted through the Windows lookup (`TlsSystemTrustLiveTest`, P2P_LIVE=1). On Linux and macOS there is no such lookup: a missing authority needs the PEM bundle or `P2P_CA_FILE`.
- **Revocation** (`tls_revoke.odin`): once the chain is good, the certificate of the server and every intermediate above it (not the root) are looked up on the CRLs they name
  (CRL distribution points, `http://`; Let's Encrypt switched OCSP off in 2025, so the relays only have lists). A list is fetched, its signature checked against the certificate of
  the authority (ECDSA, RSA PKCS#1, Ed25519), its dates and issuer checked, the serial looked for; it stays in memory until its next update (a leaf list of Let's Encrypt is about
  100 to 250 KB, the lists of intermediates a few hundred bytes) and on disk between runs (`%LOCALAPPDATA%\p2p\crl`, `$XDG_CACHE_HOME/p2p/crl` or `~/.cache/p2p/crl`;
  `P2P_CACHE_DIR` moves it, `off` = none; a file that is read back is verified like a fresh list, so a changed file is ignored and replaced), and a list that could not be had is not
  asked for again for ten minutes. Certificates valid for 10 days or less are not
  checked (the rule of the browsers). `P2P_TLS_REVOCATION=soft` (default): a revoked certificate is refused, a list that cannot be had is let through, because a down CDN must
  not take the relays down (and many proxies refuse port 80); `strict`: no answer = refused; `off`. Measured: real revoked certificates (a test site of Amazon Trust and one of
  SSL.com) are refused with the list named, good ones pass, all the relays pass in `strict` (3 small lists on the first connection, about 50 ms each); offline tests with a CA made
  with openssl (good and revoked certificate), the real list of ISRG Root X2, a damaged / wrong-issuer / expired list, and the HTTP side (Content-Length, chunked, 404).
- **Not covered:** OCSP (stapled or fetched), delta lists, the scope of an Issuing Distribution Point, removing old list files from the cache folder, certificate transparency, name constraints beyond what the x509 package enforces, pinning. A relay is still only a carrier: the
  packets inside are sealed end to end whatever the TLS says.

## When it does not connect: what to check
| What you see | Likely cause | What to do |
|---|---|---|
| `DERP_FAILED` `NO_NETWORK` | no TCP 443 out, or a proxy is needed | set `HTTPS_PROXY`; `derp diagnose` |
| `NOT_DERP`, `TLS`, `REFUSED` | the relay moved or changed | `derp map` for the current list, `--derp-host`, your own `derper` |
| `TLS` with "certificate" in the text | wrong date on this computer, a proxy that inspects HTTPS, a private authority | fix the clock; `P2P_CA_FILE=<pem>`; as a last resort `P2P_TLS_VERIFY=off` |
| relay fine, `PEER_FAILED` on direct | UDP blocked by a firewall (company network, Windows Firewall prompt declined), or two strict NATs | the relay carries it; allow the program in Windows Firewall |
| LAN discovery finds nobody | Wi-Fi client isolation, a VPN adapter took the broadcast, another subnet | paste the code, or use the relay (`--derp N`) |
| a code is refused | typo (crc), a code from an older version (format 4 or older: make a new one), or somebody else's session | make a new code |
| connected, then `PEER_LOST` after about 8 s | the path closed (NAT timeout, Wi-Fi roaming) | keepalives are sent every second; reconnect (`--reconnect` in amsg) |
| IPv6 only network | not tested (no NAT64/DNS64 handling) | the relay by name works when the name resolves |
| WireGuard step fails | the installer address or signing name changed, or no administrator rights | `--wireguard-dry` shows the whole flow; the Link is encrypted anyway |

## Tests
```
odin test p2p -strict-style -vet                 # 64 tests: codes, STUN/TURN/PCP/NAT-PMP/UPnP parsing against independent values and fake routers,
                                                 # 36 NAT pairs, NAT measurement, relay and renewal, IPv6, loss, failure timeouts
odin run p2p/tool/chat -- selftest [--upnp]      # both ends in one process, real STUN servers, real LAN addresses, 20% loss
odin run p2p/tool/chat -- host Ann               # computer 1 (flags: --upnp --turn host:port user pass --relay-only --no-ipv6 --find-relay --wireguard)
odin run p2p/tool/chat -- join Bob               # computer 2, on another network for the real NAT test
odin test p2p/wireguard -strict-style -vet       # 4 tests: keys, config, package manager choice
odin run p2p/tool/multi -- 4                    # host + 3 guests as separate processes on this computer: codes passed automatically, merged log, PASS/FAIL (2..8)
odin run p2p/tool/derp                           # which public DERP relays answer from here; pair / listen / send modes
odin run p2p/tool/chat -- selftest --derp-only --short   # both ends in one process through a real DERP relay
odin run p2p/tool/probe                          # which free STUN / TURN servers work from here, and what this NAT does
odin run p2p/tool/portmap                        # can this router forward a port (opens one, shows it, removes it)
odin run p2p/tool/turn -- host:port user pass --relay-test
```
Two programs on one computer or one router prove the code path but not a real NAT crossing (the packets take the LAN route). For the real thing run
`host` and `join` on two networks (a phone hotspot is enough for one of them).
