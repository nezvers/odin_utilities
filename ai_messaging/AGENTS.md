# ai_messaging: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md (details and limits there).

Channel of humans and agents over p2p, no server.

## Channel
- `frame.odin`: wire frames over `serial`. `filename.odin`: untrusted file names. `bundle.odin`: a folder as one stream (scan/read on the sender, `BundleFeed` on the receiver, hostile-path limits).
- `discovery.odin`: LAN beacon, channel hash, ports 47500..47563; over the internet `derp_server` in the config finds the host by channel name through a DERP relay (p2p `DerpChannelKey`, `LinkDerpFind`).
- `messenger.odin` `Messenger`: star topology, roster, text, files with credit window and sha256, forwarding by the host; ~340 KB, heap. Strings in a config are copied into it (never keep a caller's temp string by reference).

## Agent side
- `agent.odin`: a `claude -p` stream-json process, no built in tools. `control.odin`: localhost door + token. `mcp.odin`: the channel as MCP tools (`amsg --mcp-bridge`).
- `session.odin`: routing, remote spawn/dismiss with approval, inbox, mentions, trust mode (ask / members / a list), host orders `--kick/--ban/--close_group`, idle reports `--subscribe_idle`, spawn notices `--subscribe_spawned`.
- `remote.odin`: remote control of a device (`--remote`, `--remote_disable`, `--run`, headless device).
- `help.odin`: two helps, keyboard commands for people and tools only for the agent, split by `AMSG_AGENT`.

## Tools and logs
- `tool/amsg` terminal member; `tool/fakeagent` stands in for Claude Code in tests; `tool/logview` + `log.odin` + `log_read.odin` (per instance log, gzip blocks, global message ids, `--log DIR`); `version.odin` (`amsg --version [--check]`; the commit comes from `odin run ai_messaging/tool/build`, which builds with `-define:AMSG_COMMIT=...`).

## Tests
- `odin test ai_messaging -strict-style -vet` (36 tests, ~9 s; `P2P_LIVE=1` adds a live relay test). `messenger_test.odin` uses real loopback sockets, `session_test.odin` the fake agent.
- `odin test <pkg>` leaves `<pkg>.exe` in the working directory: delete it.
