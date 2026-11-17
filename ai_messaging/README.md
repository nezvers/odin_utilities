# ai_messaging

A channel where people and AI agents talk to each other directly (no server): text to everybody or to one member, files, and whole folders.
It is a layer over `p2p` (hole punching, reliable channel) and `serial` (message frames).

Status: the channel, the files and the terminal tool `amsg` work and are tested. Starting the agents themselves (Claude or another
provider inside `amsg`) is **not built yet**, see "Next".

## 1. Setup
- Needs the Odin compiler on your PATH (`odin version` prints something).
- Build the tool once, from the `odin_utilities` folder:
  - Windows: `odin build ai_messaging/tool/amsg -out:amsg.exe -o:speed`
  - Linux / macOS: `odin build ai_messaging/tool/amsg -out:amsg -o:speed` (macOS is not tested yet)
- Put it on your PATH so any folder can call it:
  - Windows: copy `amsg.exe` into a folder that is on the PATH (or add its folder: Settings, Environment Variables, Path).
  - Linux / macOS: `cp amsg ~/.local/bin/`
- Check: `amsg` with no arguments prints the usage line.
- Allow it through the firewall the first time (Windows asks). Same-computer use needs nothing else.
- One executable does everything; there is nothing to install next to it.

## 2. Quick start (two terminals, same computer or same network)
- Pick any channel name. Everybody who uses the same name meets in the same channel. Here it is `my-team`.
- Terminal 1 (the first member hosts the channel):
  - `amsg my-team --name alice`
  - It prints `* connected as alice (member 0), hosting`.
- Terminal 2 (finds the host by the channel name, nothing to copy):
  - `amsg my-team --name bob`
  - Both terminals print `* bob joined` / `* alice joined`.
- Type a line and press Enter: everybody in the channel gets it.
  - In terminal 2: `hello alice, the build is green` -> terminal 1 shows `<bob> hello alice, the build is green`.
- Start order: if two members start at the very same moment both may host. Start the first one, then the others, or force the roles with
  `--host` (one member) and `--guest` (all others).

## 3. Commands you type
- A line is a tool command only when it starts with `--` and a letter. Everything else is a message to everybody, including lines that start
  with `/` (so an agent attached later keeps all its own slash commands).
- Commands:
  - `--who`: list the members (`member 0: alice (host) (you)`).
  - `--to bob text`: a private message to one member.
  - `--send bob notes.txt`: send a file to bob.
  - `--send bob my_project`: send a whole folder to bob (see "Folders").
  - `--send all my_project`: send to every member.
  - `--yes 3` / `--no 3`: accept or decline the offer number 3.
  - `--cancel 3`: stop transfer number 3 (works for sending and receiving, the other side is told).
  - `--code`: show your code, for another network (see section 5).
  - `--quit`: leave.
- To send a message that really starts with `--` or looks like a command, put a space in front: ` --force is a flag name`.
- A pasted session code (one long word) joins or accepts a reply, see section 5.

## 4. Sending files and folders (example)
- Alice sends bob a file and a project folder:
  - `--send bob build/game.zip`
  - `--send bob my_project`
- Bob sees the offer (the number is the transfer number):
  - `* alice offers the folder "my_project" (42 files, 1830211 bytes): --yes 1 or --no 1`
  - `--yes 1`
- When it is done, both sides print the result:
  - bob: `* folder transfer 1 from alice done, 1830211 bytes, saved as received/my_project`
  - alice: `* folder transfer 1 to bob done, 1830211 bytes`
- Where files land: the `received` folder in the current folder (change with `--dir other_folder`). An existing name is never overwritten:
  a second `my_project` arrives as `my_project (1)`.
- Skip the question with `--auto-accept` (start bob as `amsg my-team --name bob --auto-accept`). Do that only for members you trust.
- Folders:
  - Arrive as one new folder, all or nothing: built as `my_project.part` and renamed when the sha256 of the whole stream matched.
  - Hidden files and empty folders are kept (`.claude/settings.json`, `.gitignore`). Symbolic links are skipped.
  - Left out by default: `.git`, `node_modules`, `__pycache__`, `.DS_Store`. Add more with `--exclude target` or `--exclude *.tmp` (repeat the flag).
    `--include-git` keeps `.git`.
  - Executable bits are only restored with `--keep-exec` (received files never run by themselves otherwise).
- Limits (change with `--max-mb 200`): 1 GiB per transfer, 20000 files per folder, 4 transfers at a time in each direction.
- Setting up a new coworker or agent from scratch is one command: `--send carol my_project`.

## 5. Another network (over the internet)
- Names are found by broadcast, which stays on one network. For another network the members swap one line of text each way:
  - alice: `amsg my-team --name alice --host --stun` (prints `CODE: 0C0M4-...`; `--stun` puts the public address in it)
  - alice sends that line to carol (chat, mail, anything).
  - carol: `amsg my-team --name carol --guest --stun`, then pastes alice's line into the terminal. She gets a reply code (`CODE: ...`).
  - carol sends her reply line back; alice pastes it. Both print `* ... joined`.
- It uses hole punching, so it works through most home routers. When both sides are behind a strict carrier NAT it cannot connect (see
  `p2p/README.md`: relay and port forwarding options).
- There is no encryption of its own. Do not send secrets, or run it over a VPN / the WireGuard option of `p2p/tool/chat`.

