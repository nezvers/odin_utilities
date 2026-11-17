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

The code is about 90 characters (`0C0H2-PT5R4-4DVAC-...`), Crockford base32 with a crc: case free, dashes and spaces ignored, a typo or a half
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
  SIGNAL packets, short codes), `tls13.odin`: a small TLS 1.3 client (Odin has none in core; certificates are NOT checked, see its header: fine for DERP
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

## Encryption with WireGuard (`chat --wireguard`, optional)
The Link has no encryption; WireGuard adds it and a virtual LAN (10.73.82.1 / .2). It is **not a relay**: the tunnel uses the same UDP path the punch
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
  The TLS to the relay does not check its certificate, so someone in the middle can pretend to be the relay: they still cannot read the sealed packets, they can
  drop them. A relay sees who talks to whom and how much.

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
- **No encryption by default.** The random session id in the code is a shared secret that keeps strangers' packets out, not a key. Anyone who can read the
  traffic can read the chat. Do not send passwords, or use `--wireguard` (above).
- A random-port symmetric NAT against another strict NAT cannot be guessed (no birthday attack: it would need hundreds of sockets).
- The CHANGE-REQUEST test measures the router **and this computer's firewall** together (an unprogrammed Windows firewall drops unsolicited UDP,
  which is correct for security and does not stop punching, because the first outgoing packet opens it).
- A port mapping lasts 2 hours (the lease) and is removed by `LinkClose`; there is no renewal yet. Not for the web build (`core:net`).
- The simulation proves the logic, not the real world: NAT counters shared with other devices on the same router, carrier NAT quirks and
  provider TURN servers can differ. The guessing in particular assumes the NAT port counter is not touched between the measurement and the punch.

## Tests
```
odin test p2p -strict-style -vet                 # 42 tests: codes, STUN/TURN/PCP/NAT-PMP/UPnP parsing against independent values and fake routers,
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
