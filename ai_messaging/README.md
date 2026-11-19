# ai_messaging

A channel where people and AI agents talk to each other directly (no server): text to everybody or to one member, files, and whole folders.
It is a layer over `p2p` (hole punching, reliable channel) and `serial` (message frames).

Status: the channel, the files, the terminal tool `amsg` and a private Claude Code agent per terminal (start, dismiss, ask a remote member to do the same, which model) work and are
tested, see section 11.

## 1. Setup
- Needs the Odin compiler on your PATH (`odin version` prints something).
- Build the tool once, from the `odin_utilities` folder: `odin run ai_messaging/tool/build` (`amsg.exe` on Windows, `amsg` on Linux and macOS (not tested yet); `-- --out PATH` puts it somewhere else).
  It records which commit of the repository the program was made from, so `amsg --version` can tell (section 13). The plain way works too: `odin build ai_messaging/tool/amsg -out:amsg.exe -o:speed`
  (its version says `commit unknown`).
- Put it on your PATH so any folder can call it:
  - Windows: copy `amsg.exe` into a folder that is on the PATH (or add its folder: Settings, Environment Variables, Path).
  - Linux / macOS: `cp amsg ~/.local/bin/`
- Check: `amsg --version` prints the version and the commit; `amsg --version --check` says whether that is the newest one on GitHub; `amsg --help` lists every command (section 12 is the complete reference).
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
(The short version; section 12 has every command and option in one table, section 14 has scenarios: team of agents, remote control of a PC, drop box, scripts.)
- A line is a tool command only when it starts with `--` and a letter. Everything else is a message, including lines that start with `/`: to your agent when you have one (section 11),
  else to everybody.
- Commands:
  - `--who`: list the members (`member 1: bob (with an agent) [same network (LAN)]`). The bracket is how your link to that member travels right now: `same network (LAN)`
    (direct, to a private address: the one that actually answered, not a guess from subnets), `direct over the internet`, or `through a relay` (it keeps trying for a direct path; `"path"`
    in `--json`: lan / direct / relay / unknown). The host sees every member's path; a guest only the one to the host, because nobody measures the path between two guests (they show
    nothing). A VPN with private addresses also reads as LAN. In code: `p2p.LinkPeerPath`, `ai.MessengerPath`.
  - `--group_msg text`: a message to everybody (what a plain line is when you have no agent).
  - `--trust ask|members|bob,carol`: how far your agent believes what other members write (section 11).
  - `--spawn [model]` / `--dismiss`: start or end your agent; `--spawn bob [model]` / `--dismiss bob` ask bob to do it for their agent; `--agents`, `--listen all|mentions|none`; `--yes agent` / `--no agent`.
  - `--to bob text`: a private message to one member.
  - `--send bob notes.txt`: send a file to bob.
  - `--send bob my_project`: send a whole folder to bob (see "Folders").
  - `--send all my_project`: send to every member.
  - `--yes 3` / `--no 3`: accept or decline the offer number 3.
  - `--cancel 3`: stop transfer number 3 (works for sending and receiving, the other side is told).
  - `--code`: show your code, for another network (see section 5).
  - `--reconnect`: leave and join again. `--version`: which build this is. `--help`: the list.
  - Agents and devices: `--spawn`, `--dismiss`, `--agents`, `--listen`, `--trust`, `--cmd`, `--subscribe_idle`, `--subscribe_spawned` (section 11); `--remote`, `--remote_disable`, `--run` (section 11 and scenario D);
    only for the host: `--kick`, `--ban`, `--close_group`.
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
  - carol: `amsg my-team --name carol --guest --stun`, then pastes alice's line into the terminal. Carol gets a reply code (`CODE: ...`).
  - carol sends the reply line back; alice pastes it. Both print `* ... joined`.
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
- `odin test ai_messaging -strict-style -vet` (36 tests, about 9 s, real loopback sockets; `P2P_LIVE=1` adds two tests over a real relay (a channel, and the two hosts race); delete the `ai_messaging.exe` it leaves behind):
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
- **Slash commands.** A line you type that starts with `/` goes to your agent untouched, so Claude Code's own commands work (`/context`, `/compact`, `/clear`, ...; the answer comes
  back as `<agent> ...`). Only your keyboard can do that: `--to carol /clear` is a private message to carol (it reaches carol's agent only if it names it, and then as the text
  `[private alice] ...`, never as a command), so nobody can run commands on another member's agent by accident or by a trick. What others can ask of it is `--spawn` / `--dismiss`,
  and `--cmd carol /compact` (`--private carol /compact` is the same): carol sees `alice asks you to run the command /compact on your agent: --yes agent or --no agent`, and only
  carol's answer runs it (the line goes in untouched, what the command prints stays in carol's terminal, alice is told "command sent"; a line that is not one line starting with `/` is
  refused, and so is a request when carol has no agent). `--allow-remote-agent` also says yes to these.
