package demo_karl2d

// The 3D drawing of the demos with the 3D layer of the Karl2D fork (karl2d.r3d_*): the list of shapes of demo_common.Scene on the camera
// of the player. The floor, the boxes and the spheres are instanced, one draw call per mesh and material.

import "../../karl2d"
import kit "../../demo_kit"
import demo_common "../demo_common"
import fps "../"

MAX_FLOOR_TILES :: 2 * demo_common.FLOOR_EXTENT * 2 * demo_common.FLOOR_EXTENT

Renderer :: struct {
    ready: bool,
    plane: karl2d.R3d_Mesh,
    cube: karl2d.R3d_Mesh,
    sphere: karl2d.R3d_Mesh,
    floor_a: karl2d.R3d_Material,
    floor_b: karl2d.R3d_Material,
    box: karl2d.R3d_Material,
    ball: karl2d.R3d_Material,
    tiles_a: [MAX_FLOOR_TILES]karl2d.R3d_Instance,
    tiles_b: [MAX_FLOOR_TILES]karl2d.R3d_Instance,
    count_a: int,
    count_b: int,
}
renderer: Renderer

draw_scene :: proc(ctx: ^kit.Context, view: ^fps.View, scene: ^demo_common.Scene) {
    if !renderer.ready { renderer_init() }

    camera: karl2d.R3d_Camera = {
        position = view.position,
        target = view.target,
        up = view.up,
        fov_y_degrees = view.fov_y,
        near = 0.1,
        far = 400,
    }
    environment: karl2d.R3d_Environment = karl2d.r3d_environment_default()
    environment.sun_direction = {0.4, 0.9, 0.3}
    environment.fog_density = 0.004
    environment.fog_start = 60
    karl2d.r3d_begin_scene(camera, environment)

    if scene.floor {
        // every tile of one color is an instance of the same plane: one draw call each
        renderer.count_a, renderer.count_b = 0, 0
        demo_common.SceneFloorTiles(collect_tile, nil)
        karl2d.r3d_draw(renderer.plane, renderer.floor_a, renderer.tiles_a[:renderer.count_a])
        karl2d.r3d_draw(renderer.plane, renderer.floor_b, renderer.tiles_b[:renderer.count_b])
    }

    // boxes: the tint of the instance is the color of the box
    boxes: [demo_common.MAX_BOXES]karl2d.R3d_Instance
    for i in 0 ..< scene.box_count {
        box: demo_common.SceneBox = scene.boxes[i]
        boxes[i] = karl2d.r3d_instance(box.center, box.rotation, box.half * 2, color4(box.color))
    }
    karl2d.r3d_draw(renderer.cube, renderer.box, boxes[:scene.box_count])

    balls: [demo_common.MAX_SPHERES]karl2d.R3d_Instance
    for i in 0 ..< scene.sphere_count {
        sphere: demo_common.SceneSphere = scene.spheres[i]
        balls[i] = karl2d.r3d_instance(sphere.center, 1, {sphere.radius, sphere.radius, sphere.radius}, color4(sphere.color))
    }
    karl2d.r3d_draw(renderer.sphere, renderer.ball, balls[:scene.sphere_count])
    karl2d.r3d_end_scene()

    // the 2D that follows (the HUD and the menu of the kit) is in front of the 3D depth values
    karl2d.set_z(1)
}

collect_tile :: proc(center: fps.Vec3, size: f32, color: kit.Color, user: rawptr) {
    instance: karl2d.R3d_Instance = karl2d.r3d_instance(center, 1, {1, 1, 1}, color4(color))
    if color == demo_common.FLOOR_COLOR_A {
        renderer.tiles_a[renderer.count_a] = instance
        renderer.count_a += 1
    } else {
        renderer.tiles_b[renderer.count_b] = instance
        renderer.count_b += 1
    }
}

color4 :: proc(color: kit.Color) -> [4]f32 {
    return {f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
}

renderer_init :: proc() {
    ensure(karl2d.r3d_init())
    data := karl2d.r3d_mesh_data_plane({demo_common.TILE_SIZE, demo_common.TILE_SIZE})
    renderer.plane, _ = karl2d.r3d_mesh_create_from_data(data)
    karl2d.r3d_mesh_data_destroy(&data)
    data = karl2d.r3d_mesh_data_cube({1, 1, 1})
    renderer.cube, _ = karl2d.r3d_mesh_create_from_data(data)
    karl2d.r3d_mesh_data_destroy(&data)
    data = karl2d.r3d_mesh_data_sphere(1, 16, 24)
    renderer.sphere, _ = karl2d.r3d_mesh_create_from_data(data)
    karl2d.r3d_mesh_data_destroy(&data)

    renderer.floor_a = karl2d.r3d_material_default()
    renderer.floor_a.tint = color4(demo_common.FLOOR_COLOR_A)
    renderer.floor_a.rim_color = {}
    renderer.floor_b = karl2d.r3d_material_default()
    renderer.floor_b.tint = color4(demo_common.FLOOR_COLOR_B)
    renderer.floor_b.rim_color = {}
    renderer.box = karl2d.r3d_material_default()
    renderer.box.outline_width = 2
    renderer.box.toon_bands = 3
    renderer.ball = karl2d.r3d_material_default()
    renderer.ball.outline_width = 2
    renderer.ball.toon_bands = 4
    renderer.ready = true
}
