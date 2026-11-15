# FPS Controller

First person movement and camera animation: strafe jumping, boomer shooter velocity, head bob, lean and recoil. Framework agnostic: the library reads no
device and draws nothing, it moves a `Player` and gives a `View` (position, target, up, field of view) for any renderer.

```odin
fps.PlayerLook(&player, mouse_delta)
player.input = {x = 1, y = 1, jump = true}
jumped := fps.PlayerUpdateVelocity(&player, dt)        // true on the frame it jumped: play the sound
landed := fps.PlayerCollideFloor(&player, dt)          // a flat floor at y = 0, or your own collision (Box3D below)
fps.PlayerUpdateCameraAnimations(&player, &fov, dt)
fps.PlayerView(&player, &view)
```

- Strafe jumping: the acceleration is clamped per frame, turning the view while moving sideways in the air adds speed past the ground limit.
- Boomer shooter camera: crouch height, step bobbing, strafe and forward lean, recoil kick, field of view that narrows while moving.
- Based on the raylib example `core_3d_camera_fps.c`.

## Files
- `fps_controller.odin` - the player, the movement and the camera animation. Tests: `odin test fps_controller -strict-style -vet`.
- `box3d/mover_box3d.odin` - glue for Box3D (`vendor:box3d`): the player as a capsule mover. Every frame it gathers collision planes (`World_CollideMover`),
  solves them (`SolvePlanes`), casts the move (`World_CastMover`), clips the velocity (`ClipVector`) and pushes the dynamic bodies it touches.
  Ported from the Box2D `GeometricMover` sample. Physics only, no drawing.
- `demo_common/` - the two demos, written once against the demo kit: `controller` (flat floor, collision is a clamp to `y = 0`) and `box3d` (static ground and
  towers, a wall of crates and shot spheres in a Box3D world, LMB shoots a sphere, `R` resets). They fill a list of shapes (`scene.odin`) and the framework draws it.
- `demo_raylib/` - runs them on raylib, `scene3d.odin` draws the shapes with raylib 3D.
- `demo_karl2d/` - runs them on Karl2D, `scene3d.odin` draws the shapes with the 3D layer of the fork.

## The Karl2D demo needs the custom Karl2D fork
`demo_karl2d` does **not** build with upstream Karl2D. It uses the 3D layer (`karl2d.r3d_*`: meshes, instanced draw, toon material, fog) of my fork:
`odin_utilities/karl2d` is a directory junction to `odin_plug/karl2d`, repository `nezvers/karl2d_fork`, branch `render3d` (upstream Karl2D + the odin_plug
embed commits + the 3D layer, see `RENDER3D.md` in the fork). Karl2D has to be started with `depth_test = true`, the demo does that.
The raylib demo and the library work without the fork.

## Demos and tests
`odin run demo_raylib`, `odin run demo_karl2d`: WASD move, SPACE jump, CTRL crouch, LMB shoot, mouse look, `R` reset in the Box3D demo. The demo menu is on the
right (the mouse is captured while a demo runs: use PAGE UP / PAGE DOWN to switch).
Each demo has a script of simulated input with checks (walk, look, jump, land, shoot, crouch, push the crates):
`odin test demo_common -strict-style -vet` plays them headless (with the real Box3D world), `odin run demo_raylib -define:DEMO_TEST=true` plays them in the window.
