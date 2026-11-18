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
