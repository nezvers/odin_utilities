#+private file
package demo

import b2_odin ".."
import glue "../raylib"
import b2 "vendor:box2d"
import rl "vendor:raylib"

Vec2 :: b2.Vec2
Sensor :: b2_odin.Sensor(SensorKind)
Contact :: b2_odin.Contact(EntityKind)

@(private="package")
state_platformer : State = {
    init,
    finit,
    update,
    draw,
}

EntityKind :: enum {
    none            = 0,
    platform_static = 1 << 0,
    actor           = 1 << 1,
    coin            = 1 << 2,
    jumpad          = 1 << 3,
    player          = 1 << 4,
    enemy           = 1 << 5,
}

SensorKind :: enum {
    none,
    actor,
    coin,
    jumpad,
    ground,
    hurt,
}

PlatformStatic :: struct {
    pos: Vec2,
    size: Vec2,
    body: b2.BodyId,
    shape: b2.ShapeId,
    contact: Contact,
}

Actor :: struct {
    input: struct {
        x: f32,
        jump: bool,
    },
    state: struct {
        pos: Vec2,
        grounded: bool,
        is_jumping: bool,
        velocity: Vec2,
        remaining_jumps: u32,
    },
    values: struct {
        jump_force: f32,
        max_speed: f32,
        acceleration: f32,
        deacceleration: f32,
        jump_count: u32,
    },
    body: b2.BodyId,
    contact: Contact,
    shape_torso: b2.ShapeId,
    shape_feet: b2.ShapeId,
    sensor_ground: Sensor,
    sensor_hurt: Sensor,
    sensor_coin: Sensor,
}

Trigger :: struct {
    pos: Vec2,
    size: Vec2,
    active: bool,
    triggered: bool,
    body: b2.BodyId,
    sensor: Sensor,
    // TODO: add state for animations
}
Coin :: Trigger

JUMP_FORCE :: 550
SPEED_MAX :: 400
ACCELERATE :: 600
DEACCELERATE :: 800
GRAVITY :: -1000
JUMP_COUNT :: 2

world_ctx: b2_odin.WorldContext

platforms: []PlatformStatic = {
    {pos = {10, 500}, size = {1260, 32}}, // bottom floor
    {pos = {200, 500 - 128}, size = {128, 32}},
    {pos = {500, 500 - 128}, size = {128, 32}},
    {pos = {800, 500 - 128}, size = {128, 32}},
}

player: Actor
score: int = 0

coins: []Coin = {
    {pos = {264, 330}, size = {8, 8}},
    {pos = {564, 330}, size = {8, 8}},
    {pos = {864, 330}, size = {8, 8}},
}

jump_pads: []Trigger = {
    {pos = {380, 496}, size = {32, 4}},
}

init :: proc(){
    b2_odin.WorldInit(&world_ctx, 32, {0, 0}, sensor_begin_event, sensor_end_event)
    glue.WorldInitDebug(&world_ctx)
    b2.World_SetPreSolveCallback(world_ctx.world, PreSolveFcn, nil)
    create_platforms()
    create_coins()
    create_jump_pads()
    init_actor(&player, EntityKind.player, EntityKind.enemy, EntityKind.coin, "Player")

    score = 0
}

finit :: proc(){
    for i:int=0; i < len(platforms); i += 1 {
        if b2.Shape_IsValid(platforms[i].shape){b2_odin.DestroyShape(platforms[i].shape)}
        if b2.Body_IsValid(platforms[i].body){b2_odin.DestroyBody(platforms[i].body)}
    }
    for i:int=0; i < len(coins); i += 1 {
        if b2.Shape_IsValid(coins[i].sensor.shape){b2_odin.DestroyShape(coins[i].sensor.shape)}
        if b2.Body_IsValid(coins[i].body){b2_odin.DestroyBody(coins[i].body)}
    }
    for i:int=0; i < len(jump_pads); i += 1 {
        if b2.Shape_IsValid(jump_pads[i].sensor.shape){b2_odin.DestroyShape(jump_pads[i].sensor.shape)}
        if b2.Body_IsValid(jump_pads[i].body){b2_odin.DestroyBody(jump_pads[i].body)}
    }

    // Free Actors
    if b2.Shape_IsValid(player.shape_torso){b2_odin.DestroyShape(player.shape_torso)}
    if b2.Shape_IsValid(player.shape_feet){b2_odin.DestroyShape(player.shape_feet)}
    if b2.Shape_IsValid(player.sensor_ground.shape){b2_odin.DestroyShape(player.sensor_ground.shape)}
    if b2.Shape_IsValid(player.sensor_hurt.shape){b2_odin.DestroyShape(player.sensor_hurt.shape)}
    if b2.Shape_IsValid(player.sensor_coin.shape){b2_odin.DestroyShape(player.sensor_coin.shape)}
    if b2.Body_IsValid(player.body) {b2_odin.DestroyBody(player.body)}
    // Free world
    if b2.World_IsValid(world_ctx.world) {b2_odin.WorldFinit(&world_ctx)}
}

