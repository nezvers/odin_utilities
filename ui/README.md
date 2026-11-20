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

## The look: themes, fonts, icons
The default style follows **Baldr** (https://github.com/BuLEEto/Baldr, by Lee Fry and the Baldr contributors, zlib License): its colors, its corners, its typeface and its icons.
No code of Baldr is in this library; the numbers come from its theme generator and its pictures, and are credited in `default_style/default_style.odin`.
- `ui_default.THEME_DARK` and `THEME_LIGHT` are plain data (`painter.theme = ui_default.THEME_LIGHT`): the window, cards one step lighter, wells for fields, a surface above the
  cards for popups, the accent as a fill and as a soft fill, a focus ring, danger / warning / success, a shadow (a light theme needs it), state washes of 8 and 14 percent. Controls
  have corners of 8 pixels, cards of 12.
- `ui_default.ThemeFromAccent(color, dark)` makes a whole theme from one color (a brand color): the surfaces get a breath of its hue, the accent gets the lightness that reads in
  the mode, and every text is moved away from what it lies on until it has the contrast text needs (4.5 to 1 for labels, 7 to 1 for body text). The two constants are this
  generator run for a blue; a grey accent gives a grey theme that still warns in red. `ColorFromOklch`, `ColorToOklch` and `ColorContrast` are the color math under it. The
  generator is a port of Baldr's (`theme_from_seed`, zlib License), credited and marked as altered in `default_style/theme_make.odin`.
- Text is drawn in a `Face` of the painter: REGULAR, STRONG (the labels of controls, titles), ITALIC, MONO. The style sets the face, a glue draws it: `ui/kit` loads Inter and
  JetBrains Mono into the demo kit; a program on raylib or Karl2D calls `FontsLoad(&fonts)` and `PainterUseFonts(&painter, &fonts)` of the glue (or `PainterUseVectorFonts` when
  the text is drawn from outlines by the font library). A glue with one font draws every face in it.
- Icons are numbers (`ui.Icon`): the few the library names itself (FOLDER, FILE, CLOSE, CHECK, the chevrons...) and every Lucide icon through `ui_default.LucideIcon(.SAVE)`
  (the `icons` library of this repository: 188 icons as a font). `ui.UiIcon` shows one; `ui.UiButton(ctx, "Save", icon = ui_default.LucideIcon(.SAVE))` puts one before the name, a
  button with an icon and a hidden name (`"##settings"`) is a square. A painter without icons draws the file and folder pictures and the arrows with rectangles and triangles.
- A button is picked by the tag around it: `if ui.UiTagged(&ctx, "primary") { ui.UiButton(...) }`; "primary" (the accent), "secondary" (the soft accent), "outline", "ghost",
  "danger", none (a neutral fill). A slider or a progress bar with the tag "thin" is a line with a round handle. A text with the tag "title" is strong, with "dim" dim, with "mono"
  in the code face (`ui.UiTitle`, `ui.UiLabelDim`). A panel with the tag "popup" is a raised surface, with "flat" it has no shadow.
- The fonts and the icons have licenses that ask for their notices to go with a program: Inter and JetBrains Mono are under the SIL Open Font License (`assets/fonts/inter/Inter-OFL.txt`,
  `assets/fonts/jetbrains_mono/OFL.txt`), Lucide is ISC with a part under MIT (`icons/lucide/LICENSE`).

## Small widgets
`widgets_extra.odin`, after the gallery of Baldr: `UiSwitch` (a toggle as a track with a knob that slides), `UiBadge` (a word in a pill, colored by a `Tone`), `UiChip` (a choice
in a pill, with a check mark when it is on), `UiTag` (a pill with a cross: it tells whether the cross or the rest was clicked), `UiAvatar` (letters on a disc), `UiSegmented` (one of a
few options in one track), `UiBreadcrumbs` (the parts of a path, the index of the one that was clicked), `UiSpinner`, `UiTitle`, `UiLabelDim`, `UiCard` (a panel with a title), and
`UiInteract` (the pointer and the keyboard for an element the program declares itself: a row of an icon and texts that can be clicked).

## Markdown
`markdown.odin`: `ui.UiMarkdown(&ctx, source)` shows a text written in Markdown as widgets: headings as titles, paragraphs that wrap, lists (bullets and numbers, nested by
indent), quotes with a bar, fenced code in the code face in a well, rules, tables (columns of the same width, a cell wraps and has its marks, the header is strong; `MarkdownTableCell` reads a cell). It reads the text again every frame, block by block (`MarkdownNext` is the reader, for a program
that wants the blocks itself), with no tree and no memory of its own: a note that is edited is shown as it is typed. Inside of a paragraph, an entry of a list and a quote the marks are styles (rich text, below); a heading is one text in the
strong face, its marks are taken away (`MarkdownInline`). No images, no alignment of the columns of a table. `ui.UiMarkdown(&ctx, source, name)`: two views in one container need two names.

## Rich text
`richtext.odin`: `ui.UiRichText(&ctx, name, "plain, **strong**, *italic*, `code` and a [link](address)")` is a paragraph that wraps at words with several styles in it. The
layout only knows texts of one style, so the widget breaks the lines itself for the width it had in the last frame (its first frame is a plain wrapped text) and declares a
row of texts per line: one text per run of a style, with the tags "strong", "italic", "mono" and "link" for the style to draw (the default style: strong face, italic
face, code face, accent with a line under it) and to measure in. `RichNext` reads a text piece by piece for a program that wants the pieces. With `max_width` it is as wide as its text up to that width (a bubble of a chat). A paragraph keeps one widget
state (its width) and one per link. A link takes the pointer (the hand cursor) and the keyboard focus; `address, clicked := ui.UiRichText(...)` (and `ui.UiMarkdown(...)`)
give the address of a clicked link, a part of the source: opening it is the program's.

## Date and time
`date.odin`: `ui.UiDateField(&ctx, name, &date)` shows a `Date` (day/month/year) and opens a month of days: arrows go a month back and on, a click on a day takes it. The
calendar math is in the library (`DateDaysInMonth`, `DateWeekday` with Monday as 0, `DateAddMonths`, `DateIsValid`, `DateFormat`). `ui.UiTimeField(&ctx, name, &minutes, step)`
is a list of the times of a day in steps (a combo: typing "07" finds the time); the time is minutes after midnight.

## Charts
`chart.odin`: `ui.UiChart(&ctx, name, &view, series, kind, x_labels, size)` draws one or more series of points as a LINE, an AREA, BARs or a SCATTER. The axes pick round
numbers (`ChartStep`: 1, 2 or 5 times a power of ten), bars and areas stand on 0. The pointer finds the nearest point (a bar: the one under it), a click picks it, the arrows
of the navigation walk the points of the picked series; `hit, picked := ui.UiChart(...)` tells the program. The `ChartView` is the program's (what is picked) and is what
the style draws from, so **the series and the labels have to live until the frame is drawn** (keep them in the state of the program, not in a local array of the proc that
declares the frame: the compiler warns about that). The default style draws the lines across with their numbers, the names of the x values, a legend for two series or
more, a ring around the hovered and the picked point with its value, in a palette of eight colors that people who do not see every color can tell apart (Baldr's, credited
in `default_style/chart.odin`). A style of your own draws with `ChartPlotRect`, `ChartPosition` and `ChartBarRect`.

## The gallery of Baldr, remade
`demo_common/demo_gallery.odin` is the first page of Baldr's gallery (`examples/00_gallery`) with this library: the same cards (Buttons, Inputs, Menus, Choices, Project, Badges,
Date and time, Files), the same sample data, dark and light. Baldr is retained (a view builds a tree, messages change a state); here the page is declared every frame. What this
library does not do (frosted glass: the blur of what is behind a card) is left out. A second page shows every icon with its name. Its script finds the widgets by their rectangles of the last frame
(`ui.UiElementRect`, `kit.ClickAt`), because the page is laid out by the widths of its texts.

