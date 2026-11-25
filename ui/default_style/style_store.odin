package ui_default

// Where saved styles live. The style editor (style_editor.odin) talks to a `StyleStore`, a table of four procedures, so an application keeps its styles where it wants (a file, a settings database, a
// server); `FileStyleStore` (style_store_file.odin) is the one that keeps one `<name>.style` file for each style in a folder. Names are short and plain: letters, digits, space, dash and underscore.

STYLE_NAMES :: 64               // how many styles a list holds
STYLE_NAME_LENGTH :: 48         // the longest name

StyleNames :: struct {
    names: [STYLE_NAMES][STYLE_NAME_LENGTH]u8,
    lengths: [STYLE_NAMES]u8,
    count: int,
}

StyleStore :: struct {
    user: rawptr,                                                                   // the store's own data (the FileStore of a folder)
    list: proc(store: ^StyleStore, names: ^StyleNames),                             // fills `names` (sorted, at most STYLE_NAMES)
    load: proc(store: ^StyleStore, name: string, theme: ^Theme) -> bool,           // changes only the fields the style has
    save: proc(store: ^StyleStore, name: string, theme: ^Theme) -> bool,           // false when the name is not a valid one or the storage refuses
    delete: proc(store: ^StyleStore, name: string) -> bool,
    load_fonts: proc(store: ^StyleStore, name: string, fonts: ^SkinFonts) -> bool,     // optional (nil: the store keeps no fonts): the font files the style names, see skin.odin
    save_fonts: proc(store: ^StyleStore, name: string, fonts: ^SkinFonts) -> bool,     // keeps the colors the style has; `save` keeps the fonts
}

// The name `index` of a list as a string (it lives in the list)
StyleNameAt :: proc(names: ^StyleNames, index: int) -> string {
    return string(names.names[index][:names.lengths[index]])
}

StyleNamesAdd :: proc(names: ^StyleNames, name: string) -> bool {
    if names.count >= STYLE_NAMES || len(name) == 0 || len(name) > STYLE_NAME_LENGTH { return false }
    names.lengths[names.count] = u8(copy(names.names[names.count][:], name))
    names.count += 1
    return true
}

// Whether a name can be a style name: 1 to STYLE_NAME_LENGTH letters, digits, space, dash or underscore, not starting or ending with a space (so a name cannot reach another folder or hide)
StyleNameValid :: proc(name: string) -> bool {
    if len(name) == 0 || len(name) > STYLE_NAME_LENGTH || name[0] == ' ' || name[len(name) - 1] == ' ' { return false }
    for character in transmute([]u8)name {
        switch character {
        case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', ' ', '-', '_':
        case:
            return false
        }
    }
    return true
}

// A store in memory: the styles of a program that has no files (a web build) or keeps them in its own settings. `MemoryStyles` is plain data: copy it to save it with the settings.
MEMORY_STYLES :: 16

MemoryStyles :: struct {
    names: [MEMORY_STYLES][STYLE_NAME_LENGTH]u8,
    lengths: [MEMORY_STYLES]int,
    themes: [MEMORY_STYLES]Theme,
    fonts: [MEMORY_STYLES]SkinFonts,
    count: int,
}

MemoryStyleStoreMake :: proc(memory: ^MemoryStyles) -> StyleStore {
    return {user = memory, list = memoryList, load = memoryLoad, save = memorySave, delete = memoryDelete, load_fonts = memoryLoadFonts, save_fonts = memorySaveFonts}
}

@(private)
memoryFind :: proc(memory: ^MemoryStyles, name: string) -> int {
    for i in 0 ..< memory.count {
        if string(memory.names[i][:memory.lengths[i]]) == name { return i }
    }
    return -1
}

@(private)
memoryList :: proc(store: ^StyleStore, names: ^StyleNames) {
    memory: ^MemoryStyles = cast(^MemoryStyles)store.user
    names.count = 0
    for i in 0 ..< memory.count { StyleNamesAdd(names, string(memory.names[i][:memory.lengths[i]])) }
}

@(private)
memoryLoad :: proc(store: ^StyleStore, name: string, theme: ^Theme) -> bool {
    memory: ^MemoryStyles = cast(^MemoryStyles)store.user
    at: int = memoryFind(memory, name)
    if at < 0 { return false }
    theme^ = memory.themes[at]
    return true
}

@(private)
memorySave :: proc(store: ^StyleStore, name: string, theme: ^Theme) -> bool {
    memory: ^MemoryStyles = cast(^MemoryStyles)store.user
    if !StyleNameValid(name) { return false }
    at: int = memoryFind(memory, name)
    if at < 0 {
        if memory.count >= MEMORY_STYLES { return false }
        at = memory.count
        memory.count += 1
        memory.fonts[at] = {}
    }
    memory.lengths[at] = copy(memory.names[at][:], name)
    memory.themes[at] = theme^
    return true
}

@(private)
memoryLoadFonts :: proc(store: ^StyleStore, name: string, fonts: ^SkinFonts) -> bool {
    memory: ^MemoryStyles = cast(^MemoryStyles)store.user
    at: int = memoryFind(memory, name)
    if at < 0 { return false }
    fonts^ = memory.fonts[at]
    return true
}

@(private)
memorySaveFonts :: proc(store: ^StyleStore, name: string, fonts: ^SkinFonts) -> bool {
    memory: ^MemoryStyles = cast(^MemoryStyles)store.user
    at: int = memoryFind(memory, name)
    if at < 0 { return false }
    memory.fonts[at] = fonts^
    return true
}

@(private)
memoryDelete :: proc(store: ^StyleStore, name: string) -> bool {
    memory: ^MemoryStyles = cast(^MemoryStyles)store.user
    at: int = memoryFind(memory, name)
    if at < 0 { return false }
    for k in at ..< memory.count - 1 {
        memory.names[k], memory.lengths[k], memory.themes[k], memory.fonts[k] = memory.names[k + 1], memory.lengths[k + 1], memory.themes[k + 1], memory.fonts[k + 1]
    }
    memory.count -= 1
    return true
}