update :: proc(){
    b2_odin.WorldUpdate(&world_ctx, rl.GetFrameTime())
    
    // player input update
    player.input.jump = rl.IsKeyDown(rl.KeyboardKey.SPACE)
    right:bool = rl.IsKeyDown(rl.KeyboardKey.D)
    left:bool = rl.IsKeyDown(rl.KeyboardKey.A)
    player.input.x = f32(i32(right)) - f32(i32(left))
    update_actor(&player)

    update_coins()
}

draw :: proc(){
    b2_odin.WorldDebug(&world_ctx)

    text:cstring
    if score < len(coins) {
        text = rl.TextFormat("SCORE: %d", score)
    } else  {
        text = rl.TextFormat("COMPLTED!!!")
    }
    rl.DrawText(text, 500, 10, 20, rl.YELLOW)
}

create_platforms :: proc() {
    name:cstring = "Platform"
    fixed_rotation :: true
    not_sensor :: false
    for i:int=0; i < len(platforms); i += 1 {
        platforms[i].body = b2_odin.CreateBody(
            &world_ctx,
            platforms[i].pos,
            platforms[i].size,
            .staticBody,
            fixed_rotation,
            name,
        )
        platforms[i].shape = b2_odin.CreateShapeBox(
            platforms[i].body,
            platforms[i].size,
            u64(EntityKind.platform_static),
            u64(EntityKind.player | EntityKind.enemy),
            1,
            rawptr(&platforms[i].contact),
            not_sensor,
        )
        platforms[i].contact.entity = rawptr(&platforms[i])
        platforms[i].contact.kind = EntityKind.platform_static
    }
}

create_coins :: proc() {
    name:cstring = "Coin"
    fixed_rotation :: true
    is_sensor :: true
    enable_sensor :: true
    for i:int = 0; i < len(coins); i += 1 {
        coins[i].body = b2_odin.CreateBody(
            &world_ctx,
            coins[i].pos,
            coins[i].size,
            .staticBody,
            fixed_rotation,
            name,
        )
        coins[i].sensor.shape = b2_odin.CreateShapeBox(
            coins[i].body,
            coins[i].size,
            u64(EntityKind.coin),
            u64(EntityKind.player),
            1,
            rawptr(&coins[i].sensor),
            is_sensor,
            enable_sensor,
        )
        coins[i].sensor.entity = &coins[i]
        coins[i].sensor.kind = SensorKind.coin
        coins[i].active = true
        coins[i].triggered = false
    }
}

create_jump_pads :: proc() {
    name:cstring = "JumpPad"
    fixed_rotation :: true
    is_sensor :: true
    enable_sensor :: true
    for i:int = 0; i < len(jump_pads); i += 1 {
        jump_pads[i].body = b2_odin.CreateBody(
            &world_ctx,
            jump_pads[i].pos,
            jump_pads[i].size,
            .staticBody,
            fixed_rotation,
            name,
        )
        jump_pads[i].sensor.shape = b2_odin.CreateShapeBox(
            jump_pads[i].body,
            jump_pads[i].size,
            u64(EntityKind.jumpad),
            u64(EntityKind.player),
            1,
            rawptr(&jump_pads[i].sensor),
            is_sensor,
            enable_sensor,
        )
        jump_pads[i].sensor.entity = &jump_pads[i]
        jump_pads[i].sensor.kind = SensorKind.jumpad
        jump_pads[i].active = true
        jump_pads[i].triggered = false
    }
}

update_coins :: proc() {
    // Remove just triggered coin
    // TODO: use triggered buffer
    for i:int = 0; i < len(coins); i += 1 {
        if !coins[i].active { continue }
        if coins[i].triggered {
            coins[i].active = false
            if b2.Shape_IsValid(coins[i].sensor.shape){b2_odin.DestroyShape(coins[i].sensor.shape)}
            if b2.Body_IsValid(coins[i].body){b2_odin.DestroyBody(coins[i].body)}
        }
    }
}

