# arena: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- arena` prints the open ones.

- [x] A playable game on the database: move, coins, scoreboard, join and leave; the module in Odin, the client from the generated schema
- [x] p2p: a host with an invite (and a reply, or one code through a free DERP relay), a guest through a tunnel; tested on one machine and live through a relay
- [x] A window on raylib and Karl2D (demo_kit), a script that plays a solo game headless and in both windows
- [ ] (high) Try it between two real computers on different networks (`host --derp --internet`, `join <code>`) and write down what happened (NAT types, relay or direct, latency)
- [x] In-window start screen: name, Play solo / Host a game / Join a game, paste and copy of the codes (kit clipboard and TextField), Escape leaves a game
- [ ] (medium) The host's p2p stepping when the window is minimised or the host joins late guests: more guests than one are served (the tunnel supports it) but this has only been tested with one
- [ ] (medium) Game: obstacles, a round timer and a winner, a second reducer with a cost (a dash), more than coins; shows more of the database (tables with indexes, a scheduled round)
- [ ] (medium) Client side prediction for the own player (the 50 ms step and the round trip make the own circle feel slightly late)
- [x] The same game from Godot (`gdextension/godot_spacetimedb`: the class `ArenaClient` with host and join, the project `arena_project/`; tested headless with a host and a guest)
- [ ] (low) A dedicated server mode (`host --no-window`) for a machine that only hosts
- [x] Join by a room name through the relay (no code to paste)
- [x] Sign in with an account in the game (`oidc`, `ui`): the name from the claims and the identity of the person in the database (tested with a provider of our own and real servers)
- [x] The sign in is remembered between runs (refresh token in a file of the user, `offline_access`)
- [ ] (medium) A module that keeps scores per person (the identity is now the one of the account)
- [ ] (low) A module that only lets in a trusted provider (`module/example/auth` shows how)
