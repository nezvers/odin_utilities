#+build !js
package ui_default

import "core:os"
import "core:testing"
import ui ".."

@(test)
test_a_theme_is_written_and_read_back_field_by_field :: proc(t: ^testing.T) {
    buffer: [4096]u8
    for original in ([2]Theme{THEME_DARK, THEME_LIGHT}) {
        original := original
        text: string = ThemeText(&original, buffer[:])
        testing.expect(t, len(text) > 400 && len(text) < len(buffer), "all fields fit the buffer")
        loaded: Theme
        applied, skipped := ThemeParse(text, &loaded)
        testing.expect_value(t, applied, ThemeFieldCount())
        testing.expect_value(t, skipped, 0)
        testing.expect(t, loaded == original, "the theme that was read is the theme that was written")
        again: [4096]u8
        testing.expect_value(t, ThemeText(&loaded, again[:]), text)
    }
}

@(test)
test_a_theme_file_may_miss_fields_have_comments_and_unknown_names :: proc(t: ^testing.T) {
    theme: Theme = THEME_DARK
    applied, skipped := ThemeParse("# a style\n\naccent = #ff0000\n  border_width =  3\n// more\nmade_up = 5\ndark = false\nbad_color = 1\nrounding = x\nscrim = #11223344\nbroken line\n", &theme)
    testing.expect_value(t, applied, 4)
    testing.expect_value(t, skipped, 4)
    testing.expect_value(t, theme.accent, ui.Color{255, 0, 0, 255})
    testing.expect_value(t, theme.border_width, 3)
    testing.expect_value(t, theme.dark, false)
    testing.expect_value(t, theme.scrim, ui.Color{0x11, 0x22, 0x33, 0x44})
    testing.expect_value(t, theme.panel, THEME_DARK.panel)               // not in the text: what it was
    testing.expect_value(t, theme.rounding, THEME_DARK.rounding)         // a value that does not read changes nothing
    // a field is found by name and by index
    index: int = ThemeFieldFind("edit_overlay")
    testing.expect(t, index >= 0 && ThemeFieldKindOf(index) == .COLOR && ThemeFieldName(index) == "edit_overlay")
    testing.expect_value(t, ThemeFieldColor(&theme, index)^, THEME_DARK.edit_overlay)
    testing.expect_value(t, ThemeFieldFind("nothing"), -1)
    // a buffer that is too small is cut, not overrun
    small: [40]u8
    testing.expect_value(t, len(ThemeText(&theme, small[:])), 40)
}

@(test)
test_a_folder_of_styles_lists_saves_loads_and_deletes :: proc(t: ^testing.T) {
    folder: string = "style_store_test_folder"
    defer os.remove_all(folder)
    file_store: FileStore
    store: StyleStore = FileStyleStoreMake(&file_store, folder)
    names: StyleNames
    store.list(&store, &names)
    testing.expect_value(t, names.count, 0)                      // no folder yet: no styles
    dark, light: Theme = THEME_DARK, THEME_LIGHT
    dark.accent = {1, 2, 3, 255}
    testing.expect(t, store.save(&store, "Dark mine", &dark))
    testing.expect(t, store.save(&store, "light", &light))
    testing.expect(t, !store.save(&store, "../escape", &light), "a name cannot reach another folder")
    testing.expect(t, !store.save(&store, "", &light) && !store.save(&store, " x", &light) && !store.save(&store, "a/b", &light))
    store.list(&store, &names)
    testing.expect_value(t, names.count, 2)
    testing.expect(t, StyleNameAt(&names, 0) == "Dark mine" && StyleNameAt(&names, 1) == "light", "sorted")
    loaded: Theme = THEME_LIGHT
    testing.expect(t, store.load(&store, "Dark mine", &loaded))
    testing.expect(t, loaded == dark)
    testing.expect(t, !store.load(&store, "nothing", &loaded))
    testing.expect(t, store.delete(&store, "light"))
    testing.expect(t, !store.delete(&store, "light"))
    store.list(&store, &names)
    testing.expect_value(t, names.count, 1)
    testing.expect(t, StyleNameValid("A-b_c 1") && !StyleNameValid("a.b") && !StyleNameValid("a "))
}
