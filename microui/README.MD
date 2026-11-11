# MicroUI
Glue code for `vendor:microui` (immediate mode UI) with raylib and karl2d. The library doesn't allocate: everything lives in a `MuiState` struct that you place in a global or your own struct.    

`odin run demo_raylib` / `odin run demo_karl2d`    
Demo shows the default microui windows: widgets, log panel with text input, style editor and background color sliders.    

```odin
import mu "vendor:microui"
import mui_rl "microui/raylib"     // or mui_k2 "microui/karl2d"

mui_state: mui_rl.MuiState
ctx: ^mu.Context

ctx = mui_rl.Init(&mui_state)       // after the window is created
// every frame
mui_rl.Update(&mui_state)           // feed input
mu.begin(ctx)
// ... mu.window(...), buttons, sliders ...
mu.end(ctx)
// while drawing
mui_rl.Render(&mui_state)
// on exit
mui_rl.Cleanup(&mui_state)
```

## Parts
- `microui.odin` (package `microui_utils`) - framework agnostic helpers: `MuiLog` text log (`LogWrite`, `LogRead`, `LogIsUpdated`, `LogReset`), `U8Slider` for colors, `AtlasToRGBA`.
- `raylib/microui_raylib.odin` - `Init`, `Update` (text, mouse, wheel, shift/ctrl/alt, enter, backspace), `Render` (rects, atlas text and icons, scissor clipping), `Cleanup`.
- `karl2d/microui_karl2d.odin` - same API for Karl2D. It expects the Karl2D repository next to other libraries, like this library. Holding backspace repeats.
