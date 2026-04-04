#+private file
package demo

// import "core:fmt"
import "core:strings"

import rl "vendor:raylib"
Rectangle :: rl.Rectangle

// import "core:os"
import local ".."
LocalizationData :: local.LocalizationData

@(private="package")
state_localization : State = {
    init,
    finit,
    update,
    draw,
}

csv_localization: []byte = #load("../../assets/data/localization.csv")
local_data: LocalizationData

init :: proc() {
    local_data = local.MakeLocalizationData(csv_localization[:])
}

finit :: proc() {
    local.DeleteLocalizationData(&local_data)
}

update :: proc() {}

draw :: proc() {
    ROW_HEIGHT :: 25
    buffer: [1000]byte

    // Language buttons
    language_strings, lang_ok: = local.GetLanguages(&local_data)
    if lang_ok {
        button_rect: Rectangle = {10, 10, 100, 20}

        for lang_str in language_strings {
            sb: = strings.builder_from_bytes(buffer[:])
            strings.write_string(&sb, lang_str)
            cstr: = strings.unsafe_to_cstring(&sb)
            text:cstring = rl.TextFormat("%s", cstr)
            if rl.GuiButton(button_rect, text) {

            }
            button_rect.y += ROW_HEIGHT
        }
    }
}

