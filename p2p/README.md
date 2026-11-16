# p2p

Connect two (up to eight) programs over the internet with **no server of your own, no account and no port forwarding**: one person
copies a short code, the other pastes it, the answer goes back the same way. Then the programs talk over UDP: unreliable messages
and reliable ordered ones (resent until acknowledged).

How it works, in one paragraph: each program asks a free public STUN server (Google, Cloudflare) *"what address do you see me at?"*
from the same socket the game uses, and puts that address and its local network addresses in a code. Both sides then send packets
at each other at the same time; every NAT sees outgoing traffic first and lets the answer in (UDP hole punching). The STUN servers
only answer one small packet at the start and carry no game traffic.

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

The code is about 85 characters (`040PB-2SAK9-7Z7A2-...`), Crockford base32 with a crc: case free, dashes and spaces ignored, a typo
or a half copied code is refused before any packet is sent. The host can paste more replies at any time (up to `MAX_PEERS` = 8).

## Files
- `stun.odin`: STUN binding request and response (RFC 5389), pure functions, the server list.
- `code.odin`: `Invite` (candidates, session, id, name) and its text form.
- `link.odin`: `Link`: socket, gathering, punching, reliable channel, events, inbox. Tests at the bottom.
- `tool/chat/`: terminal chat, the demo and the manual test. `odin run p2p/tool/chat -- host|join|selftest`.

## Use
```odin
link: ^p2p.Link = new(p2p.Link)               // ~320 KB of fixed storage (8 peers x two 16 KB windows, inbox): place it once
p2p.LinkInit(link)
servers: [p2p.STUN_MAX_SERVERS]net.Endpoint
count: int = p2p.LinkResolveStun(servers[:])    // blocking DNS, do it at start
p2p.LinkGatherBegin(link, servers[:count], p2p.LinkNow())
// frame loop: p2p.LinkUpdate(link, p2p.LinkNow())
buffer: [p2p.CODE_TEXT_MAX]byte
text, _ := p2p.InviteEncode(p2p.LinkMakeInvite(link), buffer[:])   // show it, copy it with your framework (SetClipboardText ...)
p2p.LinkSend(link, peer, data, reliable = true, now)               // false: window full, try next frame
peer, length, ok := p2p.LinkReceive(link, message[:])
```
`LinkPollEvent` reports `GATHERED`, `PEER_CONNECTED`, `PEER_FAILED` (nobody answered in 20 s), `PEER_LOST` (closed or 8 s of silence).
Binary messages: build them with `serial.Writer` / `Reader` (`odin_utilities/serial`, bounds checked, little endian, on untrusted data too).

Memory: no allocation after the `Link` exists. Capacities are constants (`MAX_PEERS`, `WINDOW`, `INBOX`, `MAX_PAYLOAD`), failures are returned
(`LinkSend` false), never grown. Time is a parameter (`now_ms`), so tests run a fake clock.

## Reliable channel
Selective repeat over a window of 16: the receiver keeps messages that arrive early and reports exactly which ones it has (next expected
sequence + a bit mask), the sender resends only the missing ones on a timer of 2x the measured round trip (doubling per resend).
Messages come out of `LinkReceive` once and in order; a peer that acknowledges nothing for 6 s is lost. A selftest over 20% random loss each
way delivers 200 messages each way in order in about 2.5 s.

## What it cannot do (be honest with players)
- **No relay.** If both sides are behind a *symmetric* NAT (a new public port per destination) or both behind carrier grade NAT (mobile data,
  some ISPs), no direct connection exists; a TURN relay would be needed and there is no free public one. The link measures it
  (`link.nat_mapping`, `link.nat_filtering`) so the program can say why a punch failed. A phone hotspot on one side usually fixes it.
- **No encryption.** The random session id in the code is a shared secret that keeps strangers' packets out, not a key. Anyone who can read the
  traffic can read the chat. Do not send passwords.
- IPv4 only. Not for the web build (`core:net` sockets): browsers need WebRTC.
- The first run on Windows asks the firewall to allow the program.

## Tests
```
odin test p2p -strict-style -vet                 # codes, STUN parsing, a fake STUN server, two links punching on loopback, 33% loss, failure after timeout
odin run p2p/tool/chat -- selftest               # both ends in one process, real STUN servers, real LAN addresses, 20% loss
odin run p2p/tool/chat -- host Ann               # computer 1
odin run p2p/tool/chat -- join Bob               # computer 2, on another network for the real NAT test
```
Two programs on one computer or one router prove the code path but not a real NAT crossing (the packets take the LAN route). For the real thing run
`host` and `join` on two networks (a phone hotspot is enough for one of them).
