package projectile

import karl2d "../../karl2d"
import "../assets"


texture_bullet1: karl2d.Texture


Load :: proc() {
    texture_bullet1 = karl2d.load_texture_from_bytes(assets.texture_projectile_bullet1, {.Premultiply_Alpha})
    prefab_bullet1.texture = texture_bullet1
}

Destroy :: proc() {
    prefab_bullet1.texture = {}
    karl2d.destroy_texture(texture_bullet1)
}