init_actor :: proc(actor: ^Actor, kind: EntityKind, enemy: EntityKind, coin: EntityKind, name:cstring = "") {
    // TODO: pass in "config" values
    actor.values.jump_force = JUMP_FORCE
    actor.values.acceleration = ACCELERATE
    actor.values.deacceleration = DEACCELERATE
    actor.values.max_speed = SPEED_MAX
    actor.values.jump_count = JUMP_COUNT

    actor.state.grounded = false
    actor.contact.entity = rawptr(actor)
    actor.contact.kind = EntityKind.actor
    pos: Vec2 = {50, 100}
    size: Vec2 = {32, 32}
    half_size: = size * 0.5

    body_def := b2.DefaultBodyDef()
    body_def.position = {pos.x, -pos.y - size.y}
    body_def.type = .dynamicBody
    body_def.fixedRotation = true
    body_def.name = name
    body_def.userData = rawptr(actor)
    // body_def.gravityScale = 0
    actor.body = b2.CreateBody(world_ctx.world, body_def)

    // Torso
    // TODO: use "config" values
    torso_def := b2.DefaultShapeDef()
    torso_def.filter.categoryBits = u64(kind)
    torso_def.filter.maskBits = u64(EntityKind.platform_static)
    torso_def.material.friction = 0
    torso_def.density = 1
    torso_def.enableSensorEvents = false
    torso_def.enablePreSolveEvents = true   // Call PreSolveCallback
    torso_def.userData = rawptr(&actor.contact)

    capsule_radius := half_size.x - 3.0
    capsule_top: Vec2 = {0, half_size.y - capsule_radius - 5.0}
    capsule_bottom: Vec2 = {0, -half_size.y + capsule_radius + 3.0}
    capsule := b2.Capsule{capsule_bottom, capsule_top, capsule_radius}
    actor.shape_torso = b2.CreateCapsuleShape(actor.body, torso_def, capsule)

    // Coin Sensor
    coin_sensor_def := b2.DefaultShapeDef()
    coin_sensor_def.filter.categoryBits = u64(kind)
    coin_sensor_def.filter.maskBits = u64(coin) | u64(EntityKind.jumpad)
    // coin_sensor_def.isSensor = true
    coin_sensor_def.enableSensorEvents = true
    coin_sensor_def.userData = rawptr(&actor.sensor_coin)

    actor.sensor_coin.shape = b2.CreateCapsuleShape(actor.body, coin_sensor_def, capsule)
    actor.sensor_coin.entity = rawptr(actor)
    actor.sensor_coin.kind = .actor

    // Feet
    // feet_def := b2.DefaultShapeDef()
    // feet_def.filter.categoryBits = u64(kind)
    // feet_def.filter.maskBits = u64(EntityKind.platform_static | EntityKind.coin)
    // feet_def.material.friction = 1
    // feet_def.density = 1

    // feet_box := b2.MakeOffsetRoundedBox(
    // 	half_size.x - 6.0,
    // 	1.0,
    // 	{0, -half_size.y + 2.0},
    // 	b2.Rot_identity,
    // 	0.5,
    // )
    // actor.shape_feet = b2.CreatePolygonShape(actor.body, feet_def, feet_box)

    // Ground Sensor
    // ground_sensor_def := b2.DefaultShapeDef()
    // ground_sensor_def.filter.categoryBits = u64(kind)
    // ground_sensor_def.filter.maskBits = u64(EntityKind.platform_static)
    // ground_sensor_def.isSensor = true
    // ground_sensor_def.enableSensorEvents = true
    // ground_sensor_def.userData = rawptr(&actor.sensor_ground)

    // ground_sensor_box := b2.MakeOffsetBox(half_size.x - 1.0, 4.0, {0, -half_size.y - 1.0}, b2.Rot_identity)
    // actor.sensor_ground.shape = b2.CreatePolygonShape(actor.body, ground_sensor_def, ground_sensor_box)
    // actor.sensor_ground.entity = rawptr(actor)
    // actor.sensor_ground.kind = .ground

    // Hurt Sensor
    // hurt_sensor_def := b2.DefaultShapeDef()
    // hurt_sensor_def.filter.categoryBits = u64(kind)
    // hurt_sensor_def.filter.maskBits = u64(enemy)
    // // hurt_sensor_def.isSensor = true
    // hurt_sensor_def.enableSensorEvents = true
    // hurt_sensor_def.userData = rawptr(&actor.sensor_hurt)

    // actor.sensor_hurt.shape = b2.CreateCapsuleShape(actor.body, hurt_sensor_def, capsule)
    // actor.sensor_hurt.entity = rawptr(actor)
    // actor.sensor_hurt.kind = .hurt
}

