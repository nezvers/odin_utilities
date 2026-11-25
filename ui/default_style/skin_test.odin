#+build !js
package ui_default

import "core:os"
import "core:testing"

@(test)
test_font_lines_are_written_read_and_kept_apart_from_the_colors :: proc(t: ^testing.T) {
    fonts: SkinFonts
    testing.expect(t, SkinFontSet(&fonts, .STRONG, "fonts/Lato-Bold.ttf"))
    testing.expect(t, SkinFontSet(&fonts, .MONO, "C:/fonts/Mono.ttf"))
    testing.expect(t, !SkinFontSet(&fonts, .ITALIC, "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"))
    testing.expect_value(t, SkinFontsCount(&fonts), 2)
    buffer: [1024]u8
    text: string = SkinFontsText(&fonts, buffer[:])
    testing.expect_value(t, text, "font_strong = fonts/Lato-Bold.ttf\nfont_mono = C:/fonts/Mono.ttf\n")
    read: SkinFonts
    testing.expect_value(t, SkinFontsParse(text, &read), 2)
    testing.expect_value(t, SkinFontFile(&read, .STRONG), "fonts/Lato-Bold.ttf")
    testing.expect_value(t, SkinFontFile(&read, .REGULAR), "")
    // a file with colors and fonts: each reader takes its own lines, and the theme reader is not troubled by the fonts
    mixed: [2048]u8
    theme: Theme = THEME_DARK
    colors: string = ThemeText(&theme, mixed[:])
    both: string = colors
    both = string(append_text(mixed[:], colors, text))
    applied, _ := ThemeParse(both, &theme)
    testing.expect(t, applied == ThemeFieldCount())
    only: [2048]u8
    stripped: string = SkinTextWithoutFonts(both, only[:])
    testing.expect_value(t, stripped, colors)
    again: SkinFonts
    testing.expect_value(t, SkinFontsParse(stripped, &again), 0)
    testing.expect_value(t, FaceKey(.MONO_STRONG_ITALIC), "mono_strong_italic")
}

@(private = "file")
append_text :: proc(out: []u8, first: string, second: string) -> []u8 {
    length: int = copy(out, first)
    length += copy(out[length:], second)
    return out[:length]
}

@(test)
test_a_file_style_keeps_its_fonts_when_the_colors_are_saved_and_the_colors_when_the_fonts_are :: proc(t: ^testing.T) {
    folder: string = "skin_store_test_folder"
    defer os.remove_all(folder)
    file_store: FileStore
    store: StyleStore = FileStyleStoreMake(&file_store, folder)
    theme: Theme = THEME_DARK
    theme.accent = {9, 8, 7, 255}
    testing.expect(t, store.save(&store, "mine", &theme))
    fonts: SkinFonts
    SkinFontSet(&fonts, .STRONG, "Lato-Bold.ttf")
    testing.expect(t, store.save_fonts(&store, "mine", &fonts))
    // the colors again: the fonts stay
    theme.accent = {1, 2, 3, 255}
    testing.expect(t, store.save(&store, "mine", &theme))
    loaded: SkinFonts
    testing.expect(t, store.load_fonts(&store, "mine", &loaded))
    testing.expect_value(t, SkinFontFile(&loaded, .STRONG), "Lato-Bold.ttf")
    colors: Theme = THEME_LIGHT
    testing.expect(t, store.load(&store, "mine", &colors))
    testing.expect_value(t, colors.accent, theme.accent)
    // the fonts again: the colors stay
    SkinFontSet(&fonts, .STRONG, "")
    SkinFontSet(&fonts, .REGULAR, "Lato.ttf")
    testing.expect(t, store.save_fonts(&store, "mine", &fonts))
    testing.expect(t, store.load_fonts(&store, "mine", &loaded))
    testing.expect_value(t, SkinFontFile(&loaded, .STRONG), "")
    testing.expect_value(t, SkinFontFile(&loaded, .REGULAR), "Lato.ttf")
    testing.expect(t, store.load(&store, "mine", &colors))
    testing.expect_value(t, colors.accent, theme.accent)
    testing.expect(t, !store.save_fonts(&store, "nothing", &fonts), "no style of that name")
}

@(test)
test_a_memory_style_keeps_its_fonts :: proc(t: ^testing.T) {
    memory: ^MemoryStyles = new(MemoryStyles)
    defer free(memory)
    store: StyleStore = MemoryStyleStoreMake(memory)
    theme: Theme = THEME_DARK
    testing.expect(t, store.save(&store, "a", &theme))
    fonts: SkinFonts
    SkinFontSet(&fonts, .MONO, "Fira.ttf")
    testing.expect(t, store.save_fonts(&store, "a", &fonts))
    loaded: SkinFonts
    testing.expect(t, store.load_fonts(&store, "a", &loaded))
    testing.expect_value(t, SkinFontFile(&loaded, .MONO), "Fira.ttf")
    testing.expect(t, store.save(&store, "b", &theme))
    testing.expect(t, store.load_fonts(&store, "b", &loaded))
    testing.expect_value(t, SkinFontsCount(&loaded), 0)
    testing.expect(t, store.delete(&store, "a"))
    testing.expect(t, store.load_fonts(&store, "b", &loaded))
}

@(test)
test_the_font_files_of_a_skin_are_read_from_the_folder_of_the_style :: proc(t: ^testing.T) {
    fonts: SkinFonts
    SkinFontSet(&fonts, .REGULAR, "Inter-Regular.ttf")
    SkinFontSet(&fonts, .STRONG, "missing.ttf")
    bytes: SkinFontBytes
    defer SkinFontBytesFree(&bytes)
    read: int = SkinFontsRead(&fonts, #directory + "../../assets/fonts/inter", &bytes)
    testing.expect_value(t, read, 1)
    testing.expect(t, len(bytes[.REGULAR]) > 1000, "the file was read")
    testing.expect(t, len(bytes[.STRONG]) == 0 && len(bytes[.MONO]) == 0, "a missing file and an unnamed face have no bytes: the built in font")
}
