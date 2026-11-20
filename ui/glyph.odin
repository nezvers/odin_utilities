package ui

// The picture of an input: a keycap with the name of the key, the round face buttons of a gamepad, a shoulder button, a trigger, a d-pad, a stick, a mouse button. Menus that
// list actions with the button that does them (a rebinding page, a help overlay, a prompt "Press A") draw them with `UiGlyph`, `UiBindingGlyph` and `UiBindingField`.
//
//     glyph := ui.Glyph{shape = .FACE, label = "A", color = {70, 160, 90, 255}}          // drawn by the style from vectors
//     glyph := ui.Glyph{shape = .FACE, texture = my_pad_atlas, source = {64, 0, 32, 32}} // or a picture of the program's own (the art of the pad in use)
//
// What an input looks like is the program's choice: `GlyphProc` turns a `Binding` into a `Glyph` (the kit has one, `ui_kit.GlyphOf`, that names keys and draws the buttons of its
// `PadButton`s, and takes a texture per button from `ui_kit.GlyphTextures` when the program sets one). A texture is a handle the framework glue understands (the kit: `kit.Texture`);
// the style draws it through the painter's `draw_texture`, and falls back to the vector shape when there is no such proc.
//
// `UiBindingField` is the button of a rebinding page, as `UiShortcutField` is for a chord: it shows the glyph of the binding, a click makes it listen, the next input the program
// reports (`pressed`) becomes the binding, Backspace takes it away, Escape lets go.
//
// Limits: strings of a glyph (labels) have to live until the frame is drawn (a literal, an enum name); a glyph is one picture (no "Ctrl + C" made of two caps: its label is the
//     whole text); the texture path is only in the painters that have `draw_texture` (the kit; raylib and Karl2D glues draw the vector shapes); no animation; Backspace cannot be bound
//     by a field; the field takes one input (a stick direction or a trigger axis has to be reported by the program as a button press)

GlyphShape :: enum u8 {
    KEY,                // a keycap: as wide as its label
    FACE,               // a round button with a letter or a symbol
    SHOULDER,           // a bumper: a wide flat pill
    TRIGGER,            // a trigger: a wide tall pill
    DPAD,               // a cross; the label is the direction ("U", "D", "L", "R" mark an arm)
    STICK,              // a round stick with a ring
    MOUSE,              // a mouse button: the label says which
}

Glyph :: struct {
    shape: GlyphShape,
    label: string,
    color: Color,       // the accent of the shape (a face button's color); alpha 0: the theme's
    texture: u32,       // the program's picture (0: draw the shape); a handle of the glue
    source: Rect,       // the part of the texture in pixels (zero size: all of it)
}

// How an input looks. `user` is whatever the program passed to the widget.
GlyphProc :: proc(user: rawptr, binding: Binding) -> Glyph

// The size of a glyph in a row `height` high (0: the height of a control)
GlyphSize :: proc(ctx: ^Context, glyph: Glyph, height: f32 = 0) -> Vec2 {
    metrics: ^Metrics = &ctx.style.metrics
    h: f32 = height if height > 0 else metrics.control_height * 0.8
    if glyph.texture != 0 {
        if glyph.source.z > 0 && glyph.source.w > 0 { return {h * glyph.source.z / glyph.source.w, h} }
        return {h, h}
    }
    switch glyph.shape {
    case .KEY, .MOUSE:
        return {max(h, measureText(ctx, glyph.label, metrics.font_size * 0.85).x + h * 0.6), h}
    case .SHOULDER:
        return {h * 1.7, h * 0.7}
    case .TRIGGER:
        return {h * 1.2, h}
    case .FACE, .DPAD, .STICK:
        return {h, h}
    }
    return {h, h}
}

// Draws a glyph; not interactive.
UiGlyph :: proc(ctx: ^Context, glyph: Glyph, height: f32 = 0) {
    size: Vec2 = GlyphSize(ctx, glyph, height)
    ElementOpen(ctx, {
        layout = {size = {Fixed(size.x), Fixed(size.y)}},
        draw = {kind = .GLYPH, text = glyph.label, actual = f32(glyph.shape), color = glyph.color, texture = glyph.texture, source = glyph.source, font_size = ctx.style.metrics.font_size * 0.85},
    })
    ElementClose(ctx)
}

// The glyph of an input, asked from `lookup`; an empty slot (no device) is "None" in dim text
UiBindingGlyph :: proc(ctx: ^Context, binding: Binding, lookup: GlyphProc, user: rawptr = nil, height: f32 = 0) {
    if binding.device == .NONE || lookup == nil {
        UiLabelDim(ctx, "None")
        return
    }
    UiGlyph(ctx, lookup(user, binding), height)
}

// The button of one binding. `pressed`: the input that went down in this frame (device NONE: nothing did). True in the frame the binding changed. `listening`: it waits for
// an input; the program keeps its own actions off then.
UiBindingField :: proc(ctx: ^Context, name: string, binding: ^Binding, pressed: Binding, lookup: GlyphProc, user: rawptr = nil, size: Size = {}, disabled: bool = false) -> (changed: bool, listening: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    opened_now: bool
    if interaction.clicked {
        state.open = !state.open
        opened_now = state.open
        if state.open { ctx.focus = id }
    }
    if state.open && (ctx.focus != id || disabled) { state.open = false }
    if state.open && !opened_now {
        if ctx.cancel_pending {
            state.open = false
            ctx.cancel_pending = false
        } else if .BACKSPACE in ctx.input.keys {
            changed = binding.device != .NONE
            binding^ = {}
            state.open = false
        } else if pressed.device != .NONE {
            changed = binding^ != pressed
            binding^ = pressed
            state.open = false
        }
    }
    listening = state.open
    state.editing = listening
    state.own_vertical = listening
    glyph: Glyph = lookup(user, binding^) if binding.device != .NONE && lookup != nil else {}
    width: f32 = max(GlyphSize(ctx, glyph).x if binding.device != .NONE else textWidth(ctx, "None"), textWidth(ctx, SHORTCUT_LISTENING)) + metrics.padding.x * 2
    UiPushTag(ctx, "primary" if listening else "outline")
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, width, metrics.control_height), align = {x = .CENTER, y = .CENTER}, direction = .LEFT_TO_RIGHT},
        hit = {} if disabled else {.INTERACTIVE},
        draw = {kind = .BUTTON, name = "", font_size = metrics.font_size, flags = {.DISABLED} if disabled else {}},
    })
    if listening {
        UiLabel(ctx, SHORTCUT_LISTENING)
    } else {
        UiBindingGlyph(ctx, binding^, lookup, user)
    }
    ElementClose(ctx)
    UiPopTag(ctx)
    return
}
