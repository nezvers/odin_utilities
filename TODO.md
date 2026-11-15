# TODO

Kept by hand and by Claude: tick an item when it is done and verified (tests pass, committed). Source of most items: the study of the RAD Debugger
(`references/raddebugger`, see the notes at the bottom of this file) and of Dear ImGui (`references/imgui`).

## ui (odin_utilities/ui)
- [x] Widget state survives one absent frame (RAD prunes at `last_touched + 2`): state is dropped after 3 frames without a declaration
- [x] `UiAnimating(ctx)`: true while any hover / press fade is still moving, so a host can redraw on demand; fades use the frame rate independent `1 - 2^(-rate * dt)`; `UiAnimate(ctx, id, target)` for styles
- [x] `UiDisabled(ctx)` scope (like ImGui BeginDisabled): every widget declared inside is greyed out and takes no input and no focus
- [x] `Interaction.double_clicked` (press history of the last press: id + time)
- [x] Cursor hints: `UiCursor(ctx)` (arrow, text, hand, resize, not allowed) from the widget under the pointer, applied by the glue
- [x] `UiUsage(ctx)`: elements, commands, text lines, text bytes, states, roots: now and the highest so far, for sizing `Storage`
- [ ] Focus memory per container: leaving and entering a window / panel / tab again returns to its last focused child (RAD `default_nav_focus_*`)
- [ ] Style tags: `UiPushTag(ctx, "danger")` / `UiPopTag`, `DrawInfo.tag`, so a style picks colors by tag without new StyleKinds
- [ ] Text truncation with "..." and the full text as a tooltip on hover
- [ ] Drag and drop with a small payload (source, target, a fixed buffer for the data)
- [ ] Shrink priority ("strictness" of RAD sizes): which child of an overfull container gives way first

## odin_plug
- [ ] Thread names (`SetThreadDescription`): audio threads, graph pool workers, device and capture threads, simulated driver thread; a `platform.ThreadName`
- [ ] A `-sanitize:address` step in `tools/dev verify` if the toolchain here supports it
- [ ] Source line / current step recorded per thread for crash reports (RAD `tctx_write_srcloc`), next to `trace_scope`

## odin_utilities
- [ ] `scratch`: two thread local scratch arenas with the conflict rule (`ScratchBegin(conflict)` / `ScratchEnd`), for non realtime tools
- [ ] `scene` assets: cancellation tokens for superseded requests, a generation so a reloaded asset is served stale until the new one is ready,
      a per frame "held" guard against eviction, priority levels, eviction by time (RAD artifact cache)
- [ ] `lanes`: barrier, broadcast and index range for fan out of non realtime work (RAD lanes); the realtime graph pool of odin_plug stays as it is

## Notes: what the RAD Debugger does (summary)
UI: persistent box table keyed by name (hash part and display part split with `##`), pruned two frames after the last touch; animations keyed by id with a
frame rate independent rate and an `is_animating` flag; hot / active / keyboard focus states, default nav roots that remember the focused child, permission flags to
disable classes of input for a subtree; double and triple click from press history; tag stacks resolved by a theme; size kinds pixels / text / parent percent /
children sum with strictness; per box cursor; drag data store; tooltips and context menus as layers; two build arenas that alternate.
Threads and memory: arenas that reserve 64 MB and commit 64 KB steps; two scratch arenas per thread with a conflict argument; lanes (all worker threads run the
same tick, barrier + broadcast + range); an artifact cache with generations (stale while revalidate), cancellation, priorities, access scopes that hold entries,
eviction by time and update index; lock striping (RW mutex + condition variable + arena per stripe); thread names, a source line and a progress counter per thread.
