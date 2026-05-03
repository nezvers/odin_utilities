package actor

import karl2d "../../karl2d"
import "../assets"

texture_plumber: karl2d.Texture
texture_electrician: karl2d.Texture
texture_zombie: karl2d.Texture

Load :: proc() {
    texture_plumber = karl2d.load_texture_from_bytes(assets.texture_char_plumber, {.Premultiply_Alpha})
    prefab_plumber.texture = texture_plumber
    texture_electrician = karl2d.load_texture_from_bytes(assets.texture_char_electrician, {.Premultiply_Alpha})
    prefab_electrician.texture = texture_electrician
    texture_zombie = karl2d.load_texture_from_bytes(assets.texture_char_zomby_walker, {.Premultiply_Alpha})
    prefab_zombie.texture = texture_zombie
}

Destroy :: proc() {
    prefab_plumber.texture = {}
    karl2d.destroy_texture(texture_plumber)
    prefab_electrician.texture = {}
    karl2d.destroy_texture(texture_electrician)
    prefab_zombie.texture = {}
    karl2d.destroy_texture(texture_zombie)
}