#+private file
package demo_common

// No actual physics, just movement: the floor is a clamp to y = 0. See demo_box3d.odin for the same player with collision.

import "core:fmt"
import kit "../../demo_kit"
import fps ".."

@(private="package")
demo_controller: kit.Demo = {
    name = "controller",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

player: fps.Player
view: fps.View
scene: Scene
sound_jump: kit.Sound
sound_land: kit.Sound
sound_gun: kit.Sound
jumps: int
landings: int
shots: int

init :: proc(ctx: ^kit.Context) {
    kit.MouseCapture(ctx, true)
    sound_jump = kit.SoundLoad(ctx, #load("../../assets/sounds/snd_huh_jump.wav"))
    sound_land = kit.SoundLoad(ctx, #load("../../assets/sounds/snd_landing.wav"))
    sound_gun = kit.SoundLoad(ctx, #load("../../assets/sounds/snd_gun_1.wav"))
    fps.PlayerInit(&player)
    view = {up = {0, 1, 0}, target = {0, 0, -1}, fov_y = fps.FOV_STANDING}
    scene.floor = true
    jumps, landings, shots = 0, 0, 0
}

finit :: proc(ctx: ^kit.Context) {
    kit.MouseCapture(ctx, false)
    kit.SoundUnload(ctx, sound_jump)
    kit.SoundUnload(ctx, sound_land)
    kit.SoundUnload(ctx, sound_gun)
}

update :: proc(ctx: ^kit.Context) {
    PlayerReadInput(ctx, &player)
    if player.input.shoot {
        kit.SoundPlay(ctx, sound_gun)
        shots += 1
    }
    if fps.PlayerUpdateVelocity(&player, ctx.delta_time) {
        kit.SoundPlay(ctx, sound_jump)
        jumps += 1
    }
    if fps.PlayerCollideFloor(&player, ctx.delta_time) {
        kit.SoundPlay(ctx, sound_land)
        landings += 1
    }
    UpdateView(&player, &view, ctx.delta_time)
}

draw :: proc(ctx: ^kit.Context) {
    SceneClear(&scene)
    SceneAddTowers(&scene)
    SceneAddSphere(&scene, {300, 300, 0}, 100, {255, 0, 0, 255})
    if scene_drawer != nil { scene_drawer(ctx, &view, &scene) }

    kit.DrawText(ctx, "WASD move, SPACE jump, CTRL crouch, LMB shoot (sound), mouse look.  Strafe jump: turn while moving sideways in the air", {10, 10}, 18, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("speed %.1f   %s", fps.PlayerHorizontalSpeed(&player), "grounded" if player.is_grounded else "air"), {10, 34}, 18, kit.DARK_GRAY)
    // the crosshair
    center: kit.Vec2 = ctx.screen * 0.5
    kit.DrawLine(ctx, center - {8, 0}, center + {8, 0}, 1, kit.BLACK)
    kit.DrawLine(ctx, center - {0, 8}, center + {0, 8}, 1, kit.BLACK)
}

script: []kit.Step = {
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player.is_grounded && landings == 1 }, "the player falls to the floor and lands once"),
    kit.Hold(.W, 90),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player.position.z < -5 && fps.PlayerHorizontalSpeed(&player) > 5 }, "W moves the player forward"),
    kit.Wait(60),
    kit.LookBy({1000, 0}),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player.look.x < -0.9 }, "moving the mouse turns the view"),
    kit.Tap(.SPACE),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return jumps == 1 && !player.is_grounded }, "space jumps once"),
    kit.Wait(90),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return landings == 2 && player.is_grounded }, "and lands again"),
    kit.Click({640, 360}),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return shots == 1 && scene.box_count == 4 && scene.sphere_count == 1 }, "the left button shoots, the scene has the four towers and the sphere"),
    kit.Hold(.LEFT_CTRL, 30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player.head_height < 0.5 }, "control crouches: the head goes down"),
    kit.Wait(2),
    kit.Capture("fps_controller_controller_end"),
    kit.Wait(1),
}
