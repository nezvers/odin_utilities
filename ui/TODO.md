# ui TODO

Tick an item when it is done and verified (tests pass, committed).

- [x] Wrapped text: the width of a space is measured between two letters (`textSpaceWidth`): a line that is the sum of its words, measured one by one, came out a few percent narrower than it is drawn (the spacing of the font is lost at every word) and ran over the edge of its container
- [x] Resizing by the pointer, automatic: `UiSplit` (two sections and the handle, the proportion kept by the split, minimum sizes, misuse stays laid out) and `UiWindowResizable` (edges and corners, keeps its own position and size, stays on the screen, the body grows with it); `Clip.cut`
- [x] Widget state survives one absent frame: state is dropped after 3 frames without a declaration
- [x] `UiAnimating(ctx)`: true while any hover / press fade is still moving, so a host can redraw on demand; fades use the frame rate independent `1 - 2^(-rate * dt)`; `UiAnimate(ctx, id, target)` for styles
- [x] `UiDisabled(ctx)` scope (like ImGui BeginDisabled): every widget declared inside is greyed out and takes no input and no focus
- [x] `Interaction.double_clicked` (press history of the last press: id + time)
- [x] Cursor hints: `UiCursor(ctx)` (arrow, text, hand, resize, not allowed) from the widget under the pointer, applied by the glue
- [x] `UiUsage(ctx)`: elements, commands, text lines, text bytes, states, roots: now and the highest so far, for sizing `Storage`
- [x] Focus memory per container: leaving and entering a window / panel / tab again returns to its last focused child
- [x] Style tags: `UiPushTag(ctx, "danger")` / `UiPopTag`, `DrawInfo.tag`, so a style picks colors by tag without new StyleKinds
- [x] Text truncation with "..." and the full text as a tooltip on hover
- [x] Drag and drop with a small payload (source, target, a fixed buffer for the data)
- [x] Shrink priority ("strictness" of a size): which child of an overfull container gives way first
- [x] Node graph: model with rules, events with user pointers, topological order and buffer plan; cable routes, bounds and distance by the style; canvas, nodes, pins, minimap, zip ties; demo with a script and screenshots
- [x] Draggable scrollbar (a hit box of its own, wider than it is drawn)
- [x] Knob, fader and level meter (`widgets_audio.odin`, default style in `default_style/audio.odin`), demo `audio` with a screenshot
- [x] Text field: selection (pointer, Shift, words), copy, cut, paste, select all, clipboard (system through the glue, else local)
- [x] Text area (`UiTextArea`): several lines, word wrap, up and down with a column, selection over rows, scrolling that follows the cursor, a scrollbar
- [x] Timeline (`UiTimeline`): tracks and clips model with rules and events, ruler, playhead, move across tracks, resize, multi selection, zoom around the pointer, lock; demo with a screenshot
- [x] Timeline: box selection (tool or Ctrl, Shift keeps), a loop range on the ruler with draggable edges and events
- [x] Timeline: markers (flags on the ruler, drag, events, Delete) and snapping to the edges of clips, markers and the playhead
- [x] Timeline: copy, cut, paste and select all of clips (a paste is told with the clip it was copied from)
- [x] Timeline: duplicate (Ctrl + D) and a vertical zoom of the tracks (Ctrl and the wheel)
- [x] Timeline: automation lanes (points on a curve in a lane, dragged in time and value, double click to add, events, interpolation for the program that plays them)
- [x] Timeline: curve shapes between points (linear, hold, smooth, bias, S), a handle that bends a segment, Ctrl and a click that cycles the shape; a block renderer for the audio thread (`AutomationCompile`, `AutomationRender`) that is 150 to 650 times faster than asking for the value of every sample
- [x] Timeline: more shapes that repeat (stairs, smooth stairs, pulse, triangle, wave), multi-point stretch (Alt drag), pattern tools (flip, mirror, rotate, repeat), undo and redo with snapshots, a bend macro per track (the ideas of TIME-12, see the README)
- [x] Timeline: tangents (`HERMITE`: a cubic with a slope at each point and two handles that are the control points of a Bezier curve)
- [x] Timeline: Alt + Left / Right rotate the selected points, a control in the corner of an automation lane sets its bend macro
- [x] Timeline: Alt and a drag stretches several selected clips and markers (`TimelineClipsStretch`); undo and redo cover clips and markers (the history snapshots everything)
- [x] The look of Baldr: dark and light themes, Inter and JetBrains Mono in faces, Lucide icons, button variants by tag, thin sliders, shadows, focus rings as outlines; the widgets of its gallery (switch, badge, chip, tag, avatar, segmented, breadcrumbs, spinner, title, card); its gallery page remade as a demo with a script and screenshots
- [x] Baldr examples remade as the demo `examples`: 01_hello, 04_controls, 03_scroll, 17_toasts (a tab each, with a script and pictures)
- [x] A theme from an accent color (`ui_default.ThemeFromAccent`: Baldr's OKLCH generator ported, contrast by construction), the theme lab example with it
- [x] Baldr's 05_overlays remade (a menu from a button, tooltips, a clickable card, a dialog)
- [x] Charts (`UiChart`: line, area, bars, scatter; picking by pointer and keys) and Baldr's 21_charts remade
- [x] Date and time fields (`UiDateField` with a month to pick from, `UiTimeField`), the "Date, time and colour" card of the gallery
- [x] Baldr's 09_jobs remade (downloads with progress, simulated without threads)
- [x] Markdown as widgets (`UiMarkdown`: headings, paragraphs, lists, quotes, code, rules) and Baldr's 19_markdown as source and preview side by side
- [x] A text is measured with the tags it is drawn with (a title in the strong face, code in the code face): `ctx.measure_tags`, `UiMeasureHasTag`
- [x] Rich text: `UiRichText`, used by `UiMarkdown` (strong, italic, code, links)
- [x] Tables in `UiMarkdown`
- [x] The output of a program in its ANSI colors (`UiAnsiText`, `UiAnsiLine`, `AnsiNext`) and Baldr's 25_terminal as a log with a prompt
- [x] ANSI output: background colors, underline
- [x] ANSI output: a screen of cells for programs that move the cursor (`AnsiScreen`)
- [x] Screen of cells: scrollback (a caller owned ring) and wide characters (two cells, combining marks)
- [x] Screen of cells: the alternate screen (`?1049`, `?47`, `?1047`)
- [x] Completion list above the caret where it would not fit below (`UiComplete`)
- [x] Reverse video (SGR 7, 27) in the log view and the screen of cells
- [x] Scroll regions of the screen of cells (DECSTBM, `S`, `T`)
- [x] Completion: the part of an item that matched is drawn, items are ranked (prefix, start of a part, elsewhere)
- [x] Selection of read text: a double click and a drag select by words
- [x] Selection of read text: a triple click and a drag select by paragraphs; a word over the runs of a paragraph is one word
- [x] Settings of the ui (click times, drag distances, the key that extends a selection) and a `KeyMap` of hotkeys that the kit uses
- [x] Input glyphs (`UiGlyph`, `UiBindingField`, textures through `Painter.draw_texture`), gamepad input in the kit, the Rebind example as the first tab
- [x] The raylib and Karl2D glues draw glyph textures (`TextureRegister`) and make their actions from a `KeyMap` (`KeyMapOf`, `ui.KeyMapFromCodes`) with pad buttons
- [x] Screen of cells: selection of cells (a drag, Copy, stays with the text through scrolling)
- [x] Screen of cells: a width table that follows Unicode more closely (more marks and emoji, ambiguous widths by a setting, emoji sequences, flags and the variation selector in one cell)
- [x] Editing commands for a text (`UiTextWrap`, `UiTextLinePrefix`) and Baldr's 08_rich as a toolbar over the Markdown source
- [x] Dashed lines and paths for overlays (`default_style/lines.odin`) and Baldr's 28_lines
- [x] Text that is read can be selected and copied (`TEXT_SELECTABLE`, select.odin) and Baldr's 27_conversation in the chat example
- [x] Selection of read text: a word by double click, the text by a third click
- [x] Selection of read text: Shift + click extends it, select all takes every selectable text
- [x] Selection of read text: a third click takes the whole paragraph of a rich text
- [x] Selection of read text: its end moved by Shift + arrows, Home, End
- [x] Selection of read text inside of a virtual list (`UiSelectRows`, `UiSelectRow`, `VirtualList.text`)
- [x] Selection in a list: several texts in a row (the cells of `UiTable`)
- [x] Selection in a list: Shift + up and down move the end out of view, the list scrolls after it
- [x] Selection survives a press on a scroll bar, a table header or a column edge, and the moving of columns (the cell of a table text is its column)
- [x] Selection in a list: Shift + left, right, page up and page down across rows that are out of view
- [x] Strong italic text and italic code faces (`ATLAS_FACES` 16, Inter SemiBold Italic made from Inter Variable Italic)
- [x] A drag that rests over a widget (`UiDragRest`) and Baldr's 35_spring
- [x] Markdown that arrives (Baldr's 26_reply): shown at every length of the text, a test over every prefix
- [x] A completion list in a text area (`UiComplete`) and Baldr's 34_mentions
- [x] `UiComplete` for the one line text field, and an undo step for an inserted item
- [x] Colors in a text area (`TextHighlight`, `HighlightCode`) and Baldr's 07_code
- [x] Highlighting that knows the lines before a row (block comments, raw strings): a state per row that the area keeps while the text does not change
- [x] A shortcut field (`UiShortcutField`, `Chord`) and Baldr's 20_shortcuts
- [x] A part of the ui in a theme of its own (`ThemeAreaSet`, `Style.before_draw`) and Baldr's 33_reading
- [x] Links of a rich text can be clicked (`address, clicked := UiRichText(...)`, the same from `UiMarkdown`)
- [x] (was) Runs of several styles in one wrapped text (bold, italic, code and links inside of a paragraph: the measure proc needs the face, the wrap has to break between runs); `UiMarkdown` would then draw emphasis instead of only taking its marks away
- [x] The desktop shell examples of Baldr (15_control_centre, 16_launcher, 18_dock, 13_taskbar, 24_desktop, 12_applet) remade as the `shell` demo: the windows, workspaces and applets are plain data, not a compositor
- [x] 31_emoji remade as the `emoji` demo: the picker in a popover, recents, skin tone, `UiTextInsert`, every emoji drawn from shapes (no color emoji font)
- [x] The cell screen write path (measured 2026-11-21, 200 x 50, 9950X, `odin run ui/tool/ansi_bench -o:speed`, MB/s before -> after): long ASCII lines 46 -> 379, short lines (ls like)
      13 -> 143, colors every 25 bytes 28 -> 254, wide letters and emoji 36 -> 207, cursor moves and erase 95 -> 97. The first guess (a run fill for printable ASCII, `screenPutRun`, ghostty's
      batching) gained only 20 percent: the cost was per line, not per byte, 2 microseconds a line, which was the `copy` of the whole screen (360 KB) at every scroll. The rows are a ring now
      (`AnsiScreen.top`, `screenRowCells`): a scroll of the whole screen turns the ring and clears one row. `AnsiScreen.bytewise` keeps the byte at a time path as the reference: a test compares
      both on 400 random streams (controls, escapes, wide letters, emoji sequences, regions, the alternate screen, pieces cut anywhere), and a model test checks the ring through 102 scrolls.
- [x] The cell is 16 bytes (it was 36) and the write path is at 780 MB/s on long lines (MB/s, 200 x 50 with a history, `odin run ui/tool/ansi_bench -o:speed`; the number before the
      16 byte cell, then after it and the two fixes below): long lines 379 -> 362 -> 779, `ls` like 143 -> 146 -> 296, colors 254 -> 246 -> 431, wide and emoji 207 -> 193 -> 246. The size alone
      gained nothing (my guess that the 36 byte stores were the limit was wrong); what did: (1) the run fill writes a cell as two words and not a struct copy and a read modify write of the
      bit field (store forwarding waited on the store just made), 513 without a history; (2) rows are cleared with the same word stores (`screenFillCells`), and the run of printable ASCII is
      found eight bytes at a time (`asciiRunLength`, a word at a time test for bytes below 0x20, 0x7f and 0x80 and above), 966 without a history. Layout: the character and two more
      characters of 21 bits in one u64 (`AnsiCell.characters`), the colors three bytes each, the attributes and the wide flags in a u16 (`attributes`); `AnsiCellMake`, `AnsiCellStyle`,
      `AnsiCellSetStyle`, `AnsiCellSameStyle` are the way to make and read a style. Two extra characters instead of four: a family of four people is shown with its first two (and copied
      so); the ghostty answer (a side table of the long sequences) needs a lifetime for the entries (a history row that holds a reference): take it up only if a program needs the tail.
- [x] Cursor movement, erase and wide letters (MB/s before -> after, same data): cursor moves and erase 136 -> 480, wide letters and emoji 246 -> 293. What it was: every `ESC [ K` and
      `ESC [ J` repaired the pairs of wide letters of the WHOLE row (or screen: 10 000 cells for a `J`) and now only the two cells next to the cleared part (`screenFixEdges`); a
      sequence zeroed a 128 byte array of numbers; a letter of several bytes that is whole in the slice is decoded at once (the byte at a time letter buffer is for a letter cut by the end of
      a write). The width function tests the big wide blocks first. A test checks that no half of a wide letter is left on random streams (broken on purpose: it fails at round 183), and an
      exhaustive test compares the reordered width function with the previous one for every code point, both modes (it found a block that started 12 code points too early).
- [x] The run scan uses the `simd` library (`AsciiRun`: 16, 32 or 64 bytes a step by level). No speed gain on this data (the scan was not the limit: 1.3 ns per byte is the cell stores and the line feeds); it removed the hand written word scan from `ui`. What is left is 1 to 3 ns per byte on every kind of output
- [x] Invalid UTF-8 in `AnsiScreenWrite`: one U+FFFD per maximal subpart (Unicode table 3-7) by `simd_utils.Utf8Decode` / `Utf8ContinuationOk`, a sequence that is valid so far at the end of a write waits for the next one, an invalid one (a start byte C0, C1, F5 and above, a continuation byte alone, a start that the next byte cannot continue) is replaced at once; the same in one write, in pieces and a byte at a time (a test of ten cases in the three modes, and the random stream equivalence test). It used to drop the bad bytes without a trace
- [x] Print by slices: `AnsiScreenWrite` once per chunk is how the demo does it; documented in README (the cost is per byte and per control sequence, not per call)
- [x] Edit mode picked nothing in the graph demo: the overlay layer of the canvas (`GRAPH_OVERLAY`, one rectangle over everything) was the topmost drawn element; it is skipped now. The demo script clicks nodes (title, body) in normal mode and picks one in edit mode, a test plays the click the way a device delivers it (`demo_common_test.odin`)
- [x] Style editing: edit mode (`ui/edit.odin`, hover veil `Theme.edit_overlay` alpha 6 of 255 white by default and `edit_selected`, press picks, the library masks the ui), `ui_default.UiStyleEditor` (every Theme field by reflection, the picked kind's fields first, load / save / delete through a `StyleStore`: files or memory), `ThemeText` / `ThemeParse`, `ui/styles` (dark, light, current), the `Style` button in every demo and the persistent current style, the `style editor` demo with masked captures
- [x] Graph node: the title band is drawn by the node inside of its outline (and the selection outline) with the top corners of the node (a radius in pixels less the border, not a part of the title's own size); `ui_default.TitleBand` / `FillRoundedCorners`, the window title uses the band too; found by a masking frame capture (`kit.CaptureAt`), which compares a small region with no pixel allowed to differ: the whole picture compare let 452 pixels (0.05 percent) pass
- [x] Review of the demos (2026-11-21): a node of the graph is dragged by its body as well as its title (the selected ones go with it); the handle of a timeline curve is pulled along the segment (right: fast at the end, left: fast at the start, equal for a rise and a fall); the inspector shows the measure cache of the last frame (a quiet ui is hits, the panel's own counters are the misses); the colour picker has HSV, HSL, RGB and OKLCH bars and no stepping; the slider has a round knob where the pointer is; the rebinding page is its own demo and the Baldr demos are named so in the menu
- [x] Baldr examples 14_bar_applets, 23_chrome and 38_windows: the `windows` demo (`demo_windows.odin`): windows that draw their own frame (title bar with icon and minimise / maximise / close, a double click on the title maximises, the right edge, the bottom edge and the corner resize, a press raises), a main and a Preferences window of one state (the theme switch changes the main window), a bar of applet slots where a stopped applet leaves a Restart button; the floating windows stand in for operating system windows (the kit has one) and the applets are plain data
- [x] Timeline block renderer with SIMD (`timeline_automation_kernels.odin`): the ramp and the exponential run are kernels per level of `simd` (baseline, AVX2, AVX-512, picked at start-up, SIMD_LEVEL honoured, a test compares the levels). The ramp is `base + i * delta` (no running sum: a sum waits for the sample before it). Measured with `odin run ui/tool/automation_bench -o:speed` (ns a sample, Zen 5): LINEAR 0.206 -> 0.054, EXP 0.354 -> 0.069, SMOOTH / CURVE / S_CURVE / HERMITE about 0.2 -> 0.08, TRIANGLE 0.228 -> about 0.08; HOLD 0.04 is the floor (the search for the segment of a block).
- [x] Timeline renderer: STAIRS, SMOOTH_STAIRS and PULSE with the shape chosen once and the floor as an integer conversion (without SSE4.1 math.floor is a call): 1.0 -> 0.49 and 1.16 -> 0.58 ns a sample, WAVE 0.29 -> 0.14 (its ramps use the kernel)
- [x] Timeline renderer, steps and pulses as a per level kernel (times in f64 into f32 positions, then the shape: 32 bit floor conversions): STAIRS 0.49 -> 0.20, PULSE 0.58 -> 0.23 ns a sample (baseline build; 0.18 / 0.22 was the most a whole -microarch:native build got). Not done on purpose: a cursor search shared by several tracks. Every track has its own segment boundaries, so nothing of the search is common; the cost of a block that stays in a segment is the compare of the cursor (HOLD, 0.04 ns a sample, is that floor), and a seek is one binary search per plan
- [ ] (low priority) Right-to-left text (needs a font with the script and shaping for Arabic: measuring, wrapping, caret and selection all change)
- [x] Virtual list and table (`UiVirtual`, `UiTable`): only the rows in view are declared, selection by pointer and keys, sortable header, resizable columns; demo with 100 000 rows and a screenshot
- [x] Inspector panel (`UiInspector`): element tree of the last frame, buffer usage, measure cache, picking by the pointer; demo with a screenshot
- [x] Inspector: the layout details of the selected element, a filter by name, text or kind, a selection that follows its element
- [x] Inspector: the draw commands of a frame as a list (Commands), collapsing of the tree (double click), a frame history (History: build time, elements and commands of the last 120 frames as plots)
- [x] Table: sideways scrolling (wheel with Shift, bar, header goes along) and a last column that fills the room
- [x] Table: reordering columns by dragging a header (`table.reorderable`, `TableColumnAt`, `table.moved`)
- [x] Table: a double click on the edge of a header asks for a fit (`table.fit`, `TableFit`, `UiTextWidth`: the program measures its cells)
- [x] Table: keys inside of a row (`table.cells`: the current cell, left and right, Enter tells which cell), demo step with a screenshot
- [x] Tree (`Tree`, `UiTree`): fixed storage model, visible rows flattened, arrows, keys, lazy loading through `view.toggled`; demo with a screenshot
- [x] Tree: drag and drop of nodes (`TreeMove`, `view.moved`, `view.can_drop`) and rename in place (F2, `TreeRename`, `view.renamed`), demo with a screenshot
- [x] Tree: a filter that opens the parents of what matches (`TreeViewFilter`, `TreeVisibleFiltered`)
- [x] Tree: several selected nodes (Ctrl and a click, Shift and a click for a range, `TreeMarked`), dragged together (`view.moved_count`)
- [x] Tree: a drop goes before, after or into a row by how far down in it the pointer is (`TreeDropZone`, a line shows where)
- [x] Tree: icons (`Icon`, `UiIcon`, `TreeNode.icon`, drawn by the style: a few built in, `Icon.USER` and above are the program's) and custom row content (`view.row`, `UiTreeRowDefault`), demo with a screenshot
- [x] Text area: the rows are kept between frames while the text, the width, the wrap and the font do not change (`UI_TEXT_AREA_CACHES` areas at once)
- [x] Text measure cache (`measure.odin`): a fixed table by hash of text and size, cleared by a new font or UI scale
- [x] UI scale factor (`Painter.scale`): layout and styles in logical units, the glue scales the drawing and divides the pointer; demo `scale`
- [x] Node graph: box selection, moving several nodes together, Delete for selected nodes
- [x] `Decl.zoom`: one container laid out in logical units and shown bigger or smaller (`Style.zoom`, `Painter.offset`); node graph zoom with the wheel around the pointer
- [x] Zoom: floating elements (a popup, a tooltip) inside of a zoomed container are zoomed with it, and the wheel scrolls a zoomed scroll area by a step of the screen
- [x] Node graph: copy and paste of a selection (`GraphClipboard`, `GraphCopy`, `GraphPaste`, `GraphDuplicate`; Ctrl + C, X, V, D with `view.clipboard`)
- [x] Node graph: reroute points on a cable (`GraphRerouteAdd`, a double click on a cable with `view.reroute_on_double_click`), labels on cables (`GraphLinkLabel`), a node that collapses to its title (`GraphNodeCollapse`, a double click on the title); demo with a screenshot
- [x] Node graph: undo and redo (`GraphHistory`, snapshots, Ctrl + Z / Y with `view.history`) and automatic layout in columns (`GraphAutoLayout`)
- [x] Docking (`Dock`, `UiDock`): panels as tabs in a tree of splits, moved by dragging a tab (middle: a tab, edge: a split), closing and opening, a layout that is plain data; demo with screenshots
- [x] Docking: tab reordering by a drop on the tab bar (`DockPanelInsert`) and close buttons on tabs (`DockPanelSetClosable`)
- [x] Docking: floating panels (a tab let go outside of the dock becomes a window, its title docks it again)
- [x] Docking: floating windows are resized by the pointer (edges and corners, a minimum)
- [x] Docking: a press raises a floating window; a drop over a floating window changes nothing
- [x] Text field and text area: undo and redo (Ctrl + Z, Ctrl + Y) with a fixed pool, a word is one step
- [x] Color picker (`UiColorPicker`: square, hue and alpha bars, hex helpers; style kinds `COLOR_FIELD`, `COLOR_STRIP`)
- [x] Combo box with search (`UiCombo`, `UiMatchText`)
- [x] Accessibility tree (`UiAccessNodes`, `UiAccessFocused`, `UiAccessDescribe`: roles, names, states of the last frame)
- [x] Vector text from the font library (`PainterUseVectorText` for raylib and Karl2D, `-define:DEMO_VECTOR_TEXT`, pictures of every demo with it)
- [x] Keyboard: a test that Tab reaches every interactive widget and that each is drawn with the FOCUSED flag; the color picker takes the focus ring and the arrow keys (`adjust_both`)
- [x] `Decl.absolute`: a child out of the flow of its parent at an offset (no root, no limit but the storage); the graph nodes use it
- [x] Node graph: nodes outside of the view are not declared (`GraphNodesByDepth` with a view)
- [x] Text field: a text longer than the field scrolls with the caret and is clipped (default), a click is mapped through the scroll; `read_only` for the field and the area (select and copy, no edits)
- [x] Held keys repeat in the kit (`Input.keys_repeat`, `InputRepeat`): Backspace, Delete, the arrows, Home and End in text, the directions and pages as actions
- [x] (low) An ellipsis or a fade at the cut edge of a clipped field; the pointer past the edge of a long text scrolls it while it is dragged (the cursor moves, the view follows on the next frame)

## Nota gaps (docs/NOTA_GAP.md, demo `nota`)
- [x] Value bar (`UiValueBar`, `widgets_valuebar.odin`): a filling bar with the value inside, relative drag, Shift for fine, double click or Enter to type, Ctrl + click or Delete to reset, snap, bipolar fill (`ValueBarPan`: 30L / C / 12R), modulation hatch by the tag "modulation"; used by the `nota` demo
- [x] Piano roll widget: key column, notes (add, move, resize, velocity), bars and beats ruler, velocity and controller lanes
- [x] Frequency response graph with draggable band nodes (log frequency axis, dB axis) and a spectrum fill; waveform view with zoom and markers
- [x] Mixer fader with a dB scale and a stereo meter; bars and beats on the timeline ruler with grid snap choices
- [x] Device card (header with switch and preset selector with arrows, tabs, sections divided by rules) and track header row (colour strip, M / S / R, value bar, pan, input)
- [x] (medium) Clip bodies (`clip_body.odin`: notes, peaks, cells inside a clip), arrangement overview strip, `overview.odin` (sections are shown, not edited; parameter picker and command palette are done: `picker.odin`; range slider, XY pad, wheel, thin scroll bar, step grid and keyboard are done: `widgets_pads.odin`)
- [x] Skins with fonts: a style names a font file for each face (`default_style/skin.odin`, the editor's Fonts section, the stores, `kit.UseSkinFonts`, `FontsLoad(..., skin)` of both glue packages)
- [ ] (low) What is left of the windows (`dialogs.odin`): icons in a dialog; skins: a font per size or script, fonts embedded in the style file, a size scale
