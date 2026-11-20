package ui_default

// A theme from one color. ThemeFromAccent gives every color of a Theme for an accent (a brand color) and a mode: the surfaces get a breath of the hue of the accent,
// the accent is given the lightness that reads in the mode, and every pair of a text and what it lies on is moved apart until it has the contrast text needs.
// ThemeFromAccent({59, 130, 246, 255}, true) is THEME_DARK and (..., false) is THEME_LIGHT: the two constants are this generator run for a blue.
//
// This file is a port of the theme generator of Baldr (https://github.com/BuLEEto/Baldr, baldr/theme.odin `theme_from_seed` and baldr/color.odin; Copyright (c) 2026
// Lee Fry and Baldr contributors, zlib License). It is an altered version: only the Dark and the Light mode are here, the roles are the ones of this style, and the
// colors are 8 bit sRGB instead of linear floats. The numbers of the roles (lightness and chroma per role and mode) are Baldr's.
//
// The colors are made in OKLCH (Björn Ottosson's OKLab as lightness, chroma and hue): equal steps of lightness look equal, and a hue stays the hue while it gets lighter.

import "core:math"
import ui ".."

// A color in linear light, 0..1 (sRGB bytes are a curve on top of this)
@(private)
Linear :: [3]f32

@(private)
toLinear :: proc "contextless" (color: ui.Color) -> Linear {
    channel :: proc "contextless" (value: u8) -> f32 {
        c: f32 = f32(value) / 255
        return c / 12.92 if c <= 0.04045 else math.pow((c + 0.055) / 1.055, 2.4)
    }
    return {channel(color.r), channel(color.g), channel(color.b)}
}

@(private)
fromLinear :: proc "contextless" (linear: Linear, alpha: u8 = 255) -> ui.Color {
    channel :: proc "contextless" (value: f32) -> u8 {
        c: f32 = clamp(value, 0, 1)
        encoded: f32 = 12.92 * c if c <= 0.0031308 else 1.055 * math.pow(c, 1 / 2.4) - 0.055
        return u8(clamp(encoded * 255 + 0.5, 0, 255))
    }
    return {channel(linear.x), channel(linear.y), channel(linear.z), alpha}
}

@(private)
cubeRoot :: proc "contextless" (x: f32) -> f32 {
    return -math.pow(-x, 1.0 / 3.0) if x < 0 else math.pow(x, 1.0 / 3.0)
}

