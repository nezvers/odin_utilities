# Widgets Nota has that `ui` does not

Nota (`odin_plug/references/nota`, Avalonia/.NET, v0.60) is a DAW. This list is what its screens need and the `ui` library lacks, from the sources (`src/managed/Nota.App/Controls`, the views next to them, `DESIGN.md`) and from `assets/screenshots`. "Have" is what `ui` has that comes closest. Priority: **high** = used on every screen or blocks a whole screen, **medium** = one screen, **low** = a detail.
The demo `nota` (`demo_common/demo_nota.odin`) recreates four screens (arrangement, mixer, modular, piano roll) from what exists; every place where it draws something by hand because the widget is missing is marked `GAP` in its source and is in this list.

## Value controls
| Missing | Nota source | Have | Priority |
|---|---|---|---|
| ~~Value bar, pan bar~~ done: `UiValueBar` (drag, Shift fine, typed entry, reset, snap, bipolar, hatch), `ValueBarPan` | `DragNumber`, `ValueBar`, `MiniFader`, `SliderTrack`, `PanBar` | | done |
| Typed entry for the knob and the fader (the bar has it) with unit parsing ("-6 dB") | `ValueEntry`, `ValueText` | `UiValueBar` only | medium |
| Pan knob with the centre mark | `PanKnob` | `UiKnob` (unipolar arc) | low |
| ~~Range slider~~ done: `UiRangeSlider` (two handles that never cross) | `RangeSliderTrack`, `RackBars` | | done |
| ~~Mixer fader~~ done: `UiMixerFader` (dB scale, mixer taper, stereo meter on the same scale with peak and clip, written value, sticks at 0 dB). Left: typed value, pre / post, loudness scales | `MeterFader`, `VFader`, `MixBar` | | done |
| Gain reduction meter (grows down); the stereo meter is in `UiMixerFader` only | `GrMeter` | `UiMeter` | medium |
| ~~Wheel with a spring~~ done: `UiWheel` (pitch bend springs to rest, modulation wheel stays) | `PerformWheel` | | done |
| ~~XY pad~~ done: `UiXYPad` (fine drag, default on double click, ghost point) | `FluxVectorPad` | | done |
| ~~Thin scroll bar~~ done: `UiScrollBar` (pill, thumb drag, paging, either direction) | `ThinScrollBar` | | done |
| Toggle with a LED / on-off switch in a header, small `M`, `S`, record, headphone buttons with their own colours (a toggle button style by tag) | `ToggleSwitch`, `SwitchTrack`, track headers | `UiSwitch`, `UiToggle`, tags | medium |

## Pickers and headers
| Missing | Nota source | Have | Priority |
|---|---|---|---|
| ~~Preset selector~~ done: `UiPresetSelector` | device card headers (`DeviceCardKit`) | | done |
| Key and scale pickers (root note + scale, "Project key" shortcuts) | `KeyPicker`, `ScaleNoteMap` | none | low |
| ~~Parameter picker~~ done: `UiPicker` with an anchor rectangle (words match name or detail, best first) | `ParamPickerPanel` | | done |
| ~~Command palette~~ done: `UiPicker` without an anchor (dimmed window, top centre) | `CommandPaletteView` | | done |

## Containers and compound views
| Missing | Nota source | Have | Priority |
|---|---|---|---|
| ~~Device card~~ done: `UiDeviceCard` (switch, title, preset selector, fold, close) with `UiDeviceSection` (rules, small titles). Left: reorder by drag, tabs inside (use `UiTabBar`) | `DeviceCards/*`, `RuleSection`, `DeviceChainView` | | done |
| ~~Track header row~~ done: `UiTrackHeader` (strip, fold, name and kind, M / S / R, volume, pan, input). Left: meter, group indentation | `ArrangementView.Tracks` | | done |
| **Mixer strip** and a row of them that scrolls sideways; a "Show sends / I/O / compact" bar | `MixerView` | composed from panels | medium |
| Vertical icon rail with an active mark (the left navigation), side panel with search, filter chips and a tree with a right aligned subtitle | `MainWindow.axaml`, `BrowserView` | `UiTree`, `UiChip`, `UiTextField` | medium |
| Transport bar: stop / play / record, position readout (`1.1.00 bars`), tempo as a drag number, time signature, snap chip, DSP %, master meter | `MainWindow.axaml` | buttons, labels | medium |
| Window chrome: tool windows (device, scope, mixer) that dock back | `NotaWindow`, `DeviceWindow` | `UiWindow*`, `UiDock` | low |
| Dialogs: welcome, about, what's new, save changes, progress, preferences with a category list, shortcut editor | `*Window.cs` | `UiModal`, `UiShortcutField`, `UiSettings` | low |
| History (undo list) view, MIDI learn overlay, "show me" hints | `HistoryView`, `MidiLearnOverlay` | none | low |

