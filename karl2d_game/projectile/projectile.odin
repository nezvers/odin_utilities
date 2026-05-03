package projectile

import spr "../../sprite"
import spr_glue "../../sprite/karl2d"
import karl2d "../../karl2d"
import "core:math/rand"
import "../../cool_math"
import "../vfx"
// import "core:math"

vec2 :: [2]f32

Properties :: struct {
    speed: f32,
    kickback: f32,
    height: f32,
    damping: f32,
    collide: u32,
    damage: f32,
    stay:bool,
    dont_rotate: bool,
}

State :: struct {
    velocity: karl2d.Vec2,
    move_dir: karl2d.Vec2,
    lifetime: f32,
}

Projectile :: struct {
    using state: State,
    using visual: spr_glue.SpriteKarl2d,
    using properties: Properties,
    vfx_impact: ^vfx.Vfx,
    id:int,
}

MAX_PROJECTILES :: 512
projectile_pool: [MAX_PROJECTILES]Projectile
projectile_count:int


Reset :: proc() {
    projectile_count = 0
}

GetNew :: proc(preset: Projectile)->(projectile: ^Projectile, ok:bool) {
    if projectile_count == MAX_PROJECTILES { return }
    projectile = &projectile_pool[projectile_count]
    projectile^ = preset
    projectile.id = projectile_count
    ok = true
    projectile_count += 1
    return
}

Remove :: proc(projectile: ^Projectile) {
    if projectile.id >= projectile_count { return }
    if projectile.id != projectile_pool[projectile.id].id { return }
    if projectile_count == 0 { return }
    if projectile.id == projectile_count - 1 {
        projectile_count -= 1
        return
    }
    new_projectile: ^Projectile = &projectile_pool[projectile_count - 1]
    new_projectile.id = projectile.id
    projectile_pool[projectile.id] = new_projectile^
    projectile_count -= 1
}

Update :: proc(delta_time: f32) {
    for i:int = projectile_count - 1; i > -1; i -= 1 {
        UpdateInstance(&projectile_pool[i], delta_time)
    }
}

UpdateInstance :: proc(projectile: ^Projectile, delta_time: f32) {
    if projectile.lifetime <= 0 {
        Remove(projectile)
        return
    }
    spr.UpdateAnimation(&projectile.animation_set, delta_time)
    projectile.lifetime -= delta_time
    projectile.position += projectile.velocity * delta_time
    projectile.velocity -= projectile.velocity * projectile.damping
    // TODO: collision check
}

Draw :: proc() {
    active_pool: = projectile_pool[:projectile_count]
    for &projectile in active_pool {
        DrawInstance(&projectile)
    }
}

DrawInstance::proc(projectile: ^Projectile){
    sprite:^spr.Sprite = &projectile.sprite
    texture:karl2d.Texture = projectile.texture
    tint:karl2d.Color = projectile.tint

    target_rect, source_rect: = spr.GetSpriteFrame(sprite)
    target_rect.y -= projectile.height

    target_rect.zw *= sprite.scale
    origin:karl2d.Vec2 = -sprite.offset * {abs(sprite.scale.x), abs(sprite.scale.y)}

    if sprite.scale.x < 0 {
        source_rect.z *= -1
    }

    if sprite.scale.y < 0 {
        origin.y = (-sprite.offset.y * sprite.scale.y) + source_rect.w
        source_rect.w *= -1
    }
    
    karl2d.draw_texture_fit(
		texture,
		transmute(karl2d.Rect)source_rect,
		transmute(karl2d.Rect)target_rect,
		origin,
		sprite.rotation,
        tint,
	)
}

SpawnProjectile :: proc(preset:Projectile, position:vec2, dir:vec2, spread:f32)->(inst: ^Projectile, ok:bool) {
    inst, ok = GetNew(preset)
    if !ok { return }
    inst.position = position
    inst.move_dir = cool_math.Vec2Rotate(dir, -spread + rand.float32() * spread * 2)
    inst.velocity = inst.move_dir * inst.speed
    if !preset.dont_rotate{
        inst.rotation = cool_math.Vec2Angle(inst.move_dir)
    }
    return
}