@(private)
linearToOklab :: proc "contextless" (c: Linear) -> [3]f32 {
    l: f32 = cubeRoot(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
    m: f32 = cubeRoot(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
    s: f32 = cubeRoot(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
    return {
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    }
}

@(private)
oklabToLinear :: proc "contextless" (lab: [3]f32) -> Linear {
    l: f32 = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
    m: f32 = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
    s: f32 = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
    l, m, s = l * l * l, m * m * m, s * s * s
    return {
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    }
}

// A color from its lightness (0..1), chroma (0 grey, about 0.3 vivid) and hue in degrees. A color that sRGB cannot show loses chroma until it can: the lightness and
// the hue are kept.
@(private)
oklchLinear :: proc "contextless" (lightness: f32, chroma: f32, hue: f32) -> Linear {
    radians: f32 = hue * math.PI / 180
    c: f32 = chroma
    linear: Linear
    for _ in 0 ..< 25 {
        linear = oklabToLinear({lightness, c * math.cos(radians), c * math.sin(radians)})
        LIMIT :: 0.0005
        if linear.x >= -LIMIT && linear.x <= 1 + LIMIT && linear.y >= -LIMIT && linear.y <= 1 + LIMIT && linear.z >= -LIMIT && linear.z <= 1 + LIMIT { break }
        c *= 0.85
    }
    return {clamp(linear.x, 0, 1), clamp(linear.y, 0, 1), clamp(linear.z, 0, 1)}
}

// The color of a lightness, a chroma and a hue (degrees), as sRGB bytes
ColorFromOklch :: proc "contextless" (lightness: f32, chroma: f32, hue: f32, alpha: u8 = 255) -> ui.Color {
    return fromLinear(oklchLinear(lightness, chroma, hue), alpha)
}

// The lightness, the chroma and the hue (degrees, 0..360) of a color
ColorToOklch :: proc "contextless" (color: ui.Color) -> (lightness: f32, chroma: f32, hue: f32) {
    lab: [3]f32 = linearToOklab(toLinear(color))
    lightness = lab.x
    chroma = math.sqrt(lab.y * lab.y + lab.z * lab.z)
    hue = math.atan2(lab.z, lab.y) * 180 / math.PI
    if hue < 0 { hue += 360 }
    return
}

@(private)
luminance :: proc "contextless" (c: Linear) -> f32 {
    return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
}

// The contrast of two colors as WCAG 2 counts it: 1 for the same color, 21 for black on white. Text wants 4.5 at least, large text and the edges of controls 3.
ColorContrast :: proc "contextless" (a: ui.Color, b: ui.Color) -> f32 {
    la, lb: f32 = luminance(toLinear(a)), luminance(toLinear(b))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// A color as a lightness, chroma and hue kept in linear light while it is worked on (the bytes are made at the end, so two steps do not round twice)
@(private)
contrastOf :: proc "contextless" (a: Linear, b: Linear) -> f32 {
    la, lb: f32 = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// `ink` with its lightness moved away from `ground` until the two have a contrast of `wanted`: the hue and the chroma stay (the chroma shrinks only when sRGB has no
// such color). An ink that has the contrast already is not touched.
@(private)
ensureContrast :: proc "contextless" (ink: Linear, ground: Linear, wanted: f32) -> Linear {
    if contrastOf(ink, ground) >= wanted { return ink }
    lab: [3]f32 = linearToOklab(ink)
    chroma: f32 = math.sqrt(lab.y * lab.y + lab.z * lab.z)
    hue: f32 = math.atan2(lab.z, lab.y) * 180 / math.PI
    lighter: bool = lab.x >= linearToOklab(ground).x
    low: f32 = lab.x
    high: f32 = 1 if lighter else 0
    best: Linear = ink
    for _ in 0 ..< 20 {
        middle: f32 = (low + high) / 2
        candidate: Linear = oklchLinear(middle, chroma, hue)
        if contrastOf(candidate, ground) >= wanted {
            best = candidate
            high = middle
        } else {
            low = middle
        }
        if abs(high - low) < 0.002 { break }
    }
    if contrastOf(best, ground) < wanted { best = oklchLinear(1 if lighter else 0, 0, hue) }
    return best
}

// An accent with less chroma than this is a choice of a grey theme: the accent roles and the tint of the neutrals fade out together below it
@(private)
NEUTRAL_ACCENT_CHROMA :: f32(0.02)

// The theme of an accent color for the dark or the light mode. The corners, the border and the state washes are the ones of THEME_DARK.
ThemeFromAccent :: proc(accent: ui.Color, dark: bool) -> (theme: Theme) {
    _, accent_chroma, hue := ColorToOklch(accent)
    // how much of the chroma of the mode this accent asks for: 1 for a color, 0 for a grey. The lightness of every role stays, so the contrasts hold for any accent.
    tint: f32 = clamp(accent_chroma / NEUTRAL_ACCENT_CHROMA, 0, 1)
    neutral: f32 = 0.006 * tint
    background, panel, track, surface_high, text, text_dim, border, border_soft: Linear
    primary, on_primary, soft, on_soft, control, on_control, danger, on_danger, warning, success, focus: Linear
    if dark {
        background = oklchLinear(0.185, neutral, hue)
        panel = oklchLinear(0.225, neutral, hue)
        track = oklchLinear(0.265, neutral, hue)
        surface_high = oklchLinear(0.315, neutral, hue)
        text = oklchLinear(0.90, neutral, hue)
        text_dim = oklchLinear(0.70, neutral, hue)
        border = oklchLinear(0.37, neutral * 1.5, hue)
        border_soft = oklchLinear(0.30, neutral * 1.5, hue)
        primary = oklchLinear(0.74, 0.13 * tint, hue)
        on_primary = oklchLinear(0.18, 0.04 * tint, hue)
        soft = oklchLinear(0.36, 0.09 * tint, hue)
        on_soft = oklchLinear(0.93, 0.05 * tint, hue)
        control = oklchLinear(0.31, 0.02 * tint, hue)
        on_control = oklchLinear(0.92, neutral, hue)
        danger = oklchLinear(0.68, 0.17, 25)
        on_danger = oklchLinear(0.15, 0.05, 25)
        warning = oklchLinear(0.78, 0.15, 75)
        success = oklchLinear(0.74, 0.14, 150)
        focus = oklchLinear(0.80, 0.12 * tint, hue)
    } else {
        // a light theme has no lightness left above a card, so the steps go down from white: the window sits back in a light grey, a card is nearly white, a popup is
        // white, and the shadow does what lightness does in a dark theme
        background = oklchLinear(0.938, neutral * 0.8, hue)
        panel = oklchLinear(0.990, neutral * 0.3, hue)
        track = oklchLinear(0.965, neutral, hue)
        surface_high = oklchLinear(1, 0, hue)
        text = oklchLinear(0.25, neutral, hue)
        text_dim = oklchLinear(0.50, neutral, hue)
        border = oklchLinear(0.83, neutral * 2, hue)
        border_soft = oklchLinear(0.90, neutral * 2, hue)
        primary = oklchLinear(0.56, 0.19 * tint, hue)
        on_primary = oklchLinear(0.99, 0.01 * tint, hue)
        soft = oklchLinear(0.92, 0.05 * tint, hue)
        on_soft = oklchLinear(0.34, 0.12 * tint, hue)
        control = oklchLinear(0.92, 0.012 * tint, hue)
        on_control = oklchLinear(0.25, neutral, hue)
        danger = oklchLinear(0.57, 0.20, 25)
        on_danger = oklchLinear(0.99, 0.01, 25)
        warning = oklchLinear(0.66, 0.16, 72)
        success = oklchLinear(0.60, 0.16, 150)
        focus = oklchLinear(0.56, 0.19 * tint, hue)
    }
    // readable by construction, whatever the accent: every text is moved away from what it lies on until it has its contrast
    text = ensureContrast(text, panel, 7)
    text_dim = ensureContrast(text_dim, track, 4.5)
    on_primary = ensureContrast(on_primary, primary, 4.5)
    on_soft = ensureContrast(on_soft, soft, 4.5)
    on_control = ensureContrast(on_control, control, 4.5)
    on_danger = ensureContrast(on_danger, danger, 4.5)
    primary = ensureContrast(primary, panel, 4.5)           // the accent is also text: links, ghost buttons
    danger = ensureContrast(danger, panel, 3)
    focus = ensureContrast(focus, background, 3)
    border = ensureContrast(border, panel, 1.35)

    theme = THEME_DARK if dark else THEME_LIGHT             // the corners, the widths, the washes, the shadow
    theme.dark = dark
    theme.background = fromLinear(background)
    theme.panel = fromLinear(panel)
    theme.track = fromLinear(track)
    theme.surface_high = fromLinear(surface_high)
    theme.text = fromLinear(text)
    theme.text_dim = fromLinear(text_dim)
    theme.border = fromLinear(border)
    theme.border_soft = fromLinear(border_soft)
    theme.track_strong = theme.border
    theme.accent = fromLinear(primary)
    theme.accent_text = fromLinear(on_primary)
    theme.accent_soft = fromLinear(soft)
    theme.accent_soft_text = fromLinear(on_soft)
    theme.control = fromLinear(control)
    // a button under the pointer and under a press: a little of its label mixed in, the way StateColor mixes every other control
    theme.control_hover = ui.ColorLerp(theme.control, fromLinear(on_control), theme.hover)
    theme.control_pressed = ui.ColorLerp(theme.control, fromLinear(on_control), theme.press)
    theme.focus = fromLinear(focus)
    theme.danger = fromLinear(danger)
    theme.danger_text = fromLinear(on_danger)
    theme.warning = fromLinear(warning)
    theme.success = fromLinear(success)
    return
}
