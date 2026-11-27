#+private file
package demo_common

import "core:fmt"
import "core:math"
import "core:math/rand"
import qt ".."
import kit "../../demo_kit"
import qtkit "../kit"

@(private = "package")
demo_balls: kit.Demo = {
    name = "bouncing balls",
    init = ballsInit,
    update = ballsUpdate,
    draw = ballsDraw,
    script = ballsScript,
}

// Balls bounce off the window and off each other. The tree is rebuilt every frame after the balls moved (the item is the ball index) and gives the neighbours to test against.
// Hold the left button to spawn more at the mouse.
BALL_CAPACITY :: 2000
BALL_START :: 60
BALL_RADIUS_MIN :: 4.0
BALL_RADIUS_MAX :: 9.0
BALL_SPEED_MIN :: 80.0
BALL_SPEED_MAX :: 260.0
BALLS_PER_FRAME :: 2
BOUNDS :: qt.Rect{0, 0, 1280, 720}

Ball :: struct {
    position: qt.Vec2,
    velocity: qt.Vec2,
    radius: f32,
    color: kit.Color,
}

BallTree :: qt.Quadtree(BALL_CAPACITY, 6000, 24576)

balls_tree: BallTree
balls: [BALL_CAPACITY]Ball
balls_count: int
balls_seed: rand.Default_Random_State
balls_random: rand.Generator
balls_pairs: int                     // pairs tested in the last frame
balls_show_tree: bool

ballsInit :: proc(ctx: ^kit.Context) {
    balls_seed = rand.create(77)
    balls_random = rand.default_random_generator(&balls_seed)
    ballsReset()
    balls_show_tree = false
}

ballsReset :: proc() {
    qt.QuadtreeInit(&balls_tree, BOUNDS, 8, 6)
    balls_count = 0
    for _ in 0 ..< BALL_START {
        ballsSpawn({BOUNDS.w * 0.1 + rand.float32(balls_random) * BOUNDS.w * 0.8, BOUNDS.h * 0.1 + rand.float32(balls_random) * BOUNDS.h * 0.8})
    }
}

ballsSpawn :: proc(position: qt.Vec2) -> bool {
    if balls_count >= BALL_CAPACITY { return false }
    radius: f32 = BALL_RADIUS_MIN + rand.float32(balls_random) * (BALL_RADIUS_MAX - BALL_RADIUS_MIN)
    angle: f32 = rand.float32(balls_random) * math.TAU
    speed: f32 = BALL_SPEED_MIN + rand.float32(balls_random) * (BALL_SPEED_MAX - BALL_SPEED_MIN)
    hue: f32 = rand.float32(balls_random)
    balls[balls_count] = {
        position = {clamp(position.x, radius, BOUNDS.w - radius), clamp(position.y, radius, BOUNDS.h - radius)},
        velocity = {math.cos(angle), math.sin(angle)} * speed,
        radius = radius,
        color = hoverColor(hue),
    }
    balls_count += 1
    return true
}

ballRect :: proc(position: qt.Vec2, radius: f32) -> qt.Rect {
    return {position.x - radius, position.y - radius, radius * 2, radius * 2}
}

ballsUpdate :: proc(ctx: ^kit.Context) {
    if !ctx.ui_hover && kit.MouseDown(&ctx.input, .LEFT) {
        for _ in 0 ..< BALLS_PER_FRAME { ballsSpawn(ctx.input.mouse_position) }
    }
    if kit.KeyPressed(&ctx.input, .R) { ballsReset() }
    if kit.KeyPressed(&ctx.input, .G) { balls_show_tree = !balls_show_tree }

    // a long frame (a window dragged around) must not let balls jump through each other
    dt: f32 = min(ctx.delta_time, 1.0 / 30.0)
    for &ball in balls[:balls_count] {
        ball.position += ball.velocity * dt
        if ball.position.x < ball.radius { ball.position.x = ball.radius; ball.velocity.x = abs(ball.velocity.x) }
        if ball.position.x > BOUNDS.w - ball.radius { ball.position.x = BOUNDS.w - ball.radius; ball.velocity.x = -abs(ball.velocity.x) }
        if ball.position.y < ball.radius { ball.position.y = ball.radius; ball.velocity.y = abs(ball.velocity.y) }
        if ball.position.y > BOUNDS.h - ball.radius { ball.position.y = BOUNDS.h - ball.radius; ball.velocity.y = -abs(ball.velocity.y) }
    }

    // immediate mode: the tree only knows this frame, so it is built again from the moved balls
    qt.QuadtreeClear(&balls_tree)
    for &ball, index in balls[:balls_count] { qt.QuadtreeInsert(&balls_tree, ballRect(ball.position, ball.radius), index) }

    // the tree gives the balls whose boxes touch, the circles decide. A pair is handled once: from the ball with the lower index
    balls_pairs = 0
    neighbours: [64]qt.Item
    for &ball, index in balls[:balls_count] {
        count: int = qt.QuadtreeQuery(&balls_tree, ballRect(ball.position, ball.radius), neighbours[:], index)
        for i in 0 ..< count {
            if neighbours[i] < index { continue }
            balls_pairs += 1
            ballsCollide(&ball, &balls[neighbours[i]])
        }
    }
}

