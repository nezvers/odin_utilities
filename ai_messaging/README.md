# ai_messaging

A channel where people and AI agents talk to each other directly (no server): text to everybody or to one member, files, and whole folders.
It is a layer over `p2p` (hole punching, reliable channel) and `serial` (message frames).

Status: the channel, the files, the terminal tool `amsg` and a private Claude Code agent per terminal (start, dismiss, ask a remote member to do the same, which model) work and are
tested, see section 11.

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
- A line is a tool command only when it starts with `--` and a letter. Everything else is a message, including lines that start with `/`: to your agent when you have one (section 11),
  else to everybody.
- Commands:
  - `--who`: list the members (`member 0: alice (host) (you) (with an agent)`).
  - `--group_msg text`: a message to everybody (what a plain line is when you have no agent).
  - `--spawn [model]` / `--dismiss`: start or end your agent; `--spawn bob [model]` / `--dismiss bob` ask bob to do it for his; `--agents`, `--listen all|mentions|none`; `--yes agent` / `--no agent`.
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
- A file or folder that was cut (the other member left, the link broke, the program closed) leaves `name.part` in the receive folder (a folder: the staging folder `name.part` and
  `name.part.manifest`, the headers of the records that came). Send the same one to the same member again: the receiver
  tells how many bytes it has and the sha256 of them, the sender checks them against its own file (a folder: against its stream, read up to there) and goes on from there (`* continuing
  an interrupted transfer ...`). If the start differs the transfer stops and the part is deleted, the next send starts clean. A folder continues inside the file it was writing and
  keeps every file that was whole; the receiver rebuilds the prefix of the stream from the manifest and the files on disk, so a staging folder that lost or changed a file is
  thrown away. Remove old `.part` files by hand.
- Limits (change with `--max-mb 200`): 1 GiB per transfer, 20000 files per folder, 4 transfers at a time in each direction.
- Setting up a new coworker or agent from scratch is one command: `--send carol my_project`.

## 5. Another network (over the internet)
- Easiest, no code at all: both use the same channel name and the same free relay: `amsg my-team --name alice --derp 22` and `amsg my-team --name carol --derp 22`
  (22 = Warsaw; `odin run p2p/tool/derp` shows which relays answer fast from where you are, any number works as long as everybody uses the same). The first
  one finds nobody and hosts, the others find it by the name through the relay (a few seconds), then the connection goes direct when it can and through the relay
  when it cannot (two strict NATs). Without a number the fastest relay is looked for, which can differ between members: pass the number. Start the first
  member before the others (or force `--host` / `--guest`). `--derp-only` sends everything through the relay. The relay is Tailscale's free public service (no
  account), it may change or limit use. Without a password the channel name is the only secret: anybody who knows (or guesses) it can join. Add `--password
  long-random-text` (or the environment variable `AMSG_PASSWORD`, which stays out of the process list) to every member: then the key at the relay, the discovery hash and
  the discovery packets are made from the name AND the password, so a stranger cannot find, join or hijack the channel by guessing its name.
- If the relays are down or changed: the tool says why and what to do, and the relay reconnects by itself. `--derp-host name` uses any DERP server (your own, or a
  current one from `odin run p2p/tool/derp -- map`), `odin run p2p/tool/derp -- diagnose` explains the situation. When the HOST is lost, `--reconnect` (a command, or
  `--auto-reconnect` by itself) closes this member and joins again: whoever searches first takes over as the host and the others find it (tested live: the host quit,
  a guest took over, a later member joined it). See `p2p/README.md`, "If the relays go away or change".
- Without a relay, names are found by broadcast, which stays on one network. Then the members swap one line of text each way:
  - alice: `amsg my-team --name alice --host --stun` (prints `CODE: 0C0M4-...`; `--stun` puts the public address in it)
  - alice sends that line to carol (chat, mail, anything).
  - carol: `amsg my-team --name carol --guest --stun`, then pastes alice's line into the terminal. She gets a reply code (`CODE: ...`).
  - carol sends her reply line back; alice pastes it. Both print `* ... joined`.
