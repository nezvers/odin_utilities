#+build !js
package ui_default

// A StyleStore of a folder: `<folder>/<name>.style`, one file for each style, in the text of ThemeText. The folder is made when the first style is saved. For the demos (odin_utilities/ui/styles)
// and for an application that keeps its styles next to itself; a web build has no files and keeps its own store.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

STYLE_EXTENSION :: ".style"
STYLE_FOLDER_LENGTH :: 256

FileStore :: struct {
    folder: [STYLE_FOLDER_LENGTH]u8,
    length: int,
}

// A store over the folder (it is copied: a literal or a temporary string will do). Give the `StyleStore` to the style editor; the `FileStore` has to live as long as it is used.
FileStyleStoreMake :: proc(file_store: ^FileStore, folder: string) -> StyleStore {
    file_store.length = copy(file_store.folder[:], folder)
    return {user = file_store, list = fileList, load = fileLoad, save = fileSave, delete = fileDelete, load_fonts = fileLoadFonts, save_fonts = fileSaveFonts}
}

@(private)
filePath :: proc(store: ^StyleStore, name: string) -> (path: string, ok: bool) {
    if !StyleNameValid(name) { return "", false }
    file_store: ^FileStore = cast(^FileStore)store.user
    return fmt.tprintf("%s/%s%s", string(file_store.folder[:file_store.length]), name, STYLE_EXTENSION), true
}

@(private)
fileList :: proc(store: ^StyleStore, names: ^StyleNames) {
    names.count = 0
    file_store: ^FileStore = cast(^FileStore)store.user
    entries, err := os.read_all_directory_by_path(string(file_store.folder[:file_store.length]), context.temp_allocator)
    if err != nil { return }
    found: [dynamic]string
    found.allocator = context.temp_allocator
    for entry in entries {
        if entry.type == .Directory || !strings.has_suffix(entry.name, STYLE_EXTENSION) { continue }
        name: string = entry.name[:len(entry.name) - len(STYLE_EXTENSION)]
        if StyleNameValid(name) { append(&found, name) }
    }
    slice.sort(found[:])
    for name in found { StyleNamesAdd(names, name) }
}

@(private)
fileLoad :: proc(store: ^StyleStore, name: string, theme: ^Theme) -> bool {
    path, ok := filePath(store, name)
    if !ok { return false }
    data, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil { return false }
    applied, _ := ThemeParse(string(data), theme)
    return applied > 0
}

@(private)
fileSave :: proc(store: ^StyleStore, name: string, theme: ^Theme) -> bool {
    path, ok := filePath(store, name)
    if !ok { return false }
    file_store: ^FileStore = cast(^FileStore)store.user
    os.make_directory_all(string(file_store.folder[:file_store.length]))
    buffer: [4096]u8
    text: string = ThemeText(theme, buffer[:])
    // the fonts the file names stay (a theme saved alone does not take the fonts away)
    fonts: SkinFonts
    if old, err := os.read_entire_file(path, context.temp_allocator); err == nil { SkinFontsParse(string(old), &fonts) }
    font_lines: [FONT_LINES_SIZE]u8
    all: [4096 + FONT_LINES_SIZE]u8
    length: int = copy(all[:], text)
    length += copy(all[length:], SkinFontsText(&fonts, font_lines[:]))
    return os.write_entire_file(path, all[:length]) == nil
}

FONT_LINES_SIZE :: 8 * (FONT_FILE_LENGTH + 40)

@(private)
fileLoadFonts :: proc(store: ^StyleStore, name: string, fonts: ^SkinFonts) -> bool {
    path, ok := filePath(store, name)
    if !ok { return false }
    data, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil { return false }
    fonts^ = {}
    SkinFontsParse(string(data), fonts)
    return true
}

// The colors of the file stay, the font lines are replaced
@(private)
fileSaveFonts :: proc(store: ^StyleStore, name: string, fonts: ^SkinFonts) -> bool {
    path, ok := filePath(store, name)
    if !ok { return false }
    old, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil { return false }
    kept: [4096 + 64]u8
    colors: string = SkinTextWithoutFonts(string(old), kept[:])
    font_lines: [FONT_LINES_SIZE]u8
    all: [4096 + 64 + FONT_LINES_SIZE]u8
    length: int = copy(all[:], colors)
    length += copy(all[length:], SkinFontsText(fonts, font_lines[:]))
    return os.write_entire_file(path, all[:length]) == nil
}

@(private)
fileDelete :: proc(store: ^StyleStore, name: string) -> bool {
    path, ok := filePath(store, name)
    if !ok { return false }
    return os.remove(path) == nil
}
