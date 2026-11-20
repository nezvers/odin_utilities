package ui

// Small widgets of a modern look: a switch, badges, chips and tags, avatars, a segmented choice, breadcrumbs, a spinner, titles, a card. The set follows the
// gallery of Baldr (https://github.com/BuLEEto/Baldr); the widgets are written for this library (immediate mode, drawn by the style).

// What a badge or a line of status says by its color
Tone :: enum u8 {
    NEUTRAL,
    ACCENT,
    SUCCESS,
    WARNING,
    DANGER,
}

// A switch: on or off, like a toggle, drawn as a track with a knob that slides. True in the frame it was flipped.
UiSwitch :: proc(ctx: ^Context, name: string, value: ^bool, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    if interaction.clicked {
        value^ = !value^
        changed = true
    }
    metrics: ^Metrics = &ctx.style.metrics
    shown: string = IdSplitName(name)
    flags: Flags = {}
    if value^ { flags += {.ON} }
    if disabled { flags += {.DISABLED} }
    // the track is two control heights wide at most, then the name
    track: f32 = switchTrackWidth(metrics)
    width: f32 = track + (metrics.padding.x + textWidth(ctx, shown) if shown != "" else 0)
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, width, metrics.control_height)},
        hit = {} if disabled else {.INTERACTIVE},
        // `value` slides from 0 to 1 over a few frames, so the style can draw the knob on its way
        draw = {kind = .SWITCH, name = shown, value = UiAnimate(ctx, id, 1 if value^ else 0), actual = 1 if value^ else 0, ratio = track, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    return
}

@(private)
switchTrackWidth :: proc(metrics: ^Metrics) -> f32 {
    return min(metrics.control_height, 22) * 1.8
}

// A badge: a few words in a pill, colored by its tone ("12 new", "Failed"). It is not interactive.
UiBadge :: proc(ctx: ^Context, text: string, tone: Tone = .NEUTRAL) {
    metrics: ^Metrics = &ctx.style.metrics
    size: f32 = metrics.font_size * 0.85
    shown: string = IdSplitName(text)
    ElementOpen(ctx, {
        layout = {size = {Fixed(measureText(ctx, shown, size).x + size * 1.2), Fixed(size * 1.5)}},
        draw = {kind = .BADGE, name = shown, actual = f32(tone), font_size = size},
    })
    ElementClose(ctx)
}

// A chip: a small choice in a pill that is on or off (a filter, a platform). True when it was clicked: the program flips its own value.
UiChip :: proc(ctx: ^Context, name: string, selected: bool, icon: Icon = .NONE, disabled: bool = false) -> (clicked: bool) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    shown: string = IdSplitName(name)
    flags: Flags = {}
    if selected { flags += {.SELECTED} }
    if disabled { flags += {.DISABLED} }
    height: f32 = metrics.control_height * 0.82
    // a chosen chip shows a check mark before its name when it has no icon of its own
    mark: f32 = metrics.font_size + 4 if icon != .NONE || selected else 0
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(textWidth(ctx, shown) + mark + metrics.padding.x * 1.6 + 2), Fixed(height)}},
        hit = {} if disabled else {.INTERACTIVE},
        draw = {kind = .CHIP, name = shown, icon = icon, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    return interaction.clicked
}

// A tag: a name in an outlined pill with a cross on its right that takes it away. `removed` is true when the cross was clicked, `clicked` when the rest was.
UiTag :: proc(ctx: ^Context, name: string, icon: Icon = .NONE) -> (clicked: bool, removed: bool) {
    id: Id = UiId(ctx, name)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    metrics: ^Metrics = &ctx.style.metrics
    shown: string = IdSplitName(name)
    height: f32 = metrics.control_height * 0.82
    mark: f32 = metrics.font_size + 4 if icon != .NONE else 0
    cross: f32 = metrics.font_size + 6
    if interaction.clicked {
        // the cross is the right end of the pill (where it was in the last frame); a click of the keyboard is the tag itself
        removed = interaction.rect.z > 0 && ctx.input.mouse_position.x >= interaction.rect.x + interaction.rect.z - cross - metrics.padding.x * 0.5 && ctx.hover == id
        clicked = !removed
    }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(textWidth(ctx, shown) + mark + cross + metrics.padding.x * 1.2), Fixed(height)}},
        hit = {.INTERACTIVE},
        draw = {kind = .CHIP, name = shown, icon = icon, actual = 1, ratio = cross, font_size = metrics.font_size},
    })
    ElementClose(ctx)
    return
}

// An avatar: a disc in a color with one or two letters on it. `size` 0 is a control height and a bit.
UiAvatar :: proc(ctx: ^Context, initials: string, color: Color, size: f32 = 0) {
    metrics: ^Metrics = &ctx.style.metrics
    side: f32 = size if size > 0 else metrics.control_height * 1.3
    ElementOpen(ctx, {
        layout = {size = {Fixed(side), Fixed(side)}},
        draw = {kind = .AVATAR, name = initials, color = color, font_size = side * 0.42},
    })
    ElementClose(ctx)
}