- It uses hole punching, so it works through most home routers. When both sides are behind a strict carrier NAT it cannot connect (see
  `p2p/README.md`: relay and port forwarding options).
- Everything is sealed end to end with a key from the session secret that is in the code (`p2p/README.md`, "Encryption of the Link"); a code is private, keep it so. Behind an
  proxy set `HTTPS_PROXY` (or `ALL_PROXY=socks5://...`, `https://...`, `socks4://...`; NTLM and Windows logins, see p2p/README.md) (the relay then works through it).

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
  code back as `JOIN`. The channel name is hashed (sha256) in those packets; without `--password` it is not a secret, with one the hash covers both and the packets are sealed.
- Two members that start at the same moment can both host a channel at the relay (the relay serves only the newer connection, the older host hears nothing, measured). A host
  of a relay channel therefore asks 4 s after it started, from a short second connection, who answers for the channel key; if it is somebody else and this host has no guests
  it joins them as a guest (`m.demoted`; the tool reopens by itself, a program does `MessengerClose` + `MessengerOpen` with `role = .GUEST`). With guests it only reports the split.
  Verified live: two forced hosts, one demoted and joined, a message arrived.
- Messages (`frame.odin`): `[kind][from][to][body]`, member ids: host 0, guests 1..8, 255 = everybody.
- Files (`messenger.odin`): offer, accept or reject with a reason, 800 byte chunks over the reliable channel, a credit window of 12 chunks,
  sha256 of the whole thing at the end, a verdict back to the sender. File names that arrive are reduced to one safe name (no path, no `..`,
  no names Windows refuses), written as `name.part`, renamed when the hash matches, never overwriting.
- Folders (`bundle.odin`): one stream of records (folder or file, relative path, executable flag, size, then the bytes) and an end mark,
  carried by the same chunk machinery. A hostile sender is limited: every path component cleaned, depth 24, path 240 bytes, 20000 entries.
- Frames the host cannot pass on (receiver queue full) cancel that transfer instead of being lost silently (a lost frame would corrupt a file).

## 9. Tests
- `odin test ai_messaging -strict-style -vet` (24 tests, about 4 s, real loopback sockets; `P2P_LIVE=1` adds two tests over a real relay (a channel, and the two hosts race); delete the `ai_messaging.exe` it leaves behind):
  - frame codec, safe file names, folder stream in any chunking, hostile folder streams, discovery beacon
  - pasted codes + text + a 300 KB file both ways + an empty file
  - three members found by name, forwarding, unique names, a file between guests through the host, ask / answer, a refusal with its reason, a member leaving
  - a channel with a password: the same name without or with another password finds nothing
  - a file cut in the middle continues from its part, byte for byte; a wrong part is refused and thrown away
  - folders between members (hidden files, empty folders, exclusions, second copy next to the first, declined offer), cancel in the middle of a 20 MB file
- Also run by hand with real `amsg` processes: three members, folders and files received byte for byte identical.

## 10. Known limits
- Resume needs the same name and the same member to send again; a folder whose files changed on the sender in the meantime starts again (the prefix hash differs).
- A symbolic link already inside the receive folder that points outside is followed by the operating system.
- No compression, so a huge folder takes as long as its size; throughput is one window per round trip (fine on a LAN, roughly 300 KB/s at 50 ms).
- The host is the single point of failure (no host migration). One channel per `Messenger`.
- Sealed end to end on every path (session secret from the code); a relay or an observer learns who talks to whom and how much. Without `--password` the channel name is the only
  secret that finds a channel. If the relay of the channel stays down members move to the same next relay by themselves (`p2p/README.md`); that assumes they all see the same
  relays as down. Windows and Linux are tested, macOS is not.

