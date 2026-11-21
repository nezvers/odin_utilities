package main

// Writes the styles that come with the library into odin_utilities/ui/styles: `odin run ui/tool/styles`. `dark.style` and `light.style` are the two default themes as text (the files the demos and
// the style editor load), nothing else in the folder is touched. Run it again after a field is added to Theme, then commit the files.

import "core:fmt"
import "core:os"
import ui_default "../../default_style"

FOLDER :: #directory + "../../styles"

main :: proc() {
    file_store: ui_default.FileStore
    store: ui_default.StyleStore = ui_default.FileStyleStoreMake(&file_store, FOLDER)
    dark, light: ui_default.Theme = ui_default.THEME_DARK, ui_default.THEME_LIGHT
    ok: bool = store.save(&store, "dark", &dark) && store.save(&store, "light", &light)
    if !ok {
        fmt.eprintln("could not write the styles to", FOLDER)
        os.exit(1)
    }
    fmt.println("wrote dark.style and light.style to", FOLDER)
}
