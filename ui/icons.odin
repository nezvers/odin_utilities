package ui

// Small pictures for rows and buttons. An icon is a number the style knows (`Icon`): the default style draws these few with rectangles, a style of a program draws its own set (the
// numbers above ICON_USER are for the program: a texture, a glyph of an icon font), so nothing here needs an image or a font. `UiIcon` is a widget that only draws it.

Icon :: enum u8 {
    NONE,
    FOLDER,
    FOLDER_OPEN,
    FILE,
    TEXT,
    IMAGE,
    AUDIO,
    USER,               // the program's own icons are USER and the numbers above it (cast(Icon)(u8(Icon.USER) + n))
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
