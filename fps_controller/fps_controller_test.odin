#+build !js
package fps_controller

import "core:math"
import "core:testing"

@(private="file")
simulate :: proc(player: ^Player, seconds: f32) {
    delta_time: f32 = 1.0 / 60.0
    fov: f32 = FOV_STANDING
    for _ in 0 ..< int(seconds / delta_time) {
        PlayerUpdateVelocity(player, delta_time)
        PlayerCollideFloor(player, delta_time)
        PlayerUpdateCameraAnimations(player, &fov, delta_time)
        player.input.jump = false
        player.input.shoot = false
    }
}

@(test)
test_player_lands_on_the_floor_and_stays :: proc(t: ^testing.T) {
    player: Player
    PlayerInit(&player, {0, 3, 0})
    landed: bool = false
    for _ in 0 ..< 120 {
        PlayerUpdateVelocity(&player, 1.0 / 60.0)
        landed ||= PlayerCollideFloor(&player, 1.0 / 60.0)
    }
    testing.expect(t, landed, "it reports the landing once")
    testing.expect(t, player.is_grounded)
    testing.expect_value(t, player.position.y, 0)
    testing.expect(t, !PlayerCollideFloor(&player, 1.0 / 60.0), "standing on the floor is not landing again")
}

@(test)
test_forward_input_accelerates_to_the_max_speed :: proc(t: ^testing.T) {
    player: Player
    PlayerInit(&player)
    player.is_grounded = true
    player.input.y = 1
    simulate(&player, 2)
    testing.expect(t, player.position.z < -10, "forward is -Z at look 0")
    testing.expect(t, PlayerHorizontalSpeed(&player) > MAX_SPEED * 0.7)
    testing.expect(t, PlayerHorizontalSpeed(&player) < MAX_SPEED * 1.1)
}

@(test)
test_crouching_limits_the_speed :: proc(t: ^testing.T) {
    player: Player
    PlayerInit(&player)
    player.is_grounded = true
    player.input.y = 1
    player.input.crouch = true
    simulate(&player, 2)
    testing.expect(t, PlayerHorizontalSpeed(&player) <= CROUCH_SPEED * 1.2)
    testing.expect(t, player.head_height < STAND_HEIGHT * 0.1, "the head goes down")
}

@(test)
test_jump_only_from_the_ground :: proc(t: ^testing.T) {
    player: Player
    PlayerInit(&player)
    player.is_grounded = true
    player.input.jump = true
    testing.expect(t, PlayerUpdateVelocity(&player, 1.0 / 60.0), "jumped")
    testing.expect(t, !player.is_grounded)
    testing.expect(t, player.velocity.y > JUMP_FORCE * 0.9)
    player.input.jump = true
    testing.expect(t, !PlayerUpdateVelocity(&player, 1.0 / 60.0), "no second jump in the air")
}

@(test)
test_air_strafing_gains_speed_past_the_ground_limit :: proc(t: ^testing.T) {
    // moving sideways in the air while turning the view adds speed: the clamped acceleration is what a boomer shooter exploits
    player: Player
    PlayerInit(&player)
    player.is_grounded = false
    player.position = {0, 1000, 0}
    player.input.x = 1
    for _ in 0 ..< 600 {
        PlayerLook(&player, {-25, 0})               // a fast steady turn
        PlayerUpdateVelocity(&player, 1.0 / 60.0)
        player.position += player.velocity * (1.0 / 60.0)
    }
    testing.expect(t, PlayerHorizontalSpeed(&player) > MAX_SPEED * 1.2, "faster than the ground limit")
}

@(test)
test_look_pitch_is_limited_and_the_view_follows :: proc(t: ^testing.T) {
    player: Player
    PlayerInit(&player, {1, 0, 2})
    view: View
    PlayerView(&player, &view)
    testing.expect_value(t, view.up, Vec3{0, 1, 0})
    forward: Vec3 = view.target - view.position
    testing.expect(t, abs(forward.z + 1) < 0.001, "looks toward -Z")
    testing.expect(t, view.position.y > CROUCH_HEIGHT, "the head is above the feet")

    PlayerLook(&player, {0, 100000})               // far down
    PlayerView(&player, &view)
    testing.expect(t, player.look.y <= MAX_PITCH + 0.0001)
    forward = view.target - view.position
    testing.expect(t, forward.y < -0.99, "straight down is the limit, not past it")

    PlayerInit(&player)
    PlayerLook(&player, {math.PI / 2 / SENSITIVITY.x, 0})   // the mouse moves right: a quarter turn to the right
    PlayerView(&player, &view)
    forward = view.target - view.position
    testing.expect(t, forward.x > 0.99, "a quarter turn looks toward +X")
    testing.expect_value(t, PlayerForward(&player).x > 0.99, true)
}

@(test)
test_shooting_kicks_the_view_and_the_walk_bobs_the_head :: proc(t: ^testing.T) {
    player: Player
    PlayerInit(&player)
    fov: f32 = FOV_STANDING
    player.input.shoot = true
    PlayerUpdateCameraAnimations(&player, &fov, 1.0 / 60.0)
    testing.expect_value(t, player.recoil_timer, 1)
    testing.expect(t, player.lean.y < 0, "the view is pushed up by the recoil")

    player.input.shoot = false
    for _ in 0 ..< 10 { PlayerUpdateCameraAnimations(&player, &fov, 1.0 / 60.0) }
    testing.expect_value(t, player.recoil_timer, 0)

    player.is_grounded = true
    player.input.y = 1
    for _ in 0 ..< 30 { PlayerUpdateCameraAnimations(&player, &fov, 1.0 / 60.0) }
    testing.expect(t, player.walk_blend > 0.9, "walking blends the animation in")
    testing.expect(t, abs(player.step.y) > 0 || abs(player.step.x) > 0, "and moves the head")
    testing.expect(t, fov < FOV_STANDING, "the field of view narrows while moving on the ground")
}
