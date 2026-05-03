package projectile

import karl2d "../../karl2d"
import "../assets"


texture_bullet1: karl2d.Texture
texture_bite: karl2d.Texture


Load :: proc() {
    texture_bullet1 = karl2d.load_texture_from_bytes(assets.texture_projectile_bullet1, {.Premultiply_Alpha})
    prefab_bullet1.texture = texture_bullet1

    texture_bite = karl2d.load_texture_from_bytes(assets.texture_projectile_bite, {.Premultiply_Alpha})
    prefab_bite.texture = texture_bite
}

Destroy :: proc() {
    prefab_bullet1.texture = {}
    karl2d.destroy_texture(texture_bullet1)

    prefab_bite.texture = {}
    karl2d.destroy_texture(texture_bite)
}