## Examples of Baldr, remade
`demo_common/demo_examples.odin` has eighteen of Baldr's examples, one per tab: `01_hello` (a counter: `if ui.UiButton(...) { count += 1 }` where the original sends a message to an
`update`), `04_controls` (check boxes, a switch and thin sliders that change the state of the program in place; the switch turns the page to the light theme), `03_scroll` (forty
cards in a scrolling region, a ghost button on each), `17_toasts` (raised cards at the top right that a click takes away: floating elements with `ui.UiInteract`) and
`02_theme_lab` (a page to judge a theme by: here its accent is picked by a tile or a hue and the theme is made on the spot with `ThemeFromAccent`) and `05_overlays` (a select,
a menu that opens from a button: `ui.UiMenu` inside of a button tag, tooltips, a card that takes a click while the cross in it keeps its own, a dialog) and `21_charts` (the
same numbers as a line, an area, bars and a scatter with `ui.UiChart`) and `09_jobs` (three downloads with their progress while the page stays live: the original
runs each on a thread that posts messages, here a download is a number that grows with the time of the frame) and `19_markdown` (a text in Markdown and how it reads, side
by side, with `ui.UiTextArea` and `ui.UiMarkdown`; the original is an editor that shows the styles while one types; its Stream button is `26_reply`: the note shown
as it arrives, some characters a frame; the buttons over the source are `08_rich`: Bold, Italic, Code, Link, Heading and List write their marks into the text) and `32_chat` with the bubbles of `29_styled_text`
(bubbles as wide as their text with styles inside, a list that stays at its newest message, a field that sends; the messages are one selectable text, which is
`27_conversation`; the panel tags "bubble" and "mine" of the default style) and `33_reading` (a page in Paper, Sepia, Dusk or Night with its
controls in the same colors, inside of a window that keeps its theme: a theme area) `20_shortcuts` (shortcuts that are set by pressing them) `07_code` (the text area with a highlighter for Odin) and `37_custom` (a star rating made in the demo: the pattern for a widget of one's own, with
`ui.UiInteract`, an element of the kind CUSTOM whose draw proc uses `ui_default.PainterOf(ctx)`, and `ui.UiNavBlock` for the arrows it takes itself) `34_mentions` (a text whose `@` offers the files of a project) and `35_spring` (folders that open under a file that is dragged and held over them:
`ui.UiDragRest(&ctx, kind, seconds)` after a widget is true once when a drag has stood still over it) and `28_lines` (the overlays of an image editor in one
CUSTOM element: a selection in dashes that march, a crop frame with its thirds, a transform box turned with its layer; `ui_default.LineDashed`, `PathDashed`,
`PathLines`, `RectCorners` in `default_style/lines.odin`) and `25_terminal` (the output of a program in its colors, with a prompt). The texts
and the sample data are the originals'. Each has its part of the script and a stored picture.

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
- **Zoom.** `GraphView.zoom` (`GraphViewZoom`, 0 is 1, `GRAPH_ZOOM_MIN` .. `GRAPH_ZOOM_MAX`): the wheel over the empty canvas zooms around the pointer. The nodes, their text and widgets are laid out once in canvas units and shown bigger or smaller
  (`Decl.zoom`, below), so everything inside of a node zooms with it; the model (`node.size`, `port.anchor`, `view.viewport`) stays in canvas units whatever the zoom. Cables, ties and the grid are drawn from the model at the zoom.
- **Minimap and view.** `GraphView` (plain data: the origin of the view, tool, selection) can be saved with the graph. `GraphMinimapTransform` gives a style the scale and the offset of the content span in its rectangle.
- A node is an absolute child of the canvas (`Decl.absolute`: out of the flow of its parent, placed at an offset from its top left corner, drawn and hit in declaration order, not a floating root), so the number of nodes is limited only by the elements of the `Storage`. Demo: `demo_common/demo_graph.odin`.

A node collapses to its title (`GraphNodeCollapse`, a double click on the title; `NODE_COLLAPSED`): its pins are not declared (`UiGraphNode` returns false for it) and its cables go to the middle of the edges of the title. A cable has a text (`GraphLinkLabel`, `LINK_LABELED`) that the style draws half way along it (`CableDraw.label`). A reroute point (`GraphRerouteAdd(graph, link, position)`) splits a cable into two through a small node (`node.reroute`: one input, one output, drawn as a dot with the two pins side by side, moved by dragging it); the color, `user` and label of the cable stay on both halves, the rules are asked first and the graph stays as it was when they refuse; with `view.reroute_on_double_click` a double click on a cable puts one there. A program that runs the plan passes the data straight through a node with `reroute` set.

Copy and paste (`graph_copy.odin`): `GraphCopy(&graph, &clipboard)` copies the selected nodes with their ports, the links that join two of them and the zip ties that gather only such links into a `GraphClipboard` that the program provides (fixed capacities `GRAPH_COPY_*`, it outlives the nodes and can be pasted into another graph); `GraphPaste(&graph, &clipboard, position)` puts the top left of the copy at a place, selects the new nodes and lets the rules decide for every link (a refused link is left out); `GraphDuplicate` does both with an offset. A pasted node tells it in its `NODE_ADDED` event (`copied_from`): a program that keeps data for a node (a plugin instance, its parameters) makes its own copy then, the `user` pointers are copied as they are. With `view.clipboard` set the canvas takes Ctrl + C, X, V (at the pointer) and D.

Undo and redo (`graph_history.odin`): `GraphHistoryInit(&history, states[:], &graph)` with storage the program provides (a ring of `GraphState` snapshots of nodes, ports, links and zip ties; a snapshot is large, so size `GRAPH_NODES`, `GRAPH_PORTS`, `GRAPH_LINKS` and `GRAPH_TIES` to the need), then `view.history = &history`: finished gestures and actions become steps (`GraphHistoryCommit` compares `graph.serial`, the count of changes) and the canvas takes Ctrl + Z and Ctrl + Y. The handles of what an undo brings back are the old ones; the program hears `RESTORED` and brings the data behind `user` in line.

Auto layout (`graph_layout.odin`): `GraphAutoLayout(&graph, origin, gap)` puts the nodes in columns by their depth from the sources, orders each column by where its inputs are (few crossings), centers the columns on each other and tells `NODE_MOVED` for every node that moved; a graph with a loop is left alone (false).

Docking (`dock.odin`): `Dock` is plain data (fixed capacities `DOCK_NODES`, `DOCK_PANELS`, no pointers into it, so it can be saved and loaded as bytes): a tree of splits whose leaves hold panels as tabs. `DockPanelAdd`, `DockPanelDock(&dock, panel, leaf, zone)` (`CENTER` makes a tab, `LEFT`, `RIGHT`, `TOP`, `BOTTOM` split the leaf), `DockPanelClose` / `DockPanelOpen`, `DockLeafOf`, `DockCheck` (the layout is consistent, for a loaded one). `UiDock(&ctx, "workspace", &dock, content)` draws it and calls `content(ctx, dock, panel, user)` for the panel shown in each leaf; a tab dragged over a panel shows where it would go (the middle or the nearest edge) and the move happens when the button goes up, after the frame was built. The handle between the parts of a split is dragged like `UiSplit`'s; `dock.serial` counts changes of the layout for a program that saves it. `DockPanelSetClosable` gives a tab a close button (`DockPanelOpen` brings the panel back, the program offers the way). Dropping a tab on the tab bar of a leaf puts it among the tabs at that place (a line shows where; `DockPanelInsert`), which also reorders the tabs of one leaf. A tab (or a title) let go where no panel takes it becomes a window of its own there (`DockPanelFloat(&dock, panel, position, size)`, `DockPanelIsFloating`); the title of such a window is dragged like a tab: let go over a panel it docks there, let go elsewhere it moves the window. A press on a floating window brings it to the front; a tab or title let go over another floating window is for nobody (nothing changes). A floating window is resized by its edges and corners like `UiWindowResizable` (`DOCK_FLOAT_MIN` is the least, the screen the most); its size and place are in the panel (`float_size`, `float_position`), so they are saved with the layout. Demo `dock` with screenshots.