update_actor :: proc(actor: ^Actor) {
    delta_time :f32 = rl.GetFrameTime()
    b2_pos: = b2.Body_GetPosition(actor.body)
    // TODO: use sprite size
    actor.state.pos = b2_odin.b2_to_pos(b2_pos, {})

    velocity: = b2.Body_GetLinearVelocity(actor.body)
    target_velocity: Vec2 = velocity
    // Horizontal speed
    if actor.input.x != 0 {
        target_velocity.x = clamp(
            target_velocity.x + actor.input.x * actor.values.acceleration * delta_time,
            -actor.values.max_speed,
            actor.values.max_speed,
        )
    } else {
        abs_speed: f32 = abs(target_velocity.x)
        if abs_speed > actor.values.deacceleration * delta_time {
            sign_speed: f32 = Sign(target_velocity.x)
            target_velocity.x += -sign_speed * delta_time * actor.values.deacceleration
        } else {
            target_velocity.x = 0
        }
    }

    // Gravity
    target_velocity.y += GRAVITY * rl.GetFrameTime()

    // Jumping 
    if actor.state.grounded {
        actor.state.remaining_jumps = actor.values.jump_count
        if actor.input.jump {
            if !actor.state.is_jumping {
                actor.state.grounded = false
                actor.state.is_jumping = true
                target_velocity.y = actor.values.jump_force
                actor.state.remaining_jumps -= 1
            }
        } else if actor.state.is_jumping {
            actor.state.is_jumping = false
        }
    } else {
        // Not grounded
        if actor.input.jump {
            if !actor.state.is_jumping && actor.state.remaining_jumps > 0 {
                // Double jump
                actor.state.is_jumping = true
                target_velocity.y = actor.values.jump_force
                actor.state.remaining_jumps -= 1
            }
        } else if actor.state.is_jumping {
            actor.state.is_jumping = false
            if target_velocity.y > actor.values.jump_force * 0.5 {
                // Jump release / variable jump height
                target_velocity.y = actor.values.jump_force * 0.5
            }
        }
    }
    
    actor.state.velocity = target_velocity
    b2.Body_SetLinearVelocity(actor.body, target_velocity)
    // Reset ground detection
    actor.state.grounded = false
}

sensor_begin_event :: proc(event: b2.SensorBeginTouchEvent) {
    sensor := cast(^Sensor)b2.Shape_GetUserData(event.sensorShapeId)
    visitor := cast(^Sensor)b2.Shape_GetUserData(event.visitorShapeId)
    
    #partial switch sensor.kind {
    case .none:
        break
    case .actor:
        break
    case .coin:
        coin: = cast(^Coin)sensor.entity
        if coin.triggered { return }
        if visitor.kind == .actor && cast(^Actor)visitor.entity == &player {
            coin.triggered = true
            score += 1
        }
        break
    case .jumpad:
        // pad: = cast(^Coin)sensor.entity
        if visitor.kind == .actor {
            actor: ^Actor = cast(^Actor)visitor.entity
            
            velocity: = b2.Body_GetLinearVelocity(actor.body)
            velocity.y = JUMP_FORCE * 1.3
            
            b2.Body_SetLinearVelocity(actor.body, velocity)
        }
        break
    case .ground:
        break
    }
}

sensor_end_event :: proc(event: b2.SensorEndTouchEvent) {
    sensor := cast(^Sensor)b2.Shape_GetUserData(event.sensorShapeId)
    
    #partial switch sensor.kind {
    case .none:
        break
    case .ground:
        break
    }
}

PreSolveFcn :: proc "c" (shapeIdA, shapeIdB: b2.ShapeId, manifold: ^b2.Manifold, ctx: rawptr) -> bool {
    contactA: = cast(^Contact)b2.Shape_GetUserData(shapeIdA)
    contactB: = cast(^Contact)b2.Shape_GetUserData(shapeIdB)
    
    if contactA.kind == EntityKind.actor {
        actor: ^Actor = cast(^Actor)contactA.entity
        // WORKAROUND: after jumping up, this still triggers frame after
        if !(actor.state.velocity.y > 0) && (manifold.normal.y > 0.5) {
            actor.state.grounded = true
        }
    }
    if contactB.kind == EntityKind.actor {
        actor: ^Actor = cast(^Actor)contactB.entity
        // WORKAROUND: after jumping up, this still triggers frame after
        if !(actor.state.velocity.y > 0) && (manifold.normal.y > 0.5) {
            actor.state.grounded = true
        }
    }

    return true
}