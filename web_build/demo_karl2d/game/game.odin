// Loads resources by name through web_build.ResourceLoad and shows them: textures, a font and a text file.
// The same code runs on desktop (files from the resource folder) and in the browser (embedded bytes).
package game

import "core:strings"
import "../../../karl2d"
import web_build "../.."

WINDOW_SIZE :: [2]int{1280, 720}

// The resource folder relative to the executable. Change it with -define:RESOURCE_PATH=...
DEMO_RESOURCE_PATH :: #config(RESOURCE_PATH, "../assets")

TEXTURE_NAMES :: [4]string{
    "textures/dust_4_strip.png",
    "textures/player_sheet.png",
    "textures/palette_journey.png",
    "textures/tileset_template.png",
}

resources: web_build.ResourceSet
textures: [4]karl2d.Texture
texture_ok: [4]bool
font: karl2d.Font
font_ok: bool
font_data: web_build.ResourceData // a dynamic font keeps using the bytes, so they live until shutdown
text_lines: [dynamic]string
text_source: string // the loaded file, the lines point into it

init :: proc() {
    karl2d.init(WINDOW_SIZE.x, WINDOW_SIZE.y, "web_build resources", options = {window_mode = .Windowed_Resizable})

    resources = {directory = DEMO_RESOURCE_PATH, embedded = embedded_resources[:]}

    names: [4]string = TEXTURE_NAMES
    for name, i in names {
        data, ok := web_build.ResourceLoad(resources, name)
        if !ok { continue }
        // the texture has its own copy of the pixels, the file bytes are not needed afterwards
        textures[i], texture_ok[i] = karl2d.load_texture_from_bytes(data.data)
        web_build.ResourceFree(data)
    }

    font_found: bool
    font_data, font_found = web_build.ResourceLoad(resources, "fonts/pixellocale-v-1-4.ttf")
    if font_found {
        font, font_ok = karl2d.load_dynamic_font_from_bytes(font_data.data)
    }

    csv, csv_found := web_build.ResourceLoad(resources, "data/localization.csv")
    if csv_found {
        // keep a copy, the loaded bytes may be freed
        text_source = strings.clone(string(csv.data))
        web_build.ResourceFree(csv)
        remaining: string = text_source
        for line in strings.split_lines_iterator(&remaining) {
            append(&text_lines, line)
        }
    }
}

step :: proc() -> bool {
    if !karl2d.update() {
        return false
    }

    karl2d.clear(karl2d.Color{32, 36, 48, 255})
    title: string = "embedded bytes (web)" if web_build.RESOURCE_EMBED else strings.concatenate({"files from ", DEMO_RESOURCE_PATH}, context.temp_allocator)
    karl2d.draw_text(title, {20, 16}, 28, karl2d.WHITE, font if font_ok else karl2d.FONT_DEFAULT)

    // Each texture in a row, as big as it fits
    names: [4]string = TEXTURE_NAMES
    x: f32 = 20
    for name, i in names {
        if !texture_ok[i] {
            karl2d.draw_text(strings.concatenate({"missing ", name}, context.temp_allocator), {x, 80}, 18, karl2d.RED)
            continue
        }
        width: f32 = f32(karl2d.get_texture_width(textures[i]))
        height: f32 = f32(karl2d.get_texture_height(textures[i]))
        scale: f32 = min(280 / width, 280 / height, 16) // pixel art: scaled up
        target: karl2d.Rect = {x, 80, width * scale, height * scale}
        karl2d.draw_rect({target.x - 2, target.y - 2, target.w + 4, target.h + 4}, karl2d.Color{70, 76, 96, 255})
        karl2d.draw_texture_fit(textures[i], {0, 0, width, height}, target)
        karl2d.draw_text(name, {x, target.y + target.h + 8}, 16, karl2d.LIGHT_GRAY)
        x += 300
    }

    // The text file
    karl2d.draw_text("data/localization.csv", {20, 420}, 22, karl2d.WHITE, font if font_ok else karl2d.FONT_DEFAULT)
    for line, i in text_lines {
        if i >= 8 { break }
        karl2d.draw_text(line, {20, 460 + f32(i) * 24}, 20, karl2d.LIGHT_GRAY, font if font_ok else karl2d.FONT_DEFAULT)
    }

    karl2d.present()
    free_all(context.temp_allocator)
    return true
}

shutdown :: proc() {
    for texture, i in textures {
        if texture_ok[i] { karl2d.destroy_texture(texture) }
    }
    if font_ok { karl2d.destroy_font(font) }
    web_build.ResourceFree(font_data)
    delete(text_lines)
    delete(text_source)
    karl2d.shutdown()
}
