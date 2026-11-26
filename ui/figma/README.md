# ui/figma: a Figma design in, Odin ui code out

Reads the JSON of a Figma file and writes an Odin source file that builds the same structure with the `ui` library: one procedure per top level frame.

```
odin run ui/figma/tool -- --in design.json --out my_screen.odin --package my_screen --ui ../ui
```

Get the JSON with a personal access token (keep the token in your shell, never in a file of the repository):

```
curl -H "X-Figma-Token: $FIGMA_TOKEN" https://api.figma.com/v1/files/<file key> -o design.json
curl -H "X-Figma-Token: $FIGMA_TOKEN" "https://api.figma.com/v1/files/<file key>/nodes?ids=1:2" -o design.json     (one frame)
```

Options: `--in`, `--out` (else printed), `--package`, `--ui` (the import path of the ui package **as seen from the output file**), `--frame <name or id>` (repeatable; default every top level frame), `--text-colors`.
What could not be carried over is printed as warnings (and the source has a comment where a node was skipped).

## What the output looks like

```odin
LoginCardState :: struct {
    textfield_email_text: [128]u8,
    textfield_email_length: int,
    button_primary_clicked: bool,
}

LoginCard :: proc(c: ^ui.Context, s: ^LoginCardState) {
    if ui.UiPanel(c, "Login Card##1:2", ui.Layout{size = ui.Size{width = ui.Fixed(320), height = ui.Fit()}, padding = {16, 16, 20, 20}, gap = 12, exact = true}) {
        ui.UiLabel(c, "Sign in", .NONE, .CENTER)
        s.button_primary_clicked = ui.UiButton(c, "Sign in##1:11", ui.Size{width = ui.Grow(), height = ui.Fixed(32)})
    }
}
```

Call the procedure between `UiBegin` and `UiEnd`; keep one state struct per frame in your program (it holds what the widgets work on and "was the button clicked this frame"). Ids are `<name>##<figma node id>`, so they stay the same when the design is generated again.
A real run: `fixtures/login.json` -> `fixtures/generated/login/login.odin` (committed; the test regenerates it, compares and compiles it).

## Mapping

| Figma | Odin |
|---|---|
| frame / group / component / instance with a fill, stroke or corner radius, and every top level frame | `UiPanel` |
| frame without a look | `UiRow` (horizontal) / `UiColumn` (vertical, and frames without auto layout) |
| auto layout: direction, item spacing, padding, primary and counter alignment | `Layout.direction`, `gap`, `padding`, `align` (always `exact = true`: the design's zeros are zeros) |
| fixed / hug / fill (`layoutSizing*`, or in older files `layoutGrow`, `layoutAlign STRETCH`, `*AxisSizingMode`) | `Fixed(n)` / `Fit()` / `Grow()` |
| text | `UiLabel` (wrap words when the text has a fixed width; alignment kept), `UiLabelColored` with `--text-colors` |
| rectangle | an empty `UiPanel` of that size |
| line | `UiSeparator` |
| frame named `Button...` | `UiButton` (label: the first text inside) |
| `Checkbox...` / `Toggle...`, `Switch...` | `UiToggle`, `UiSwitch` |
| `Slider...`, `Progress...` | `UiSlider` (0..1), `UiProgress` |
| `TextField...`, `TextInput...`, `Input...` | `UiTextField` with a 128 byte buffer in the state |
| `Separator...`, `Divider...` | `UiSeparator` |

A widget is recognised by the letters at the start of the name (or, when none starts it, at the end: "Volume Slider"), case and punctuation ignored: "Button / Primary", "button=hover", "Text Field" all match.

## Limits

- Colors, fonts, shadows, images, vectors, ellipses and boolean operations are not carried over: the style of the ui library draws, the generator keeps the structure. Text colors only with `--text-colors`.
- Free positions (frames without auto layout) are lost: the children are stacked in a column (warning). Space between is not kept (put a spacer frame between). Wrapping/clipping, min and max sizes, constraints, rotation and effects are ignored.
- Hidden layers are left out. Variables, styles and component variants are not read; an instance is its own tree.
- One top level frame is one procedure; nested components are inlined, not turned into procedures of their own.

## Copy to another project (odin_plug)

The package imports only `core`: copy the folder `ui/figma/` next to the ui library of the other project and run the tool with `--ui` set to the import path of THAT ui package, as seen from the generated file
(odin_plug: the copy in `source/ui`). Keep the folder directly inside the ui folder, like here: the committed fixture output imports the ui package as `../../../..`, which the test compiles.
Tests: `odin test figma` and `odin test figma/tool`. Change the library here and copy again, not the other way around.
