# ui

An immediate mode ui for release applications and for test harness tools, with a style callback for every widget.
The layout is a port of [Clay](https://github.com/nicbarker/clay) (MIT, Nic Barker; a copy for reference is in `references/clay`, which git ignores):
sizing fit / grow / fixed / percent with min and max, padding, child gap, alignment, floating elements (popups, tooltips, windows), clipping and
scrolling containers, text wrapping, aspect ratio. Clay's element ids and its two pass sizing are kept, the macros, transitions and the debug
view are not, and the output is not rectangles but `DrawInfo` for your style procs.

## Idea
- **The library never draws.** For every element with something to show it calls a style proc of yours with the rectangle and what is known:
  `DrawInfo{kind, rect, flags, name, text, value 0..1, actual, minimum, maximum, hover, press, font_size, cursor, user}`.
  A slider from 0 to 200 at 50 gets `value = 0.25`, `actual = 50`, `text = "50.00"`, `name = "Volume"`.
- **Same batch as your frame.** `UiRender(&ctx)` only calls the style procs, so call it where the ui belongs in the frame; it opens no pass, no batch, no texture.
- **No hidden allocations.** Memory is a `ui.Storage(elements, commands, text lines, text bytes)` you own; widgets with state (scroll offset, text
  cursor, hover fade) live in a fixed `core:container/handle_map` (`UI_STATES`, `-define:UI_STATES=512`) and are dropped when not declared for a frame.
- **Problems do not crash a frame**: a full storage, a duplicate id, a floating element without its parent set a bit in `UiProblems(&ctx)`.
- **Pointer** is tested against the layout of the last frame (hit boxes kept in draw order), so a click always means what the person saw.
  `UiPointerOverUi` tells a game not to take the click.

## Use
```odin
storage: ui.Storage(512, 1024, 128, 8192)
ctx: ui.Context
ui.UiInit(&ctx, &storage, ui_default.Measure, &painter)        // the measure proc of your font, `painter` is ctx.user

// every frame
ui.UiBegin(&ctx, input, delta_time, screen_size, &style)
if ui.UiWindow(&ctx, "Settings", {40, 40}) {                    // `if` blocks close themselves
    if ui.UiButton(&ctx, "Save") { Save() }
    ui.UiToggle(&ctx, "Music", &music)
    ui.UiSlider(&ctx, "Volume", &volume, 0, 100)
    ui.UiProgress(&ctx, "Loading", loaded)
    ui.UiTextField(&ctx, "Name", buffer[:], &length)
    ui.UiDropdown(&ctx, "Quality", options[:], &quality)
    if ui.UiScroll(&ctx, "list", {ui.Grow(), ui.Fixed(200)}) { ... }
}
ui.UiEnd(&ctx)
ui.UiRender(&ctx)
```
Widgets: `UiWindow UiPanel UiRow UiColumn UiBox UiScroll UiLabel UiButton UiToggle UiSlider UiProgress UiTextField UiDropdown UiSeparator UiSpacer UiCustom`.
`UiBox` takes a whole `Decl`, `UiCustom` draws a widget of your own with a proc. A zero `Size` is what the style metrics say, `{ui.Grow(), ui.Fixed(30)}` is yours.
Names are ids inside their container: `"Save##slot2"` shows "Save" and hashes the whole string. `UiIdPath("Settings", "Volume")` finds an id from outside.

## Navigation without a pointer
`nav.odin` is input agnostic. The default actions of Godot's input map are `ui.Action`s; a glue maps keys and gamepad buttons to `Input.actions`
(ui/kit, glue_raylib and glue_karl2d do, with the keyboard and the first gamepad) and `UiBegin` applies them before the widgets are declared:

| Godot action | `ui.Action` | keys / gamepad | what the ui does |
|---|---|---|---|
| `ui_accept` / `ui_select` | `ACCEPT` / `SELECT` | Enter, Space / A | clicks the focused widget (button, toggle; a dropdown opens on its chosen option) |
| `ui_cancel` | `CANCEL` | Escape / B | closes a dropdown, a text field lets go; what is left is `UiCancelled(&ctx)` for the program to close its dialog |
| `ui_focus_next` / `ui_focus_prev` | `FOCUS_NEXT` / `FOCUS_PREV` | Tab, Shift+Tab / shoulders | the order of the layout, around the end |
| `ui_up` `ui_down` `ui_left` `ui_right` | `UP` `DOWN` `LEFT` `RIGHT` | arrows / d-pad | the nearest widget that way; a slider takes left and right as steps; a text field keeps them for its caret |
| `ui_home` / `ui_end` | `HOME` / `END` | Home, End | the first / the last widget |
| `ui_page_up` / `ui_page_down` | `PAGE_UP` / `PAGE_DOWN` | Page up, Page down | a page of widgets (the height of the scrolling container the focus is in) |

The focus is one id for mouse and keyboard (`UiFocused`, `UiFocus`, `UiIsFocused`); the style sees the `FOCUSED` flag (the default style draws a ring). A
scrolling container scrolls the focused widget into view. Overrides, right after a widget: `UiNavLink(&ctx, .DOWN, UiId(&ctx, "Quit"))` jumps to a given
widget, `UiNavBlock(&ctx, .UP)` allows no move that way. `UiAction(&ctx, .PAGE_DOWN)` does an action from code (tests, scripted input) and
`UiNavigate` / `UiActivate` are the plain moves. See `demo_common/demo_navigation.odin`: a menu, a dropdown, a scrolling list and a dialog, driven by keys only.

## Styles
A `Style` is a table of procs per `StyleKind` (PANEL, LABEL, BUTTON, TOGGLE, SLIDER, PROGRESS, TEXT_FIELD, SEPARATOR, DROPDOWN, DROPDOWN_ITEM, SCROLLBAR,
CUSTOM), a `clip` proc for the scissor (nested clips are resolved for you) and `Metrics` (font size, padding, control height).
`default_style/` (package `ui_default`) is a ready style and the model for yours: it draws through a small `Painter` (fill rect / polygon / rounded,
text, measure, clip) that the glue fills in. `demo_common/demo_styles.odin` swaps single procs for a neon look and draws a gauge as a custom element.

Rounded rectangles: `RoundedRadius(rect, rounding, max_radius)` takes the rounding as a part of the shortest side (1 = full round, a pill or a circle),
clamped to half of it and to `max_radius` pixels; `RoundedPoints` writes the polygon into a buffer of yours (`RoundedBuffer`) for a triangle fan.

## Layout of the folder
```
ui.odin files   common, id, element (types), context (Begin/End/state), layout (Clay port), widgets, style, render, rounded, ui_test.odin
default_style/  the default style + Painter
kit/            Painter and input over demo_kit (the demos use it)         glue_raylib/, glue_karl2d/   Painter + InputPoll for a plain program
demo_common/    widgets, layout, styles demos with scripted input          demo_raylib/, demo_karl2d/   thin mains
```
Run: `odin test ui`, `odin test ui/demo_common` (the scripts click real widgets), `odin run ui/demo_raylib`, `odin run ui/demo_karl2d`.

## Testing the look
Three levels: `odin test ui` (layout and behavior with a fake font), `odin test ui/demo_common` (scripted clicks on real widgets, headless) and screen captures:
`odin run ui/demo_raylib -define:DEMO_TEST=true -define:DEMO_CAPTURE=true` compares frames with `demo_common/captures/<backend>/*.png`
(see `demo_kit/README.md`). `UiCommands(&ctx)` is the third way: assert on what the style would be asked to draw, without pixels.

## Known limits
Text is measured per word each frame (no cache); the scrollbar is not draggable (wheel only); a text field edits one line of UTF-8 without selection;
an element that is declared after the floating element that names it as parent is not found (declare the parent first).
