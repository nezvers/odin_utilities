# arena

A small multiplayer game for trying `odin_utilities/spacetimedb`: everybody moves a coloured circle on one field and picks up coins. The whole world lives in a SpacetimeDB database; the clients only send which way they hold the stick and draw the rows they subscribed to. Players find each other with `odin_utilities/p2p`: no server of anybody's, no account.

```
odin run spacetimedb/tool/setup                      # once: the server and the game module (also builds the Rust fixture when cargo is there)
odin run spacetimedb/arena/demo_raylib               # solo: starts a server and a game, nobody else can join
odin run spacetimedb/arena/demo_raylib -- host --derp      # host: prints and draws an invite code, friends join with this one code (free relay, works behind strict NATs)
odin run spacetimedb/arena/demo_raylib -- join <code>      # a friend: the code is all that is needed
```
`demo_karl2d` is the same on Karl2D. Move with WASD or the arrows. Options: `host` without `--derp` makes a code that needs a reply: the friend's program prints a reply code, paste it into the console of the host and press Enter. `--internet` adds the public address (STUN) so that a friend on another network can connect directly. `--port N` is the port of the server (3000). The last argument is your name.

The host keeps the world in `arena_server/` (a persistent database, owned by the identity in `arena_server/owner.token`), so the next start continues it.

## How it works
```
 friend's computer                                         host's computer
 arena window ── websocket/HTTP ──► 127.0.0.1:port         arena window ── websocket ──► SpacetimeDB server (module: arena/module)
                     tunnel guest ══ p2p Link (UDP) ══ tunnel host ──► 127.0.0.1:3000   ▲ the same server, scheduled step every 50 ms
```
- `module/`: the game, written in Odin and run by the database: tables `player` and `coin`, reducers `join(name)` and `set_input(dx, dy)`, and a scheduled reducer `tick` (every 50 ms) that moves players, lets them pick up coins and puts new coins on the field. A player who disconnects leaves the field.
- `schema/`: generated from the module (`odin run spacetimedb/arena/tool/schema`): the row structs, readers and writers, `CallJoin`, `CallSetInput`, the tables for the cache.
- `game/`: the client without a window (`Game`): connection, cache of the two tables, the input, smoothing of the 20 steps per second. Used by every front end.
- `session/`: the p2p side: `HostStart` (server, published module, invite code), `GuestJoin` (the codes, the tunnel to the host's database).
- `../tunnel/`: TCP over a p2p Link, so a client reaches a server that is on another computer behind NATs.
- `demo_common/`, `demo_raylib/`, `demo_karl2d/`: the window (one demo written against `odin_utilities/demo_kit`): the start screen, the game, and two scripts (the start screen with its buttons, paste and copy; a solo game) that play headless.

## Tests
- `odin test spacetimedb/arena/session`: the whole chain on one computer (host, guest, codes, tunnel, two clients that play); `ARENA_LIVE=1` also joins through a real DERP relay with one code.
- `odin test spacetimedb/arena/demo_common`: the demo's script headless; `odin run spacetimedb/arena/demo_raylib -define:DEMO_TEST=true` plays it in a window (same for karl2d).
- Needs the server and the module: `odin run spacetimedb/tool/setup`; the tests are skipped without them.

What to try next: TODO.md.
