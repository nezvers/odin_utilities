#+private file
package game

// import "core:strings"
// import "core:fmt"
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
font: karl2d.Font
language_id: u32 = 1

init :: proc() {
    background_color = karl2d.WHITE

    local_data = local.MakeLocalizationData(csv_localization[:])
    ok:bool
    language_id, ok = local.GetLanguageId(&local_data, "en")
    // Generate UTF-8 codepoints
    codepoints: [1280]rune
    for i:int = 0; i < len(codepoints); i += 1 { codepoints[i] = cast(rune)i }
    // Use font that supports required languages
    // font = rl.LoadFontEx("../assets/fonts/pixellocale-v-1-4.ttf", 32, &codepoints[0], cast(i32)len(codepoints))
    font = karl2d.load_font_from_bytes(#load("../../../assets/fonts/pixellocale-v-1-4.ttf"))
    _ = font
}

finit :: proc() {
    local.DeleteLocalizationData(&local_data)
    karl2d.destroy_font(font)
}

process :: proc() {}

draw :: proc() {
	ROW_HEIGHT :: 25
    FONT_SIZE :: 20
	BUTTON_SIZE :Vec2: {150, 25}
	BUTTON_PADDING :f32: 2
    mouse_position: = get_local_mouse_position()
    // buffer: [1000]byte

    // Language buttons
    lang_ok: bool
    language_strings: []string
    language_strings, lang_ok = local.GetLanguages(&local_data)
    if lang_ok {
        button_rect: Rect = {10, 10, BUTTON_SIZE.x, BUTTON_SIZE.y}

        for i:int = 0; i < len(language_strings); i += 1 {
            // lang_str:string = language_strings[i]
            // sb:strings.Builder = strings.builder_from_bytes(buffer[:])
            // strings.write_string(&sb, lang_str)
            text: string = language_strings[i]
            
            karl2d.draw_rect(button_rect, karl2d.LIGHT_GRAY)
            karl2d.draw_text(text, {button_rect.x, button_rect.y}, FONT_SIZE, karl2d.BLACK)
            if (check_hover(mouse_position, button_rect)){
                if karl2d.mouse_button_went_down(.Left) {
                    ok:bool
                    language_id, ok = local.GetLanguageId(&local_data, text)
                }
                is_hovering_buttons = true
            }
		    button_rect.y += BUTTON_SIZE.y + BUTTON_PADDING
        }
    }
}