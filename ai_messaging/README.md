# ai_messaging

A channel where humans and AI agents talk to each other directly, no server: text to everybody or to one member, and file transfer. It is
a layer over `p2p` (hole punching, reliable channel) and `serial` (frames). Starting the agents themselves (Claude or another provider in
the current folder) is not part of it yet, see "Next".

```
m: ^ai.Messenger = new(ai.Messenger)                 // ~340 KB of fixed storage
ai.MessengerOpen(m, {channel = "my-project", name = "alice", receive_dir = "received", auto_accept = true}, p2p.LinkNow())
// every frame
ai.MessengerUpdate(m, p2p.LinkNow())
for event in ai.MessengerPoll(m) ...                  // CONNECTED, MEMBER_JOINED/LEFT, TEXT, FILE_OFFERED/PROGRESS/DONE, ERROR
ai.MessengerSendText(m, ai.ALL, "hello", now)         // or a member id (MessengerFindMember)
ai.MessengerSendFile(m, member, "build/game.zip", now)
```

## How members find each other
- **Same computer or network**: by the channel name alone. The first member hosts (a UDP beacon on the first free port of 47500..47563,
  so several channels fit on one computer); a newcomer asks `WHO` on loopback and broadcast, the host answers `HERE` with its invite code,
  the newcomer joins and sends its reply code back as `JOIN`. `role = .AUTO` looks for 1.5 s (plus jitter) and hosts when nobody answers;
  `.HOST` / `.GUEST` force it (use them when two members start at the very same moment).
- **Over the internet**: pasted codes, the same as `p2p/tool/chat`: `MessengerCode` shows yours, `MessengerUseCode` takes the other's.
  `use_stun = true` puts the public address in the code (blocking lookup at open).
- A star: the host forwards between guests and checks who is speaking (a frame claiming another sender is dropped). Names are made unique
  by the host (`bob`, `bob2`). When the host leaves the channel ends.

## Files
Offer, accept (or reject with a reason), chunks of 800 bytes over the reliable channel with a credit window of 8 chunks, `sha256` of the
whole file at the end, verdict back to the sender. Receiving is the receiver's decision: `auto_accept` into `receive_dir`, or a
`FILE_OFFERED` event and `MessengerFileAnswer`. Names that arrive are reduced to one safe file name (no path, no `..`, no reserved Windows
names), written as `name.part` and renamed when the hash matches, never overwriting (`name (1).ext`). Default limit 1 GiB (`max_file_size`).
Up to 4 outgoing and 4 incoming transfers at once. Guest to guest goes through the host.

## Tool
`odin run ai_messaging/tool/amsg -- <channel> [--name N] [--dir received] [--auto-accept] [--host|--guest] [--no-lan] [--stun]`
Typed lines go to everybody; `/to name text`, `/send name|all path`, `/yes n` `/no n`, `/who`, `/code`, `/quit`; a pasted code joins or accepts.
Output is one event per line (`<name> text`, `<name> (to you) text`, `* ...`) so a program or an agent can read it.

## Tests
`odin test ai_messaging -strict-style -vet` (5 tests, ~0.1 s, real loopback sockets): frame codec, safe file names, discovery beacon,
pasted codes + text + a 300 KB file both ways, three members found by name with forwarding, unique names, a file between guests through
the host with the ask/answer flow, a refusal with its reason, a member leaving. Also run by hand: three `amsg` processes, a 200 KB file
received byte for byte identical.

## Not done / limits
- No encryption of its own (use the WireGuard option of `p2p/tool/chat` or run it over a VPN); the channel name is not a secret.
- The host is the single point: no host migration. One channel per Messenger. Windows and Linux/macOS desktop only (`core:net`, `core:os`).
- Discovery by name works on one network only; over the internet somebody has to carry the codes (a pasted line, a shared note).
- Throughput: one chunk window per round trip, fine on a LAN, roughly 300 KB/s at 50 ms.

## Next (not built): the agent side
Start the agent (`claude`, or another provider's CLI) in the current folder with its stdin and stdout on pipes, run it next to `amsg`
(messages from the channel become lines on its stdin, its stdout lines become messages), keep the human's terminal as one more member.
