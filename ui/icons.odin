package ui

// Small pictures for rows and buttons. An icon is a number the style knows (`Icon`): the library names the few it needs itself, a style draws them and its own set (the default
// style draws the Lucide icons: ui_default.LucideIcon(.SAVE) is the number of one; the numbers from USER on are for the program: a texture, a glyph of another icon font), so
// nothing here needs an image or a font. `UiIcon` is a widget that only draws it; buttons and chips take an icon.

Icon :: enum u16 {
    NONE,
    FOLDER,
    FOLDER_OPEN,
    FILE,
    TEXT,
    IMAGE,
    AUDIO,
    CLOSE,              // a cross
    CHECK,
    SEARCH,
    CHEVRON_UP,
    CHEVRON_DOWN,
    CHEVRON_LEFT,
    CHEVRON_RIGHT,
    CALENDAR,
    CLOCK,
    USER,               // the program's own icons are USER and the numbers above it (cast(Icon)(u16(Icon.USER) + n)), up to 0x0fff: the default style has its Lucide icons above
}

// The picture of an icon, `size` pixels (0: the font size of the style) wide and high, in `color` (alpha 0: the style's own). It is not interactive.
UiIcon :: proc(ctx: ^Context, icon: Icon, size: f32 = 0, color: Color = {}) {
    metrics: ^Metrics = &ctx.style.metrics
    side: f32 = size if size > 0 else metrics.font_size
    ElementOpen(ctx, {
        layout = {size = {Fixed(side), Fixed(side)}},
        draw = {kind = .ICON, actual = f32(icon), color = color, font_size = metrics.font_size},
    })
    ElementClose(ctx)
}