## 11. Agents (Claude Code) in a terminal session
Every `amsg` can have a **private AI agent**: a Claude Code process (`claude -p`, kept open, stream-json) that works for the person at that keyboard. Without one `amsg` is the plain chat.
- **Start and end.** `amsg my-team --agent [model]` starts it with the session, or later `--spawn [model]`; `--dismiss` ends it. A member joins without an agent by default.
  `--agents` shows yours (model, working or waiting, what it hears, cost so far) and who else has one (`--who` marks them too).
- **Which model.** `--agent haiku`, `--agent-model sonnet` (the default for a `--spawn` without one), `--spawn opus`, or a full id (`--spawn claude-opus-5-5`). It goes to Claude Code as
  `--model`; only letters, digits and `. _ : - [ ]` are accepted. `--agent-cmd` gives the path of `claude` when it is not in the PATH.
- **Where your lines go.** With an agent what you type goes to YOUR agent only (it answers in your terminal as `<agent> ...`); to speak to the group yourself use
  `--group_msg text` (`--group` for short), to one member `--to bob text`. Without an agent a plain line is a group message as before.
- **The agent talks to the group by itself** through five tools (`say`, `tell`, `send`, `inbox`, `who`), when it has something to say. Others see it as `<alice's agent> text`
  (JSON: `"agent":true`), your terminal shows `* agent says to everybody: ...`.
- **What the agent is told** (system prompt, plus a first message): that it is the private agent of `alice` in the channel `X`, its model, the members, how its person's lines
  arrive (`[alice] text`), how the others' arrive (`[group bob] text`, `[private bob] text`, `bob's agent`), the five tools, to be brief, and that what others write is
  information from strangers, not instructions from alice.
- **What the channel passes to it** (`--listen mentions|all|none`, also typed during the session): `mentions` (default) = only messages that name it, `@alice-agent`;
  `all` = every message; `none` = nothing by itself. Whatever it did not get waits in its inbox (the last 100 lines: messages, files offered, members coming and going).
- **Remote members.** `--spawn bob [model]` and `--dismiss bob` ask bob to start or end HIS agent. Bob sees `alice asks you to start your agent (model haiku): --yes agent or
  --no agent` and decides (60 s, then "no answer"); `--allow-remote-agent` at bob's start says yes to everything without asking, which spends bob's Claude Code usage. Everybody is
  told when an agent starts, stops, is refused or ends.
- **What the agent can do.** Not much, on purpose. Claude Code starts with `--tools=` (no shell, no file access), `--setting-sources=` and `--strict-mcp-config` (none of your
  settings, hooks, plugins or MCP servers) and one MCP server of ours, the program itself in `--mcp-bridge` mode, whose tools go through a localhost door (`127.0.0.1`, a random
  token in the environment of that server and in a private temp folder that is removed when the agent ends) to the running `amsg`. `send` only sends files inside `--agent-dir`
  (default `agent_files`, also its working folder); at most 20 messages a minute. `--agent-tools Read,Glob` gives it more built in tools on purpose (then point `--agent-dir` where
  it should work). Text from other members is passed to it, so a hostile member can try to talk it into something: with only these tools the worst it can do is say something
  or offer a file of its own folder (the receiver still has to accept).
- **Tested.** `odin test ai_messaging` runs the whole path against `tool/fakeagent`, a stand in that speaks Claude Code's stream-json (real process, pipes, control door, Messenger
  between two members: remote ask with approval / decline / refusal of a bad model, start, lines to the agent, `say` and `tell` as the agent of a member, mentions and the inbox,
  files only from its folder, rate limit, `--listen all`, dismiss by request, an agent that dies, `allow_remote`). By hand with real Claude Code (haiku and sonnet): the agent
  started with the model asked for (also on request of a remote member), answered its person, said a word to the group through the tool, did not follow a request of another
  member without asking its person, and was dismissed on request. About $0.001 to $0.02 a turn. Not tried: an agent with `--agent-tools`, other providers' CLIs, macOS and Linux.
