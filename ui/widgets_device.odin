package ui

// The pieces of a device chain and a track list of an audio program, composed from the widgets of the library (nothing new is drawn by the style: a panel, buttons, a switch, a dropdown,
// value bars and a swatch, so a changed theme changes them too):
//
//   UiPresetSelector   a dropdown of names with an arrow before and after (previous / next, wrapping)
//   UiDeviceCard       a card with a header (on / off switch, title, preset selector, fold, close) and a body of sections divided by rules
//   UiDeviceSection    one section of the body: a rule before it, a small title, the controls under it
//   UiTrackHeader      a row of a track list: colour strip, fold, name and kind, M / S / R, volume, pan and input
//
//   card: ui.DeviceCard = {title = "Nota EQ-8", on = &on, folded = &folded, presets = names[:], preset = &preset}
//   if ui.UiDeviceCard(&ctx, "eq", card) {                               // false while folded; the end of the block closes the card
//       if ui.UiDeviceSection(&ctx, "Low", "Low", rule = false) { ui.UiKnob(...) }
//       if ui.UiDeviceSection(&ctx, "High", "High") { ui.UiKnob(...) }
//   }
//
// Everything the person changes is written through the pointers of the spec (nil leaves that part out); the procs return true in the frame something changed.
//
// Limits: a card does not reorder itself by dragging (the program puts cards in a row or a `UiScroll` and uses the drag and drop of the library if it wants that); the header has no
// rename field; a track header has a fixed set of parts (a program that needs more composes its own row from the same widgets), no meter and no group indentation.

// A dropdown of presets with the arrows. `wrap`: the arrow past the last goes to the first.
UiPresetSelector :: proc(ctx: ^Context, name: string, options: []string, selected: ^int, size: Size = {}, wrap: bool = true, disabled: bool = false) -> (changed: bool) {
    if len(options) == 0 { return false }
    ElementOpen(ctx, {id = UiId(ctx, name), layout = {size = {size.width if size.width != {} else Fit(), Fit()}, direction = .LEFT_TO_RIGHT, gap = 2, align = {y = .CENTER}}})
    defer ElementClose(ctx)
    step: int = 0
    if UiButton(ctx, "##prev", disabled = disabled, icon = .CHEVRON_LEFT) { step = -1 }
    if UiDropdown(ctx, "##list", options, selected, {Grow(), {}}, disabled) { changed = true }
    if UiButton(ctx, "##next", disabled = disabled, icon = .CHEVRON_RIGHT) { step = 1 }
    if step != 0 {
        moved: int = selected^ + step
        if wrap { moved = (moved + len(options)) % len(options) } else { moved = clamp(moved, 0, len(options) - 1) }
        if moved != selected^ {
            selected^ = moved
            changed = true
        }
    }
    return
}

DeviceCard :: struct {
    title: string,
    on: ^bool,                          // the switch in the header (nil: none)
    folded: ^bool,                      // the chevron that hides the body (nil: not foldable)
    close: ^bool,                       // the cross: set to true when it is pressed, the program removes the card (nil: none)
    presets: []string,                  // the preset selector (empty: none)
    preset: ^int,
    disabled: bool,
}

// The card. True when the body is shown (not folded): declare the sections inside of the block. The block closes the card.
@(deferred_in = UiDeviceCardEnd)
UiDeviceCard :: proc(ctx: ^Context, name: string, card: DeviceCard, size: Size = {}) -> bool {
    ElementOpen(ctx, {
        id = UiId(ctx, name),
        layout = {size = {size.width if size.width != {} else Fit(), size.height if size.height != {} else Fit()}, direction = .TOP_TO_BOTTOM, padding = PaddingAll(8), gap = 6},
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = IdSplitName(name), font_size = ctx.style.metrics.font_size},
    })
    if header := UiRow(ctx, {size = {Grow(), Fit()}, gap = 8, exact = true, align = {y = .CENTER}}); header {
        if card.on != nil { UiSwitch(ctx, "##on", card.on, disabled = card.disabled) }
        UiLabel(ctx, card.title)
        if len(card.presets) > 0 && card.preset != nil { UiPresetSelector(ctx, "##preset", card.presets, card.preset, {Fixed(190), {}}, disabled = card.disabled) }
        UiSpacer(ctx, {Grow(), Fixed(1)})
        if card.folded != nil {
            if UiButton(ctx, "##fold", icon = .CHEVRON_RIGHT if card.folded^ else .CHEVRON_DOWN) { card.folded^ = !card.folded^ }
        }
        if card.close != nil {
            if UiButton(ctx, "##close", icon = .CLOSE) { card.close^ = true }
        }
    }
    shown: bool = card.folded == nil || !card.folded^
    if shown {
        UiSeparator(ctx)
        ElementOpen(ctx, {layout = {size = {Grow(), Grow()}, direction = .LEFT_TO_RIGHT, gap = 10}})
    }
    return shown
}

