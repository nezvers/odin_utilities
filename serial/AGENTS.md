# serial: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `serial.odin` (binary `Writer`/`Reader` over user buffers with a counting pass, versioned length-prefixed chunks, file frame with crc32, `RleWrite`/`RleRead`; safe on untrusted data, builds for js so tests are in `serial_test.odin`). Used by `tilemap/tilemap_serial.odin` (tilemap layers by name, atlas, tileset), `box2d_odin/physics_serial.odin` (`PhysicsDesc` of bodies, shapes, hinges: write, read with validation, `PhysicsCreate`), `scene/level.odin` (entities as prefab instances with overrides by field path, asset names, `LevelAttach`). `scene/level_integration_test.odin` is the whole level file pipeline.
