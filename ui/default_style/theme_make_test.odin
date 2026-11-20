#+build !js
package ui_default

import "core:testing"
import ui ".."

// The accent the two themes of the style were made for (Baldr's blue, #3B82F6)
@(private = "file")
BLUE :: ui.Color{59, 130, 246, 255}

@(private = "file")
near :: proc(a: ui.Color, b: ui.Color, tolerance: int = 1) -> bool {
    return abs(int(a.r) - int(b.r)) <= tolerance && abs(int(a.g) - int(b.g)) <= tolerance && abs(int(a.b) - int(b.b)) <= tolerance && a.a == b.a
}

@(test)
test_oklch_goes_there_and_back :: proc(t: ^testing.T) {
    lightness, chroma, hue := ColorToOklch(BLUE)
    testing.expect(t, abs(lightness - 0.623) < 0.002 && abs(chroma - 0.188) < 0.002 && abs(hue - 259.8) < 0.3, "the blue in OKLCH")
    testing.expect(t, near(ColorFromOklch(lightness, chroma, hue), BLUE))
    for color in ([?]ui.Color{{0, 0, 0, 255}, {255, 255, 255, 255}, {200, 30, 40, 255}, {20, 160, 90, 255}, {128, 128, 128, 255}}) {
        l, c, h := ColorToOklch(color)
        testing.expectf(t, near(ColorFromOklch(l, c, h), color), "%v comes back", color)
    }
    // white and black are the ends of the lightness, a grey has no chroma
    l, c, _ := ColorToOklch({255, 255, 255, 255})
    testing.expect(t, abs(l - 1) < 0.001 && c < 0.001)
    l, c, _ = ColorToOklch({0, 0, 0, 255})
    testing.expect(t, l < 0.001 && c < 0.001)
    // a color that sRGB does not have keeps its lightness and hue and loses chroma
    vivid: ui.Color = ColorFromOklch(0.7, 0.4, 150)
    vl, vc, vh := ColorToOklch(vivid)
    testing.expect(t, abs(vl - 0.7) < 0.02 && vc < 0.4 && vc > 0.1 && abs(vh - 150) < 4)
    testing.expect_value(t, ColorFromOklch(0.5, 0.1, 30, 128).a, 128)

    testing.expect(t, abs(ColorContrast({0, 0, 0, 255}, {255, 255, 255, 255}) - 21) < 0.01)
    testing.expect_value(t, ColorContrast(BLUE, BLUE), 1)
    testing.expect_value(t, ColorContrast({10, 20, 30, 255}, {200, 210, 220, 255}), ColorContrast({200, 210, 220, 255}, {10, 20, 30, 255}))
}

@(test)
test_the_themes_of_the_style_are_the_generator_run_for_its_blue :: proc(t: ^testing.T) {
    for dark in ([2]bool{true, false}) {
        made: Theme = ThemeFromAccent(BLUE, dark)
        stored: Theme = THEME_DARK if dark else THEME_LIGHT
        pairs: [20][2]ui.Color = {
            {made.background, stored.background}, {made.panel, stored.panel}, {made.surface_high, stored.surface_high}, {made.border, stored.border},
            {made.border_soft, stored.border_soft}, {made.text, stored.text}, {made.text_dim, stored.text_dim}, {made.control, stored.control},
            {made.track, stored.track}, {made.track_strong, stored.track_strong}, {made.accent, stored.accent}, {made.accent_text, stored.accent_text},
            {made.accent_soft, stored.accent_soft}, {made.accent_soft_text, stored.accent_soft_text}, {made.focus, stored.focus}, {made.danger, stored.danger},
            {made.danger_text, stored.danger_text}, {made.warning, stored.warning}, {made.success, stored.success}, {made.shadow, stored.shadow},
        }
        for pair, i in pairs {
            testing.expectf(t, near(pair[0], pair[1]), "dark %v, color %d: made %v, stored %v", dark, i, pair[0], pair[1])
        }
        testing.expect(t, near(made.control_hover, stored.control_hover) && near(made.control_pressed, stored.control_pressed))
        testing.expect_value(t, made.dark, dark)
        testing.expect_value(t, made.max_radius, stored.max_radius)
        testing.expect_value(t, made.hover, stored.hover)
    }
}

@(test)
test_a_theme_of_any_accent_is_readable :: proc(t: ^testing.T) {
    accents: [8]ui.Color = {
        {59, 130, 246, 255}, {229, 72, 77, 255}, {242, 181, 68, 255}, {34, 197, 94, 255}, {139, 92, 246, 255}, {236, 72, 153, 255}, {250, 250, 40, 255}, {10, 10, 60, 255},
    }
    for accent in accents {
        for dark in ([2]bool{true, false}) {
            theme: Theme = ThemeFromAccent(accent, dark)
            // text on what it lies on (a little under the numbers the generator asks for: the colors are rounded to bytes at the end)
            testing.expectf(t, ColorContrast(theme.text, theme.panel) >= 6.8, "%v %v: text on a panel %v", accent, dark, ColorContrast(theme.text, theme.panel))
            testing.expectf(t, ColorContrast(theme.text_dim, theme.track) >= 4.3, "%v %v: dim text in a well %v", accent, dark, ColorContrast(theme.text_dim, theme.track))
            testing.expectf(t, ColorContrast(theme.accent_text, theme.accent) >= 4.3, "%v %v: the label of a primary button %v", accent, dark, ColorContrast(theme.accent_text, theme.accent))
            testing.expectf(t, ColorContrast(theme.accent_soft_text, theme.accent_soft) >= 4.3, "%v %v: the label of a secondary button", accent, dark)
            testing.expectf(t, ColorContrast(theme.danger_text, theme.danger) >= 4.3, "%v %v: the label of a danger button", accent, dark)
            testing.expectf(t, ColorContrast(theme.accent, theme.panel) >= 4.3, "%v %v: the accent as text (a ghost button)", accent, dark)
            testing.expectf(t, ColorContrast(theme.focus, theme.background) >= 2.9, "%v %v: the focus ring", accent, dark)
            // the surfaces are steps: the window, a card, a popup
            _, _, accent_hue := ColorToOklch(accent)
            background, _, _ := ColorToOklch(theme.background)
            panel, _, _ := ColorToOklch(theme.panel)
            high, _, _ := ColorToOklch(theme.surface_high)
            testing.expect(t, background < panel && panel < high)
            // the accent keeps the hue that was asked for
            _, chroma, hue := ColorToOklch(theme.accent)
            difference: f32 = abs(hue - accent_hue)
            testing.expectf(t, chroma > 0.05 && min(difference, 360 - difference) < 12, "%v %v: the accent has the hue (%v, wanted %v)", accent, dark, hue, accent_hue)
        }
    }
    // a grey accent gives a grey theme: no chroma in the accent and none in the surfaces, and it still warns in red
    grey: Theme = ThemeFromAccent({128, 128, 128, 255}, true)
    _, accent_chroma, _ := ColorToOklch(grey.accent)
    _, panel_chroma, _ := ColorToOklch(grey.panel)
    _, danger_chroma, _ := ColorToOklch(grey.danger)
    testing.expect(t, accent_chroma < 0.005 && panel_chroma < 0.005 && danger_chroma > 0.1)
    testing.expect(t, ColorContrast(grey.accent_text, grey.accent) >= 4.3)
}