## Audio controls
`widgets_audio.odin`: `UiKnob` (drag up and down, `KNOB_DRAG_PIXELS` for the whole range; wheel, navigation keys and a double click that sets the default also turn it), `UiFader` (stands up, the middle of the handle is at the pointer, `FaderHandleHeight`)
and `UiMeter` (a level and a peak mark that the program holds and lets fall, standing or lying). Each is one element with a style kind (`KNOB`, `FADER`, `METER`): value 0..1, the real number, its text, where the default is. Nothing allocates;
the scroll areas have a draggable scrollbar (the thumb keeps its place under the pointer, a press on the track centers it).

## Tree
`tree.odin`: a tree of rows that open and close (a file browser, an outline, presets in folders). The model is the program's, in fixed storage with checked handles (`Tree`, `TreeAdd` as the last child of a parent, `TreeRemove` with the subtree,
`TreeExpand`, `TreeReveal`, a node with `branch = true` shows an arrow before it has children). `UiTree(&ctx, "Files", &tree, &view, size, row_height)` shows the visible nodes (the children of open nodes) as a virtual list (only the rows in view are
declared): the arrow opens and closes, a click on a name selects, a double click or Enter activates (a branch opens too), right opens a closed branch or goes to its first child, left closes an open branch or goes to the parent, up, down, page up, page down, Home and End move.
`TreeView` tells what happened in the frame: `changed`, `activated`, `toggled` (the node that was opened or closed: a program that reads a folder when it is opened adds the children then, see the demo), and holds the selection (`selected`).
Several nodes: Ctrl and a click marks or unmarks one (the selected node is the first mark), Shift and a click marks the visible rows from the last node clicked, a plain click selects one again; `TreeMarked(&tree, out)` gives the marked nodes in the order of the tree (none marked: the selection is `view.selected`). A press on a marked node keeps the marks, so a drag moves all of them (the nodes under another moving node go with it; `view.moved_count`, `view.moved` is the first). Drag a row onto another: on a branch the middle half moves it in (as the last child, the branch opens) and the top or bottom quarter puts it before or after the branch as a sibling, on a file the top half is before and the bottom half after (a line shows where; `view.drop_zone`); Escape cancels; `view.moved` says which node moved (it is moved already: `TreeMove` is the model proc, it refuses to put a node under itself) and `view.can_drop` is the program's veto. F2 (the action `RENAME`) edits the name of the selected node in place with the whole name selected: Enter keeps it (`view.renamed`, `TreeRename`), Escape drops it.
Icons: `TreeAdd(..., icon = .FOLDER)` draws a small picture before the name (a folder that is open shows `FOLDER_OPEN`); `Icon` has a few built in (folder, file, text, image, audio, drawn by the default style with rectangles) and the numbers from `Icon.USER` up are the program's, which its own style draws (a texture, a glyph of an icon font); `UiIcon(ctx, icon, size, color)` is the same picture as a widget. For more in a row set `view.row` to a `TreeRowProc`: the program declares what comes after the arrow (a badge, a visibility toggle, colored text) and calls `UiTreeRowDefault` for the usual icon and name. `TreeViewFilter(&view, text)` shows only the nodes whose name contains the text (any case) and the nodes above them, all open (`TreeVisibleFiltered` for a program with its own rows); the nodes themselves are not changed, an empty text brings the tree back. `TreeVisible` flattens the tree into rows for a program that wants its own row look (with `UiVirtual`). Demo: `demo_common/demo_tree.odin`.

## Inspector
`UiInspector(&ctx, "Inspector", size)` (`inspector.odin`) is a panel for looking at the ui while it runs: the tree of the elements of the last frame (kind, name, indented by depth, `Text` adds the text elements), what the buffers cost against the sizes of the
The tree opens and closes: a double click or Enter on an element with children leaves its children out (`[-]` open, `[+]` closed). **Commands** lists the draw commands of the frame in order (style kind or clip or zoom, rectangle, name or text: `InspectorCommands`), **History** plots the time to declare and lay out the frame (UiBegin to UiEnd), the elements and the commands of the last 120 frames; `UiInspectorView(ctx, commands, history)` sets both from a program.
`Storage` (elements with their peak, commands, text bytes, lines, roots, states, hits), the measure cache and the frame time, and picking: with `Pick` on (or `UiInspectorPick(&ctx)` from a key) a press outside of the panel does not click what is under the pointer, it selects
that element in the tree (marked on the screen with a `HIGHLIGHT` rectangle, the hovered one orange, the selected one blue); the details show its id, rect and hit kinds. The elements are copied at the end of a frame that declared the panel into a fixed table
(`INSPECTOR_ROWS`, 1024), so a frame without it costs nothing, and its own elements are left out. The details of the selected element show what its layout was told (the sizing of each axis, padding, gap, direction, the size it got and the least one, floating, absolute, zoom, clipping and scroll); `UiInspectorDetail` gives them to a program.
A filter field keeps the rows whose name, text or kind contain what is typed (the selected one stays), and the selection follows its element when the rows change (a filter, the texts coming in). `InspectorRows`, `UiInspectorSelected` give the data to a program. Demo: `demo_common/demo_inspector.odin`.
A `Context` is big now (about 300 KB: the tables of the measure cache, the inspector, the text area rows): make it a global or allocate it, as the `Storage`.

## Lists and tables of many rows
`virtual.odin`: only the rows in view are declared, the rest of the height is a spacer, so a hundred thousand rows cost the rows on screen. The program owns the data and the selection (`VirtualList`, `selected` is `VIRTUAL_NONE` for none).
`if ui.UiVirtual(&ctx, "Files", &list, len(files), 24, size) { for row in list.first ..< list.last { if ui.UiVirtualRow(&ctx, &list, row) { ...widgets... } } }`: a click selects the row under the pointer (`list.changed`), a double click or
Enter sets `list.activated`, up, down, page up, page down, Home and End move the selection while the list has the focus (they do not move the keyboard focus away), the view follows it, the wheel and the scrollbar scroll, a button inside of a row takes its own clicks.
With `table.cells = true` the keys work inside of a row: the cell of the selected row that is the current one (`table.cell`, a column) is marked while the table has the focus, left and right move it (by place, so it follows moved columns), up and down move the row and keep the column, a click sets both, and Enter or a double click sets `table.cell_activated` (the program toggles the value, opens its editor, ... in `list.selected`, `cell`); `cell_changed` says it moved. With `table.reorderable = true` a header can be dragged to another place (a drag is not a click: it does not sort; Escape drops it): the program declares the cells of a row by place, `UiTableText(ctx, table, TableColumnAt(table, place), ...)`, and `table.moved` tells the column that was dropped. A double click on the edge of a header sets `table.fit` to its column: the table declares only the rows in view, so the program measures its cells (`UiTextWidth`) and calls `TableFit(&table, column, widest)`. `UiTable` adds a header: a click on a column makes it ascending, descending, then none (`table.sort_changed`, `sort_column`, `sort_descending`: the program sorts its own list of row numbers), the edge of a header is dragged to resize the column (`TableColumn.width`,
never below `min_width`), `UiTableRow` / `UiTableCell` / `UiTableText` declare the cells at the width of their column. A table wider than its room scrolls sideways (the wheel with Shift, a sideways wheel, or the bar under the rows; the header goes with the rows, `UiTableScrollX` / `UiTableScrollSet`); `table.fill_last` makes the last column take
the room that the others leave, so a narrow table has no empty strip. Before the size of the view is known the first frame declares a fixed height worth of rows (or ten): give a table a fixed height when its rows have many elements
and the storage is small. A tree is a list of the rows that are visible: the program flattens its tree and draws the indentation and the arrow in the row. Demo: `demo_common/demo_table.odin`.