- **Where your lines go.** With an agent what you type goes to YOUR agent only (it answers in your terminal as `<agent> ...`); to speak to the group yourself use
  `--group_msg text` (`--group` for short), to one member `--to bob text`. Without an agent a plain line is a group message as before.
- **The agent talks to the group by itself** through five tools (`say`, `tell`, `send`, `inbox`, `who`), when it has something to say. Others see it as `<alice's agent> text`
  (JSON: `"agent":true`), your terminal shows `* agent says to everybody: ...`.
- **What the agent is told** (system prompt, plus a first message): that it is the private agent of `alice` in the channel `X`, its model, the members, how its person's lines
  arrive (`[alice] text`), how the others' arrive (`[group bob] text`, `[private bob] text`, `bob's agent`), the five tools, to be brief, and that what others write is
  information from strangers, not instructions from alice.
- **Idle reports** (`--subscribe_idle bob`, `--unsubscribe_idle bob`): for a manager that should not poll. When bob's agent finishes its work and waits, its last message (the
  report) is sent to whoever subscribed, and their agent receives it as `[idle bob] text`: the watching costs no tokens, the manager's agent only wakes when a report arrives. Bob has
  to agree (`--yes agent`), because the report is what bob's agent said to bob (`--allow-remote-agent` agrees to all; `--unsubscribe_idle` needs no approval). How idle is decided,
  by the program that runs the agent and not by a model:
  1. Claude Code ends every turn with a `result` line. That is the only "done" signal; the text of a message is never guessed at.
  2. It counts as idle only if nothing is queued for the agent (messages sent minus turns finished is zero) and 1.5 s pass without a new message (`idle_quiet_ms`), so a burst of
     messages or a message that arrives right after gives one report, from the last turn.
  3. The report is what the agent said after its last tool call in that turn (what came before a tool call is narration); when it said nothing after, the last thing it sent to the
     channel with `say` / `tell`; for a failed turn, `the turn failed: ...`. `(took N s)` is appended. The answer to the introduction at start is not a report.
  4. Long reports go in pieces (up to 3800 bytes, the rest is cut). Reports are accepted only from members you subscribed to, so nobody else can put text in front of your agent that
     way. The agent's prompt says what `[idle bob] ...` is, and the trust setting decides how far it acts on it. Subscriptions last as long as the two programs run (they survive the
     agent being restarted); at most 8 members can watch one agent.
- **Spawn notices** (`--subscribe_spawned`, `--unsubscribe_spawned`): for a manager that hands out work. Your agent gets `[spawned] bob's agent started (haiku). Agents of the others now: bob, carol`
  (or `... ended ...`, or `bob left the channel, their agent is gone`) whenever an agent of the channel starts or ends, so it can reorganize the workload. Nobody has to agree: those
  statuses are public in the channel already, this only decides whether your agent is told. The notice is news, not an order (the prompt says so). Off by default, lasts as long as the program.
