# ui TODO

Tick an item when it is done and verified (tests pass, committed).

- [x] Resizing by the pointer: `UiSplitter` between two sections (side by side or stacked, drag and arrow keys, limits from the container) and `UiWindowResizable` (edges and corners, minimum and maximum size, the body grows with the window)
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
