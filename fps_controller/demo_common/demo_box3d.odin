#+private file
package demo_common

// The same player as demo_controller.odin, but the collision is done by Box3D (vendor:box3d): the player is a capsule mover (see
// box3d/mover_box3d.odin), static ground and towers, a wall of crates and shot spheres are simulated by the Box3D world.
// Ported from the Box2D GeometricMover sample.

import "core:fmt"
import "core:math/linalg"
import b3 "vendor:box3d"
import kit "../../demo_kit"
import fps ".."
import mover "../box3d"

@(private="package")
demo_box3d: kit.Demo = {
    name = "box3d",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

PHYSICS_GRAVITY :: 25
SUB_STEPS :: 4

CRATE_COLUMNS :: 5
CRATE_ROWS :: 5
CRATE_COUNT :: CRATE_COLUMNS * CRATE_ROWS
SPHERE_COUNT :: 32
SPHERE_RADIUS :: 0.3
SHOT_SPEED :: 40
CRATE_HALF :: f32(0.5)
GROUND_HALF :: fps.Vec3{125, 0.5, 125}
START_POSITION :: fps.Vec3{0, 0.1, 0}

player: fps.Player
view: fps.View
scene: Scene
sound_jump: kit.Sound
sound_land: kit.Sound
sound_gun: kit.Sound

world: b3.WorldId

// Hulls have to stay alive as long as the shapes that use them
ground_hull: b3.BoxHull
tower_hull: b3.BoxHull
crate_hull: b3.BoxHull

crates: [CRATE_COUNT]b3.BodyId
spheres: [SPHERE_COUNT]b3.BodyId
next_sphere: int

planes: mover.PlaneBuffer
total_iterations: int
shots: int

init :: proc(ctx: ^kit.Context) {
    kit.MouseCapture(ctx, true)
    sound_jump = kit.SoundLoad(ctx, #load("../../assets/sounds/snd_huh_jump.wav"))
    sound_land = kit.SoundLoad(ctx, #load("../../assets/sounds/snd_landing.wav"))
    sound_gun = kit.SoundLoad(ctx, #load("../../assets/sounds/snd_gun_1.wav"))
    reset_player()
    view = {up = {0, 1, 0}, target = {0, 0, -1}, fov_y = fps.FOV_STANDING}
    scene.floor = true
    shots = 0
    create_world()
}

finit :: proc(ctx: ^kit.Context) {
    destroy_world()
    kit.MouseCapture(ctx, false)
    kit.SoundUnload(ctx, sound_jump)
    kit.SoundUnload(ctx, sound_land)
    kit.SoundUnload(ctx, sound_gun)
}

reset_player :: proc() {
    fps.PlayerInit(&player, START_POSITION)
}

create_world :: proc() {
    world_def: b3.WorldDef = b3.DefaultWorldDef()
    world_def.gravity = {0, -PHYSICS_GRAVITY, 0}
    world = b3.CreateWorld(world_def)

    shape_def: b3.ShapeDef = b3.DefaultShapeDef()

    // Ground, top surface at y = 0
    ground_hull = b3.MakeBoxHull(GROUND_HALF.x, GROUND_HALF.y, GROUND_HALF.z)
    body_def: b3.BodyDef = b3.DefaultBodyDef()
    body_def.position = {0, -GROUND_HALF.y, 0}
    ground: b3.BodyId = b3.CreateBody(world, body_def)
    _ = b3.CreateHullShape(ground, shape_def, &ground_hull.base)

    // Towers
    tower_hull = b3.MakeBoxHull(TOWER_HALF.x, TOWER_HALF.y, TOWER_HALF.z)
    for position in TOWER_POSITIONS {
        body_def = b3.DefaultBodyDef()
        body_def.position = position
        tower: b3.BodyId = b3.CreateBody(world, body_def)
        _ = b3.CreateHullShape(tower, shape_def, &tower_hull.base)
    }

    // A wall of crates to knock down
    crate_hull = b3.MakeCubeHull(CRATE_HALF)
    shape_def.density = 1
    for row in 0 ..< CRATE_ROWS {
        for column in 0 ..< CRATE_COLUMNS {
            body_def = b3.DefaultBodyDef()
            body_def.type = .dynamicBody
            body_def.position = {(f32(column) - 0.5 * (CRATE_COLUMNS - 1)) * 1.05, CRATE_HALF + f32(row) * 1.02, -12}
            crate: b3.BodyId = b3.CreateBody(world, body_def)
            _ = b3.CreateHullShape(crate, shape_def, &crate_hull.base)
            crates[row * CRATE_COLUMNS + column] = crate
        }
    }

    spheres = {}
    next_sphere = 0
}

destroy_world :: proc() {
    if b3.World_IsValid(world) { b3.DestroyWorld(world) }
    world = {}
}

shoot :: proc(origin: fps.Vec3, direction: fps.Vec3) {
    if b3.Body_IsValid(spheres[next_sphere]) { b3.DestroyBody(spheres[next_sphere]) }

    body_def: b3.BodyDef = b3.DefaultBodyDef()
    body_def.type = .dynamicBody
    body_def.position = origin + direction
    body_def.linearVelocity = direction * SHOT_SPEED
    body: b3.BodyId = b3.CreateBody(world, body_def)

    shape_def: b3.ShapeDef = b3.DefaultShapeDef()
    shape_def.density = 4
    sphere: b3.Sphere = {radius = SPHERE_RADIUS}
    _ = b3.CreateSphereShape(body, shape_def, &sphere)

    spheres[next_sphere] = body
    next_sphere = (next_sphere + 1) % SPHERE_COUNT
}

update :: proc(ctx: ^kit.Context) {
    PlayerReadInput(ctx, &player)

    if kit.KeyPressed(&ctx.input, .R) {
        destroy_world()
        create_world()
        reset_player()
    }

    if player.input.shoot {
        kit.SoundPlay(ctx, sound_gun)
        forward: fps.Vec3 = linalg.normalize(view.target - view.position)
        shoot(view.position, forward)
        shots += 1
    }

    if fps.PlayerUpdateVelocity(&player, ctx.delta_time) { kit.SoundPlay(ctx, sound_jump) }
    result := mover.MoverUpdate(world, &player, &planes, ctx.delta_time)
    total_iterations = result.iterations
    if result.landed { kit.SoundPlay(ctx, sound_land) }
    b3.World_Step(world, ctx.delta_time, SUB_STEPS)

    UpdateView(&player, &view, ctx.delta_time)
}

draw :: proc(ctx: ^kit.Context) {
    SceneClear(&scene)
    SceneAddTowers(&scene)
    for crate in crates {
        if !b3.Body_IsValid(crate) { continue }
        SceneAddBox(&scene, b3.Body_GetPosition(crate), {CRATE_HALF, CRATE_HALF, CRATE_HALF}, {211, 176, 131, 255}, {127, 106, 79, 255}, b3.Body_GetRotation(crate))
    }
    for sphere in spheres {
        if !b3.Body_IsValid(sphere) { continue }
        SceneAddSphere(&scene, b3.Body_GetPosition(sphere), SPHERE_RADIUS, {230, 41, 55, 255})
    }
    if scene_drawer != nil { scene_drawer(ctx, &view, &scene) }

    kit.DrawText(ctx, "Box3D capsule mover: WASD, SPACE jump, CTRL crouch, LMB shoot, R reset", {10, 10}, 18, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("planes %d, solver iterations %d, %s", planes.count, total_iterations, "grounded" if player.is_grounded else "air"), {10, 34}, 18, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player.is_grounded && abs(player.position.y) < 0.05 }, "the capsule stands on the ground"),
    kit.Hold(.W, 30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player.position.z < -2 }, "and walks forward"),
    kit.Wait(30),
    kit.Tap(.SPACE),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !player.is_grounded && player.position.y > 0.2 }, "jumps"),
    kit.Wait(90),
    kit.Click({640, 360}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shots == 1 && scene.sphere_count == 1 }, "a shot adds a physics sphere"),
    kit.Hold(.W, 150),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player.position.z < -9 }, "the player walks up to the wall of crates and pushes it"),
    kit.Tap(.R),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return scene.sphere_count == 0 && player.position.z > -0.5 }, "R resets the world and the player"),
    kit.Wait(2),
    kit.Capture("fps_controller_box3d_end"),
    kit.Wait(1),
}