- **Remote control of a device** (`--remote bob`, `--remote_disable [bob]`, `--run bob <command>`, `--headless`; `remote.odin`): start amsg on a device (a server, a laptop elsewhere) and give a
  member control of it. Bob can then (1) run shell commands there, `--run alice echo hi` (his agent: the `run` tool), and (2) give orders to the agent of that device: his private messages
  (and those of his agent) reach it as `[remote bob] ...`, with the authority of the person, only while the access lasts (a group message never carries it). `--remote_disable bob` (or
  without a name: everybody) takes it back, stops a running command, and bob is told (`alice took back your remote control`); the same notice comes when the program ends or the member
  leaves. `--who` marks both directions (`controls this device`, `you control their device`; `controls_this_device` / `you_control` in `--json`).
  - A device without a keyboard: `amsg <channel> --headless --password P --remote bob [--remote carol] [--agent haiku --agent-tools ...] [--remote-dir folder] [--remote-timeout 60]`.
    `--headless` does not read the standard input (the program runs until it is closed, by `--close_group` of the host or by killing it). `--remote NAME` on the command line trusts that
    name whenever it joins, so the channel must have a password (the program refuses to start without one); at the keyboard `--remote bob` is for the member that is there now and ends when he leaves.
  - What bounds it: only the person of the device grants it, one named member at a time; the host of the channel checks who sent every frame and the device checks the grant on every command
    (a modified controller that skips its own check is refused: tested); one command at a time, one line, no control characters, no input (stdin closed), stopped after 60 s
    (`--remote-timeout`) or after 4 MB of output, run in a private folder; every command is shown on the device before it runs; the output that comes back (its end, 3800 bytes, `(output cut)`
    otherwise) is cleaned of control characters and bytes that are not UTF-8, so a hostile device cannot write into the terminal of whoever asked.
  - What it does not bound: the command runs with the rights of the user that started amsg, and nothing limits what it does (that is what was granted). Do not give it to a member you
    would not give a shell. The agent of the controller can use the `run` tool: its trust setting (`--trust`) decides whether it does that for what other members ask it; the default asks its person first.
    Windows runs the command through a `.cmd` file in the private folder, other systems through `sh -c`; both were run in the tests (Windows) and the Windows run was also tried live with two
    real programs (headless device, a member typing `--run`). Not tried on Linux or macOS.