// Elastic collision, the mass is the area
ballsCollide :: proc(a: ^Ball, b: ^Ball) {
    offset: qt.Vec2 = b.position - a.position
    distance_squared: f32 = offset.x * offset.x + offset.y * offset.y
    reach: f32 = a.radius + b.radius
    if distance_squared >= reach * reach || distance_squared == 0 { return }
    distance: f32 = math.sqrt(distance_squared)
    normal: qt.Vec2 = offset / distance
    mass_a: f32 = a.radius * a.radius
    mass_b: f32 = b.radius * b.radius
    overlap: f32 = reach - distance
    a.position -= normal * overlap * (mass_b / (mass_a + mass_b))
    b.position += normal * overlap * (mass_a / (mass_a + mass_b))
    approach: f32 = (a.velocity.x - b.velocity.x) * normal.x + (a.velocity.y - b.velocity.y) * normal.y
    if approach <= 0 { return }
    impulse: f32 = 2 * approach / (mass_a + mass_b)
    a.velocity -= normal * impulse * mass_b
    b.velocity += normal * impulse * mass_a
}

ballsDraw :: proc(ctx: ^kit.Context) {
    if balls_show_tree { qtkit.DrawQuadtree(ctx, &balls_tree) }
    for &ball in balls[:balls_count] { kit.DrawCircle(ctx, ball.position, ball.radius, ball.color) }
    nodes, links := qt.QuadtreeUsage(&balls_tree)
    kit.DrawText(ctx, "bouncing balls: hold LMB to spawn at the mouse, R reset, G tree", {10, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("balls = %v, pairs tested = %v (all pairs would be %v), nodes = %v, links = %v", balls_count, balls_pairs, balls_count * (balls_count - 1) / 2, nodes, links), {10, 36}, 20, kit.DARK_GRAY)
}

// Every ball is inside of the window and the rebuilt tree holds exactly the balls
ballsConsistent :: proc(ctx: ^kit.Context) -> bool {
    if qt.QuadtreeLen(&balls_tree) != balls_count { return false }
    for &ball in balls[:balls_count] {
        if ball.position.x < ball.radius - 0.01 || ball.position.x > BOUNDS.w - ball.radius + 0.01 { return false }
        if ball.position.y < ball.radius - 0.01 || ball.position.y > BOUNDS.h - ball.radius + 0.01 { return false }
    }
    everything: [BALL_CAPACITY]qt.Item
    return qt.QuadtreeQuery(&balls_tree, BOUNDS, everything[:]) == balls_count
}

ballsScript: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return balls_count == BALL_START }, "the balls start spawned"),
    kit.Wait(120),
    kit.Check(ballsConsistent, "after two seconds all balls are in the window and in the tree"),
    // hold the left button over the middle of the window: two balls a frame
    kit.MoveTo({640, 360}),
    kit.MouseDownStep(.LEFT),
    kit.Wait(30),
    kit.MouseUpStep(.LEFT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return balls_count >= BALL_START + 50 }, "holding the left button spawns balls at the mouse"),
    kit.Wait(240),
    kit.Check(ballsConsistent, "with more balls they still stay in the window and in the tree"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return balls_pairs < balls_count * (balls_count - 1) / 2 / 4 }, "the tree tests far fewer pairs than all of them"),
    kit.Tap(.R),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return balls_count == BALL_START }, "R starts again"),
}