## Graphs and editors
| Missing | Nota source | Have | Priority |
|---|---|---|---|
| ~~Piano roll~~ done: `UiPianoRoll` (keys, notes add / move / resize / delete, ruler in bars and beats, velocity lane, scale highlight, preview events). Left: controller lanes, box select, copy / paste, triplet grids | `PianoRollView*` | | done |
| ~~Frequency response graph~~ done: `UiFreqGraph` (log axis, dB axis, RBJ biquad curve, draggable nodes, Q by wheel, spectrum fill, readout). Left: stereo / mid-side bands, steeper cut cascades | `Eq8Views`, `FilterGraphBase`, `SpectrumFill` | | done |
| Envelope editors: ADSR with draggable points, LFO strip, plots with titled corner axes | `ClipAdsrKit`, `VoltEnv`, `AuroraLfoStrip`, `NotaGraph` | timeline automation lanes | medium |
| ~~Waveform view~~ done: `UiWaveform` (min / max columns with a peak table, zoom, ruler in seconds, selection, markers, playhead). Left: stereo, fades and gain handles, editing | `WaveformPainter`, `AudioClipEditorView` | | done |
| ~~Step / pattern grid~~ done: `UiStepGrid` (paint by drag, playhead column, beat shading). Left: per step lengths, ratchets | `DrumPatternView`, `ArpGrid`, `RhythmViews` | | done |
| ~~Piano keyboard~~ done: `UiKeyboard` (lit notes, root marked, press and glide send note on / off). Left: velocity by press height | `ChordKeysViz`, `KeysViews` | | done |
| Modulation matrix (sources x targets, amount per cell) | `VoltMatrix` | `UiTable` | low |
| ~~Arrangement overview strip~~ done: `UiOverview` (clip blocks, sections band, draggable and zoomable window; used in the nota arrangement). Left: marking sections by drag | `ArrangementView.Overview`, `.Sections` | | done |
| ~~Bars and beats on the ruler, grid snap choices~~ done: `TimelineView.tempo` turns the ruler into bars and beats, `TimelineSnapChoice` (off, bar, 1/4 .. 1/32, auto). Left: tempo map, triplets | `ArrangementView.TimeAxis`, `SnapChip` | | done |
| ~~Clip body drawing~~ done: `TimelineClipSetBody` (notes as dashes, mirrored peaks, pattern cells; the content repeats along the clip) | `ArrangementView` clips | | done |
| Node graph nodes with an on/off switch in the header, CV ports (diamond), edge colours by signal kind, a minimap | `ModularView` | `UiGraph` (round pins, no header widgets) | medium |

## Look
- Nota's skin system (`Skins`, accent colours, `token-roles.json`): `ui` has `ThemeFromAccent` and the style editor; no skin files with fonts.
- Hatched fills (modulation), dashed rings (channel marks), inner clipping of rounded borders (`BorderInnerClip`): a pattern fill and a clip to a rounded rectangle are missing in the painter.

## Order that gives the most
1. ~~Value bar with typed entry, pan bar~~ (done).
2. ~~Preset selector and device card~~ (done).
3. ~~Track header row and bars-and-beats ruler~~ (done).
4. ~~Mixer fader with a scale and a stereo meter~~ (done).
5. ~~Frequency graph with draggable bands and the waveform view~~ (done).
6. ~~Piano roll~~ (done).
