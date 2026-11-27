#+private file
package demo_common

// The translations of a CSV file (key, one column per language). The buttons choose the language, every key is shown with its text.
// The font has the glyphs of the languages (cyrillic, turkish, latvian accents): the default font of a framework has latin letters only.

import "core:slice"
import local ".."
import kit "../../demo_kit"

@(private="package")
demo_localization: kit.Demo = {
    name = "localization",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

csv_localization: []byte = #load("../../assets/data/localization.csv")
font_bytes: []byte = #load("../../assets/fonts/pixellocale-v-1-4.ttf")

local_data: local.LocalizationData
font: kit.Font
language_id: u32 = 1
sorted_keys: [dynamic]string        // the keys in the order of the file rows, so the list does not jump around

ROW_HEIGHT :: 25
LANGUAGE_BUTTON :: kit.Rect{10, 10, 100, 20}

init :: proc(ctx: ^kit.Context) {
    local_data = local.MakeLocalizationData(csv_localization[:])
    ok: bool
    language_id, ok = local.GetLanguageId(&local_data, "en")
    font = kit.FontLoad(ctx, font_bytes, 32, 1280)

    // a map has no order: sort the keys by the row they came from
    for key in local_data.key_map { append(&sorted_keys, key) }
    slice.sort_by(sorted_keys[:], proc(a, b: string) -> bool { return local_data.key_map[a] < local_data.key_map[b] })
}

finit :: proc(ctx: ^kit.Context) {
    local.DeleteLocalizationData(&local_data)
    delete(sorted_keys)
    sorted_keys = nil
    kit.FontUnload(ctx, font)
}

update :: proc(ctx: ^kit.Context) {}

draw :: proc(ctx: ^kit.Context) {
    // Language buttons
    languages, language_ok := local.GetLanguages(&local_data)
    if language_ok {
        button: kit.Rect = LANGUAGE_BUTTON
        for language in languages {
            if kit.Button(ctx, button, language) {
                language_id, _ = local.GetLanguageId(&local_data, language)
            }
            button.y += ROW_HEIGHT
        }
    }

    FONT_SIZE :: 32
    key_y: f32 = 10
    for key in sorted_keys {
        // Translation key
        kit.DrawTextFont(ctx, font, key, {120, key_y}, FONT_SIZE, kit.BLACK)
        // Translation
        translation, ok := local.GetTranslationById(&local_data, local_data.key_map[key], language_id)
        if ok {
            kit.DrawTextFont(ctx, font, translation, {350, key_y}, FONT_SIZE, kit.BLACK)
        }
        key_y += 30
    }
}

text_of :: proc(key: string) -> string {
    translation, _ := local.GetTranslation(&local_data, key, current_language())
    return translation
}

current_language :: proc() -> string {
    languages, _ := local.GetLanguages(&local_data)
    for language in languages {
        id, _ := local.GetLanguageId(&local_data, language)
        if id == language_id { return language }
    }
    return ""
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return current_language() == "en" && text_of("Right") == "Right" }, "starts in english"),
    // the second button is german: the buttons are in the column on the left, one per language
    kit.Click({60, 10 + ROW_HEIGHT * 1 + 10}),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return current_language() == "de" && text_of("Right") == "Rechts" }, "a button changes the language, the text follows"),
    kit.Click({60, 10 + ROW_HEIGHT * 4 + 10}),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return current_language() == "ru" && text_of("Right") == "Вправо" }, "other alphabets are text as well (the font has their glyphs)"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        languages, ok := local.GetLanguages(&local_data)
        return ok && len(languages) == 10 && len(sorted_keys) > 3
    }, "ten languages, every key listed"),
    kit.Wait(2),
    kit.Capture("localization_localization_end"),
    kit.Wait(1),
}