## Timeline
A retained model with an immediate mode widget, like the node graph. The model (`timeline.odin`: `Timeline`, tracks, clips in fixed storage with checked handles, `TIMELINE_TRACKS`, `TIMELINE_CLIPS`, `TIMELINE_EVENTS` are `#config`, no allocation) is the
program's: a clip has a start and a length in the unit of the program (seconds, beats, samples), a track keeps its clips and a `user` pointer. `TimelineRules.can_place` says where a clip may be (`TimelineRuleNoOverlap` is one), `min_length` the shortest.
Every change is a `TimelineEvent` (`CLIP_ADDED`, `CLIP_REMOVED`, `CLIP_MOVED`, `CLIP_RESIZED` with what it was before, `PLAYHEAD`, `EMPTY_DOUBLE_CLICK`, `TRACK_*`) with the user pointers of the clip, its track and the timeline, through `timeline.on_event`
and/or `TimelinePollEvent`. A program that plays the clips reads them in the order of their start (`TimelineTrackClips`, `TimelineClipAt`).
`UiTimeline(&ctx, "Arrangement", &timeline, &view, size)` (`timeline_widgets.odin`) draws a ruler (ticks at 1, 2 or 5 times a power of ten), the lanes, the clips and the playhead, and returns true when the person changed something: a press on the ruler puts the playhead
(and drags it), a press on a clip selects it (Shift adds or removes) and drags it with every selected clip to another start or track, the edges resize it, an empty lane pans, a double click on one is an event, the wheel zooms around the pointer
(Shift + wheel pans), Delete removes the selected clips, a locked track (`TrackFlag.LOCKED`) keeps its clips. `TimelineView` (origin, zoom in pixels per unit, scroll, playhead, snap) is plain data a project can save.
Ctrl and a drag over the lanes (or `view.tool = .BOX`, then a drag on an empty lane) draws a box that selects the clips it touches, live (Shift keeps the selection). Shift and a drag on the ruler makes a loop range (`view.loop_start`, `loop_end`, `loop_enabled`,
`LOOP_CHANGED` events): its edges are dragged on the ruler, the style draws it as a band (`RulerDraw.loop_x`, `loop_end_x`); a plain press on the ruler is still the playhead.
Copy, cut, paste and select all work while the timeline has the focus (Ctrl + C, X, V, A, the actions of the glue): `TimelineCopy` keeps the selected clips in the timeline (up to `TIMELINE_COPIES`, with where they were relative to the earliest one and the top track),
`TimelinePaste(timeline, time, track)` makes them again, the earliest at `time` (the playhead for the pointer), the top one on `track` (the lane under the pointer, else where it was), selected, each one through the rules. A pasted clip comes as a `CLIP_ADDED` event with `copied_from`,
the clip it is a copy of, so a program that keeps data for a clip can copy that data now (the `user` pointer is the same). Automation lanes: `TimelineAutomationAdd(timeline, "Cutoff", minimum, maximum, user = &parameter)` makes a track of points (`TimelinePointAdd`, `Move`, `Remove`, up to `TIMELINE_POINTS` for all of them; the value is kept in the range, clips cannot go on it) with events (`POINT_ADDED`,
`POINT_MOVED` with the old time and value, `POINT_REMOVED`, the user pointer of the track says which parameter). The program that plays it asks `TimelineAutomationValue(timeline, track, time)` (a straight line between points, or held until the next one with `track.steps`)
or the points in order (`TimelineTrackPoints`). The lane draws the curve through `TimelineStyle.draw_curve` (the points in view and one on each side, `CurveDraw`); a point is dragged in time and value (every selected point moves by the same part of its own range), a double
click on the empty lane adds one, Delete removes the selected points, a box (Ctrl) selects them with the clips. Curve shapes: the curve that leaves a point is `LINEAR`, `HOLD` (a step), `SMOOTH` (3x^2 - 2x^3), `CURVE` (Schlick's bias: fast first and slowing down, or slow first, by `point.curve` from -1 to 1) or `S_CURVE` (Schlick's gain: steeper or flatter in the middle):
rational functions with one division and no pow, exp or log, always monotonic, end points exact (`timeline_curve.odin`: `CurveEval`, `CurveCoefficient`, `CurveSegmentPoints` for a style). `EXP` is an exponential (`(e^(c x) - 1) / (e^c - 1)`, c up to 8: a factor of about 3000 between the end and the start): the way pitch and loudness are heard; the renderer takes one multiply a sample from an exact start every 64 samples. `HERMITE` has a tangent at each end (`TimelinePointTangents(in, out)`, 0 to `TANGENT_LIMIT` = 3 times the slope of the straight line: monotone, no overshoot, 0 and 0 is the smooth step): `((a x + b) x + c) x`, no division, evaluated like the other smooth shapes; its two handles are the control points of the Bezier curve (a third of the way along, at the height of the slope), dragging one sets the tangent of its point (`CurveHandles` for a style). The shapes that repeat (`STAIRS`, `SMOOTH_STAIRS`, `PULSE`, `TRIANGLE`, `WAVE`) take their count from `curve` (`CurveCount`: 1 at 0, 30 at the limit, growing with the square so the small counts are easy; below 0 a pulse starts high), the idea of the point types of
[TIME-12](https://github.com/tiagolr/time12) (GPL, only looked at; the code is not used). The ones with edges (STAIRS, SMOOTH_STAIRS, PULSE) are evaluated exactly per sample by the renderer (2 to 3 ns a sample); TRIANGLE is a ramp per run and WAVE anchored ramps inside of a run (about 1 ns a sample). The bend macro of a track (`TimelineTrackBend(rise, fall)`) is added to the curve of every CURVE and S_CURVE
segment that goes up or down (`TimelineSegmentCurve`), it is in the coefficients of the plan, so the renderer pays nothing for it.
Ctrl and a click on a point makes its curve the next shape, a handle in the middle of
a segment bends it (or sets the count) (`POINT_SHAPED` events with the old shape). `TimelineAutomationValue` and the drawing use the same functions as the audio renderer, so what is drawn is what plays.
For the audio thread: `AutomationCompile` makes a flat plan of segments (copy it while the person edits), `AutomationRender(&plan, &cursor, time, step, block)` fills a block: the segment is found by a cursor that only moves forward (a jump back is one binary search), everything a segment
needs is computed in the plan, HOLD and the stretches before and after the points are a fill, LINEAR is a ramp started again from an exact value every 64 samples, the curved shapes are evaluated exactly only every few samples (a 125th of the segment, at most 64) and ramped between,
so the error is a small part of the change whatever the length (2e-6 for linear, 2e-4 for the curved shapes, 3e-3 for a very strong bend, exact for segments shorter than 125 samples); `AutomationRenderExact` is the per-sample reference. Measured (48 kHz, blocks of 512, 60 segments, one core):
the block renderer costs 0.1 ns a sample (hold), 0.3 (linear), 0.4 (smooth, bias, S) against 62 ns for asking `TimelineAutomationValue` for every sample and 3.4 to 4.2 ns for the exact value of every sample from the plan with a binary search, about 150 to 650 times faster than the first; the cheap bias costs about a seventh of
a `pow` (0.95 ns against 6.6 ns including the loop). The ideas: [exp without exp()](https://musicdsp.readthedocs.io/en/latest/Synthesis/189-fast-exponential-envelope-generator.html) and its drift (re-anchor in chunks), [Schlick's bias and gain](https://arxiv.org/abs/2010.09714) (Barron generalizes them), sample accurate automation as a
target and a delta per sample ([JUCE forum](https://forum.juce.com/t/sample-accurate-parameter-automation/50277?page=2)).
Ctrl + C, X, V work on the selected points when no clip is selected (`TimelineCopyPoints`, `TimelinePastePoints`: at the playhead, on the lane under the pointer, curves with them); `view.value_snap` puts the values of dragged and added points on a grid of the lane. Alt and a drag of one of two or more selected clips stretches the clips and the selected markers from the end that is farther from the pointer: the starts and the lengths scale together (`TimelineClipsSnapshot`, `TimelineClipsStretch`, which always work from the snapshot; the rules decide for each clip, one that may not be there keeps its last place). Alt and a drag of the first or last selected point (of two or more) stretches the selection from the other end: sideways scales the times, up makes the far end taller (a rising wedge): `TimelinePointsSnapshot` and `TimelinePointsStretch`, which always work from the snapshot. Pattern tools on the selected points, with events like any edit
(`timeline_points_edit.odin`): `TimelinePointsFlip` (values upside down), `TimelinePointsMirror` (backwards, curves reversed with it), `TimelinePointsRotate(from, to, amount)` (around inside a range), `TimelinePointsRepeat` (a copy after the selection); in the widget they are Alt + I (`INVERT`), Alt + R (`REVERSE`), Alt + D (`REPEAT`) and Alt + Left / Right (`ROTATE_LEFT`, `ROTATE_RIGHT`: by the snap step, around the loop or the whole timeline) on the selected points. The bend macro of an automation lane is set by the control in its top right corner (two bars, the segments that rise and the ones that fall: drag up or down; shown while the lane is hovered or bent) or by the wheel with Alt over the lane (Shift: the segments that fall).
Undo and redo (`timeline_history.odin`): `TimelineHistoryInit(&history, states[:], &timeline)` with storage the program provides (a ring of `TimelineState` snapshots, the handle maps, so handles stay right), `view.history = &history`: finished edits become steps and Ctrl + Z, Ctrl + Y (Ctrl + Shift + Z) walk through them, a `RESTORED` event says that everything was replaced.
`Modifier.ALT` is new in the input (the glues set it). Duplicate (Ctrl + D, the action `DUPLICATE`) puts a copy of the selected clips right after the last of them, on the tracks they are on, selected (it uses the copy of the timeline). Ctrl and the wheel make the tracks taller or shorter
around the pointer (`view.track_zoom`, `TIMELINE_TRACK_ZOOM_MIN` .. `MAX`; the time zoom stays); the style gets the heights already multiplied. Markers (`TimelineMarkerAdd`, `Move`, `Remove`, `TIMELINE_MARKERS`) are named points of time with events (`MARKER_ADDED`, `MARKER_MOVED` with the old time, `MARKER_REMOVED`): a flag in the upper half of the ruler and a line down through the tracks, dragged by the flag,
removed by Delete when selected; a double click on the ruler is a `RULER_DOUBLE_CLICK` event for the program to put a marker there. With `view.snap_to_edges` starts and ends of clips (the start or the end, whichever is nearer), markers, the loop and the playhead snap to the edges of other
clips, to markers and to the playhead when they are within `view.snap_pixels` (8), else to the grid. Lanes, clips, the ruler and the playhead are drawn by `TimelineStyle` procs (`timeline_style.odin`, default in `default_style/timeline.odin`) from the model, only what is in view, so thousands of clips cost the ones on screen. Demo: `demo_common/demo_timeline.odin`.

## Colors in a text area
`highlight.odin`: `ui.UiTextArea(..., highlight = ui.HighlightCode, highlight_user = &ui.HIGHLIGHT_ODIN)` draws the words of every row in view in the colors of what they
are. A highlighter (`ui.TextHighlight`) cuts a row into `ui.TextSpan`s, each with a tag; the area declares a text per span, placed by the same measure as the caret. The
default style has the colors of the tags `ui.SYNTAX_KEYWORD`, `_TYPE`, `_STRING`, `_NUMBER`, `_COMMENT` (`ui_default.SyntaxColor`). `HighlightCode` reads languages that
look like C or Odin by a `HighlightLanguage` (keywords, types, the marks of comments, the quote of raw strings). What goes over several lines (a block comment, nested
in Odin, a raw string) is carried from row to row in a `state` number: the area runs the highlighter over all rows once when the text changed and keeps the state of every
row with its cached rows, so a frame only asks for the rows in view. A string in quotes ends with its row. Nothing is allocated; at most `AREA_SPANS` (96) spans a row.

## The output of a program
`ansi.odin`: `ui.UiAnsiText(&ctx, output)` draws a text with the colors and styles its escape sequences ask for (what a compiler, a test runner or git writes): bold, dim,
italic, the 16 colors (`ANSI_COLORS_DARK` / `ANSI_COLORS_LIGHT`, or a palette of the program), the 256 colors and a color by its parts. `ui.UiAnsiLine` draws one line and
carries the style to the next (`AnsiState`): for a long log declare only the lines in view with it. `AnsiNext` is the reader, run by run, for a program that wants the
runs. The text is read every frame it is shown, nothing is kept or allocated. Bold and italic are the tags "strong" and "italic" on a text in the code face: the default style draws them in JetBrains Mono Bold, Italic and Bold Italic
(`Face.MONO_STRONG`, `MONO_ITALIC`, `MONO_STRONG_ITALIC`). A ground behind a run is a rectangle of the kind FILL, underline the tag "underline". Every other escape sequence (moving the cursor,
clearing) is skipped: `UiAnsiText` shows a log. A program that moves the cursor needs the screen below.

## A screen of cells
`ansi_screen.odin`: `screen := ui.AnsiScreenMake(cells[:], 80, 24)`, `ui.AnsiScreenWrite(&screen, bytes)` (in any pieces: an escape sequence or a letter may be cut between two
writes), `ui.UiAnsiScreen(&ctx, &screen)`. The caller owns the cells (`ui.AnsiCell`: a letter and its style), nothing is allocated. Read: letters (UTF-8, one cell each),
`\r \n \b \t`, the cursor moves (`A B C D E F G H f d s u`, ESC 7 and 8), erasing (`J K X P @`, an erased cell keeps the ground that is set), inserting and deleting lines
(`L M`), reverse index, reset, and the styles of `UiAnsiText`. Modes, titles and character sets are skipped. The lines that scroll off the top go to a history that the caller gives (`AnsiScreenMake(cells, columns, rows, history)`, a ring of rows: the oldest is lost
when it is full, `ESC [ 3 J` empties it); the wheel over `UiAnsiScreen` scrolls the view back through it (`AnsiScreenScroll`, `AnsiScreenFollow`, `AnsiScreenViewCell`), and
a view that is scrolled back stays on what it shows while lines arrive. A wide letter (`AnsiRuneWidth` is 2: Chinese, Japanese, Korean, emoji) takes two cells and is a text
of its own, two cells wide, so that what follows it stays on the grid; a combining mark goes on the letter before it. Writing or erasing over half of a wide letter
makes the other half an empty cell. The width table covers the ranges that matter, not all of Unicode; ambiguous widths are 1. A full screen program (an editor, a pager) asks for the alternate
screen with `ESC [ ? 1049 h` (the older 47 and 1047 too): with room for a second buffer (`AnsiScreenMake(..., history, alternate)`) the two buffers swap places, the program
draws on a clean screen (1049 saves the cursor and the style) and the screen as it was comes back with `l`; while it is shown nothing feeds the history and the view
cannot be scrolled back (`AnsiScreenAlternate`). Without room for it the sequences are skipped. The cursor is a block over its cell. `AnsiScreenRow` gives the text of a row (a test, a copy). Selection of the cells is not done.

## Editing commands for a text
`textformat.odin`: what the buttons of an editor do to the text of a `ui.UiTextArea` or `ui.UiTextField` from outside of it. `ui.UiTextWrap(&ctx, id, buffer[:], &length,
"**", "**")` puts marks around the selection (around the cursor when nothing is selected, the cursor between them) and takes them away when they are already there;
`ui.UiTextLinePrefix(&ctx, id, buffer[:], &length, "- ")` does the same with a mark at the start of the line of the cursor; `ui.UiTextSelectionOf(&ctx, id)` gives the
selection. The widget gets the focus back, so the typing goes on, and the change is a step of its undo history.

## Selecting text that is read
`select.odin`: everything declared inside of `ui.UiTagged(&ctx, ui.TEXT_SELECTABLE)` (labels, wrapped texts, the paragraphs of rich text and Markdown) is one text to the
pointer: a press on it and a drag select from letter to letter, over lines and from one text into the next (the messages of a chat, the blocks of a page). The copy
action puts the selection on the clipboard (a new line between two texts, none between the runs of one paragraph), a press somewhere else or the cancel action lets it
go; `ui.UiTextSelected(&ctx)` gives the text, `ui.UiTextSelectionClear` lets it go. A press on a widget (a button, a link) stays the widget's and lets the selection go, except a press on a scroll bar, the header of a table or the edge of a column
(`ui.UiTextSelectionKeep`): the selection stays while the list is scrolled or the columns are moved. One selection for the
whole ui, kept as a text (its place among the elements of the frame) and a byte in it: right while the texts before it stay the same. A list that only declares its
rows in view (`UiVirtual`, `UiTable`) is told to the selection: `group := ui.UiSelectRows(&ctx, "log", count, row_text, user)` right before it and `if ui.UiSelectRow(&ctx,
group, row) { ... }` around the text of every row it declares. A place in a row is the row and a byte of its text, so it stays right while the list scrolls, and the rows
between the ends of the selection, in view or not, are copied from `row_text(user, row)` (the text of any row; valid until the end of the frame). A row may have several texts (a table:
`cells` of `UiSelectRows`; the selectable texts of a row are its cells in the order they are declared, in a `UiTableCell` the cell is the column, so the selection stays on
its columns when they are moved: give `cells` the number of columns and `row_text` the text of a column; a copy has the columns in column order) and `row_text(user, row, cell)` gives the text of one of them: a copy has
a tab between the cells of a row and a new line between the rows. With the id of the scrolling list and the height of its rows (`UiSelectRows(..., cells, scroll, row_height)`) Shift with the up and down arrows, the left and right arrows (over the border of a cell into the next cell, of a row into the
next row) and Page up and down also moves the end to rows that are out of view and scrolls the list to show it. A double click selects the word under the pointer (held and moved it goes on by words; a word that goes over the runs of a paragraph is one), a third click the whole text, held and moved by paragraphs (a label, or the
paragraph with all of its runs and lines). Shift and a click extend the selection to there; the select all action takes every selectable text (while the pointer is over the
text or a part is selected, and no text field is edited). The selection follows the pointer one frame behind. Shift with the arrows, Home or End moves its end by a letter, a line or to the end of its line (not while a text field is edited).

## Completion in a text area or field
`complete.odin`: `inserted, item := ui.UiComplete(&ctx, "Message", buffer[:], &length, items[:])` right before the `ui.UiTextArea` of the same name: after a trigger
(`@` by default) at the start of a word, the items that contain what was typed since are offered in a list under the caret (at most `COMPLETE_ROWS`, 8). The arrows
choose, Enter or a click writes the item in place of the typed word with a space after it, Escape closes the list for that word. The items that start with the word come
first, then those that have it at the start of a part (after a dot, a dash, a slash, an underscore, a space or at a capital), then the others, in the order of the items
within each; the part that matched is drawn in the strong face and the accent color (the range is in `cursor` and `anchor` of the DROPDOWN_ITEM). It is declared before the area because
it takes the keys of the open list out of the input, so the area does not move its caret or break the line by them. The items are looked through every frame the list
is open; `CompleteQuery` finds the word at the caret for a program that searches by itself. It works the same before a `ui.UiTextField` (Enter then picks and does not
submit, the arrows stay in the list). An inserted item is a step of the undo history of the widget.

## Shortcut field
`shortcut.odin`: `changed, listening := ui.UiShortcutField(&ctx, name, &chord, pressed, key_name)` is a shortcut that is set by pressing it. A click or the confirm key makes it
listen; the next key that goes down, with the modifiers held, is written into the `ui.Chord` (modifiers and a key number of the program). Escape lets go, Backspace
takes the shortcut away, the focus going elsewhere ends it. The ui does not know the keys of a framework: the program passes the key that went down in this frame
(`pressed`, never a key that only is a modifier) and a proc that names a key; `ChordFormat` writes "Ctrl+Shift+S". While `listening` a program keeps its own
shortcuts off. What the operating system takes for itself (Alt+Tab) never arrives: holding those off is the work of the window system, not of the ui.

## A list that is read
`ui.VirtualList.text = true` (a `ui.Table` has one: `table.list.text`): the list takes the wheel and the bar but not the pointer or the keys (no row is picked), so a press on a row is for the selection of text.
See the selection below.

## A part in a theme of its own
`ui_default.ThemeAreaSet(&painter, 0, theme)` and `if ui.UiTagged(&ctx, ui_default.ThemeAreaTag(0)) { ... }`: everything declared inside is drawn with that theme (a
page in sepia inside of a dark window, a preview of a theme), its controls and a popup declared there too. Up to `THEME_AREAS` (4) areas; `ThemeAreaClear` ends one. It
works through `Style.before_draw`, a proc the renderer calls before every draw command, where the default style swaps the theme of the painter by the tags of the
command. A command carries its innermost `ui.DRAW_TAGS` (4) tags: deeper inside of other tags the area is not seen.

## Measuring text
A text is measured with the tags it was declared in (`ctx.measure_tags`, `ui.UiMeasureHasTag(&ctx, "mono")` for a measure proc): the default style measures a "title" in its
strong face and a "mono" text in its code face, so they get the room they are drawn in and wrap where they should. A text area measures its lines the same way.

Every size of a text goes through a cache (`measure.odin`): a table of `UI_MEASURE_CACHE` slots (2048) in the context, found by a 64 bit hash of the bytes, the length and the font size, overwritten by a text that lands on the same slot (no growing, no aging).
A frame that shows the same texts as the last one calls the measure proc of the glue zero times. `UiMeasureCacheClear` forgets everything (a new font), `UiMeasureCacheScale(ctx, scale)` clears when the UI scale changed (`ui_kit.Begin` calls it; call it
yourself with the raylib and Karl2D glue when the scale can change), `UiMeasureCacheStats` gives the hits and the misses.

## Editing text
`UiTextField` has a selection (anchor and cursor in bytes: `WidgetState`, `DrawInfo.anchor` for the style): the pointer drags one, a double click takes a word, Shift with the arrows, Home and End extends it, Ctrl moves and deletes by words, typing and pasting replace it.
The rows of a text area (where its lines wrap) are kept from one frame to the next for up to `UI_TEXT_AREA_CACHES` areas (4): they are found again only when the text, the width, the wrap, the font size or the measure cache (a new font or scale, `UiMeasureCacheClear`) changed, so an area that is only shown costs a hash of its bytes and a copy of its rows.
`Input.modifiers` (Shift, Ctrl, the command key of a Mac is Ctrl) and the actions `COPY`, `CUT`, `PASTE`, `SELECT_ALL` (Ctrl + C, X, V, A; glues map them, and drop the typed letter when Ctrl is held) drive it.
Vector text (the font library, `odin_utilities/font`): `ui_raylib.PainterUseVectorText(&painter, &system)` and `ui_karl2d.PainterUseVectorText` draw the text of the ui from the outlines of a font (the Slug method or the Scanline Sweeper) instead of the framework's bitmap font, so text is sharp at any size and under the UI scale. `system` is a `font_raylib.TextSystem` / `font_karl2d.TextSystem` made after the window exists (`TextSystemInit(&system, font_bytes, .SLUG)`). The size of a text stays the height of its line, so the layout does not change (the glyphs are a few percent wider than raylib's bitmap font, which cuts every advance to a whole pixel). With the vector text of the glue the labels are batched: the text of a run of widgets is one draw call, drawn when a shape, a clip or the end of `UiRender` comes (`Style.render_end`, `Painter.flush`, `ui_default.PainterFlush`: a glue that collects something flushes in the procs that draw shapes). `odin run ui/tool/vector_text` shows it on raylib. `-define:DEMO_VECTOR_TEXT=slug` (or `scanline`) runs every kit demo with vector text, and `odin run demo_kit/tool/captures -- --karl2d --vector-text slug ui` checks the pictures (`demo_common/captures/raylib_slug`, `karl2d_slug`).

Accessibility (`accessibility.odin`): after `UiEnd`, `UiAccessNodes(&ctx, nodes[:])` lists what the last frame showed as nodes with a role (`TEXT`, `BUTTON`, `CHECKBOX`, `SLIDER`, `TEXT_FIELD`, `COMBO_BOX`, `TAB`, `DISCLOSURE`, ...), a name, the shown value, the state (`focused`, `disabled`, `on`, `selected`, `open`), the rectangle and whether Tab stops there, in the order of the layout; `UiAccessFocused` gives the node that has the keyboard, `UiAccessDescribe(&ctx, buffer)` writes one line per node (`button "Save" [focused]`). It is made from the draw commands and hit boxes of the last frame, so a frame that does not ask pays nothing. A screen reader bridge reads it, and so can a test or an agent that drives the ui by what it says and not by where it is.

Combo box (`widgets_combo.odin`): `UiCombo(&ctx, "Font", options, &selected, size, max_rows)` is a dropdown with a search field on top of its list: typing narrows the options to those that contain the text (`UiMatchText`, any case), up and down and Page up and down walk the matches, Enter or a click takes one, Escape or a click elsewhere closes it, and at most `max_rows` matches show (the wheel and the keys scroll the rest). Only one list is open at a time, so its text is a fixed buffer of the context (`UI_COMBO_FILTER`). Demo `combo` with a screenshot.

Color picker (`colorpicker.odin`): `UiColorPicker(&ctx, "Tint", &color, &alpha, size)` is a square for saturation and brightness, a hue bar, an optional alpha bar, a swatch and the three channels as drag values; true in the frames the person changes the color. Tab reaches the square and each bar, and the arrow keys move the focused one. The picker keeps the hue and the saturation that were chosen in its state (a gray or a black has none in RGB), and takes a color that the program set meanwhile. `ColorHsvToRgb`, `ColorRgbToHsv`, `ColorToHex` and `ColorFromHex` (`#rgb`, `#rrggbb`, `#rrggbbaa`) are plain helpers. Style kinds `COLOR_FIELD` and `COLOR_STRIP` (the default style draws small cells: the painter has no gradients). Demo `color` with screenshots.

Undo and redo in text (`textundo.odin`): the text field and the text area that have the focus take Ctrl + Z and Ctrl + Y (Ctrl + Shift + Z). The history is the whole text after each edit, in a fixed pool of the context (`UI_TEXT_UNDO_BYTES`, `UI_TEXT_UNDO_STEPS`): a typed word is one step, a run of backspaces is one, a paste, a cut or a delete is one each. Another field getting the focus, or a text that the program changed itself, starts a new history; a text over half of the pool has none.

The clipboard: `UiClipboardSet` / `UiClipboardGet`; a glue that knows the system's connects it (`ui_raylib.ClipboardInstall(&ctx)`), without it the text stays in a buffer of the context (`CLIPBOARD_LOCAL` bytes), so copy and paste work inside of the program and in the tests.
Karl2D has no clipboard: its glue uses the local one. Pasted newlines and tabs become spaces (a field is one line).
`UiTextArea(ctx, name, buffer, &length, size, wrap)` is the same for several lines (`textarea.odin`): Enter makes a new line, up and down keep the column, Home and End go to the start and the end of a row (with Ctrl: of the text), page up and down move by the rows in view,
a selection runs over rows, the view follows the cursor and has a scrollbar. The rows are found each frame from the text and the width in a fixed table (`UI_TEXT_AREA_LINES`, 2048: a longer text shows its first rows) and only the rows in view become elements
(the line of text, the rectangles of the selection and the caret are absolute children), so a long text costs the rows on screen. Style kinds `TEXT_AREA`, `TEXT_SELECTION`, `TEXT_CARET`. `UiTextCursor` tells where the cursor is.

## Zoom of one container
`Decl.zoom` (0 or 1: none): the children of the container are laid out in logical units (the room they have is its size divided by the zoom, the origin is its top left corner) and shown `zoom` times bigger around that corner. Drawing goes through
`Style.zoom` (the default style moves its painter: `Painter.scale` and `Painter.offset`, the glue draws a point as `p * scale + offset`), hit boxes, `UiElementRect` and the pointer stay in screen space, so widgets inside need no change
(a slider still reads the pointer against its rectangle). A floating element attached to something inside of the container (a popup, a tooltip, a dropdown list) is laid out in the same logical units and shown zoomed with it (its root announces the zoom: `ZOOM_BEGIN` and `ZOOM_END` around it, the clip of an element outside of the zoom is converted); its rect is on the screen like every other. A scroll area inside of it keeps its offset in logical units, and the wheel moves it by a step of the screen (`WidgetState.zoom`), so it scrolls the same distance on the screen at every zoom. A zoomed container inside of a zoomed one is not zoomed again.

## UI scale
`ui_default.Painter.scale` (0 is 1) makes the whole ui bigger or smaller, for a high DPI screen or a setting for people who want it bigger. The layout and every style keep working in logical units; the glue does the rest at the two borders:
the painter multiplies every coordinate and size it draws (text is measured at the drawn size and the answer is divided, so the layout gets logical sizes) and the pointer and the screen size are divided
(`InputPoll(scale)`, `ScreenSize(scale)` of the raylib and Karl2D glue, `ui_kit.Begin` reads the painter). A style that draws through the painter needs no change (borders, radii and lines scale with it).
Pass `ui_default.PainterScale(&painter)` to the glue; the scale can change from one frame to the next. Demo: `demo_common/demo_scale.odin`.

## Layout of the folder
```
ui.odin files   common, id, element (types), context (Begin/End/state), layout (Clay port), widgets, widgets_extra, style, render, rounded, graph* (node graph), ui_test.odin
default_style/  the default style + Painter (themes, faces, icons), extra.odin (the look of widgets_extra)
kit/            Painter and input over demo_kit (the demos use it)         glue_raylib/, glue_karl2d/   Painter + InputPoll for a plain program
demo_common/    widgets, layout, styles demos with scripted input          demo_raylib/, demo_karl2d/   thin mains
```
Run: `odin test ui`, `odin test ui/demo_common` (the scripts click real widgets), `odin run ui/demo_raylib`, `odin run ui/demo_karl2d`.

## Testing the look
Three levels: `odin test ui` (layout and behavior with a fake font) and `odin test ui/default_style` (the default style draws a frame of every widget into a painter that only counts: both themes, with and without icons), `odin test ui/demo_common` (scripted clicks on real widgets, headless) and screen captures:
The ui demos draw with Inter, JetBrains Mono and the Lucide icons (`ui/kit` loads them with `kit.FontLoad`; with `-define:DEMO_VECTOR_TEXT=slug` they are faces of the text system of the kit). The other demos of the repository draw with Fira Code, the font of every text of `demo_kit` that asks for no other.
`odin run ui/demo_raylib -define:DEMO_TEST=true -define:DEMO_CAPTURE=true` compares frames with `demo_common/captures/<backend>/*.png`
(see `demo_kit/README.md`). `UiCommands(&ctx)` is the third way: assert on what the style would be asked to draw, without pixels.

## Settings and hotkeys
`ui.UiSettings(&ctx)` gives the `Settings` of a context (`settings.odin`): `double_click_seconds` (0.35, also the time of a triple click), `multi_click_limit` (3: a
triple click selects a paragraph; 2: a third quick press starts again; 1: no selection by double click), `drag_start_distance` (5 pixels) and `drag_rest_distance` (4),
`extend_modifier` (Shift: held with a click or an arrow it extends a selection). A program with a settings page writes them; the widgets read them every frame.

Hotkeys are a `ui.KeyMap` (`keymap.odin`): for every `Action` (accept, cancel, the arrows, page up and down, copy, paste, undo, rename ...) `KEYMAP_SLOTS` (4) bindings, any one
of which does it. A `Binding` is a device (`KEYBOARD`, `MOUSE`, `GAMEPAD`), a code (the program's own number for the key or the button) and `ctrl`, `alt`, `shift` that are
`ANY`, `YES` or `NO` (so Tab and Shift + Tab are two actions). `ui.KeyMapSet`, `KeyMapClear`, `KeyMapFreeSlot` and `KeyMapConflict` edit and check it; `ui.KeyMapActions` turns
the inputs that went down in a frame into `Input.actions`. The kit (`ui_kit`) keeps the table of every demo in `ui_kit.KeyMapOf()` and starts from
`ui_kit.KeyMapDefault()`, the keys that were fixed before: `ui.KeyMapSet(ui_kit.KeyMapOf(), .COPY, 0, {device = .KEYBOARD, code = u16(kit.Key.K), ctrl = .YES})`.
The raylib and Karl2D glues of this library still have their keys fixed (see `TODO.md`).

Pictures of inputs (`glyph.odin`): `ui.UiGlyph(&ctx, glyph)` draws a keycap, a face button, a bumper, a trigger, a d-pad, a stick or a mouse button; `UiBindingGlyph` asks a
`GlyphProc` (binding to glyph; the kit has `ui_kit.GlyphOf`) and `UiBindingField(&ctx, name, &binding, pressed, lookup)` is the button of a rebinding page: it shows the picture,
a click makes it listen, the next input the program reports (`ui_kit.BindingPressed(&input)`) is the binding, Backspace takes it away, Escape lets go. A `Glyph` can carry a texture of the
program's own (`texture`, `source`): the style draws it through `Painter.draw_texture` (the kit sets it; `ui_kit.GlyphTextures[.FACE_DOWN] = {texture, source}` replaces the shape of a pad
button). The first example tab, Rebind, is a controls page of a game with two inputs per action (a key and a gamepad button), conflicts, a count of the actions done and the switch
that gives the face buttons pictures. The kit has gamepad input now: `kit.PadButton`, `Input.pad_down` / `pad_pressed` (the first pad, raylib and Karl2D), `kit.PadTap` in scripts.

## Known limits
a text field edits one line of UTF-8 (a text area several, wrapped by words);
an element that is declared after the floating element that names it as parent is not found (declare the parent first).

- **Settings and hotkeys** (`settings.odin`, `keymap.odin`): plain numbers and a table read every frame, nothing is saved and nothing tells the program that they changed; a double click is by time and place, not by the button; a binding is one input with modifiers (no sequences, no two inputs at once, no hold); two actions on one input both fire unless the program checks `KeyMapConflict`; only the kit uses the table, the raylib and Karl2D glues have fixed keys.

- **Input glyphs** (`glyph.odin`): the strings of a glyph have to live until the frame is drawn; a glyph is one picture (no "Ctrl + C" made of two caps); textures only through a painter with `draw_texture` (the kit; the raylib and Karl2D glues draw the shapes); the field takes one input and Backspace cannot be bound; a stick direction or a trigger axis has to be reported by the program as a button press; the kit reads the first gamepad only.

### Widgets

What the widgets do not do (yet): the same words are in the header of the source file of each (`Limits:`), and a limit that is lifted is changed in both places and
ticked off in `TODO.md`. Look here before relying on a widget for something it may not do.

- **UiMarkdown** (`markdown.odin`):
  - no images, no HTML, no footnotes, no reference links or bare addresses as links, no setext headings (underlined with = or -), no `~~~` fences, no language for a fenced block
  - a list is nested by two spaces of indent and is not checked (a list item holds one paragraph: no block of its own inside), a quote is its lines as text (no block inside)
  - a heading is one text in the strong face: its marks are taken away, not drawn; a table has no alignment of its columns and every column is as wide as the others
- **UiRichText** (`richtext.odin`):
  - marks: strong, italic, code, links; `~~strike~~` is taken away, not drawn; no underline, no colors, no images
  - a link that is broken over two lines is two links with the same address; a run keeps the innermost `ui.DRAW_TAGS` (4) tags, so a paragraph inside of three tags loses the outer ones
  - lines are broken by the width the paragraph had in the last frame (the first frame is plain); a word wider than the line is not cut
- **selection of read text** (`select.odin`):
  - one selection for the whole ui; a text outside of a list is a place by its index among the elements, right only while the texts before it stay the same
  - a list needs UiSelectRows and a row_text proc (at most UI_SELECT_GROUPS, 8, lists in a frame); a row has a cell for each selectable text and a copy has a tab between them (columns in column order for a table)
  - a copy is cut at UI_SELECT_BYTES (4096); letters are runes (a mark or an emoji sequence is several); no right-to-left text, no touch, no menu; the end follows the pointer one frame behind
  - no selection in an icon, an image or a text of a widget (a field has its own selection); Shift + arrows move the end of a selection by letters, lines and pages; a double click selects a word and a drag from it goes on by words, a triple click a paragraph and a drag from it by paragraphs
- **UiComplete** (`complete.odin`):
  - one trigger character, ASCII letters only match without regard to case, one match of the word in an item (the first) and a ranking by where it is, not by how often an item
  - is used; at most COMPLETE_ROWS (8) rows and no scrolling of a longer list
  - the list opens below the caret of the last frame, or above its row when it would not fit below and does; it is declared right before its field or area
- **UiShortcutField** (`shortcut.odin`):
  - one chord, no sequences; a modifier alone is not a chord; what the operating system takes (Alt + Tab) never arrives; no conflict check (the program does it, as the demo does)
  - the keys are numbers of the program: the ui has no key names and no layout of the keyboard
- **syntax colors** (`highlight.odin`):
  - HighlightCode reads languages like C or Odin by a table of words: no grammar, no language detection, a string in quotes ends with its row, numbers are a guess (digits and letters)
  - at most AREA_SPANS (96) spans in a row; the state of a row is one number, so it carries block comments and raw strings and nothing more; all rows are read again when the text changes
- **UiAnsiText** (`ansi.odin`):
  - SGR only: bold, dim, italic, underline, reverse video, the 16, 256 and RGB colors and the ground; no blink, strike or hidden text, no hyperlinks
  - it is a log: the cursor moves and clears are skipped, and the text is read again every frame it is shown (declare only the lines in view for a long one)
- **AnsiScreen** (`ansi_screen.odin`):
  - a fixed grid (no resize: make another screen and write the output again), no origin or wrap modes, no tab stops that are set; a scroll region feeds no history unless it is the whole screen
  - the width of a character is a table of the ranges that matter: ambiguous widths are 1, no grapheme clusters, no emoji sequences, no right-to-left text; a mark goes on the cell before it and one mark only
  - the history and the second buffer for the alternate screen are the caller's memory, and without the second buffer the alternate screen is skipped; no selection of cells, no mouse or paste modes, no cursor shapes or hiding
  - it only draws: nothing reads the keyboard or talks to a process; a cell is as wide as the code face's M, and a wide letter takes two of them whatever the font does
- **Theme areas** (`default_style`): four areas (`THEME_AREAS`); a draw command carries its innermost `ui.DRAW_TAGS` tags, so an area tag with three tags inside of it is not seen; a popup is in the area only when it is declared inside of it.
- **Lines** (`default_style/lines.odin`): dashes are cut at their ends, no round caps or joins on dashed paths; the pattern is by length along the path.
- **Faces** (`default_style`): the vector text of the standalone glues has 8 faces for the ui; a face a glue lacks is drawn in the nearest one it has (`FaceFallback`).
- **Dates** (`date.odin`): the Gregorian calendar, Monday first, English month names; no time zones, no ranges.
