#+private file
package game

import "core:fmt"
import "../../../karl2d"

import local "../.."
LocalizationData :: local.LocalizationData

@(private="package")
localization_state: GameState = {
    init,
    finit,
    process,
    draw,
}

csv_localization: []byte = #load("../../../assets/data/localization.csv")
local_data: LocalizationData
language_id: u32 = 1
font: karl2d.Font

init :: proc() {
    background_color = karl2d.WHITE

    local_data = local.MakeLocalizationData(csv_localization[:])
    ok:bool
    language_id, ok = local.GetLanguageId(&local_data, "en")

    // Dynamic font builds its atlas from the characters that are drawn, so any language in the font works.
    // Use font that supports required languages
    font = karl2d.load_dynamic_font_from_bytes(#load("../../../assets/fonts/pixellocale-v-1-4.ttf"))
}

finit :: proc() {
    local.DeleteLocalizationData(&local_data)
    karl2d.destroy_font(font)
}

process :: proc() {}

draw :: proc() {
    ROW_HEIGHT :: 25
    BUTTON_SIZE :Vec2: {100, 20}
    FONT_SIZE :: 20

    // Language buttons
    language_strings, lang_ok: = local.GetLanguages(&local_data)
    if lang_ok {
        mouse_position: = get_local_mouse_position()
        button_rect: Rect = {10, 10, BUTTON_SIZE.x, BUTTON_SIZE.y}

        for lang_str in language_strings {
            is_current: bool = local_data.lang_map[lang_str] == language_id
            karl2d.draw_rect(button_rect, karl2d.LIGHT_BLUE if is_current else karl2d.LIGHT_GRAY)
            karl2d.draw_text(lang_str, {button_rect.x + 5, button_rect.y + 1}, 18, karl2d.BLACK)
            if check_hover(mouse_position, button_rect) && karl2d.mouse_button_went_down(.Left) {
                ok:bool
                language_id, ok = local.GetLanguageId(&local_data, lang_str)
            }
            button_rect.y += ROW_HEIGHT
        }
    }

    key_y: f32 = 10
    for key, text_id in local_data.key_map {
        // Translation key
        karl2d.draw_text(fmt.tprintf("%s:", key), {120, key_y}, FONT_SIZE, karl2d.BLACK, font)

        // Translation
        translation, ok: = local.GetTranslationById(&local_data, text_id, language_id)
        if ok {
            karl2d.draw_text(translation, {350, key_y}, FONT_SIZE, karl2d.BLACK, font)
        }

        key_y += 20
    }
}
