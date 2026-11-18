# ui

An immediate mode ui for release applications and for test harness tools, with a style callback for every widget.
The layout is a port of [Clay](https://github.com/nicbarker/clay) (MIT, Nic Barker):
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
More widgets (`widgets_more.odin`): `UiCollapsing` / `UiTreeNode` (headers with a body; opening one scrolls the container to show what it opened, with the header kept in view), `UiRadio`, `UiSelectable`, `UiListBox`, `UiTabBar`, `UiArrowButton` (repeats),
`UiDrag` / `UiDragInt`, `UiSliderInt` / `UiSliderAngle`, `UiInputInt` / `UiInputFloat`, `UiPlotLines` / `UiPlotHistogram`, `UiColorEdit3` / `UiColorButton`,
`UiLabelColored` / `UiBullet` / `UiLabelText` / `UiSeparatorText`, `UiTooltip`, `UiDisabled` (a block of disabled widgets), menus (`UiMenuBar`, `UiMenu` with submenus, `UiMenuItem` with shortcut and check),
`UiModal` (a dialog over a dimmed screen that keeps the focus), `UiWindowTitled` (a window with a title bar that is dragged), `UiWindowResizable` and `UiSplit` (see below).
Resizing by the pointer (`resize.odin`, demo `resize`), with nothing to configure and nothing for the program to keep:
```odin
if ui.UiWindowResizable(&ctx, "Workspace", initial_position = {60, 40}, initial_size = {520, 360}) {
    if ui.UiSplit(&ctx, "main", .HORIZONTAL, 0.3) {          // side by side; .VERTICAL: one above the other
        if ui.UiSplitFirst(&ctx) { ... }
        if ui.UiSplitSecond(&ctx) { ... }                     // a UiSplit inside of a section makes three sections
    }
}
```
- `UiSplit` is a container with two sections and the handle between them. It keeps the proportion (`ratio` is where it starts, or `first_size` pixels when the program thinks in pixels: the pixels are used in the first frame and become a proportion once the room is known; `UiSplitRatio` / `UiSplitSetRatio` read and set it, to save a layout), so the
  proportion stays when the container or the window changes size. It builds the handle (a bar; dragging it, or the arrow keys when it has the focus, moves the border), sizes both sections from the room
  it has, keeps each above its minimum (`min_first`, `min_second`, 40 px by default) whatever the ratio and the room, and cuts what does not fit at the edge of its section. It takes all the room it is given
  unless `size` says otherwise. A pointer pushed past a limit does not pull the border away: the border follows again from where it is. Used wrongly it still lays out right: a section left out is made empty,
  the second declared before the first works, a third one is not shown, and the `SPLIT_MISUSE` problem tells (`UiProblems`).
- `UiWindowResizable` is `UiWindowTitled` that the user also resizes: its four edges and four corners take the pointer (cursors `RESIZE_HORIZONTAL`, `RESIZE_VERTICAL` and the two diagonals, mapped by the glue),
  the edge that moves follows the pointer and the opposite one stays. It keeps its own position and size (`UiWindowPosition`, `UiWindowSize` tell them), or the program owns them: pass `position` and `size`.
  The size stays between `min_size` and `max_size` (0: none) and never above the screen, the window cannot be pushed off the screen (its title bar stays reachable) and follows a screen that shrinks.
  The body fills what is below the title bar: widgets that are `Grow()` take the room a bigger window gives, and what does not fit is cut. The bottom right corner is drawn by the style as `RESIZE_GRIP`, a
  handle as `SPLITTER` (`actual` 0 for a vertical bar, 1 for a horizontal one). The edges and the title bar take the pointer but not the keyboard focus (`HitKind.NO_FOCUS`).
- `Clip.cut`: a clipping container that only hides what does not fit. Its children are sized as in any other container (they grow and shrink to the room), a content bigger than the room does not make them
  bigger. The sections of a split, the split and the body of a resizable window use it.
``UiBox` takes a whole `Decl`, `UiCustom` draws a widget of your own with a proc. A zero `Size` is what the style metrics say, `{ui.Grow(), ui.Fixed(30)}` is yours.
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

## Frames, animation, cursor, usage
Widget state is kept for 2 frames after the last declaration (`STATE_GRACE_FRAMES`). Hover and press fades are frame rate independent; `UiAnimating(&ctx)` is true while any of them
(or a `UiAnimate(&ctx, id, target)` value of a style) is still moving, so an app that draws on demand keeps drawing while it is true. `Interaction.double_clicked` reports a second press
within 0.35 s. `UiCursor(&ctx)` is what the mouse cursor should look like (the glue's `ApplyCursor` sets it). `UiUsage(&ctx)` returns the use of the buffers now and the highest so far,
to size a `Storage` and `UI_STATES`.

## Focus memory, tags, truncated text, drag and drop, shrink priority
- Moving the focus with Tab into another window or popup returns to the widget that had the focus there (`UiFocusRoot(&ctx, window_id)` does it from code).
- `UiPushTag(&ctx, "danger")` / `UiPopTag` or the block `if ui.UiTagged(&ctx, "danger") { ... }` put tags on the widgets declared inside; a style asks `DrawInfoHasTag(info, "danger")`
  (the default style tints "danger" and "primary" controls).
- `UiLabelTruncated(&ctx, text)` (or `TextConfig{wrap = .TRUNCATE}`) ends in "..." when its container is too narrow and shows the whole text in a tooltip while hovered.
- `UiDragSource(&ctx, "kind", bytes)` / `UiDragSourceValue` after a widget, `UiDropTarget(&ctx, "kind")` and `UiDropHover` after another, `UiDragPreview(&ctx, text)`: a payload of up to 64 bytes
  kept by the ui, a drag starts 5 px from the press.
- `SizingAxis.shrink`: in an overfull container the elements with the lowest number shrink first, the others only once those are at their minimum.

## Styles
A `Style` is a table of procs per `StyleKind` (PANEL, LABEL, BUTTON, TOGGLE, SLIDER, PROGRESS, TEXT_FIELD, SEPARATOR, DROPDOWN, DROPDOWN_ITEM, SCROLLBAR,
CUSTOM), a `clip` proc for the scissor (nested clips are resolved for you) and `Metrics` (font size, padding, control height).
`default_style/` (package `ui_default`) is a ready style and the model for yours: it draws through a small `Painter` (fill rect / polygon / rounded,
text, measure, clip) that the glue fills in. `demo_common/demo_styles.odin` swaps single procs for a neon look and draws a gauge as a custom element.

Rounded rectangles: `RoundedRadius(rect, rounding, max_radius)` takes the rounding as a part of the shortest side (1 = full round, a pill or a circle),
clamped to half of it and to `max_radius` pixels; `RoundedPoints` writes the polygon into a buffer of yours (`RoundedBuffer`) for a triangle fan.

## The demo of Dear ImGui, remade
`demo_common/demo_imgui.odin` is the layout of `ShowDemoWindow` (`imgui_demo.cpp` of ocornut/imgui): a window with a title bar and
a menu bar (Menu with submenus, Examples, Tools), collapsing headers (Help, Configuration, Window options, Widgets, Layout & Scrolling, Popups & Modal windows, Tables, Inputs & Focus)
and under Widgets the tree nodes Basic, Trees, Collapsing Headers, Bullets, Text, Combo, Selectables, Tabs, Plotting, Color, Multi-component, Querying status. What the
library does not have (multi-line text input, sortable tables, docking, drag and drop, resizing) is left out. Its script drives it with the keyboard only.

## Node graph
A retained model with immediate mode widgets. The graph is the program's data (`graph.odin`: `Graph`, nodes, ports, links, zip ties in fixed storage with checked handles,
no allocation; `GRAPH_NODES`, `GRAPH_PORTS`, `GRAPH_LINKS`, `GRAPH_TIES`, `GRAPH_EVENTS` are `#config`), the widgets (`graph_widgets.odin`) draw it and change it with the pointer.
```
if ui.UiGraph(&ctx, "Audio", &graph, &view) {                  // the canvas: it pans, selects cables and ties, takes Delete
    for node in order[:ui.GraphNodesByDepth(&graph, order[:])] {   // the front node last
        if ui.UiGraphNode(&ctx, &graph, node) {                    // the title bar drags it; any widget fits in the body
            for each port: ui.UiGraphPin(&ctx, &graph, port)       // dragging a pin draws a cable, letting go over a pin it fits connects
        }
    }
}
ui.UiGraphMinimap(&ctx, "map", &graph, &view)                      // the content span (nodes and view together) and the view in it; press or drag to move the view
```
- **Rules.** `GraphCanConnect` / `GraphConnect` answer with a `ConnectResult` (`OK`, `REPLACES`, `SAME_NODE`, `SAME_KIND`, `TYPE`, `DUPLICATE`, `FULL`, `CYCLE`). Defaults: an output goes to any
  number of inputs, an input takes one cable (a second replaces it, or is refused with `refuse_when_full`; `PortFlag.MERGE` takes any number, `.SINGLE` on an output limits it),
  data types must be equal (0 fits all), loops are refused (`allow_cycles` for feedback). The program replaces or extends them with `GraphRules` (`can_connect`, `types_fit`).
- **Tell the program.** Every change is a `GraphEvent` (`CONNECTED`, `DISCONNECTED` with a `DisconnectReason`, `NODE_ADDED/REMOVED/MOVED`, `TIE_*`, `DROPPED_ON_EMPTY`) that carries the handles and
  the `user` pointers of both ports, both nodes and the graph, so a handler needs no lookup: through `graph.on_event` right when it happens and/or `GraphPollEvent` (a ring, `events_lost` counts what was never read).
- **Data transition (audio, buffers).** A port keeps a doubly linked list of its links, so splitting (an output to many) and merging (an input with `MERGE`) are walked in link order without searching.
  `GraphOrder` gives an order in which every node follows what feeds it (stable, iterative, `OrderResult.CYCLE` names a loop). `GraphCompile` writes a flat plan into your arrays: steps in order, one binding per
  (port, buffer) with a merging input as several bindings in a row, and the number of buffers needed: a buffer is reused as soon as its last reader has run (never in place). The audio thread runs the plan, the
  UI thread edits the graph: compile again after an edit.
- **Cables.** The style decides how a cable runs (`GraphStyle`, `graph_style.odin`): `route_connected` and `route_dragged` make the route (a few cubic Bezier segments, one more than the ties it passes) and can differ
  (a straight line while dragging, right angles when connected), `pickup` (take the cable of a connected input, or start a new one), `draw_cable` / `draw_tie` draw. Each cable has a **rectangle** (`bounds`, default: the control
  points) that the draw loop and the hit test use as a broad phase, and a **distance function** (`distance`, default: the nearest of 16 pieces per segment, 0 on the cable) for the exact hit test; the same arithmetic in
  a shader draws a cable with a width or a glow (`CableSegmentPoint`, `CableSegmentDistance`, `CableFlatten`). Only cables whose rectangle meets the view are drawn.
- **Zip ties.** With the tie tool (`view.tool = .TIES`) a stroke across cables gathers them into a tie: a strap that every cable passes in its own lane (side by side, in the order the stroke met them) so a bundle
  of cables runs as a ribbon and comes apart after it. A tie is moved by its middle, turned by its head (steps of `rotate_snap` degrees), removed by a stroke across it or by Delete; a cable passes up to `GRAPH_LINK_TIES`
  ties, ties made later keep the lane order of earlier ones, and a tie without cables goes away. The idea follows the zip ties of the ComfyUI extension `comfyui-zip-ties` (MIT) and the Blender add-on
  `Zip-ties-for-Blender` (GPL-3): no code was taken from either.
- **Selecting and moving nodes.** Selection is a flag of the node (`GraphNodeSelect`, `GraphSelectClear`, `GraphSelectedCount`). Pressing a title selects that node alone, unless it is already selected: then a drag moves all selected nodes
  together, in the same frame (snapped to `GraphStyle.snap` at the end, one `NODE_MOVED` each). With `view.tool = .BOX` a drag on the canvas draws a rectangle that selects the nodes it touches. Delete removes the selected nodes
  (with their cables, events included), a cable or a tie.
- **Many nodes.** `GraphNodesByDepth(graph, order, &view)` leaves out the nodes that are known to be outside of the view: they are not declared, so they cost nothing in layout. Cables and ties are drawn from the model, and `GraphNodeMove`
  keeps the anchors of the pins right for a node that is not on screen (the offsets of the pins are measured while it is).
- **Minimap and view.** `GraphView` (plain data: the origin of the view, tool, selection) can be saved with the graph. `GraphMinimapTransform` gives a style the scale and the offset of the content span in its rectangle.
- A node is an absolute child of the canvas (`Decl.absolute`: out of the flow of its parent, placed at an offset from its top left corner, drawn and hit in declaration order, not a floating root), so the number of nodes is limited only by the elements of the `Storage`. Demo: `demo_common/demo_graph.odin`.

## Audio controls
`widgets_audio.odin`: `UiKnob` (drag up and down, `KNOB_DRAG_PIXELS` for the whole range; wheel, navigation keys and a double click that sets the default also turn it), `UiFader` (stands up, the middle of the handle is at the pointer, `FaderHandleHeight`)
and `UiMeter` (a level and a peak mark that the program holds and lets fall, standing or lying). Each is one element with a style kind (`KNOB`, `FADER`, `METER`): value 0..1, the real number, its text, where the default is. Nothing allocates;
the scroll areas have a draggable scrollbar (the thumb keeps its place under the pointer, a press on the track centers it).

## UI scale
`ui_default.Painter.scale` (0 is 1) makes the whole ui bigger or smaller, for a high DPI screen or a setting for people who want it bigger. The layout and every style keep working in logical units; the glue does the rest at the two borders:
the painter multiplies every coordinate and size it draws (text is measured at the drawn size and the answer is divided, so the layout gets logical sizes) and the pointer and the screen size are divided
(`InputPoll(scale)`, `ScreenSize(scale)` of the raylib and Karl2D glue, `ui_kit.Begin` reads the painter). A style that draws through the painter needs no change (borders, radii and lines scale with it).
Pass `ui_default.PainterScale(&painter)` to the glue; the scale can change from one frame to the next. Demo: `demo_common/demo_scale.odin`.

## Layout of the folder
```
ui.odin files   common, id, element (types), context (Begin/End/state), layout (Clay port), widgets, style, render, rounded, graph* (node graph), ui_test.odin
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
Text is measured per word each frame (no cache); a text field edits one line of UTF-8 without selection;
an element that is declared after the floating element that names it as parent is not found (declare the parent first).
