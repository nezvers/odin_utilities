# microui: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `microui.odin` (package `microui_utils`: `MuiLog`, `U8Slider`, `AtlasToRGBA`), glue `glue_raylib/microui_raylib.odin` and `glue_karl2d/microui_karl2d.odin` (`Init/Update/Render/Cleanup` on a user owned `MuiState`), demos `demo_raylib/` and `demo_karl2d/game/` (`demo_microui.odin`).
