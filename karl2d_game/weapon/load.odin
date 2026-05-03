package weapon

import karl2d "../../karl2d"
import "../assets"

texture_shotgun: karl2d.Texture

Load :: proc() {
    texture_shotgun = karl2d.load_texture_from_bytes(assets.texture_weapon_shotgun, {.Premultiply_Alpha})
    prefab_shotgun.texture = texture_shotgun
    assert(prefab_shotgun.sound != nil)
}

Destroy :: proc() {
    prefab_shotgun.texture = {}
    karl2d.destroy_texture(texture_shotgun)
}