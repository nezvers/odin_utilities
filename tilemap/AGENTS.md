# tilemap: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- Core: `common.odin` (types), `tilemap.odin`, `tileset.odin`, `tile.odin`, `tile_atlas.odin`, `rule_tile.odin`, `dual_grid.odin`, `editing.odin` (input helpers + paint/drag/select), `rand.odin`.
- TileID 0 is TILE_EMPTY, 255 is TILE_INVALID. Chain: Tilemap (grid of TileID) -> Tileset -> Tile (alternatives) -> TileAtlas (texture positions).
- `glue_raylib/tilemap_raylib.odin`, `glue_karl2d/tilemap_karl2d.odin` - Draw* procs.
- `demo_raylib/` - raylib demo (`odin run demo_raylib`, Odin package `demo_raylib`). Each demo file is `#+private file` with `@(private="package") state_xxx:State = {enter, exit, update, draw}`; register in `demo_raylib/demo.odin` (`state_list`, `Example` enum, `example_names`).
- `demo_karl2d/` - same demos for karl2d (`odin run demo_karl2d`); files in `demo_karl2d/game/`, states are `GameState{init, finit, update, draw}`, register in `game_state.odin` (`state_list`, `StateIndex`).
- Shared demo data (atlas/tile/tilemap buffers, textures) is in each `demo_common.odin`; demo executables set working dir to exe dir, raylib demo loads `../assets/textures/...`, karl2d demo embeds with `#load`.
- To port an example: put reusable logic in the library package, keep only input/drawing in the two demos.
