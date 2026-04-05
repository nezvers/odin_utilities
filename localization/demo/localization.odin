#+private file
package demo

import "core:strings"

import rl "vendor:raylib"
Rectangle :: rl.Rectangle

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
    // Generate UTF-8 codepoints
    codepoints: [1280]rune
    for i:int = 0; i < len(codepoints); i += 1 { codepoints[i] = cast(rune)i }
    // Use font that supports required languages
    font = rl.LoadFontEx("../assets/fonts/pixellocale-v-1-4.ttf", 32, &codepoints[0], cast(i32)len(codepoints))
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
    for key, text_id in local_data.key_map {
        // Translation key
        sb: = strings.builder_from_bytes(buffer[:])
        strings.write_string(&sb, key)
        cstr: = strings.unsafe_to_cstring(&sb)
        text:cstring = rl.TextFormat("%s:", cstr)
        rl.DrawTextEx(font, text, {120, key_y}, FONT_SIZE, 0, rl.BLACK)
        
        // Translation
        translation, ok: = local.GetTranslationById(&local_data, text_id, language_id)
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

