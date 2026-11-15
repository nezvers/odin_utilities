package demo_common

// What the demos draw in 3D, as a list of plain shapes the demo fills every frame. The kit is 2D, so the 3D part of a frame is drawn
// by a proc of the framework that runs the demo: demo_raylib sets `scene_drawer` to raylib (BeginMode3D), demo_karl2d sets it to the
// 3D layer of the Karl2D fork. The demos themselves know nothing of either.

import kit "../../demo_kit"
import fps ".."

MAX_BOXES :: 64
MAX_SPHERES :: 64

FLOOR_EXTENT :: 25
TILE_SIZE :: 5
FLOOR_COLOR_A :: kit.Color{150, 200, 200, 255}
FLOOR_COLOR_B :: kit.Color{200, 200, 200, 255}

TOWER_POSITIONS :: [4]fps.Vec3{{16, 16, 16}, {-16, 16, 16}, {-16, 16, -16}, {16, 16, -16}}
TOWER_HALF :: fps.Vec3{8, 16, 8}

SceneBox :: struct {
    center: fps.Vec3,
    half: fps.Vec3,
    rotation: quaternion128,
    color: kit.Color,
    wire: kit.Color,            // the color of the edges, alpha 0: none
}

SceneSphere :: struct {
    center: fps.Vec3,
    radius: f32,
    color: kit.Color,
}

Scene :: struct {
    boxes: [MAX_BOXES]SceneBox,
    box_count: int,
    spheres: [MAX_SPHERES]SceneSphere,
    sphere_count: int,
    floor: bool,                // the checker floor of FLOOR_EXTENT x FLOOR_EXTENT tiles
}

// Draws a frame of 3D: the view of the player and the shapes. Set by the demo of a framework before it runs the demos.
SceneDrawer :: proc(ctx: ^kit.Context, view: ^fps.View, scene: ^Scene)
scene_drawer: SceneDrawer

SceneClear :: proc(scene: ^Scene) {
    scene.box_count = 0
    scene.sphere_count = 0
}

SceneAddBox :: proc(scene: ^Scene, center: fps.Vec3, half: fps.Vec3, color: kit.Color, wire: kit.Color = {}, rotation: quaternion128 = 1) {
    if scene.box_count >= MAX_BOXES { return }
    scene.boxes[scene.box_count] = {center = center, half = half, rotation = rotation, color = color, wire = wire}
    scene.box_count += 1
}

SceneAddSphere :: proc(scene: ^Scene, center: fps.Vec3, radius: f32, color: kit.Color) {
    if scene.sphere_count >= MAX_SPHERES { return }
    scene.spheres[scene.sphere_count] = {center = center, radius = radius, color = color}
    scene.sphere_count += 1
}

// The four towers of the level, the reference for the movement
SceneAddTowers :: proc(scene: ^Scene) {
    for position in TOWER_POSITIONS {
        SceneAddBox(scene, position, TOWER_HALF, FLOOR_COLOR_A, {100, 150, 150, 255})
    }
}

// The checker floor is on the tiles where x and y are both odd (one color) or both even (the other), the rest is empty: a visual
// reference for the speed. `visit` gets the center, the size and the color of each tile.
SceneFloorTiles :: proc(visit: proc(center: fps.Vec3, size: f32, color: kit.Color, user: rawptr), user: rawptr) {
    for y in -FLOOR_EXTENT ..< FLOOR_EXTENT {
        for x in -FLOOR_EXTENT ..< FLOOR_EXTENT {
            center: fps.Vec3 = {f32(x * TILE_SIZE), 0, f32(y * TILE_SIZE)}
            if (y & 1 == 1) && (x & 1 == 1) {
                visit(center, TILE_SIZE, FLOOR_COLOR_A, user)
            } else if (y & 1 == 0) && (x & 1 == 0) {
                visit(center, TILE_SIZE, FLOOR_COLOR_B, user)
            }
        }
    }
}

// The input of a player from the devices of the kit: WASD, space, control, the mouse. Returns what the demo needs to play sounds.
PlayerReadInput :: proc(ctx: ^kit.Context, player: ^fps.Player) {
    input: ^kit.Input = &ctx.input
    player.input.x = i8(kit.AxisKeys(input, .A, .D))
    player.input.y = i8(kit.AxisKeys(input, .S, .W))
    player.input.crouch = kit.KeyDown(input, .LEFT_CTRL)
    player.input.jump = kit.KeyPressed(input, .SPACE)
    player.input.shoot = kit.MousePressed(input, .LEFT) && !ctx.ui_hover
    fps.PlayerLook(player, input.mouse_delta)
}

// The camera of a frame, from the player: the same for every demo
UpdateView :: proc(player: ^fps.Player, view: ^fps.View, delta_time: f32) {
    fps.PlayerUpdateCameraAnimations(player, &view.fov_y, delta_time)
    fps.PlayerView(player, view)
}
