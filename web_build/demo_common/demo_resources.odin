#+private file
package demo_common

// Loads resources by name through web_build.ResourceLoad and shows them: textures, a font and a text file. A resource is read from the resource folder
// when the file is there (bytes that belong to the caller) and comes from the bytes compiled into the program otherwise, the only way a browser has.

import "core:fmt"
import "core:strings"
import web_build ".."
import kit "../../demo_kit"

@(private="package")
demo_resources: kit.Demo = {
    name = "resources",
    init = init,
    finit = finit,
    draw = draw,
    script = script,
}

// The resource folder relative to the working directory. Change it with -define:RESOURCE_PATH=...
DEMO_RESOURCE_PATH :: #config(RESOURCE_PATH, "../assets")

TEXTURE_NAMES :: [4]string{
    "textures/dust_4_strip.png",
    "textures/player_sheet.png",
    "textures/palette_journey.png",
    "textures/tileset_template.png",
}

// Compiled into the program: what is used when the folder has no such file
EMBEDDED :: "../../assets/"
embedded_resources: [6]web_build.Resource = {
    {"textures/dust_4_strip.png", #load(EMBEDDED + "textures/dust_4_strip.png")},
    {"textures/player_sheet.png", #load(EMBEDDED + "textures/player_sheet.png")},
    {"textures/palette_journey.png", #load(EMBEDDED + "textures/palette_journey.png")},
    {"textures/tileset_template.png", #load(EMBEDDED + "textures/tileset_template.png")},
    {"fonts/pixellocale-v-1-4.ttf", #load(EMBEDDED + "fonts/pixellocale-v-1-4.ttf")},
    {"data/localization.csv", #load(EMBEDDED + "data/localization.csv")},
}

textures: [4]kit.Texture
from_disk: [4]bool          // the bytes came from the folder (owned), not from the program
font: kit.Font
font_loaded: bool
lines: [dynamic]string
text_source: string

init :: proc(ctx: ^kit.Context) {
    resources: web_build.ResourceSet = {directory = DEMO_RESOURCE_PATH, embedded = embedded_resources[:]}
    names: [4]string = TEXTURE_NAMES
    for name, i in names {
        data, ok := web_build.ResourceLoad(resources, name)
        if !ok { continue }
        from_disk[i] = data.owned
        textures[i] = kit.TextureLoad(ctx, data.data)      // the backend keeps its own copy of the pixels
        web_build.ResourceFree(data)
    }

    font_data, font_found := web_build.ResourceLoad(resources, "fonts/pixellocale-v-1-4.ttf")
    if font_found {
        font = kit.FontLoad(ctx, font_data.data, 24, 1280)
        font_loaded = font != kit.FONT_DEFAULT
        web_build.ResourceFree(font_data)
    }

    csv, csv_found := web_build.ResourceLoad(resources, "data/localization.csv")
    if csv_found {
        text_source = strings.clone(string(csv.data))
        web_build.ResourceFree(csv)
        remaining: string = text_source
        for line in strings.split_lines_iterator(&remaining) {
            append(&lines, line)
        }
    }
}

finit :: proc(ctx: ^kit.Context) {
    for texture in textures { kit.TextureUnload(ctx, texture) }
    textures = {}
    kit.FontUnload(ctx, font)
    font = kit.FONT_DEFAULT
    delete(lines)
    lines = nil
    delete(text_source)
    text_source = ""
}

draw :: proc(ctx: ^kit.Context) {
    ctx.background = {32, 36, 48, 255}
    kit.DrawTextFont(ctx, font, fmt.tprintf("files from %s, else the bytes of the program", DEMO_RESOURCE_PATH), {20, 16}, 28, kit.WHITE)
    names: [4]string = TEXTURE_NAMES
    x: f32 = 20
    for name, i in names {
        if textures[i] == kit.TEXTURE_NONE {
            kit.DrawText(ctx, fmt.tprintf("missing %s", name), {x, 80}, 18, kit.RED)
            continue
        }
        size: kit.Vec2 = kit.TextureSize(ctx, textures[i])
        scale: f32 = min(280 / size.x, 280 / size.y, 16)
        target: kit.Rect = {x, 80, size.x * scale, size.y * scale}
        kit.DrawRect(ctx, {target.x - 2, target.y - 2, target.z + 4, target.w + 4}, {70, 76, 96, 255})
        kit.DrawTextureRect(ctx, textures[i], {0, 0, size.x, size.y}, target)
        kit.DrawText(ctx, fmt.tprintf("%s (%s)", name, "disk" if from_disk[i] else "program"), {x, target.y + target.w + 8}, 16, kit.LIGHT_GRAY)
        x += 300
    }
    kit.DrawTextFont(ctx, font, "data/localization.csv", {20, 420}, 22, kit.WHITE)
    for line, i in lines {
        if i >= 8 { break }
        kit.DrawTextFont(ctx, font, line, {20, 460 + f32(i) * 24}, 20, kit.LIGHT_GRAY)
    }
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        for texture in textures { if texture == kit.TEXTURE_NONE { return false } }
        return true
    }, "every texture was found: in the folder, or in the bytes of the program"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return font_loaded }, "the font was loaded from its resource"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return len(lines) > 3 && strings.has_prefix(lines[0], "id,en") }, "the csv text resource was read line by line"),
}
