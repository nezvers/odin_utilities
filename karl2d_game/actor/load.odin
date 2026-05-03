package actor

import karl2d "../../karl2d"
import "../assets"

texture_plumber: karl2d.Texture
texture_electrician: karl2d.Texture

Load :: proc() {
    texture_plumber = karl2d.load_texture_from_bytes(assets.texture_char_plumber, {.Premultiply_Alpha})
    prefab_plumber.texture = texture_plumber
    texture_electrician = karl2d.load_texture_from_bytes(assets.texture_char_electrician, {.Premultiply_Alpha})
    prefab_electrician.texture = texture_electrician
}

Destroy :: proc() {
    karl2d.destroy_texture(texture_plumber)
    prefab_plumber.texture = {}
    karl2d.destroy_texture(texture_electrician)
    prefab_electrician.texture = {}
}