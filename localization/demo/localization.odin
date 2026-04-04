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
font: rl.Font
language_id: u32 = 1

init :: proc() {
    local_data = local.MakeLocalizationData(csv_localization[:])
    ok:bool
    language_id, ok = local.GetLanguageId(&local_data, "en")
    // TODO: load all symbols
    font = rl.LoadFontEx("../assets/fonts/pixellocale-v-1-4.ttf", 32, nil, 0)
}

finit :: proc() {
    local.DeleteLocalizationData(&local_data)
    rl.UnloadFont(font)
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
                ok:bool
                language_id, ok = local.GetLanguageId(&local_data, lang_str)
            }
            button_rect.y += ROW_HEIGHT
        }
    }

    FONT_SIZE :: 32
    key_y: f32 = 10
    for k, v in local_data.key_map {
        sb: = strings.builder_from_bytes(buffer[:])
        strings.write_string(&sb, k)
        cstr: = strings.unsafe_to_cstring(&sb)
        text:cstring = rl.TextFormat("%s", cstr)
        rl.DrawTextEx(font, text, {120, key_y}, FONT_SIZE, 0, rl.BLACK)
        
        translation, ok: = local.GetTranslationId(&local_data, v, language_id)
        if ok {
            sb = strings.builder_from_bytes(buffer[:])
            strings.write_string(&sb, translation)
            cstr = strings.unsafe_to_cstring(&sb)
            text = rl.TextFormat("%s", cstr)
            rl.DrawTextEx(font, text, {350, key_y}, FONT_SIZE, 0, rl.BLACK)
        }
        
        key_y += 20
    }
}

