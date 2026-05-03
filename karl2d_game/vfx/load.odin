package vfx

import "../assets"
import "../../karl2d"

texture_impact: karl2d.Texture

Load :: proc() {
    texture_impact = karl2d.load_texture_from_bytes(assets.texture_vfx_impact, {.Premultiply_Alpha})
    prefab_impact.texture = texture_impact
}

Destroy :: proc() {
    karl2d.destroy_texture(texture_impact)
    prefab_impact.texture = {}
}