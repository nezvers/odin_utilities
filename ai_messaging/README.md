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
ai.MessengerSendFolder(m, member, "my_project", {".git", "node_modules", "*.tmp"}, now)   // a whole folder, all or nothing
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
Up to 4 outgoing and 4 incoming transfers at once. Guest to guest goes through the host. `MessengerCancel` stops a transfer from either side.

### Folders (`bundle.odin`)
`MessengerSendFolder` sends a whole folder as ONE stream (records of folder / file with relative path, executable flag and size, then an end mark), so it
uses the same chunks, credit window and sha256 as a file and arrives all or nothing: the receiver builds `<name>.part/` and renames it to `<name>`
(or `<name> (1)`) when the hash matched; a failure deletes the staging folder. Hidden files and empty folders are kept, symbolic links are skipped,
`excludes` (names or `*.ext`) are left out anywhere in the tree (the tool excludes `.git node_modules __pycache__ .DS_Store` unless told otherwise).
A hostile sender is limited: every path component is cleaned (no `..`, no absolute path, no names Windows refuses), depth 24, path 240 bytes, 20000
entries, the size limit counts the whole stream, and executable bits are only applied with `keep_executable`. Setting up a coworker's project is
`/send name my_project`.

### Bugs found and fixed in review
- A frame the host could not forward (receiver queue full) was silently lost, which corrupts a reliable stream: now the transfer is cancelled for the
  sender and an ERROR event is raised (the queue also grew from 64 to 96).
- A chunk that did not fit the window was read again from the file next time (and could hash twice): it is read once and waits in `pending`.
- A receiver that stalled in the middle of a transfer kept its `.part` for ever: it fails after 30 s; an unanswered offer is refused after 60 s.
- No way to stop a transfer: `MessengerCancel` / `/cancel n`. A cancelled or failed receive never leaves a `.part` file or staging folder.
- The window was 8 chunks (about 130 KB/s at 50 ms): now 12 of the 16 the link holds.
- Strings in the config were kept by reference (a temporary string dangled): copied now.

### Still open (known)
- No resume: a transfer that breaks starts again from zero. A symlink INSIDE the receive folder that points outside is followed by the OS.
- One file at a time per transfer slot and no compression; a huge folder is limited by the 20000 entries.

## Tool
`odin run ai_messaging/tool/amsg -- <channel> [--name N] [--dir received] [--auto-accept] [--host|--guest] [--no-lan] [--stun] [--json] [--exclude name] [--include-git] [--keep-exec]`
Typed lines go to everybody; `/to name text`, `/send name|all path` (a file or a folder), `/yes n` `/no n`, `/cancel n`, `/who`, `/code`, `/quit`; a pasted
code joins or accepts. Output is one event per line: text mode `<name> text`, `<name> (to you) text`, `* ...`; with `--json` every line is one JSON object
(`{"event":"text","from":"bob","to":"all","text":"..."}`, events: info, code, connected, joined, left, text, member, file_offered, file_progress,
file_done with `path` and `message`, error), so a program or an agent parses it without guessing.

## Tests
`odin test ai_messaging -strict-style -vet` (10 tests, ~0.3 s, real loopback sockets): frame codec, safe file names, folder stream round trip in any
chunking and hostile streams, discovery beacon, folders between members, cancel,
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