## 6. For programs and agents: `--json`
- `amsg my-team --name alice --json` prints one JSON object per line, easy to parse.
- Events: `info`, `code`, `connected`, `joined`, `left`, `text`, `member`, `file_offered`, `file_progress`, `file_done`, `error`.
- Examples:
  - `{"event":"text","from":"bob","from_id":1,"to":"all","text":"hello alice"}`
  - `{"event":"file_offered","from":"alice","from_id":0,"transfer":1,"name":"my_project","size":1830211,"folder":true,"files":42}`
  - `{"event":"file_done","member":"alice","transfer":1,"incoming":true,"ok":true,"folder":true,"files":42,"size":1830211,"path":"received/my_project","message":""}`
- Commands stay the same plain lines on stdin (`--send bob my_project`, `--to bob text`, `--yes 1`).
- Every failure is an event with a reason (`"ok":false,"message":"rejected: this member does not receive files"`).

## 7. Using it from your own Odin program
- Allocate once (it is about 340 KB of fixed storage), open, then call `MessengerUpdate` every frame:
```
m: ^ai.Messenger = new(ai.Messenger)
ai.MessengerOpen(m, {channel = "my-team", name = "alice", receive_dir = "received", auto_accept = false}, p2p.LinkNow())
// every frame
ai.MessengerUpdate(m, p2p.LinkNow())
for {
    event, ok := ai.MessengerPoll(m)       // CONNECTED, MEMBER_JOINED/LEFT, TEXT, FILE_OFFERED/PROGRESS/DONE, ERROR
    if !ok { break }
    // ... show it
}
bob: u8 = ai.MessengerFindMember(m, "bob")
ai.MessengerSendText(m, ai.ALL, "hello", p2p.LinkNow())                      // or bob
ai.MessengerSendFile(m, bob, "build/game.zip", p2p.LinkNow())
ai.MessengerSendFolder(m, bob, "my_project", {".git", "node_modules", "*.tmp"}, p2p.LinkNow())
ai.MessengerFileAnswer(m, event.member, event.transfer, true, p2p.LinkNow())    // answer a FILE_OFFERED event
ai.MessengerCancel(m, bob, transfer, p2p.LinkNow())
ai.MessengerCode(m, buffer[:])  /  ai.MessengerUseCode(m, text, p2p.LinkNow())  // the pasted codes of section 5
```
- Everything is non blocking after `MessengerOpen` (it only looks up STUN servers, blocking, when `use_stun` is set).
- Fixed capacities, failures are returned (`false`) or become events; nothing grows. Strings in the config are copied.

## 8. How it works
- Topology: a star. The first member is the host, the others are its guests. The host forwards between guests and checks who is speaking
  (a frame claiming another sender is dropped). Names are made unique by the host (`bob`, `bob2`). When the host leaves, the channel ends.
- Finding the others on one network (`discovery.odin`): the host listens on the first free UDP port of 47500..47563 (several channels fit on one
  computer). A newcomer asks `WHO` (loopback + broadcast), the host answers `HERE` with its invite code, the newcomer joins and sends its reply
  code back as `JOIN`. The channel name is hashed (sha256) in those packets; it is not a secret.
- Messages (`frame.odin`): `[kind][from][to][body]`, member ids: host 0, guests 1..8, 255 = everybody.
- Files (`messenger.odin`): offer, accept or reject with a reason, 800 byte chunks over the reliable channel, a credit window of 12 chunks,
  sha256 of the whole thing at the end, a verdict back to the sender. File names that arrive are reduced to one safe name (no path, no `..`,
  no names Windows refuses), written as `name.part`, renamed when the hash matches, never overwriting.
- Folders (`bundle.odin`): one stream of records (folder or file, relative path, executable flag, size, then the bytes) and an end mark,
  carried by the same chunk machinery. A hostile sender is limited: every path component cleaned, depth 24, path 240 bytes, 20000 entries.
- Frames the host cannot pass on (receiver queue full) cancel that transfer instead of being lost silently (a lost frame would corrupt a file).

## 9. Tests
- `odin test ai_messaging -strict-style -vet` (10 tests, about 0.3 s, real loopback sockets; delete the `ai_messaging.exe` it leaves behind):
  - frame codec, safe file names, folder stream in any chunking, hostile folder streams, discovery beacon
  - pasted codes + text + a 300 KB file both ways + an empty file
  - three members found by name, forwarding, unique names, a file between guests through the host, ask / answer, a refusal with its reason, a member leaving
  - folders between members (hidden files, empty folders, exclusions, second copy next to the first, declined offer), cancel in the middle of a 20 MB file
- Also run by hand with real `amsg` processes: three members, folders and files received byte for byte identical.

## 10. Known limits
- No resume: a transfer that breaks starts again from zero.
- A symbolic link already inside the receive folder that points outside is followed by the operating system.
- No compression, so a huge folder takes as long as its size; throughput is one window per round trip (fine on a LAN, roughly 300 KB/s at 50 ms).
- The host is the single point of failure (no host migration). One channel per `Messenger`.
- No encryption of its own. Windows and Linux are tested, macOS is not.

## Next (not built): the agent side
- `amsg my-team --name carol --agent claude` would start the agent (Claude, or another provider's CLI) in the current folder and keep your
  terminal: a line you type goes to the agent as typed (only `--word` lines go to the tool), channel messages for the agent become its
  next user message, the agent's output is shown with a prefix.
- The agent sends through the same executable (`amsg say bob "..."`, `amsg send bob file`, `amsg inbox`) which reaches the running `amsg`
  over a localhost port with a random token (single executable, no separate daemon).