- **Log of an instance** (`--log DIR`, also with `--headless`; `log.odin`, `log_read.odin`, `tool/logview`): every message heard and sent, the commands typed at the terminal, the lines typed to the
  private agent, and what the agent does (its replies, tool calls, errors, the end of each turn with cost and seconds), joins and leaves, file transfers, remote commands. Off by default; the
  file is for its owner only (it holds private messages and typed lines: do not type secrets to an agent with the log on). Each instance writes its own file
  (`<channel>.<name>.<pid>.<instance>.<part>.amsglog.gz`), so several on one device never share anything.
  - Format: a header line (`#amsglog`, version, instance, pid, start time, channel, name, part), then one record per line, fields separated by a TAB:
    `<ms after the previous record> TAB <kind> TAB <who> TAB <ref> TAB <text>`. The text escapes only `\`, newline, carriage return and TAB (`\n`, `\r`, `\t`), so `split on TAB, 5 parts`
    parses any line. Kinds are one or two letters (`g`/`p` heard, `G`/`P` sent, `GA`/`PA` sent by the agent, `u` typed to the agent, `c` command, `i` handed to the agent, `a` `t` `e` `d` the
    agent's reply / tool call / tool error / end of turn, `j` `l` `x` `r` `R` `n` ...; all of them are listed at the top of `log.odin`). Names are written once (`@` records), not on every line.
  - Size: delta times, member numbers instead of names, short kinds, nothing logged twice (a message handed to the agent is named by its id, not written again), text over 4000 bytes cut
    (`...(+N bytes)`). The file is a series of gzip members of up to 48 KB of text (BGZF layout: plain `zcat file` reads all of it, a reader can skip members), written when a block is full, every
    10 s and when the program ends; a program that is killed loses at most the last 10 s. After 8 MB of text the next part starts. Chat and agent prose compress to about a fifth or less.
  - Traceable between logs: every text frame carries a number from its sender (the sender's instance and a counter). The sender logs it with its message (`G`, `P`, `GA`, `PA`, `u`), every receiver logs
    the same number (`g`, `p`) and the sender's instance (`I` record), so the global id `<instance>:<seq>` is the same in all the files. The agent's turns are `<run>.<turn>`: `i` (what started the
    turn, naming the message that caused it), `a` `t` `e` `d` (what came of it), and the messages the agent sent during it (`GA`/`PA` carry the turn), so a trace can go from a typed line through
    the agent to the message it sent and to the members that heard it, and on through their agents.
  - `logview FILE... --cost` shows what the agents cost: for each instance and run (a run is one start of the agent) the turns, the turns that ended in an error, the tool calls, the dollars, the seconds and the
    price per turn, a row for all the runs of an instance that had several, the total, and the five dearest turns with what started each (the message of a member, a line typed, or an idle report).
    The prices are what Claude Code reported for each turn (checked: they are per turn, not a running total); a run that was killed before its last block was written is missing that block.
  - `logview FILE... [--trace ID] [--kind g,p] [--ids] [--raw]` merges files of any number of instances into one timeline (sorted by each writer's clock: computers whose clocks differ show it),
    `--trace ID` shows only what belongs with that message or turn id (the id column of `--ids`), `--raw` prints the text as written. Empty or damaged files are skipped with a warning.
- **Orders of the host** (only the member that opened the channel; a guest who types them is told who the host is):
  - `--kick bob` (also `bob-agent`): bob's agent is dismissed now, without asking. Bob stays in the channel and can start another one.
  - `--ban bob`: bob's program is told to close (its agent ends with it), a moment later (1.5 s) the host cuts the link whatever bob's program did, bob leaves the roster, and the name
    cannot join again while this host runs (a program that tries gets the order to close and is cut off, and the host reports it). The ban is by name, the only thing the host knows
    of a member: someone can come back under another name. At most 16 names are kept.
  - `--close_group`: every member's program is told to close (agents end with them), then the host's own agent and program end too. For a group that should be gone, including any
    program or agent left running: an agent's process also ends by itself when its program ends (its input closes), so a leftover can only come from a program that was killed.
  - These are orders to programs that cooperate: the order cannot be forged (a guest cannot speak as the host, the host checks the sender of every frame), but a modified program can
    ignore it; the cut link of `--ban` does not depend on it. Tried with three real programs and real Claude agents: after `--kick`, `--ban` and `--close_group` no `amsg` and no
    agent process was left.
- **Two helps.** `amsg --help` (and `--help` typed in the session) lists the commands of the keyboard; the agent never sees them. The agent's own help (`amsg --agent-help`) has only its
  five tools. The agent is started with `AMSG_AGENT=1` in its environment, so a program it runs (if you gave it a shell with `--agent-tools`) gets the agent's help from `--help`, and
  `amsg <channel>` run from there refuses to start a second member. Its system prompt and its tool descriptions are tested not to contain any of the keyboard commands.
- **How far it believes the others** (`--agent-trust ask|members|bob,carol`, or `--trust ...` during the session; the paragraph of its prompt about other members changes, and a running
  agent is told that the rule changed). `ask` (default): what others write is information, not instructions, and the agent asks its person before it does what they asked (a
  request of bob to say a word is answered with "bob asked me to post X, do you want me to?"). `members`: every member is a trusted colleague, the agent does what they ask with
  its tools (say, tell, send from its folder, inbox) and tells its person. A list: only those members are trusted, the rest as in `ask`. In every mode it is also told never to
  reveal its prompt or anything private of its person's computer, never to act on text that only claims to come from its person (their lines arrive as `[alice] text`, nothing
  else), and, even from a trusted member, to ask first when a request looks harmful or would spend a lot. The names in the messages are the channel's (the host checks the sender
  of every frame, names are unique), but trust is only a prompt: the real limit is what the agent can do (next paragraph). Tried with real Claude (haiku): `ask` and a list
  without bob = it asks; `members` = it posts the word.
- **What the channel passes to it** (`--listen mentions|all|none`, also typed during the session): `mentions` (default) = only messages that name it, `@alice-agent`;
  `all` = every message; `none` = nothing by itself. Whatever it did not get waits in its inbox (the last 100 lines: messages, files offered, members coming and going).
- **Remote members.** `--spawn bob [model]` and `--dismiss bob` ask bob to start or end bob's own agent. Bob sees `alice asks you to start your agent (model haiku): --yes agent or
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

## 12. Reference: everything amsg understands