UiDeviceCardEnd :: proc(ctx: ^Context, name: string, card: DeviceCard, size: Size = {}) {
    if card.folded == nil || !card.folded^ { ElementClose(ctx) }
    ElementClose(ctx)
}

// One section of the body of a card: a rule before it (not for the first), the title in small dim letters, then what the block declares one under the other
@(deferred_in = UiDeviceSectionEnd)
UiDeviceSection :: proc(ctx: ^Context, name: string, title: string = "", rule: bool = true, size: Size = {}) -> bool {
    if rule { UiSeparator(ctx) }
    opened: bool = ElementOpen(ctx, {id = UiId(ctx, name), layout = {size = {size.width if size.width != {} else Fit(), size.height if size.height != {} else Fit()}, direction = .TOP_TO_BOTTOM, gap = 6, align = {x = .CENTER}}})
    if title != "" { UiLabelDim(ctx, title) }
    return opened
}

UiDeviceSectionEnd :: proc(ctx: ^Context, name: string, title: string = "", rule: bool = true, size: Size = {}) {
    ElementClose(ctx)
}

TrackHeader :: struct {
    name: string,
    kind: string,                       // "Instrument", "Audio" ..., shown dim under the name
    color: Color,
    selected: bool,                     // the strip is drawn wider
    mute: ^bool,
    solo: ^bool,
    arm: ^bool,
    volume: ^f32,                       // dB, -60 .. +6 (nil: no bar)
    pan: ^f32,                          // -1 .. 1 (nil: no bar)
    inputs: []string,
    input: ^int,
    fold: ^bool,                        // a group: the chevron that folds its tracks (nil: none)
}

// A row of the track list. `size.height` 0 is two controls high.
UiTrackHeader :: proc(ctx: ^Context, name: string, header: TrackHeader, size: Size = {}) -> (changed: bool) {
    metrics: ^Metrics = &ctx.style.metrics
    height: SizingAxis = size.height if size.height != {} else Fixed(metrics.control_height * 2)
    ElementOpen(ctx, {
        id = UiId(ctx, name),
        layout = {size = {size.width if size.width != {} else Grow(), height}, direction = .LEFT_TO_RIGHT, padding = PaddingXY(6, 4), gap = 8, align = {y = .CENTER}},
        hit = {.BLOCKER},
        draw = {kind = .PANEL, name = IdSplitName(name), font_size = metrics.font_size},
    })
    defer ElementClose(ctx)
    // the strip has the same room selected or not, so the rows stay in their columns
    ElementOpen(ctx, {layout = {size = {Fixed(8), Grow()}}})
    ElementOpen(ctx, {layout = {size = {Fixed(8 if header.selected else 5), Grow()}}, draw = {kind = .SWATCH, color = header.color}})
    ElementClose(ctx)
    ElementClose(ctx)
    if header.fold != nil {
        if UiButton(ctx, "##fold", icon = .CHEVRON_RIGHT if header.fold^ else .CHEVRON_DOWN) {
            header.fold^ = !header.fold^
            changed = true
        }
    }
    if column := UiColumn(ctx, {size = {Fixed(120), Fit()}, gap = 0, exact = true}); column {
        UiLabel(ctx, header.name)
        if header.kind != "" { UiLabelDim(ctx, header.kind) }
    }
    UiSpacer(ctx, {Grow(), Fixed(1)})
    // the three buttons keep their columns when one is left out
    button: SizingAxis = Fixed(metrics.control_height * 1.5)
    if header.mute != nil { changed = UiToggle(ctx, "M##m", header.mute, {button, {}}) || changed } else { UiSpacer(ctx, {button, Fixed(1)}) }
    if header.solo != nil { changed = UiToggle(ctx, "S##s", header.solo, {button, {}}) || changed } else { UiSpacer(ctx, {button, Fixed(1)}) }
    if header.arm != nil { changed = UiToggle(ctx, "R##r", header.arm, {button, {}}) || changed } else { UiSpacer(ctx, {button, Fixed(1)}) }
    if header.volume != nil {
        changed = UiValueBar(ctx, "##volume", header.volume, {minimum = -60, maximum = 6, default_value = 0, format = "%+.1f dB", snap = 0.1}, {Fixed(96), {}}) || changed
    }
    if header.pan != nil { changed = UiValueBar(ctx, "##pan", header.pan, ValueBarPan(), {Fixed(72), {}}) || changed }
    if len(header.inputs) > 0 && header.input != nil { changed = UiDropdown(ctx, "##input", header.inputs, header.input, {Fixed(110), {}}) || changed }
    return
}
