# Widgets Nota has that `ui` does not

Nota (`odin_plug/references/nota`, Avalonia/.NET, v0.60) is a DAW. This list is what its screens need and the `ui` library lacks, from the sources (`src/managed/Nota.App/Controls`, the views next to them, `DESIGN.md`) and from `assets/screenshots`. "Have" is what `ui` has that comes closest. Priority: **high** = used on every screen or blocks a whole screen, **medium** = one screen, **low** = a detail.
The demo `nota` (`demo_common/demo_nota.odin`) recreates four screens (arrangement, mixer, modular, piano roll) from what exists; every place where it draws something by hand because the widget is missing is marked `GAP` in its source and is in this list.

## Value controls
| Missing | Nota source | Have | Priority |
|---|---|---|---|
| **Value bar**: a drag number as a bar that fills, the value written inside it, drag = change, Shift = fine, double click = type, reset to default; unipolar and bipolar fill (pan: grows from the centre); a hatched "modulation" fill | `DragNumber`, `ValueBar`, `MiniFader`, `SliderTrack`, `ValueEntry` | `UiSlider` (thin track), `UiDragInt` (no bar, no typing) | high |
| Typed entry on double click for every value control (knob, fader, bar), with unit parsing ("30L", "-6 dB") | `ValueEntry`, `ValueText` | none | high |
| **Pan** bar and knob with the centre mark and text `30L / C / 12R` | `PanBar`, `PanKnob` | `UiKnob` (unipolar arc) | high |
| **Range slider**: two handles (low, high) or one selector on a track | `RangeSliderTrack`, `RackBars` | none | medium |
| **Mixer fader with a scale** (dB ticks) and a stereo meter beside it, handle with a coloured mark | `MeterFader`, `VFader`, `MixBar` | `UiFader`, `UiMeter` (one channel, no scale) | high |
| Stereo meter, gain reduction meter (grows down) | `StereoMeter`, `GrMeter` | `UiMeter` | medium |
| Wheel with a spring (pitch bend returns to the centre on release) | `PerformWheel` | none | low |
| XY pad / vector pad with a ghost of the effective position | `FluxVectorPad` | none | medium |
| Standalone thin scroll bar (a pill) for views that scroll by their own data | `ThinScrollBar` | scroll bar of `UiScroll` only | medium |
| Toggle with a LED / on-off switch in a header, small `M`, `S`, record, headphone buttons with their own colours (a toggle button style by tag) | `ToggleSwitch`, `SwitchTrack`, track headers | `UiSwitch`, `UiToggle`, tags | medium |

## Pickers and headers
| Missing | Nota source | Have | Priority |
|---|---|---|---|
| **Preset selector**: dropdown with previous / next arrows | device card headers (`DeviceCardKit`) | `UiDropdown` | high |
| Key and scale pickers (root note + scale, "Project key" shortcuts) | `KeyPicker`, `ScaleNoteMap` | none | low |
| Parameter picker: searchable list popup at the pointer or under an anchor | `ParamPickerPanel` | `UiCombo`, `UiComplete` | medium |
| Command palette | `CommandPaletteView` | `UiComplete` + `UiModal` (not assembled) | medium |

## Containers and compound views
| Missing | Nota source | Have | Priority |
|---|---|---|---|
| **Device card**: header (on/off, name, preset, fold, close), tabs inside, sections divided by rules, scrolls sideways in a chain, drag to reorder | `DeviceCards/*`, `RuleSection`, `DeviceChainView` | `UiCard`, `UiCollapsing`, drag and drop | high |
| **Track header** row: colour strip, name and kind, M / S / R, value bar, pan, input dropdown, group fold | `ArrangementView.Tracks` | `UiTable`, tags | high |
| **Mixer strip** and a row of them that scrolls sideways; a "Show sends / I/O / compact" bar | `MixerView` | composed from panels | medium |
| Vertical icon rail with an active mark (the left navigation), side panel with search, filter chips and a tree with a right aligned subtitle | `MainWindow.axaml`, `BrowserView` | `UiTree`, `UiChip`, `UiTextField` | medium |
| Transport bar: stop / play / record, position readout (`1.1.00 bars`), tempo as a drag number, time signature, snap chip, DSP %, master meter | `MainWindow.axaml` | buttons, labels | medium |
| Window chrome: tool windows (device, scope, mixer) that dock back | `NotaWindow`, `DeviceWindow` | `UiWindow*`, `UiDock` | low |
| Dialogs: welcome, about, what's new, save changes, progress, preferences with a category list, shortcut editor | `*Window.cs` | `UiModal`, `UiShortcutField`, `UiSettings` | low |
| History (undo list) view, MIDI learn overlay, "show me" hints | `HistoryView`, `MidiLearnOverlay` | none | low |

## Graphs and editors
| Missing | Nota source | Have | Priority |
|---|---|---|---|
| **Piano roll**: key column, note rectangles (add, move, resize, velocity), ruler in bars and beats, velocity / controller lanes under it, scale highlight | `PianoRollView*` | `UiTimeline` (tracks of clips, no pitch rows, no per note velocity) | high |
| **Frequency response graph with draggable band nodes** (log frequency axis, dB axis, a curve from the filters, hover read-out) and a spectrum fill under it | `Eq8Views`, `FilterGraphBase`, `SpectrumFill`, `Fft` | `UiChart` (no log axis, no draggable points) | high |
| Envelope editors: ADSR with draggable points, LFO strip, plots with titled corner axes | `ClipAdsrKit`, `VoltEnv`, `AuroraLfoStrip`, `NotaGraph` | timeline automation lanes | medium |
| Waveform view (audio clip, sample, grain) with zoom and markers | `WaveformPainter`, `AudioClipEditorView`, `GrainWaveViz` | none | high |
| Step / pattern grid (drum pattern, arpeggiator steps) | `DrumPatternView`, `ArpGrid`, `RhythmViews` | none | medium |
| Piano keyboard display (lit notes, root outline) | `ChordKeysViz`, `KeysViews` | none | medium |
| Modulation matrix (sources x targets, amount per cell) | `VoltMatrix` | `UiTable` | low |
| Arrangement **overview** strip and sections ruler (bar numbers, drag to mark a section) | `ArrangementView.Overview`, `.Sections` | `UiTimeline` ruler (seconds, not bars), minimap of the graph | medium |
| Time in bars and beats on the ruler, grid snap choices (1/4, 1/16, bar, auto) | `ArrangementView.TimeAxis`, `SnapChip` | `UiTimeline` (plain numbers) | high |
| Clip body drawing: notes as dashes, waveform, drum steps inside a clip | `ArrangementView` clips | clip with a title | medium |
| Node graph nodes with an on/off switch in the header, CV ports (diamond), edge colours by signal kind, a minimap | `ModularView` | `UiGraph` (round pins, no header widgets) | medium |

## Look
- Nota's skin system (`Skins`, accent colours, `token-roles.json`): `ui` has `ThemeFromAccent` and the style editor; no skin files with fonts.
- Hatched fills (modulation), dashed rings (channel marks), inner clipping of rounded borders (`BorderInnerClip`): a pattern fill and a clip to a rounded rectangle are missing in the painter.

## Order that gives the most
1. Value bar with typed entry (every screen), then the pan bar as its bipolar form.
2. Preset selector and device card (the bottom half of the arrangement screen).
3. Track header row and bars-and-beats ruler (the arrangement screen).
4. Mixer fader with a scale and a stereo meter (the mixer).
5. Frequency graph with draggable bands (EQ, filters) and the waveform view.
6. Piano roll (the biggest: note editing).