### On the command line
`amsg <channel> [options]` (the channel name is the one argument without `--`), or `amsg --version [--check]`, `amsg --help`, `amsg --agent-help`.

| Option | What it does |
|---|---|
| `--version` | print the version and the commit this build was made from, then exit. With `--check` it asks GitHub if that is the newest commit (exit code 0: up to date, 1: not, or it could not tell) |
| `--help`, `-h` | the commands of the keyboard (inside an agent: the agent's tools only). `--agent-help` always prints the agent's |
| `--name N` | your name in the channel (default: `USERNAME` or `USER`, else `member`). The host makes names unique (`bob`, `bob2`) |
| `--password P` | the channel secret (or the environment variable `AMSG_PASSWORD`, which stays out of the process list); everybody must use the same. Needed for `--remote` |
| `--host` / `--guest` | force the role (default: the first to start hosts, the others find it) |
| `--dir DIR` | where received files and folders land (default `received`) |
| `--auto-accept` | accept every offered file or folder without asking (only for members you trust) |
| `--max-mb N` | the largest transfer you accept, in MB (default 1024; 0 means the default) |
| `--exclude name` / `--include-git` / `--keep-exec` | what a folder you send leaves out (repeatable, `*.ext` works; `.git`, `node_modules`, `__pycache__`, `.DS_Store` by default), keep `.git`, restore executable bits of received files |
| `--json` | one JSON object per line instead of text (section 6) |
| `--no-lan` | do not look for the others by broadcast on this network |
| `--stun` | put your public address in your code (for pasted codes over the internet) |
| `--derp [N]` / `--derp-host name` / `--derp-only` | find the others through a free Tailscale relay (same number for everybody), a relay of your own, or send everything through the relay |
| `--auto-reconnect` | when the host is lost, rejoin by itself (whoever searches first becomes the new host) |
| `--agent [model]` | start your private agent with the session (`haiku`, `sonnet`, `opus` or a full model id) |
| `--agent-model M` | the model a later `--spawn` without one uses |
| `--agent-cmd path` | the `claude` program when it is not in the PATH |
| `--agent-tools Read,Glob` | give the agent more built in Claude Code tools than its channel tools (on purpose; then set `--agent-dir`) |
| `--agent-dir DIR` | the agent's working folder, and the only folder its `send` tool sends from (default `agent_files`) |
| `--agent-trust ask|members|a,b` | how far the agent believes what other members write (section 11) |
| `--listen mentions|all|none` | what the channel passes to the agent without being asked (default `mentions`) |
| `--allow-remote-agent` | say yes to every request of another member (start or end your agent, run a slash command on it): it spends your Claude Code usage |
| `--log DIR` | write the log of this instance (messages, typed lines, what the agent does, costs) into `DIR`, read it with `logview` (section 11) |
| `--headless` | no keyboard: the standard input is not read, the program runs until it is closed (by `--close_group` of the host, or by killing it) |
| `--remote name` | (repeatable) `name` controls this device whenever it joins; needs a password; see section 14, "An agent controls a PC remotely" |
| `--remote-dir folder` / `--remote-timeout seconds` | the private folder remote commands run in / how long one may run (default 60) |

Exit codes: 0 normal end, 1 the socket could not be opened (or `--version --check` says not up to date), 2 a wrong argument (the message says which).
Environment: `AMSG_PASSWORD` (the password), `HTTPS_PROXY` / `ALL_PROXY` (the relay through a proxy), `AMSG_AGENT=1` (set by amsg for its agent's process: a program the agent starts gets the agent's help and cannot start a second member).

### Lines you type in a session
A line is a command only when it starts with `--` and a letter; a leading space makes any line a plain message. Everything else (`/` lines included) is text to your agent, or to everybody when you have none.

| Command | What it does |
|---|---|
| `text` | to your agent, or to everybody without one |
| `/compact`, `/clear`, `/context` ... | a slash command of Claude Code, to your own agent untouched |
| `--group_msg text` (`--group`) | a message to everybody |
| `--to bob text` | a private message |
| `--send bob path` / `--send all path` | a file or a whole folder |
| `--yes N` / `--no N` | accept or decline offer N; `--cancel N` stops transfer N |
| `--yes agent` / `--no agent` | answer a request of another member about your agent |
| `--who` | the members, how you reach each (LAN, direct, relay), who has an agent, who controls what |
| `--code` | your code (pasted codes, section 5) |
| `--reconnect` | leave and join again (a lost host is replaced) |
| `--version` | the version and the commit of this build |
| `--help` | this list, short |
| `--quit` | leave |
| `--spawn [model]` / `--dismiss` | start or end your agent |
| `--spawn bob [model]` / `--dismiss bob` | ask bob to start or end bob's agent (bob decides) |
| `--cmd bob /compact` (`--private`) | ask bob to run a slash command on bob's agent (bob decides) |
| `--agents` | your agent and the ones of the others (model, working or waiting, cost) |
| `--listen mentions|all|none` | what the channel passes to your agent |
| `--trust ask|members|bob,carol` | how far your agent believes other members |
| `--subscribe_idle bob` / `--unsubscribe_idle bob` | your agent is told, without spending tokens, when bob's agent finishes and goes idle, with its last message |
| `--subscribe_spawned` / `--unsubscribe_spawned` | your agent is told whenever an agent starts or ends |
| `--remote bob` / `--remote_disable [bob]` | bob may run commands on THIS device and give orders to its agent / take it back (from everybody without a name) |
| `--run bob <command>` | run one command on bob's device, when bob gave you remote control |
| `--kick bob` / `--ban bob` / `--close_group` | only the host: dismiss bob's agent / remove bob and keep the name out / end the group |

### The programs
- `amsg` (`ai_messaging/tool/amsg`): the member. Build it with `odin run ai_messaging/tool/build` (it records the commit, so `--version` can tell).
- `logview` (`ai_messaging/tool/logview`): reads logs, `--trace`, `--cost`, `--kind`, `--ids`, `--raw` (section 11).
- `fakeagent` (`ai_messaging/tool/fakeagent`): a stand in for Claude Code that the tests use; you never need it.

## 13. Is my amsg up to date?
- `amsg --version` prints the version of the program and the commit it was built from, for example `amsg 1.0, commit 52e3841, built 2026-11-19 11:17 UTC`. `(+ local changes)` means the folders of the program
  (`ai_messaging`, `p2p`, `serial`) had changes that were not committed when it was built; `commit unknown` means it was built with a plain `odin build` instead of `tool/build`.
- `amsg --version --check` asks GitHub (`curl` and a network; the unauthenticated API allows 60 asks an hour) for the newest commit that touched those three folders and compares. It prints
  `up to date with the repository` (exit code 0) or `NOT the newest: the repository has 9f8e7d6 (2026-11-20): <what changed>` (exit code 1). Commits of your own that are not pushed yet make it say
  "not the newest" too: the message says so.
- Update: `git pull` in your `odin_utilities` folder, then `odin run ai_messaging/tool/build` again, then restart the running members (a running program keeps the build it started from).
- The version number (`ai.VERSION`) is raised when the behaviour or the format between members changes; members of different builds still talk when the frames are compatible, the tool does not
  check it at the connection. When something works for one member and not for another, compare their `--version` first.

## 14. Scenarios (what to do, step by step)

### A. Two people talk and swap files
Section 2 and 4. One channel name, `amsg my-team --name alice` and `amsg my-team --name bob`, then `--send bob notes.txt`, `--yes 1`.

### B. Different offices, no server (the internet)
1. Both: `amsg my-team --name alice --derp 22 --password long-random-text` and the same with `--name carol` (use the same `--derp` number everybody; `odin run p2p/tool/derp` shows which answer fast).
2. Start the first one before the others (or `--host` on one, `--guest` on the rest). `--who` shows `direct over the internet` or `through a relay`.
3. If the host drops: `--reconnect` (or start everybody with `--auto-reconnect`).
4. No relay allowed: the pasted codes of section 5.

### C. Everybody has a private agent, one person manages
1. Each person: `amsg team --name bob --agent haiku` (their own Claude Code usage; or later `--spawn haiku`).
2. The manager's agent watches without polling: `--subscribe_idle bob`, `--subscribe_idle carol` (they agree with `--yes agent`), `--subscribe_spawned`. The manager's agent receives `[idle bob] ...` when bob's agent finishes.
3. The manager gives work through their agent (`@bob-agent please run the tests and report`; mentions reach it by default) or asks others to start theirs: `--spawn carol sonnet`.
4. Trust: the default (`--trust ask`) makes each agent ask its person before doing what another member wrote; `--trust members` for a team that trusts each other; `--trust bob,carol` for named ones.
5. Costs afterwards: start everybody with `--log logs` and run `logview logs/*.amsglog.gz --cost`.

### D. An agent controls a PC remotely
The PC (the device) runs amsg without a keyboard; the person who controls it uses their own terminal and, usually, their own agent.
1. Pick a channel name and a long password. The password is required: it is what stops a stranger from taking the name that is trusted.
2. On the PC: `amsg home --name pc --headless --password "long random text" --remote me --derp 22 --log C:\amsg-logs`
   - `--remote me` means: the member called `me` may control this PC whenever it joins (that is why the password is needed).
   - Add `--agent haiku --agent-tools Read,Glob --agent-dir C:\work` if the PC should also have an agent that takes orders (`[remote me] ...` arrive with the authority of the person).
   - Put it in a scheduled task or a service so it comes back after a restart, with `--auto-reconnect` so it rejoins when the host disappears.
   - `--remote-dir folder` is where commands run (a private folder by default), `--remote-timeout 120` raises the limit of 60 s per command.
3. On your laptop: `amsg home --name me --password "long random text" --derp 22 --agent sonnet`
   - Type `--run pc dir` (or `--run pc echo hi`): the command is shown on the PC, runs with the rights of the user that started amsg there, and the end of its output (3800 bytes) comes back.
   - Or ask your agent: `run "git status" on pc` and it uses its `run` tool; what comes back reaches it as `[run pc] exit 0: ...`.
   - To work on files there: `--send pc my_project` puts a folder on the PC (it lands in the PC's `--dir`, accepted automatically only with `--auto-accept`: start the PC with it for that use).
4. Taking it back: from the PC's keyboard `--remote_disable me` (a headless PC has none: stop the program, or be the host yourself and use `--close_group`: start your laptop first with `--host`, and the PC with `--guest`, then `--close_group` ends the PC's program).
5. Safety: only the person who started the PC's amsg decides who controls it; every command is shown on the PC; one at a time, 60 s, 4 MB of output at most; output is cleaned of control characters. What it does not limit is what the command itself does:
   give this only to someone you would give a shell, and keep the password secret. Not tried on Linux or macOS (section 11).
6. Check afterwards: `logview C:\amsg-logs\*.amsglog.gz --kind c,n` shows the commands typed at the PC and what the program reported, remote commands that ran included.

### E. A new machine or a new agent gets a whole project
`--send carol my_project` (the folder arrives all or nothing, without `.git` unless `--include-git`), then `--spawn carol haiku` so carol's agent starts and can work in it (its folder is `--agent-dir`).
Or the reverse: carol sends the results with `--send alice results`.

### F. A drop box that accepts files by itself
`amsg builds --name drop --auto-accept --dir /srv/drops --max-mb 200 --json --password P`: every member's file lands in `/srv/drops` (never overwritten: `name (1)`), and the `file_done` events on standard
output say what arrived. Limit it to members you trust (the channel password) because it accepts everything.

### G. From a script or a CI job
Start `amsg ci --name runner --json --password P` as a child process: read one JSON object per line from its standard output (`text`, `file_offered`, `file_done`, `error`, ...) and write plain command lines to its
standard input (`--send alice build.zip`, `--group_msg "tests green"`, `--quit`). `--version --check` in a script has the exit code 0 only when the build is current.

### H. Keep a group in order (the host)
The host (the first to open the channel) can `--kick bob` (dismiss bob's agent), `--ban bob` (close bob's program, cut the link, keep the name out while this host runs) and `--close_group` (every program and agent ends). Start the member you trust first.

### I. Find out what happened
`--log DIR` on every member, then `logview DIR/*.amsglog.gz` (one timeline), `--trace ID` (one message through every member and agent), `--cost` (what each agent cost). Logs hold private messages: for their owner only.