// A segmented choice: one of a few options next to each other in one track, the chosen one raised. True in the frame it changed.
UiSegmented :: proc(ctx: ^Context, name: string, labels: []string, selected: ^int) -> (changed: bool) {
    track: Id = UiId(ctx, name)
    metrics: ^Metrics = &ctx.style.metrics
    selected^ = clamp(selected^, 0, max(len(labels) - 1, 0))
    ElementOpen(ctx, {
        id = track,
        layout = {size = {Fit(), Fit()}, direction = .LEFT_TO_RIGHT, padding = PaddingAll(3), gap = 2},
        draw = {kind = .SEGMENTED},
    })
    for label, i in labels {
        segment: Id = IdFromIndex(u32(i), track)
        _ = stateGet(ctx, segment)
        interaction: Interaction = widgetBehavior(ctx, segment)
        if interaction.clicked && selected^ != i {
            selected^ = i
            changed = true
        }
        shown: string = IdSplitName(label)
        ElementOpen(ctx, {
            id = segment,
            layout = {size = {Fixed(textWidth(ctx, shown) + metrics.padding.x * 2), Fixed(metrics.control_height - 6)}},
            hit = {.INTERACTIVE},
            draw = {kind = .SEGMENT, name = shown, font_size = metrics.font_size, flags = {.SELECTED} if selected^ == i else {}},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
    return
}

// Breadcrumbs: the parts of a path with an arrow between them. The last one is where the user is; the ones before it can be clicked. The index of the part that
// was clicked, -1 for none.
UiBreadcrumbs :: proc(ctx: ^Context, name: string, parts: []string) -> (clicked: int) {
    row: Id = UiId(ctx, name)
    metrics: ^Metrics = &ctx.style.metrics
    clicked = -1
    ElementOpen(ctx, {id = row, layout = {size = {Fit(), Fit()}, direction = .LEFT_TO_RIGHT, gap = 2, align = {y = .CENTER}}})
    for part, i in parts {
        last: bool = i == len(parts) - 1
        if i > 0 { UiIcon(ctx, .CHEVRON_RIGHT, metrics.font_size * 0.9, {}) }
        crumb: Id = IdFromIndex(u32(i), row)
        _ = stateGet(ctx, crumb)
        interaction: Interaction = widgetBehavior(ctx, crumb, last)
        if interaction.clicked { clicked = i }
        shown: string = IdSplitName(part)
        ElementOpen(ctx, {
            id = crumb,
            layout = {size = {Fixed(textWidth(ctx, shown) + metrics.padding.x), Fixed(metrics.control_height * 0.82)}},
            hit = {} if last else {.INTERACTIVE},
            draw = {kind = .BREADCRUMB, name = shown, font_size = metrics.font_size, flags = {.SELECTED} if last else {}},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
    return
}

// A spinner: something is going on and it is not known for how long. `size` 0 is the font size. It turns with the time of the context.
UiSpinner :: proc(ctx: ^Context, size: f32 = 0) {
    metrics: ^Metrics = &ctx.style.metrics
    side: f32 = size if size > 0 else metrics.font_size * 1.2
    ElementOpen(ctx, {
        layout = {size = {Fixed(side), Fixed(side)}},
        draw = {kind = .SPINNER, value = f32(ctx.time), font_size = metrics.font_size},
    })
    ElementClose(ctx)
}

// A title: a text in the strong face of the style, `scale` times the font size (the heading of a card is 1.25, of a page 1.6)
UiTitle :: proc(ctx: ^Context, text: string, scale: f32 = 1.25) {
    UiPushTag(ctx, "title")
    TextOpen(ctx, IdSplitName(text), {font_size = ctx.style.metrics.font_size * scale})
    UiPopTag(ctx)
}

// A text in the dim color of the style: a caption, a hint, the name of a field next to it
UiLabelDim :: proc(ctx: ^Context, text: string, wrap: TextWrap = .NONE, scale: f32 = 1) {
    UiPushTag(ctx, "dim")
    TextOpen(ctx, IdSplitName(text), {wrap = wrap, font_size = ctx.style.metrics.font_size * scale})
    UiPopTag(ctx)
}

// A card: a panel with a title on top of its content. `if ui.UiCard(&ctx, "Buttons") { ... }`
@(deferred_in = UiCardEnd)
UiCard :: proc(ctx: ^Context, title: string, layout: Layout = {}) -> bool {
    metrics: ^Metrics = &ctx.style.metrics
    card: Layout = layout
    if card == {} { card = {size = {Grow(), Fit()}, direction = .TOP_TO_BOTTOM, padding = PaddingAll(metrics.padding.x * 1.6), gap = metrics.gap * 1.6} }
    ElementOpen(ctx, {id = UiId(ctx, title), layout = card, hit = {.BLOCKER}, draw = {kind = .PANEL, name = IdSplitName(title)}})
    if IdSplitName(title) != "" { UiTitle(ctx, title) }
    return true
}

UiCardEnd :: proc(ctx: ^Context, title: string, layout: Layout = {}) {
    ElementClose(ctx)
}

// The pointer and the keyboard for an element the program declares itself (a row made of an icon and texts, a card that can be clicked): call it before ElementOpen
// with the same id and `hit = {.INTERACTIVE}`. What it returns is what a widget of the library gets.
UiInteract :: proc(ctx: ^Context, id: Id, disabled: bool = false) -> Interaction {
    _ = stateGet(ctx, id)
    return widgetBehavior(ctx, id, disabled)
}
