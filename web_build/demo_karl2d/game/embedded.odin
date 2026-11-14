package game

import web_build "../.."

// Resources that are compiled into the program. A web build needs them, there is no disk to read from.
// Desktop builds read the same names from the resource folder instead, so they don't carry the bytes:
// -define:RESOURCE_EMBED=true embeds them on desktop too.
// #load paths are relative to this file, the names are relative to the resource folder.
when web_build.RESOURCE_EMBED {
    EMBEDDED :: "../../../assets/"
    embedded_resources: [6]web_build.Resource = {
        {"textures/dust_4_strip.png", #load(EMBEDDED + "textures/dust_4_strip.png")},
        {"textures/player_sheet.png", #load(EMBEDDED + "textures/player_sheet.png")},
        {"textures/palette_journey.png", #load(EMBEDDED + "textures/palette_journey.png")},
        {"textures/tileset_template.png", #load(EMBEDDED + "textures/tileset_template.png")},
        {"fonts/pixellocale-v-1-4.ttf", #load(EMBEDDED + "fonts/pixellocale-v-1-4.ttf")},
        {"data/localization.csv", #load(EMBEDDED + "data/localization.csv")},
    }
} else {
    embedded_resources: [0]web_build.Resource
}
